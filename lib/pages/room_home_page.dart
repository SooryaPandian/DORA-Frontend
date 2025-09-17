// pages/room_home_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';

import 'chat_page.dart';
import 'map_page.dart';
import 'location_page.dart';
import 'sos_page.dart';

class RoomHomePage extends StatefulWidget {
  final String roomCode;
  const RoomHomePage({super.key, required this.roomCode});

  @override
  State<RoomHomePage> createState() => _RoomHomePageState();
}

class _RoomHomePageState extends State<RoomHomePage>
    with SingleTickerProviderStateMixin {
  IO.Socket? socket;
  Map<String, dynamic> users = {}; // { user_id: {role, last_location} }
  Map<String, String> usernames = {}; // { user_id: username }
  String? myRole;
  String? myUserId;
  Timer? locationTimer;
  bool loading = true;

  int _selectedIndex = 0;

  final List<String> _titles = [
    "Live Location",
    "Chat",
    "Features",
    "SOS",
  ];

  // SOS state
  List<Map<String, dynamic>> sosLogs = [];
  bool mySOSActive = false;

  // Animation for blinking SOS alerts
  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _connectSocket();
    _startLocationUpdates();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _blinkAnimation =
        Tween<double>(begin: 1.0, end: 0.3).animate(_blinkController);
  }

  void _connectSocket() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final userId = prefs.getString("user_id") ?? "";
    myUserId = userId;

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

    // === Location ===
    socket!.on("members_update", (data) {
      _updateMembers(data["members"]);
    });

    socket!.on("location_update", (data) {
      _updateMembers(data["members"]);
    });

    // === SOS Events ===
    socket!.on("sos_alert", (data) {
      _handleSosAlert(data);
    });

    socket!.on("sos_stopped", (data) {
      _handleSosStop(data);
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

    locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        socket?.emit("send_location", {
          "user_id": userId,
          "room_code": widget.roomCode,
          "role": myRole ?? "member",
          "lat": pos.latitude,
          "lng": pos.longitude,
        });
      } catch (e) {
        print("Location error: $e");
      }
    });
  }

  // === SOS handling ===
  void _toggleSOS() {
    if (mySOSActive) {
      _stopSOS();
    } else {
      _sendSOS();
    }
  }

  void _sendSOS() {
    if (myUserId == null) return;
    socket?.emit("send_sos", {
      "user_id": myUserId,
      "room_code": widget.roomCode,
    });
    setState(() => mySOSActive = true);
  }

  void _stopSOS() {
    if (myUserId == null) return;
    socket?.emit("stop_sos", {
      "user_id": myUserId,
      "room_code": widget.roomCode,
    });
    setState(() => mySOSActive = false);
  }

  void _handleSosAlert(dynamic data) async {
    final uid = data["user_id"];
    final alert = data["alert"];
    final ts = alert["timestamp"];

    setState(() {
      sosLogs.add({
        "user_id": uid,
        "username": usernames[uid] ?? uid,
        "timestamp": ts,
        "active": true,
      });
    });

    // Vibrate device
    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 500, 250, 500, 250, 500], repeat: 0);
    }

    // Show popup
    if (mounted) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("🚨 SOS Alert!"),
          content: Text("${usernames[uid] ?? uid} has triggered an SOS!"),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                Vibration.cancel(); // ✅ stop vibration when closing popup
              },
              child: const Text("Close"),
            ),
          ],
        ),
      );
    }
  }

  void _handleSosStop(dynamic data) {
    final uid = data["user_id"];
    setState(() {
      for (var log in sosLogs) {
        if (log["user_id"] == uid && log["active"] == true) {
          log["active"] = false;
        }
      }
    });
    if (uid == myUserId) {
      mySOSActive = false;
    }
    Vibration.cancel();
  }

  @override
  void dispose() {
    socket?.disconnect();
    socket?.dispose();
    locationTimer?.cancel();
    _blinkController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      LocationPage(
        roomCode: widget.roomCode,
        users: users,
        usernames: usernames,
        loading: loading,
      ),
      ChatPage(roomCode: widget.roomCode, userMap: usernames),
      _buildFeaturesPage(),
      SOSPage(
        sosLogs: sosLogs,
        mySOSActive: mySOSActive,
        onToggleSOS: _toggleSOS,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text("Room: ${widget.roomCode} - ${_titles[_selectedIndex]}"),
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: Colors.white, // background of navbar
        selectedItemColor: Colors.blue, // active icon color
        unselectedItemColor: Colors.grey, // inactive icon color
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: "Location",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.chat),
            label: "Chat",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.menu),
            label: "Features",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.sos),
            label: "SOS",
          ),
        ],
      ),

    );
  }

  Widget _buildFeaturesPage() {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      children: [
        _featureButton(Icons.travel_explore, "Travel Plan", () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Travel Plan tapped")),
          );
        }),
        _featureButton(Icons.play_arrow, "Start Trip", () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Trip Started")),
          );
        }),
        _featureButton(Icons.stop, "End Trip", () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Trip Ended")),
          );
        }),
      ],
    );
  }

  Widget _featureButton(IconData icon, String label, VoidCallback onTap) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.blue),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}
