// pages/location_page.dart
import 'package:flutter/material.dart';
import 'map_page.dart';

class LocationPage extends StatelessWidget {
  final String roomCode;
  final Map<String, dynamic> users;
  final Map<String, String> usernames;
  final bool loading;
  final String tripStatus; // <- get from parent (RoomHomePage)

  const LocationPage({
    super.key,
    required this.roomCode,
    required this.users,
    required this.usernames,
    required this.loading,
    required this.tripStatus,
  });

  void _openMapPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapPage(users: users, usernames: usernames),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (tripStatus == "upcoming") {
      return const Center(
        child: Text(
          "Start the trip to track your colleagues live...",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      );
    }

    if (tripStatus == "finished") {
      return const Center(
        child: Text(
          "Trip has ended.",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Ongoing trip
    return loading
        ? const Center(child: CircularProgressIndicator())
        : users.isEmpty
        ? const Center(child: Text("No members yet..."))
        : Column(
      children: [
        Expanded(
          child: ListView(
            children: users.entries.map((e) {
              final userId = e.key;
              final role = e.value["role"];
              final loc = e.value["last_location"];
              final uname = usernames[userId] ?? "Loading...";
              return ListTile(
                title: Text("$uname ($role)"),
                subtitle: loc == null
                    ? const Text("No location shared yet")
                    : Text(
                  "Lat: ${loc["lat"]}, Lng: ${loc["lng"]}\nUpdated: ${loc["timestamp"]}",
                ),
              );
            }).toList(),
          ),
        ),
        ElevatedButton.icon(
          onPressed: () => _openMapPage(context),
          icon: const Icon(Icons.map),
          label: const Text("View on Map"),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
