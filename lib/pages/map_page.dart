// pages/map_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MapPage extends StatefulWidget {
  // Accept the map of users from the location page.
  final Map<String, dynamic> users;        // { user_id: {role, last_location} }
  final Map<String, String> usernames;     // { user_id: username }
  const MapPage({super.key, required this.users, required this.usernames});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  late final MapController _mapController;
  List<Marker> _markers = [];

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _buildMarkers();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.users.toString() != oldWidget.users.toString()) {
      setState(() {
        _buildMarkers();
      });
      _fitBoundsToMarkers();
    }
  }

  void _buildMarkers() {
    List<Marker> markers = [];
    widget.users.forEach((userId, userData) {
      if (userData != null) {
        final role = userData["role"] ?? "member";
        final loc = userData["last_location"];

        if (loc != null && loc["lat"] != null && loc["lng"] != null) {
          final lat = (loc["lat"] as num).toDouble();
          final lng = (loc["lng"] as num).toDouble();
          final timestamp = loc["timestamp"] ?? "";
          final username = widget.usernames[userId] ?? userId;

          markers.add(
            Marker(
              point: LatLng(lat, lng),
              width: 140,
              height: 100,
              alignment: Alignment.topCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_pin,
                    color: role == "admin" ? Colors.blue : Colors.red,
                    size: 40,
                  ),
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black26,
                          blurRadius: 3,
                          spreadRadius: 1,
                        )
                      ],
                    ),
                    child: Column(
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        if (role == "admin")
                          Text(
                            "Admin",
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        Text(
                          timestamp,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    });
    _markers = markers;
  }

  void _fitBoundsToMarkers() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_markers.isEmpty || !mounted) return;

      final points = _markers.map((m) => m.point).toList();
      final uniquePoints = Set<LatLng>.from(points);

      if (uniquePoints.length > 1) {
        final bounds = LatLngBounds.fromPoints(points);
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(50.0),
          ),
        );
      } else if (uniquePoints.isNotEmpty) {
        _mapController.move(uniquePoints.first, 15.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Map View")),
      body: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: const LatLng(20.5937, 78.9629),
          initialZoom: 5.0,
          onMapReady: () {
            _fitBoundsToMarkers();
          },
        ),
        children: [
          TileLayer(
            urlTemplate: "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png",
            subdomains: const ['a', 'b', 'c'],
            userAgentPackageName: 'dev.yourcompany.yourappname',
          ),
          MarkerLayer(markers: _markers),
        ],
      ),
    );
  }
}
