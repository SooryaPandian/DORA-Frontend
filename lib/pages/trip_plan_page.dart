// lib/pages/trip_plan_page.dart

import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';

/// IMPORTANT: remove hardcoded API keys from source control.
/// Move them to secure storage or keep only on server.
const String googleMapsApiKey = "YOUR_API_KEY_PLACEHOLDER";

// Color scheme for the app
class AppColors {
  static const primary = Color(0xFF2E7D7A);
  static const primaryLight = Color(0xFF4DB6AC);
  static const primaryDark = Color(0xFF00695C);
  static const secondary = Color(0xFFFF7043);
  static const secondaryLight = Color(0xFFFFAB91);
  static const accent = Color(0xFFFFCA28);
  static const background = Color(0xFFF5F5F5);
  static const surface = Color(0xFFFFFFFF);
  static const cardShadow = Color(0x1F000000);
  static const textPrimary = Color(0xFF212121);
  static const textSecondary = Color(0xFF757575);
  static const success = Color(0xFF4CAF50);
  static const error = Color(0xFFF44336);
  static const warning = Color(0xFFFF9800);
}

// Place suggestion model for OpenStreetMap Nominatim API
class PlaceSuggestion {
  final String displayName;
  final String name;
  final double lat;
  final double lon;
  final String? category;
  final String? type;

  PlaceSuggestion({
    required this.displayName,
    required this.name,
    required this.lat,
    required this.lon,
    this.category,
    this.type,
  });

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      displayName: json['display_name'] ?? '',
      name: json['name'] ?? json['display_name'] ?? '',
      lat: double.parse(json['lat']),
      lon: double.parse(json['lon']),
      category: json['category'],
      type: json['type'],
    );
  }
}

// Route information model
class RouteInfo {
  final List<LatLng> coordinates;
  final double distanceKm;
  final int durationMinutes;
  final String geometry;

  RouteInfo({
    required this.coordinates,
    required this.distanceKm,
    required this.durationMinutes,
    required this.geometry,
  });

  factory RouteInfo.fromOSRM(Map<String, dynamic> json) {
    final route = json['routes'][0];
    final geometry = route['geometry'];
    final distance =
        (route['distance'] as num).toDouble() / 1000; // Convert to km
    final duration = ((route['duration'] as num).toDouble() / 60)
        .round(); // Convert to minutes

    // Decode the polyline geometry
    final coordinates = _decodePolyline(geometry);

    return RouteInfo(
      coordinates: coordinates,
      distanceKm: distance,
      durationMinutes: duration,
      geometry: geometry,
    );
  }

  factory RouteInfo.fromGraphHopper(Map<String, dynamic> json) {
    final path = json['paths'][0];
    final distance =
        (path['distance'] as num).toDouble() / 1000; // Convert to km
    final duration = ((path['time'] as num).toDouble() / 1000 / 60)
        .round(); // Convert to minutes
    final points = path['points'];

    // Decode the polyline geometry
    final coordinates = _decodePolyline(points);

    return RouteInfo(
      coordinates: coordinates,
      distanceKm: distance,
      durationMinutes: duration,
      geometry: points,
    );
  }

  // Decode Google's polyline algorithm
  static List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> coordinates = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      coordinates.add(LatLng(lat / 1E5, lng / 1E5));
    }

    return coordinates;
  }
}

// Routing service class
class RoutingService {
  static const String osrmBaseUrl =
      'https://router.project-osrm.org/route/v1/driving';
  static const String graphHopperBaseUrl =
      'https://graphhopper.com/api/1/route';
  static const String graphHopperApiKey =
      'YOUR_GRAPHHOPPER_API_KEY'; // Replace with actual key

  // Get route between two points using OSRM (free service)
  static Future<RouteInfo?> getRouteOSRM(LatLng start, LatLng end) async {
    try {
      final url =
          '$osrmBaseUrl/${start.longitude},${start.latitude};${end.longitude},${end.latitude}?geometries=polyline&overview=full';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TravelPlannerApp/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes']?.isNotEmpty == true) {
          return RouteInfo.fromOSRM(data);
        }
      }
    } catch (e) {
      debugPrint('Error getting OSRM route: $e');
    }
    return null;
  }

  // Get route using GraphHopper (requires API key but has more features)
  static Future<RouteInfo?> getRouteGraphHopper(
      LatLng start, LatLng end) async {
    if (graphHopperApiKey == 'YOUR_GRAPHHOPPER_API_KEY') {
      // Fallback to OSRM if no GraphHopper API key
      return getRouteOSRM(start, end);
    }

    try {
      final url =
          '$graphHopperBaseUrl?point=${start.latitude},${start.longitude}&point=${end.latitude},${end.longitude}&vehicle=car&key=$graphHopperApiKey';

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'TravelPlannerApp/1.0'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['paths']?.isNotEmpty == true) {
          return RouteInfo.fromGraphHopper(data);
        }
      }
    } catch (e) {
      debugPrint('Error getting GraphHopper route: $e');
    }
    return null;
  }

  // Get the best available route (tries GraphHopper first, falls back to OSRM)
  static Future<RouteInfo?> getRoute(LatLng start, LatLng end) async {
    // Try GraphHopper first (if API key available), otherwise use OSRM
    return await getRouteOSRM(start, end);
  }

  // Calculate route for multiple stops (complete trip)
  static Future<List<RouteInfo>> getTripRoutes(List<LatLng> stops) async {
    List<RouteInfo> routes = [];

    for (int i = 0; i < stops.length - 1; i++) {
      final route = await getRoute(stops[i], stops[i + 1]);
      if (route != null) {
        routes.add(route);
      }
    }

    return routes;
  }
}

class TripPlanPage extends StatefulWidget {
  final String roomCode;
  const TripPlanPage({super.key, required this.roomCode});

  @override
  State<TripPlanPage> createState() => _TripPlanPageState();
}

class _TripPlanPageState extends State<TripPlanPage>
    with TickerProviderStateMixin {
  final List<Map<String, dynamic>> _planStops = [];
  bool _isLoading = false; // used for initial load / fetch
  bool _isSaving = false; // used when saving
  LatLng? _currentLocation;

  // Place search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  List<PlaceSuggestion> _suggestions = [];
  bool _isSearching = false;
  Timer? _searchDebounceTimer;

  // Animation controllers
  late AnimationController _fabAnimationController;
  late AnimationController _cardAnimationController;
  late Animation<double> _fabAnimation;

  GoogleMapController? _mapController;

  // Route information
  List<RouteInfo> _routes = [];
  bool _isCalculatingRoutes = false;
  double _totalDistance = 0.0;
  int _totalTravelTime = 0;
  bool _isRoutingOptimized = false;

  @override
  void initState() {
    super.initState();
    _fabAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _cardAnimationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );
    _fabAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fabAnimationController, curve: Curves.easeInOut),
    );

    _searchController.addListener(_onSearchChanged);
    _init(); // run async init (gets location then fetches plan)
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _fabAnimationController.dispose();
    _cardAnimationController.dispose();
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.isNotEmpty) {
        _searchPlaces(_searchController.text);
      } else {
        setState(() {
          _suggestions.clear();
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _searchPlaces(String query) async {
    if (query.length < 3) return;

    setState(() => _isSearching = true);

    try {
      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/search?q=${Uri.encodeQueryComponent(query)}&format=json&limit=5&addressdetails=1',
      );

      final response = await http.get(url, headers: {
        'User-Agent': 'TravelPlannerApp/1.0',
      });

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        setState(() {
          _suggestions =
              data.map((item) => PlaceSuggestion.fromJson(item)).toList();
          _isSearching = false;
        });
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
      setState(() => _isSearching = false);
    }
  }

  void _addStopFromSuggestion(PlaceSuggestion suggestion) {
    final location = LatLng(suggestion.lat, suggestion.lon);
    setState(() {
      _planStops.add({
        "id": const Uuid().v4(),
        "title": suggestion.name,
        "name": suggestion.name,
        "location": location,
        "timeSpent": 60, // Default 1 hour
        "travelTime": 15, // Default 15 minutes
        "notes": "",
        "category": suggestion.category ?? '',
        "type": suggestion.type ?? '',
      });
      _suggestions.clear();
      _searchController.clear();
    });

    // Calculate routes after adding new stop
    _calculateRoutes();

    // Animate to new location
    if (_mapController != null) {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngZoom(location, 15.0),
      );
    }

    _fabAnimationController.forward().then((_) {
      _fabAnimationController.reverse();
    });
  }

  // Calculate routes between all consecutive stops
  Future<void> _calculateRoutes() async {
    if (_planStops.length < 2) {
      setState(() {
        _routes.clear();
        _totalDistance = 0.0;
        _totalTravelTime = 0;
      });
      return;
    }

    setState(() => _isCalculatingRoutes = true);

    try {
      final locations = _planStops
          .where((stop) => stop['location'] is LatLng)
          .map((stop) => stop['location'] as LatLng)
          .toList();

      final routes = await RoutingService.getTripRoutes(locations);

      // Calculate totals
      double totalDistance = 0.0;
      int totalTravelTime = 0;

      for (final route in routes) {
        totalDistance += route.distanceKm;
        totalTravelTime += route.durationMinutes;
      }

      setState(() {
        _routes = routes;
        _totalDistance = totalDistance;
        _totalTravelTime = totalTravelTime;
        _isCalculatingRoutes = false;

        // Update travel times in stops based on actual routing
        for (int i = 0; i < routes.length && i < _planStops.length - 1; i++) {
          _planStops[i + 1]['travelTime'] = routes[i].durationMinutes;
        }
      });
    } catch (e) {
      debugPrint('Error calculating routes: $e');
      setState(() => _isCalculatingRoutes = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not calculate routes. Using estimated times.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  // Get all route coordinates for polylines
  List<LatLng> _getAllRouteCoordinates() {
    List<LatLng> allCoordinates = [];
    for (final route in _routes) {
      allCoordinates.addAll(route.coordinates);
    }
    return allCoordinates;
  }

  // Optimize route order for shortest travel time
  Future<void> _optimizeRouteOrder() async {
    if (_planStops.length < 3) return;

    setState(() => _isCalculatingRoutes = true);

    try {
      // Get all locations except current location
      final stopsToOptimize = _planStops
          .where((stop) => stop['isCurrentLocation'] != true)
          .toList();

      final currentLocation = _planStops.firstWhere(
              (stop) => stop['isCurrentLocation'] == true,
          orElse: () => {});

      if (stopsToOptimize.length < 2) {
        setState(() => _isCalculatingRoutes = false);
        return;
      }

      // Simple nearest neighbor optimization
      List<Map<String, dynamic>> optimizedStops = [];
      if (currentLocation.isNotEmpty) {
        optimizedStops.add(currentLocation);
      }

      List<Map<String, dynamic>> remaining = List.from(stopsToOptimize);
      LatLng currentPos = currentLocation.isNotEmpty
          ? currentLocation['location'] as LatLng
          : remaining.first['location'] as LatLng;

      // Add first stop if no current location
      if (currentLocation.isEmpty && remaining.isNotEmpty) {
        optimizedStops.add(remaining.removeAt(0));
        currentPos = optimizedStops.last['location'] as LatLng;
      }

      // Nearest neighbor algorithm
      while (remaining.isNotEmpty) {
        int nearestIndex = 0;
        double shortestDistance = double.infinity;

        for (int i = 0; i < remaining.length; i++) {
          final stopLocation = remaining[i]['location'] as LatLng;
          final distance = _calculateDistance(currentPos, stopLocation);

          if (distance < shortestDistance) {
            shortestDistance = distance;
            nearestIndex = i;
          }
        }

        final nearestStop = remaining.removeAt(nearestIndex);
        optimizedStops.add(nearestStop);
        currentPos = nearestStop['location'] as LatLng;
      }

      setState(() {
        _planStops.clear();
        _planStops.addAll(optimizedStops);
        _isCalculatingRoutes = false;
      });

      // Recalculate routes with new order
      await _calculateRoutes();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Route optimized for shortest travel time!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error optimizing route: $e');
      setState(() => _isCalculatingRoutes = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not optimize route. Please try again.'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  // Calculate straight-line distance between two points (Haversine formula)
  double _calculateDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    double lat1Rad = point1.latitude * (3.14159265359 / 180);
    double lat2Rad = point2.latitude * (3.14159265359 / 180);
    double deltaLatRad =
        (point2.latitude - point1.latitude) * (3.14159265359 / 180);
    double deltaLngRad =
        (point2.longitude - point1.longitude) * (3.14159265359 / 180);

    double a = (sin(deltaLatRad / 2) * sin(deltaLatRad / 2)) +
        (cos(lat1Rad) *
            cos(lat2Rad) *
            sin(deltaLngRad / 2) *
            sin(deltaLngRad / 2));
    double c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadius * c;
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
      final existingIndex =
      _planStops.indexWhere((s) => s['isCurrentLocation'] == true);
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
      final response =
      await http.get(Uri.parse("$server/get_trip_plan/${widget.roomCode}"));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        // Backend might return either 'plan' or 'stops' depending on version.
        final rawStops = (data['plan'] ?? data['stops']);
        if (rawStops != null && rawStops is List) {
          // preserve the current location (if any) as the first element
          final cur = _planStops.firstWhere(
                  (s) => s['isCurrentLocation'] == true,
              orElse: () => {});
          final List<Map<String, dynamic>> parsed = [];
          for (var stop in rawStops) {
            try {
              // tolerant parsing of lat/lng (could be string/int/double)
              final dynamic latRaw = stop['lat'] ?? stop['latitude'];
              final dynamic lngRaw = stop['lng'] ?? stop['longitude'];

              double? lat;
              double? lng;

              if (latRaw != null) {
                if (latRaw is double)
                  lat = latRaw;
                else if (latRaw is int)
                  lat = latRaw.toDouble();
                else if (latRaw is String) lat = double.tryParse(latRaw);
              }

              if (lngRaw != null) {
                if (lngRaw is double)
                  lng = lngRaw;
                else if (lngRaw is int)
                  lng = lngRaw.toDouble();
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
            _planStops.removeWhere((s) =>
            s['isCurrentLocation'] != true); // remove non-current stops
            _planStops.addAll(
                parsed); // current location (if present) remains at index 0
          });

          // Automatically calculate routes for the loaded stops
          if (_planStops.length >= 2) {
            _calculateRoutes();
          }
        }
      } else if (response.statusCode == 404) {
        setState(() {
          // no plan found — keep current location (if any) but clear others
          _planStops.removeWhere((s) => s['isCurrentLocation'] != true);
        });
        debugPrint("No existing trip plan found (404).");
      } else {
        debugPrint(
            "Fetch plan failed: ${response.statusCode} ${response.body}");
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                Text('Failed to fetch trip plan (${response.statusCode})')),
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
            decoration:
            const InputDecoration(hintText: "Enter a name for this stop"),
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
                      "timeSpent": 60, // Default 1 hour
                      "travelTime": 15, // Default 15 minutes
                      "notes": "",
                    });
                  });
                  Navigator.pop(context);
                  // Calculate routes after adding new stop
                  _calculateRoutes();
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Server IP not set.')));
      return;
    }

    // Prepare stops while skipping any stop without valid LatLng (and skip the current-location flag if you don't want to save it)
    final stopsPayload =
    _planStops.where((s) => s['location'] is LatLng).map((stop) {
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
      // First save the basic trip plan
      final res = await http.post(
        Uri.parse("$server/trip_plan/${widget.roomCode}"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(planData),
      );

      if (res.statusCode == 200 || res.statusCode == 201) {
        // Now save route data if we have routes calculated
        if (_routes.isNotEmpty) {
          await _saveRouteData(server);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trip plan saved with routes.')));
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
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Error saving trip plan')));
      }
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _saveRouteData(String server) async {
    try {
      // Prepare route data
      final routeData = {
        "routes": _routes
            .map((route) => {
          "from_location": route.coordinates.isNotEmpty
              ? {
            "lat": route.coordinates.first.latitude,
            "lng": route.coordinates.first.longitude,
          }
              : {},
          "to_location": route.coordinates.length > 1
              ? {
            "lat": route.coordinates.last.latitude,
            "lng": route.coordinates.last.longitude,
          }
              : {},
          "coordinates": route.coordinates
              .map((point) => {
            "lat": point.latitude,
            "lng": point.longitude,
          })
              .toList(),
          "distance_km": route.distanceKm,
          "duration_minutes": route.durationMinutes,
          "geometry": route.geometry,
        })
            .toList(),
        "route_summary": {
          "total_distance_km": _totalDistance,
          "total_travel_time_minutes": _totalTravelTime,
          "total_stops": _planStops.length,
          "optimized": _isRoutingOptimized,
          "route_type": "real", // Indicates OSRM routing vs straight line
        },
      };

      final routeRes = await http.post(
        Uri.parse("$server/trip_plan/${widget.roomCode}/routes"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(routeData),
      );

      if (routeRes.statusCode != 200) {
        debugPrint(
            "Route save failed: ${routeRes.statusCode} ${routeRes.body}");
      } else {
        debugPrint("Route data saved successfully");
      }
    } catch (e) {
      debugPrint("Error saving route data: $e");
    }
  }

  void _showAddStopBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildAddStopSheet(),
    );
  }

  Widget _buildAddStopSheet() {
    return Container(
      height: MediaQuery.of(context).size.height * 0.8,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_location_rounded,
                      color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Add New Stop',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.textSecondary),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: 16),
                  if (_suggestions.isEmpty && _searchController.text.isEmpty)
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.search_rounded,
                                size: 48,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Search for Places',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Type a place name, restaurant, or attraction',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else if (_suggestions.isEmpty &&
                      _searchController.text.isNotEmpty &&
                      !_isSearching)
                    const Expanded(
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: AppColors.textSecondary,
                            ),
                            SizedBox(height: 16),
                            Text(
                              'No places found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditSheet(int index) {
    final stop = _planStops[index];
    final isCurrentLocation = stop['isCurrentLocation'] == true;

    if (isCurrentLocation) {
      // Don't allow editing current location
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Current location cannot be edited'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildEditSheet(stop, index),
    );
  }

  Widget _buildEditSheet(Map<String, dynamic> stop, int index) {
    final titleController = TextEditingController(text: stop['title']);
    final timeSpentController =
    TextEditingController(text: stop['timeSpent'].toString());
    final travelTimeController =
    TextEditingController(text: stop['travelTime'].toString());
    final notesController = TextEditingController(text: stop['notes']);

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.edit_location_rounded,
                      color: AppColors.primary),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Edit Stop Details',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _deleteStopWithConfirmation(index);
                  },
                  icon:
                  const Icon(Icons.delete_rounded, color: AppColors.error),
                  tooltip: 'Delete stop',
                ),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFormField(
                    controller: titleController,
                    label: 'Place Name',
                    icon: Icons.place_rounded,
                    hint: 'Enter the place name',
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _buildFormField(
                          controller: timeSpentController,
                          label: 'Time to Spend',
                          icon: Icons.schedule_rounded,
                          hint: 'Minutes',
                          keyboardType: TextInputType.number,
                          suffix: 'min',
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildFormField(
                          controller: travelTimeController,
                          label: 'Travel Time',
                          icon: Icons.directions_walk_rounded,
                          hint: 'Minutes',
                          keyboardType: TextInputType.number,
                          suffix: 'min',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _buildFormField(
                    controller: notesController,
                    label: 'Notes & Plans',
                    icon: Icons.note_rounded,
                    hint:
                    'Add notes, activities, or specific plans for this place...',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: AppColors.textSecondary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () {
                      _updateStop(stop, titleController, timeSpentController,
                          travelTimeController, notesController);
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save Changes',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hint,
    TextInputType? keyboardType,
    String? suffix,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            suffixText: suffix,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
              BorderSide(color: AppColors.textSecondary.withOpacity(0.3)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            filled: true,
            fillColor: AppColors.background,
            contentPadding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  void _updateStop(
      Map<String, dynamic> stop,
      TextEditingController titleController,
      TextEditingController timeSpentController,
      TextEditingController travelTimeController,
      TextEditingController notesController,
      ) {
    setState(() {
      stop['title'] = titleController.text.trim().isNotEmpty
          ? titleController.text.trim()
          : stop['title'];
      stop['name'] = stop['title'];
      stop['timeSpent'] =
          int.tryParse(timeSpentController.text) ?? stop['timeSpent'];
      stop['travelTime'] =
          int.tryParse(travelTimeController.text) ?? stop['travelTime'];
      stop['notes'] = notesController.text.trim();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stop updated successfully'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _deleteStopWithConfirmation(int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_rounded, color: AppColors.error),
            SizedBox(width: 8),
            Text('Delete Stop?'),
          ],
        ),
        content: const Text(
          'Are you sure you want to remove this stop from your trip?',
          style: TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteStop(index);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _deleteStop(int index) {
    setState(() {
      _planStops.removeAt(index);
    });

    // Show simple confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Stop removed from trip'),
        backgroundColor: AppColors.error,
        duration: Duration(seconds: 2),
      ),
    );

    // Recalculate routes for remaining stops
    _calculateRoutesForRemainingStops();

    // Animate FAB
    _cardAnimationController.forward().then((_) {
      _cardAnimationController.reverse();
    });
  }

  Future<void> _calculateRoutesForRemainingStops() async {
    if (_planStops.length < 2) {
      // Clear routes if less than 2 stops
      setState(() {
        _routes.clear();
        _totalDistance = 0.0;
        _totalTravelTime = 0;
      });
      return;
    }

    setState(() {
      _isCalculatingRoutes = true;
    });

    try {
      final validStops =
      _planStops.where((s) => s['location'] is LatLng).toList();
      if (validStops.length >= 2) {
        List<RouteInfo> newRoutes = [];
        double totalDist = 0.0;
        int totalTime = 0;

        for (int i = 0; i < validStops.length - 1; i++) {
          final start = validStops[i]['location'] as LatLng;
          final end = validStops[i + 1]['location'] as LatLng;

          final routeInfo = await RoutingService.getRoute(start, end);
          if (routeInfo != null) {
            newRoutes.add(routeInfo);
            totalDist += routeInfo.distanceKm;
            totalTime += routeInfo.durationMinutes;
          }
        }

        setState(() {
          _routes = newRoutes;
          _totalDistance = totalDist;
          _totalTravelTime = totalTime;
        });
      }
    } catch (e) {
      debugPrint('Error recalculating routes: $e');
    } finally {
      setState(() {
        _isCalculatingRoutes = false;
      });
    }
  }

  // Helper method to format duration
  String _formatDuration(int minutes) {
    if (minutes < 60) {
      return '${minutes}min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      return remainingMinutes > 0
          ? '${hours}h ${remainingMinutes}m'
          : '${hours}h';
    }
  }

  // Helper method to get time of day suggestion
  String _getTimeOfDaySuggestion() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return 'Good morning! Ready to plan your adventure?';
    } else if (hour < 17) {
      return 'Good afternoon! Let\'s plan something amazing!';
    } else {
      return 'Good evening! Time to plan tomorrow\'s journey!';
    }
  }

  // Method to reorder stops (for drag and drop functionality)
  void _reorderStops(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) {
        newIndex -= 1;
      }
      final item = _planStops.removeAt(oldIndex);
      _planStops.insert(newIndex, item);
    });

    // Recalculate routes after reordering
    _calculateRoutesForRemainingStops();

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip order updated'),
        backgroundColor: AppColors.success,
        duration: Duration(seconds: 1),
      ),
    );
  }

  // Method to calculate estimated total distance (placeholder)
  Future<double> _calculateTotalDistance() async {
    // This would integrate with a routing service
    // For now, return a placeholder
    return 0.0;
  }

  // Method to optimize route order with confirmation dialog
  void _optimizeRoute() {
    if (_planStops.length < 3) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.route_rounded, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Optimize Route'),
          ],
        ),
        content: const Text(
          'This will reorder your stops to minimize total travel time using real routing data. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _optimizeRouteOrder();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child:
            const Text('Optimize', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Set<Marker> markers =
    _planStops.where((stop) => stop['location'] is LatLng).map((stop) {
      final LatLng pos = stop['location'] as LatLng;
      final isCurrentLocation = stop['isCurrentLocation'] == true;
      return Marker(
        markerId: MarkerId(stop['id']),
        position: pos,
        icon: isCurrentLocation
            ? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen)
            : BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(
          title: stop['title'],
          snippet:
          isCurrentLocation ? 'Current Location' : 'Tap to edit details',
        ),
      );
    }).toSet();

    // Use actual route coordinates if available, otherwise fall back to straight lines
    final List<LatLng> polylinePoints = _routes.isNotEmpty
        ? _getAllRouteCoordinates()
        : _planStops
        .where((s) => s['location'] is LatLng)
        .map((stop) => stop["location"] as LatLng)
        .toList();

    final Set<Polyline> polylines = polylinePoints.length < 2
        ? {}
        : {
      Polyline(
        polylineId: const PolylineId("trip_route"),
        color: AppColors.primary,
        width: 5,
        patterns: _routes.isNotEmpty
            ? [] // Solid line for actual routes
            : [
          PatternItem.dash(30),
          PatternItem.gap(20)
        ], // Dashed for straight lines
        points: polylinePoints,
      )
    };

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.map, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "Trip Planner",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "Plan your perfect journey",
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (_planStops.length > 2)
            Container(
              margin: const EdgeInsets.only(right: 4),
              decoration: BoxDecoration(
                color: AppColors.accent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: _isCalculatingRoutes
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.route_rounded),
                onPressed: _isCalculatingRoutes ? null : _optimizeRoute,
                tooltip: "Optimize Route Order",
              ),
            ),
          if (_planStops.length > 1)
            Container(
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.circular(20),
              ),
              child: IconButton(
                icon: _isSaving
                    ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
                    : const Icon(Icons.save_rounded),
                onPressed: _isSaving ? null : _savePlan,
                tooltip: "Save Trip Plan",
              ),
            ),
        ],
      ),
      body: _isLoading
          ? _buildLoadingScreen()
          : Column(
        children: [
          _buildSearchBar(),
          Expanded(
            flex: 3,
            child: _buildMapSection(markers, polylines),
          ),
          _buildTripSummary(),
          Expanded(
            flex: 2,
            child: _buildStopsList(),
          ),
        ],
      ),
      floatingActionButton: ScaleTransition(
        scale: _fabAnimation,
        child: FloatingActionButton.extended(
          onPressed: () {
            _searchFocusNode.requestFocus();
          },
          backgroundColor: AppColors.secondary,
          icon: const Icon(Icons.add_location_rounded),
          label: const Text('Add Stop'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildLoadingScreen() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primaryLight, AppColors.primary],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
            SizedBox(height: 24),
            Text(
              'Loading your trip...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Getting your location and trip details',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Search for places to add...',
              hintStyle: TextStyle(color: AppColors.textSecondary),
              prefixIcon:
              const Icon(Icons.search_rounded, color: AppColors.primary),
              suffixIcon: _isSearching
                  ? const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              )
                  : _searchController.text.isNotEmpty
                  ? IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _suggestions.clear());
                },
                icon: const Icon(Icons.clear_rounded),
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(25),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
          if (_suggestions.isNotEmpty) _buildSuggestionsList(),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final suggestion = _suggestions[index];
          return ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getLocationIcon(suggestion.category, suggestion.type),
                size: 20,
                color: AppColors.primary,
              ),
            ),
            title: Text(
              suggestion.name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            subtitle: Text(
              suggestion.displayName,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _addStopFromSuggestion(suggestion),
          );
        },
      ),
    );
  }

  Widget _buildMapSection(Set<Marker> markers, Set<Polyline> polylines) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: _currentLocation == null
            ? _buildLocationWaiting()
            : GoogleMap(
          onMapCreated: (controller) {
            _mapController = controller;
            _fabAnimationController.forward();
          },
          initialCameraPosition: CameraPosition(
            target: _currentLocation!,
            zoom: 13.0,
          ),
          onTap: _addStop,
          markers: markers,
          polylines: polylines,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
        ),
      ),
    );
  }

  Widget _buildLocationWaiting() {
    return Container(
      color: AppColors.primaryLight.withOpacity(0.1),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.location_searching_rounded,
              size: 48,
              color: AppColors.primary,
            ),
            SizedBox(height: 16),
            Text(
              'Finding your location...',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTripSummary() {
    if (_planStops.length < 2) return const SizedBox.shrink();

    final totalTimeSpent = _planStops.fold<int>(
        0, (sum, stop) => sum + (stop['timeSpent'] as int));
    final totalStops = _planStops.length;

    // Use calculated travel time from routes if available
    final totalTravelTime = _routes.isNotEmpty
        ? _totalTravelTime
        : _planStops.fold<int>(
        0, (sum, stop) => sum + (stop['travelTime'] as int));

    final grandTotal = totalTimeSpent + totalTravelTime;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          if (_isCalculatingRoutes)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
                const SizedBox(width: 8),
                Text(
                  'Calculating optimal routes...',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          if (_isCalculatingRoutes) const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildSummaryItem(
                icon: Icons.location_on_rounded,
                label: 'Stops',
                value: '$totalStops',
                color: AppColors.primary,
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.textSecondary.withOpacity(0.3),
              ),
              _buildSummaryItem(
                icon: Icons.access_time_rounded,
                label: 'Total Time',
                value: _formatDuration(grandTotal),
                color: AppColors.secondary,
              ),
              Container(
                width: 1,
                height: 40,
                color: AppColors.textSecondary.withOpacity(0.3),
              ),
              _buildSummaryItem(
                icon: Icons.route_rounded,
                label: 'Distance',
                value: _totalDistance > 0
                    ? '${_totalDistance.toStringAsFixed(1)} km'
                    : (_isCalculatingRoutes ? '...' : 'N/A'),
                color: AppColors.accent,
              ),
            ],
          ),
          if (_routes.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.route, size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  'Routes optimized • Travel: ${_formatDuration(_totalTravelTime)} • Stay: ${_formatDuration(totalTimeSpent)}',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: AppColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStopsList() {
    if (_planStops.isEmpty) {
      return _buildEmptyState();
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.list_rounded, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Your Trip Stops (${_planStops.length})',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _planStops.length,
              onReorder: _reorderStops,
              itemBuilder: (context, index) {
                return Container(
                  key: ValueKey(_planStops[index]['id']),
                  margin: const EdgeInsets.only(bottom: 8),
                  child: _buildStopCard(index),
                );
              },
            ),
          ),
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryLight.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_location_alt_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Start Planning Your Trip!',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap on the map or search for places to add your first stop',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStopCard(int index) {
    final stop = _planStops[index];
    final LatLng? location =
    stop['location'] is LatLng ? stop['location'] as LatLng : null;
    final isCurrentLocation = stop['isCurrentLocation'] == true;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentLocation
              ? AppColors.success
              : AppColors.primary.withOpacity(0.2),
          width: isCurrentLocation ? 2 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showEditSheet(index),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isCurrentLocation
                        ? AppColors.success.withOpacity(0.1)
                        : AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: isCurrentLocation
                        ? const Icon(Icons.my_location_rounded,
                        color: AppColors.success, size: 20)
                        : Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stop['title'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '${stop['timeSpent']}min',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.directions_walk_rounded,
                              size: 14, color: AppColors.textSecondary),
                          const SizedBox(width: 4),
                          Text(
                            '${stop['travelTime']}min',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (stop['notes']?.isNotEmpty == true) ...[
                        const SizedBox(height: 4),
                        Text(
                          stop['notes'],
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!isCurrentLocation)
                  IconButton(
                    onPressed: () => _deleteStop(index),
                    icon: const Icon(Icons.delete_rounded,
                        color: AppColors.error, size: 20),
                    tooltip: 'Remove stop',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getLocationIcon(String? category, String? type) {
    if (category == null && type == null) return Icons.place_rounded;

    final key = '${category ?? ''}_${type ?? ''}'.toLowerCase();

    if (key.contains('restaurant') ||
        key.contains('food') ||
        key.contains('cafe')) {
      return Icons.restaurant_rounded;
    } else if (key.contains('hotel') || key.contains('lodging')) {
      return Icons.hotel_rounded;
    } else if (key.contains('tourism') || key.contains('attraction')) {
      return Icons.attractions_rounded;
    } else if (key.contains('shop') || key.contains('mall')) {
      return Icons.shopping_bag_rounded;
    } else if (key.contains('hospital') || key.contains('medical')) {
      return Icons.local_hospital_rounded;
    } else if (key.contains('school') || key.contains('university')) {
      return Icons.school_rounded;
    } else if (key.contains('park') || key.contains('garden')) {
      return Icons.park_rounded;
    } else if (key.contains('church') ||
        key.contains('temple') ||
        key.contains('mosque')) {
      return Icons.church_rounded;
    } else {
      return Icons.place_rounded;
    }
  }
}
