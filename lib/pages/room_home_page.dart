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
import 'location_page.dart';
import 'sos_page.dart';
import 'trip_plan_page.dart';
class RoomHomePage extends StatefulWidget {
  final String roomCode;
  const RoomHomePage({super.key, required this.roomCode});

  @override
  State<RoomHomePage> createState() => _RoomHomePageState();
}

class _RoomHomePageState extends State<RoomHomePage>
    with SingleTickerProviderStateMixin {
  IO.Socket? socket;
  Map<String, dynamic> users = {};
  Map<String, String> usernames = {};
  String? myRole;
  String? myUserId;

  Timer? locationTimer;
  Timer? tripTimer;
  Duration tripDuration = Duration.zero;
  DateTime? tripStartTime;

  String tripStatus = "upcoming"; // upcoming | ongoing | finished
  bool loading = true;

  int _selectedIndex = 0;

  final List<String> _titles = [
    "Live Location",
    "Chat",
    "Features",
    "SOS",
  ];

  // SOS
  List<Map<String, dynamic>> sosLogs = [];
  bool mySOSActive = false;

  late AnimationController _blinkController;
  late Animation<double> _blinkAnimation;

  @override
  void initState() {
    super.initState();
    _fetchRoomDetails(); // fetch initial details
    _connectSocket();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _blinkAnimation =
        Tween<double>(begin: 1.0, end: 0.3).animate(_blinkController);
  }

  // Fetch initial room details
  Future<void> _fetchRoomDetails() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    try {
      final res = await http.get(Uri.parse("$server/room_details/${widget.roomCode}"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);

        setState(() {
          // // ✅ Update members if backend sends them
          // if (data["members"] != null) {
          //   _updateMembers(List<Map<String, dynamic>>.from(data["members"]));
          // }

          // ✅ Trip status
          tripStatus = data["status"] ?? "upcoming";

          if (tripStatus == "ongoing" && data["start_date"] != null) {
            tripStartTime = DateTime.tryParse(data["start_date"]);
            if (tripStartTime != null) {
              _startTripTimer();
            }
          }


          if (tripStatus == "finished") {
            tripStartTime = null;
            tripDuration = Duration.zero;
          }

          // ✅ Optional: Handle end_date if you need it
          if (data["end_date"] != null) {
            final endDate = DateTime.tryParse(data["end_date"]);
            if (endDate != null && tripStartTime != null) {
              tripDuration = endDate.difference(tripStartTime!);
            }
          }
        });
      }
    } catch (e) {
      print("Room details fetch error: $e");
    }
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

    socket!.on("members_update", (data) {
      _updateMembers(data["members"]);
    });

    socket!.on("location_update", (data) {
      _updateMembers(data["members"]);
    });

    socket!.on("sos_alert", (data) {
      _handleSosAlert(data);
    });

    socket!.on("sos_stopped", (data) {
      _handleSosStop(data);
    });

    socket!.on("trip_started", (data) {
      DateTime? start;
      final ts = data["timestamp"];

      if (ts is int) {
        // backend sent epoch milliseconds
        start = DateTime.fromMillisecondsSinceEpoch(ts);
      } else if (ts is String) {
        // backend sent ISO8601 string
        start = DateTime.tryParse(ts);
      }

      setState(() {
        tripStatus = "ongoing";
        tripStartTime = start ?? DateTime.now();
      });

      _startTripTimer();
    });


    socket!.on("trip_ended", (_) {
      setState(() {
        tripStatus = "finished";
      });
      tripTimer?.cancel();
      locationTimer?.cancel();
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

  // ========= Trip Control =========
  void _startTrip() async {
    if (tripStatus == "ongoing") return;

    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final res = await http.post(Uri.parse("$server/start_trip/${widget.roomCode}"));

    if (res.statusCode == 200) {
      setState(() {
        tripStatus = "ongoing";
        tripStartTime = DateTime.now(); // until backend confirms
      });
      _startTripTimer();
      _startLocationUpdates();
    }
  }

  void _endTrip() async {
    if (tripStatus != "ongoing") return;

    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final res = await http.post(Uri.parse("$server/end_trip/${widget.roomCode}"));

    if (res.statusCode == 200) {
      setState(() {
        tripStatus = "finished";
      });
      tripTimer?.cancel();
      locationTimer?.cancel();
    }
  }

  void _startTripTimer() {
    tripTimer?.cancel();
    if (tripStartTime != null) {
      tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() {
          tripDuration = DateTime.now().difference(tripStartTime!);
        });
      });
    }
  }

  void _startLocationUpdates() {
    locationTimer?.cancel();
    locationTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      try {
        Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );
        socket?.emit("send_location", {
          "user_id": myUserId,
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

  // ========= SOS =========
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

    if (await Vibration.hasVibrator() ?? false) {
      Vibration.vibrate(pattern: [0, 500, 250, 500, 250, 500], repeat: 0);
    }

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
                Vibration.cancel();
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
    tripTimer?.cancel();
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
        tripStatus: tripStatus,
      ),
      ChatPage(roomCode: widget.roomCode, userMap: usernames),
      _buildFeaturesPage(),
      SOSPage(
        roomCode: widget.roomCode,
        sosLogs: sosLogs,
        mySOSActive: mySOSActive,
        onToggleSOS: _toggleSOS,
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
            "Room: ${widget.roomCode} - ${_titles[_selectedIndex]} (${tripStatus.toUpperCase()})"),
        actions: [
          if (tripStatus == "ongoing")
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Center(
                  child: Text(
                    _formatDuration(tripDuration),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  )),
            )
        ],
      ),
      body: pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
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
        ElevatedButton.icon(
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TripPlanPage(roomCode: widget.roomCode),
              ),
            );
          },
          icon: const Icon(Icons.map),
          label: const Text("Travel Plan"),
        ),
        if (tripStatus == "upcoming")
          ElevatedButton.icon(
            onPressed: _startTrip,
            icon: const Icon(Icons.play_arrow),
            label: const Text("Start Trip"),
          )
        else if (tripStatus == "ongoing")
          ElevatedButton.icon(
            onPressed: _endTrip,
            icon: const Icon(Icons.stop),
            label: const Text("End Trip"),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
          )
        else if (tripStatus == "finished")
            const Text(
              "✅ Trip has ended",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
      ],
    );
  }


  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final h = twoDigits(d.inHours);
    final m = twoDigits(d.inMinutes.remainder(60));
    final s = twoDigits(d.inSeconds.remainder(60));
    return "$h:$m:$s";
  }
}
