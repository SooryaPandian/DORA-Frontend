// pages/location_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'register_page.dart';
import 'map_page.dart';

class LocationPage extends StatefulWidget {
  final String roomCode;
  LocationPage({required this.roomCode});

  @override
  _LocationPageState createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  IO.Socket? socket;
  Map<String, dynamic> users = {};     // { user_id: {role, last_location} }
  Map<String, String> usernames = {};  // { user_id: username }
  bool loading = true;
  bool refreshing = false;
  Timer? locationTimer;
  String? myRole;

  @override
  void initState() {
    super.initState();
    _connectSocket();
    _startLocationUpdates();
  }

  void _connectSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final userId = prefs.getString("user_id") ?? "";

    socket = IO.io(server, <String, dynamic>{
      "transports": ["websocket"],
      "autoConnect": false,
      "forceNew": true,
    });

    socket!.connect();

    socket!.onConnect((_) {
      socket!.emit("join_socket_room", {
        "user_id": userId,
        "room_code": widget.roomCode,
      });
      setState(() => loading = false);
    });

    socket!.on("members_update", (data) {
      _updateMembers(data["members"]);
    });

    socket!.on("location_update", (data) {
      _updateMembers(data["members"]);
    });
  }

  void _updateMembers(List<dynamic> members) {
    setState(() {
      for (var m in members) {
        final uid = m["user_id"];
        final role = m["role"] ?? "member";
        users[uid] = {
          "role": role,
          "last_location": m["last_location"],
        };

        // Save my role for sending with location updates
        final prefsUserId = users.keys.contains(uid) ? uid : null;
        if (prefsUserId != null) {
          myRole = role;
        }

        // Fetch username if missing
        if (!usernames.containsKey(uid)) {
          _fetchUsername(uid);
        }
      }
    });
  }

  Future<void> _fetchUsername(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    try {
      final res = await http.get(Uri.parse("$server/user/$userId"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          usernames[userId] = data["username"];
        });
      }
    } catch (e) {
      print("Username fetch error: $e");
    }
  }

  void _startLocationUpdates() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString("user_id") ?? "";

    locationTimer = Timer.periodic(Duration(seconds: 5), (timer) async {
      setState(() => refreshing = true);

      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        socket?.emit("send_location", {
          "user_id": userId,
          "room_code": widget.roomCode,
          "role": myRole ?? "member", // 🔹 send role too
          "lat": pos.latitude,
          "lng": pos.longitude,
        });
      } catch (e) {
        print("Location error: $e");
      }

      Future.delayed(Duration(seconds: 1), () {
        if (mounted) setState(() => refreshing = false);
      });
    });
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    socket?.disconnect();
    socket?.dispose();
    locationTimer?.cancel();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => RegisterPage()),
          (route) => false,
    );
  }

  @override
  void dispose() {
    socket?.disconnect();
    socket?.dispose();
    locationTimer?.cancel();
    super.dispose();
  }

  void _openMapPage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MapPage(users: users,usernames:usernames),
      ),
    ).then((_) {
      // Reconnect after returning
      socket?.connect();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Room: ${widget.roomCode}"),
        actions: [
          IconButton(icon: Icon(Icons.map), onPressed: _openMapPage),
          refreshing
              ? Padding(
            padding: EdgeInsets.only(right: 16),
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            ),
          )
              : SizedBox.shrink(),
          IconButton(icon: Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: loading
          ? Center(child: CircularProgressIndicator())
          : users.isEmpty
          ? Center(child: Text("No members yet..."))
          : ListView(
        children: users.entries.map((e) {
          final userId = e.key;
          final role = e.value["role"];
          final loc = e.value["last_location"];
          final uname = usernames[userId] ?? "Loading...";
          return ListTile(
            title: Text("$uname ($role)"),
            subtitle: loc == null
                ? Text("No location shared yet")
                : Text(
                "Lat: ${loc["lat"]}, Lng: ${loc["lng"]}\nUpdated: ${loc["timestamp"]}"),
          );
        }).toList(),
      ),
    );
  }
}
