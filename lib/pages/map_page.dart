// pages/map_page.dart
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class MapPage extends StatefulWidget {
  final Map<String, dynamic> users;
  final Map<String, String> usernames;
  const MapPage({super.key, required this.users, required this.usernames});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  // Use a Completer to get a reference to the GoogleMapController.
  late GoogleMapController _mapController;
  Set<Marker> _markers = {};

  @override
  void initState() {
    super.initState();
    _buildMarkers();
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
    Set<Marker> markers = {};
    widget.users.forEach((userId, userData) {
      if (userData != null) {
        final role = userData["role"] ?? "member";
        final loc = userData["last_location"];

        if (loc != null && loc["lat"] != null && loc["lng"] != null) {
          final lat = (loc["lat"] as num).toDouble();
          final lng = (loc["lng"] as num).toDouble();
          final username = widget.usernames[userId] ?? userId;

          markers.add(
            Marker(
              markerId: MarkerId(userId), // Use a unique ID for the marker
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(
                title: "$username ($role)",
                snippet: "Lat: $lat, Lng: $lng",
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                role == "admin" ? BitmapDescriptor.hueBlue : BitmapDescriptor.hueRed,
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
      if (_markers.isEmpty) return;

      final points = _markers.map((m) => m.position).toList();

      if (points.length > 1) {
        final bounds = LatLngBounds(
          southwest: LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a < b ? a : b),
            points.map((p) => p.longitude).reduce((a, b) => a < b ? a : b),
          ),
          northeast: LatLng(
            points.map((p) => p.latitude).reduce((a, b) => a > b ? a : b),
            points.map((p) => p.longitude).reduce((a, b) => a > b ? a : b),
          ),
        );
        _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
      } else if (points.isNotEmpty) {
        _mapController.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: points.first,
              zoom: 15,
            ),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Map View")),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(20.5937, 78.9629), // Center on India
          zoom: 5.0,
        ),
        onMapCreated: (controller) {
          _mapController = controller;
          _fitBoundsToMarkers();
        },
        markers: _markers,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
      ),
    );
  }
}