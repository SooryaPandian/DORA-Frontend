// pages/room_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'location_page.dart';

class RoomPage extends StatefulWidget {
  @override
  _RoomPageState createState() => _RoomPageState();
}

class _RoomPageState extends State<RoomPage> {
  final TextEditingController _roomName = TextEditingController();
  final TextEditingController _joinCode = TextEditingController();

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
        "start_date": DateTime.now().toUtc().toIso8601String(), // required by backend
        "end_date": null
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      _goToLocationPage(data["room_code"]);
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
      _goToLocationPage(_joinCode.text);
    } else {
      _showError("Failed to join room");
    }
  }

  void _goToLocationPage(String code) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LocationPage(roomCode: code)),
    );
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Create / Join Room")),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
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
          ],
        ),
      ),
    );
  }
}
