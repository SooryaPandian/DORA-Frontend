// pages/room_home_page.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
    with TickerProviderStateMixin {
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
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _fetchRoomDetails();
    _connectSocket();

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _blinkAnimation =
        Tween<double>(begin: 1.0, end: 0.3).animate(_blinkController);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));
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
          tripStatus = data["status"] ?? "upcoming";
          if (tripStatus == "ongoing") {
            _startLocationUpdates();
          }
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
        start = DateTime.fromMillisecondsSinceEpoch(ts);
      } else if (ts is String) {
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

    HapticFeedback.mediumImpact();

    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";
    final res = await http.post(Uri.parse("$server/start_trip/${widget.roomCode}"));

    if (res.statusCode == 200) {
      setState(() {
        tripStatus = "ongoing";
        tripStartTime = DateTime.now();
      });
      _startTripTimer();
      _startLocationUpdates();
    }
  }

  void _endTrip() async {
    if (tripStatus != "ongoing") return;

    HapticFeedback.mediumImpact();

    // Show confirmation dialog
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('End Trip?'),
        content: const Text('Are you sure you want to end the current trip?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
    HapticFeedback.heavyImpact();
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: Colors.red.shade50,
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.red.shade700, size: 28),
              const SizedBox(width: 8),
              const Text("SOS Alert!", style: TextStyle(color: Colors.red)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.emergency, size: 50, color: Colors.red.shade400),
              const SizedBox(height: 16),
              Text(
                "${usernames[uid] ?? uid} has triggered an SOS!",
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Vibration.cancel();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
    _pulseController.dispose();
    super.dispose();
  }

  void _onItemTapped(int index) {
    HapticFeedback.lightImpact();
    setState(() => _selectedIndex = index);
  }

  Color _getStatusColor() {
    switch (tripStatus) {
      case "ongoing":
        return Colors.green;
      case "finished":
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  IconData _getStatusIcon() {
    switch (tripStatus) {
      case "ongoing":
        return Icons.directions_car;
      case "finished":
        return Icons.check_circle;
      default:
        return Icons.schedule;
    }
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
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titles[_selectedIndex],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              "Room: ${widget.roomCode}",
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12, top: 8, bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _getStatusColor().withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _getStatusColor().withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getStatusIcon(),
                  size: 16,
                  color: _getStatusColor(),
                ),
                const SizedBox(width: 6),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tripStatus.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: _getStatusColor(),
                      ),
                    ),
                    if (tripStatus == "ongoing")
                      Text(
                        _formatDuration(tripDuration),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: pages[_selectedIndex],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.location_on, "Location"),
                _buildNavItem(1, Icons.chat_bubble_outline, "Chat"),
                _buildNavItem(2, Icons.dashboard_outlined, "Features"),
                _buildSosNavItem(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final isSelected = _selectedIndex == index;
    return GestureDetector(
      onTap: () => _onItemTapped(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Theme.of(context).primaryColor : Colors.grey[600],
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSosNavItem() {
    final isSelected = _selectedIndex == 3;
    final hasActiveSos = sosLogs.any((log) => log["active"] == true);

    return GestureDetector(
      onTap: () => _onItemTapped(3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 12,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.red.withOpacity(0.1)
              : hasActiveSos
              ? Colors.red.withOpacity(0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: hasActiveSos
              ? Border.all(color: Colors.red.withOpacity(0.3), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            hasActiveSos
                ? AnimatedBuilder(
              animation: _blinkAnimation,
              builder: (context, child) {
                return Opacity(
                  opacity: _blinkAnimation.value,
                  child: Icon(
                    Icons.emergency,
                    color: Colors.red,
                    size: 24,
                  ),
                );
              },
            )
                : Icon(
              Icons.sos_outlined,
              color: isSelected ? Colors.red : Colors.grey[600],
              size: 24,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                "SOS",
                style: TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesPage() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white,
            Colors.grey[50]!,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trip Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: tripStatus == "ongoing"
                      ? [Colors.green.shade400, Colors.green.shade600]
                      : tripStatus == "finished"
                      ? [Colors.grey.shade400, Colors.grey.shade600]
                      : [Colors.orange.shade400, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: _getStatusColor().withOpacity(0.3),
                    blurRadius: 15,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getStatusIcon(),
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Trip Status",
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              tripStatus == "ongoing"
                                  ? "Trip in Progress"
                                  : tripStatus == "finished"
                                  ? "Trip Completed"
                                  : "Ready to Start",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (tripStatus == "ongoing") ...[
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.timer, color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            _formatDuration(tripDuration),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Quick Actions
            Text(
              "Quick Actions",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 16),

            // Action Cards Grid
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.2,
              children: [
                _buildFeatureCard(
                  icon: Icons.map_outlined,
                  title: "Travel Plan",
                  subtitle: "View itinerary",
                  color: Colors.blue,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TripPlanPage(roomCode: widget.roomCode),
                      ),
                    );
                  },
                ),
                if (tripStatus == "upcoming")
                  _buildFeatureCard(
                    icon: Icons.play_circle_outline,
                    title: "Start Trip",
                    subtitle: "Begin journey",
                    color: Colors.green,
                    onTap: _startTrip,
                    isPrimary: true,
                  )
                else if (tripStatus == "ongoing")
                  AnimatedBuilder(
                    animation: _pulseAnimation,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulseAnimation.value,
                        child: _buildFeatureCard(
                          icon: Icons.stop_circle_outlined,
                          title: "End Trip",
                          subtitle: "Complete journey",
                          color: Colors.red,
                          onTap: _endTrip,
                          isPrimary: true,
                        ),
                      );
                    },
                  )
                else
                  _buildFeatureCard(
                    icon: Icons.check_circle_outline,
                    title: "Completed",
                    subtitle: "Trip finished",
                    color: Colors.grey,
                    onTap: null,
                  ),
                _buildFeatureCard(
                  icon: Icons.people_outline,
                  title: "Members",
                  subtitle: "${users.length} active",
                  color: Colors.purple,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    setState(() => _selectedIndex = 0);
                  },
                ),
                _buildFeatureCard(
                  icon: Icons.settings_outlined,
                  title: "Settings",
                  subtitle: "Room config",
                  color: Colors.orange,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    // Navigate to settings
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Room Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        "Room Information",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildInfoRow("Room Code", widget.roomCode),
                  _buildInfoRow("Members", "${users.length}"),
                  _buildInfoRow("Your Role", myRole ?? "Member"),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback? onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey[200] : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: isPrimary
              ? Border.all(color: color.withOpacity(0.3), width: 2)
              : null,
          boxShadow: onTap == null
              ? []
              : [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(onTap == null ? 0.1 : 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  icon,
                  color: onTap == null ? Colors.grey : color,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: onTap == null ? Colors.grey : Colors.grey[800],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 14,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
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