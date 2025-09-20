// pages/room_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'room_home_page.dart';

class RoomPage extends StatefulWidget {
  @override
  _RoomPageState createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final TextEditingController _roomName = TextEditingController();
  final TextEditingController _joinCode = TextEditingController();

  List<dynamic> _rooms = [];
  bool _loadingRooms = true;

  @override
  void initState() {
    super.initState();
    _fetchUserRooms();
  }

  Future<void> _fetchUserRooms() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final userId = prefs.getString("user_id");

    if (userId == null) return;

    try {
      final res = await http.get(Uri.parse("$server/user/$userId/rooms"));
      if (res.statusCode == 200) {
        setState(() {
          _rooms = jsonDecode(res.body);
          _loadingRooms = false;
        });
      } else {
        setState(() => _loadingRooms = false);
      }
    } catch (e) {
      setState(() => _loadingRooms = false);
    }
  }

  void _createRoom() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final userId = prefs.getString("user_id");

    if (_roomName.text.isEmpty || userId == null) return;

    final res = await http.post(
      Uri.parse("$server/create_room"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "name": _roomName.text,
        "user_id": userId,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _goToRoomHomePage(data["room_code"]);
    } else {
      _showError("Failed to create room");
    }
  }

  void _joinRoom() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final userId = prefs.getString("user_id");

    if (_joinCode.text.isEmpty || userId == null) return;

    final res = await http.post(
      Uri.parse("$server/join_room/${_joinCode.text}"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"user_id": userId}),
    );

    if (res.statusCode == 200) {
      _goToRoomHomePage(_joinCode.text);
    } else {
      _showError("Failed to join room");
    }
  }

  void _goToRoomHomePage(String code) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => RoomHomePage(roomCode: code),
      ),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "ongoing":
        return Colors.green.shade100;
      case "finished":
        return Colors.red.shade100;
      default:
        return Colors.blue.shade100;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Create / Join Room")),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Create / Join section
            TextField(
              controller: _roomName,
              decoration: InputDecoration(labelText: "Room Name"),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _createRoom,
              child: Text("Create Room"),
            ),
            Divider(),
            TextField(
              controller: _joinCode,
              decoration: InputDecoration(labelText: "Room Code"),
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _joinRoom,
              child: Text("Join Room"),
            ),
            SizedBox(height: 24),

            // Room list
            Text("Your Rooms",
                style: Theme.of(context).textTheme.headlineMedium),
            SizedBox(height: 12),
            _loadingRooms
                ? Center(child: CircularProgressIndicator())
                : _rooms.isEmpty
                ? Text("No rooms joined yet.")
                : Column(
              children: _rooms.map((room) {
                final status = room["status"];
                final startDate = room["start_date"];
                final endDate = room["end_date"];
                final createdAt = room["created_at"];

                String subtitle = "";
                if (status == "ongoing" && startDate != null) {
                  subtitle = "Started: ${DateTime.parse(startDate).toLocal()}";
                } else if (status == "finished" && startDate != null) {
                  subtitle =
                  "Started: ${DateTime.parse(startDate).toLocal()}\nEnded: ${endDate != null ? DateTime.parse(endDate).toLocal() : "N/A"}";
                } else if (status == "upcoming") {
                  subtitle = "Created: ${DateTime.parse(createdAt).toLocal()}";
                }

                return Card(
                  color: _getStatusColor(status),
                  child: ListTile(
                    title: Text(room["name"]),
                    subtitle: Text(subtitle),
                    trailing: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onTap: () => _goToRoomHomePage(room["code"]),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}
