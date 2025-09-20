// lib/pages/trip_plan_page.dart

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

/// IMPORTANT: remove hardcoded API keys from source control.
/// Move them to secure storage or keep only on server.
const String googleMapsApiKey = "YOUR_API_KEY_PLACEHOLDER";

class TripPlanPage extends StatefulWidget {
  final String roomCode;
  const TripPlanPage({super.key, required this.roomCode});

  @override
  State<TripPlanPage> createState() => _TripPlanPageState();
}

class _TripPlanPageState extends State<TripPlanPage> {
  final List<Map<String, dynamic>> _planStops = [];
  bool _isLoading = false;   // used for initial load / fetch
  bool _isSaving = false;    // used when saving
  LatLng? _currentLocation;

  @override
  void initState() {
    super.initState();
    _init(); // run async init (gets location then fetches plan)
  }

  Future<void> _init() async {
    setState(() => _isLoading = true);
    try {
      await _getCurrentLocation();
      await _fetchPlan();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      // make sure permissions are handled by caller UI or earlier in app
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // user denied - do not throw, just return
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        // cannot request permissions - inform user
        return;
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      _currentLocation = LatLng(position.latitude, position.longitude);

      // Ensure current location exists once (don't duplicate)
      final existingIndex = _planStops.indexWhere((s) => s['isCurrentLocation'] == true);
      if (existingIndex >= 0) {
        _planStops[existingIndex]['location'] = _currentLocation;
      } else {
        _planStops.insert(0, {
          "id": const Uuid().v4(),
          "title": "My Current Location",
          "name": "Current Location",
          "location": _currentLocation,
          "timeSpent": 0,
          "travelTime": 0,
          "notes": "",
          "isCurrentLocation": true,
        });
      }
    } catch (e) {
      debugPrint("Location error: $e");
      // Optionally show a snackbar
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get current location')),
        );
      }
    }
  }

  Future<void> _fetchPlan() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";

    if (server.isEmpty) {
      // no server configured, nothing to fetch
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await http.get(Uri.parse("$server/get_trip_plan/${widget.roomCode}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Backend might return either 'plan' or 'stops' depending on version.
        final rawStops = (data['plan'] ?? data['stops']);
        if (rawStops != null && rawStops is List) {
          // preserve the current location (if any) as the first element
          final cur = _planStops.firstWhere((s) => s['isCurrentLocation'] == true, orElse: () => {});
          final List<Map<String, dynamic>> parsed = [];
          for (var stop in rawStops) {
            try {
              // tolerant parsing of lat/lng (could be string/int/double)
              final dynamic latRaw = stop['lat'] ?? stop['latitude'];
              final dynamic lngRaw = stop['lng'] ?? stop['longitude'];

              double? lat;
              double? lng;

              if (latRaw != null) {
                if (latRaw is double) lat = latRaw;
                else if (latRaw is int) lat = latRaw.toDouble();
                else if (latRaw is String) lat = double.tryParse(latRaw);
              }

              if (lngRaw != null) {
                if (lngRaw is double) lng = lngRaw;
                else if (lngRaw is int) lng = lngRaw.toDouble();
                else if (lngRaw is String) lng = double.tryParse(lngRaw);
              }

              if (lat == null || lng == null) {
                // skip stops with invalid coords
                continue;
              }

              parsed.add({
                "id": stop['id'] ?? const Uuid().v4(),
                "title": stop['title'] ?? stop['name'] ?? 'Unnamed Place',
                "name": stop['name'] ?? stop['title'] ?? 'Unnamed',
                "timeSpent": stop['timeSpent'] ?? 0,
                "travelTime": stop['travelTime'] ?? 0,
                "notes": stop['notes'] ?? "",
                "location": LatLng(lat, lng),
              });
            } catch (e) {
              debugPrint("Error parsing stop: $e");
              continue;
            }
          }

          setState(() {
            _planStops.removeWhere((s) => s['isCurrentLocation'] != true); // remove non-current stops
            _planStops.addAll(parsed); // current location (if present) remains at index 0
          });
        }
      } else if (response.statusCode == 404) {
        setState(() {
          // no plan found — keep current location (if any) but clear others
          _planStops.removeWhere((s) => s['isCurrentLocation'] != true);
        });
        debugPrint("No existing trip plan found (404).");
      } else {
        debugPrint("Fetch plan failed: ${response.statusCode} ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to fetch trip plan (${response.statusCode})')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error fetching trip plan: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error fetching trip plan')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _addStop(LatLng location) {
    showDialog(
      context: context,
      builder: (context) {
        final TextEditingController nameController = TextEditingController();
        return AlertDialog(
          title: const Text("Name this Place"),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(hintText: "Enter a name for this stop"),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () {
                if (nameController.text.isNotEmpty) {
                  setState(() {
                    _planStops.add({
                      "id": const Uuid().v4(),
                      "title": nameController.text,
                      "name": nameController.text,
                      "location": location,
                      "timeSpent": 0,
                      "travelTime": 0,
                      "notes": "",
                    });
                  });
                  Navigator.pop(context);
                }
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _savePlan() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";

    if (server.isEmpty) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Server IP not set.')));
      return;
    }

    // Prepare stops while skipping any stop without valid LatLng (and skip the current-location flag if you don't want to save it)
    final stopsPayload = _planStops.where((s) => s['location'] is LatLng).map((stop) {
      final LatLng loc = stop['location'] as LatLng;
      return {
        "id": stop["id"],
        "title": stop["title"],
        "name": stop["name"],
        "lat": loc.latitude,
        "lng": loc.longitude,
        "timeSpent": stop["timeSpent"] ?? 0,
        "travelTime": stop["travelTime"] ?? 0,
        "notes": stop["notes"] ?? "",
      };
    }).toList();

    final planData = {"stops": stopsPayload};

    try {
      final res = await http.post(
        Uri.parse("$server/trip_plan/${widget.roomCode}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(planData),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Trip plan saved.')));
        }
      } else {
        debugPrint("Save failed: ${res.statusCode} ${res.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save plan (${res.statusCode})')),
          );
        }
      }
    } catch (e) {
      debugPrint("Error saving plan: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Error saving trip plan')));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _showEditSheet(int index) {
    final stop = _planStops[index];
    final titleController = TextEditingController(text: stop['title']);
    final timeSpentController = TextEditingController(text: stop['timeSpent'].toString());
    final travelTimeController = TextEditingController(text: stop['travelTime'].toString());
    final notesController = TextEditingController(text: stop['notes']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Edit Place Details", style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 20),
                TextFormField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: "Place Title",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: timeSpentController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Time to Spend (in mins)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: travelTimeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: "Travel Time to Next Place (in mins)",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Text("Notes & Plan", style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 10),
                TextFormField(
                  controller: notesController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: "Add notes or a specific plan for this place",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text("Cancel"),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          stop['title'] = titleController.text;
                          stop['timeSpent'] = int.tryParse(timeSpentController.text) ?? 0;
                          stop['travelTime'] = int.tryParse(travelTimeController.text) ?? 0;
                          stop['notes'] = notesController.text;
                        });
                        Navigator.pop(context);
                      },
                      child: const Text("Save"),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _deleteStop(int index) {
    setState(() {
      _planStops.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final Set<Marker> markers = _planStops
        .where((stop) => stop['location'] is LatLng)
        .map((stop) {
      final LatLng pos = stop['location'] as LatLng;
      return Marker(
        markerId: MarkerId(stop['id']),
        position: pos,
        infoWindow: InfoWindow(title: stop['title']),
      );
    }).toSet();

    final List<LatLng> polylinePoints = _planStops.where((s) => s['location'] is LatLng).map((stop) => stop["location"] as LatLng).toList();
    final Set<Polyline> polylines = polylinePoints.length < 2 ? {} : {
      Polyline(
        polylineId: const PolylineId("trip_route"),
        color: Colors.blue,
        width: 4,
        points: polylinePoints,
      )
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text("Plan Your Trip 🗺️"),
        actions: [
          if (_planStops.isNotEmpty)
            IconButton(
              icon: _isSaving ? const CircularProgressIndicator(color: Colors.white) : const Icon(Icons.save),
              onPressed: _isSaving ? null : _savePlan,
              tooltip: "Save Plan",
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          Expanded(
            flex: 2,
            child: _currentLocation == null
                ? const Center(child: Text("Waiting for location..."))
                : GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentLocation!,
                zoom: 13.0,
              ),
              onTap: _addStop,
              markers: markers,
              polylines: polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),
          Expanded(
            flex: 1,
            child: ListView.builder(
              itemCount: _planStops.length,
              itemBuilder: (context, index) {
                final stop = _planStops[index];
                final LatLng? loc = stop['location'] is LatLng ? stop['location'] as LatLng : null;
                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  child: ListTile(
                    onTap: () => _showEditSheet(index),
                    title: Text(stop['title'], style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (loc != null)
                          Text("Lat: ${loc.latitude.toStringAsFixed(4)}, Lng: ${loc.longitude.toStringAsFixed(4)}"),
                        Text("Time to Spend: ${stop['timeSpent']} mins"),
                        Text("Travel to next: ${stop['travelTime']} mins"),
                      ],
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red),
                      onPressed: () => _deleteStop(index),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
