// lib/pages/place_search_sheet.dart

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

class PlaceSearchSheet extends StatefulWidget {
  final Function(String, LatLng) onPlaceSelected;
  final String apiKey;
  const PlaceSearchSheet({super.key, required this.onPlaceSelected, required this.apiKey});

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Uuid _uuid = const Uuid();
  List _predictions = [];
  Timer? _debounce;
  String? _sessionToken;

  @override
  void initState() {
    super.initState();
    _sessionToken = _uuid.v4();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    print("change seen"+_searchController.text);
    if (_debounce?.isActive ?? false) _debounce!.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (_searchController.text.isNotEmpty) {
        _fetchAutocompletePredictions(_searchController.text);
      } else {
        setState(() => _predictions = []);
      }
    });
  }

  Future<void> _fetchAutocompletePredictions(String query) async {
    print("REceived request");
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json?input=$query&key=${widget.apiKey}&sessiontoken=$_sessionToken');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      print(data);
      if (data['predictions'] != null) {
        setState(() {
          _predictions = data['predictions'];
        });
      }
      else{
        print("Prediction response is empty");
      }
    }
    else{
      print("error in response");
    }
  }

  Future<void> _fetchPlaceDetails(String placeId) async {
    final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=${widget.apiKey}&sessiontoken=$_sessionToken&fields=geometry');
    final response = await http.get(url);

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final location = data['result']['geometry']['location'];
      final LatLng latLng = LatLng(location['lat'], location['lng']);

      _sessionToken = _uuid.v4();

      widget.onPlaceSelected(
          _predictions.firstWhere((p) => p['place_id'] == placeId)['description'],
          latLng);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              labelText: "Search Location",
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.search),
            ),
          ),
          const SizedBox(height: 10),
          // Expanded widget is crucial for the ListView to render correctly
          Expanded(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _predictions.length,
              itemBuilder: (context, index) {
                final prediction = _predictions[index];
                return ListTile(
                  title: Text(prediction['description']),
                  onTap: () {
                    _fetchPlaceDetails(prediction['place_id']);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}