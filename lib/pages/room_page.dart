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

class _RoomPageState extends State<RoomPage> with SingleTickerProviderStateMixin {
  final TextEditingController _roomName = TextEditingController();
  final TextEditingController _joinCode = TextEditingController();
  late TabController _tabController;

  List<dynamic> _rooms = [];
  bool _loadingRooms = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _fetchUserRooms();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red.shade400,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case "ongoing":
        return Colors.green.shade50;
      case "finished":
        return Colors.grey.shade50;
      default:
        return Colors.blue.shade50;
    }
  }

  Color _getStatusAccentColor(String status) {
    switch (status) {
      case "ongoing":
        return Colors.green;
      case "finished":
        return Colors.grey;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case "ongoing":
        return Icons.play_circle_filled;
      case "finished":
        return Icons.check_circle;
      default:
        return Icons.schedule;
    }
  }

  Widget _buildCreateRoomTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.add_circle_outline,
            size: 80,
            color: Theme.of(context).primaryColor.withOpacity(0.7),
          ),
          SizedBox(height: 24),
          Text(
            "Create a New Room",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Start a new session and invite others to join",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _roomName,
              decoration: InputDecoration(
                labelText: "Room Name",
                prefixIcon: Icon(Icons.meeting_room),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
            ),
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _createRoom,
            icon: Icon(Icons.add),
            label: Text("Create Room"),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinRoomTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.login,
            size: 80,
            color: Theme.of(context).primaryColor.withOpacity(0.7),
          ),
          SizedBox(height: 24),
          Text(
            "Join an Existing Room",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).primaryColor,
            ),
          ),
          SizedBox(height: 8),
          Text(
            "Enter the room code to join an ongoing session",
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.grey.shade600,
            ),
          ),
          SizedBox(height: 32),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: TextField(
              controller: _joinCode,
              decoration: InputDecoration(
                labelText: "Room Code",
                prefixIcon: Icon(Icons.vpn_key),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              textCapitalization: TextCapitalization.characters,
            ),
          ),
          SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _joinRoom,
            icon: Icon(Icons.login),
            label: Text("Join Room"),
            style: ElevatedButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomsList() {
    return RefreshIndicator(
      onRefresh: _fetchUserRooms,
      child: SingleChildScrollView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, color: Theme.of(context).primaryColor),
                SizedBox(width: 8),
                Text(
                  "Your Rooms",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            SizedBox(height: 16),
            _loadingRooms
                ? Center(
              child: Column(
                children: [
                  SizedBox(height: 50),
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text("Loading your rooms..."),
                ],
              ),
            )
                : _rooms.isEmpty
                ? Center(
              child: Column(
                children: [
                  SizedBox(height: 50),
                  Icon(
                    Icons.inbox_outlined,
                    size: 80,
                    color: Colors.grey.shade400,
                  ),
                  SizedBox(height: 16),
                  Text(
                    "No rooms joined yet",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Create or join a room to get started",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
                : Column(
              children: _rooms.map((room) {
                final status = room["status"];
                final startDate = room["start_date"];
                final endDate = room["end_date"];
                final createdAt = room["created_at"];

                String subtitle = "";
                String timeInfo = "";
                if (status == "ongoing" && startDate != null) {
                  final start = DateTime.parse(startDate).toLocal();
                  subtitle = "Started";
                  timeInfo = "${start.day}/${start.month}/${start.year} at ${start.hour}:${start.minute.toString().padLeft(2, '0')}";
                } else if (status == "finished" && startDate != null) {
                  final start = DateTime.parse(startDate).toLocal();
                  subtitle = "Completed";
                  timeInfo = "${start.day}/${start.month}/${start.year}";
                  if (endDate != null) {
                    final end = DateTime.parse(endDate).toLocal();
                    timeInfo += " - ${end.day}/${end.month}/${end.year}";
                  }
                } else if (status == "upcoming") {
                  final created = DateTime.parse(createdAt).toLocal();
                  subtitle = "Created";
                  timeInfo = "${created.day}/${created.month}/${created.year} at ${created.hour}:${created.minute.toString().padLeft(2, '0')}";
                }

                return Container(
                  margin: EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: _getStatusColor(status),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _getStatusAccentColor(status).withOpacity(0.2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: EdgeInsets.all(16),
                    leading: Container(
                      padding: EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _getStatusAccentColor(status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getStatusIcon(status),
                        color: _getStatusAccentColor(status),
                        size: 24,
                      ),
                    ),
                    title: Text(
                      room["name"],
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: 4),
                        Text(
                          "$subtitle: $timeInfo",
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        SizedBox(height: 8),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: _getStatusAccentColor(status).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: _getStatusAccentColor(status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.grey.shade400,
                      size: 16,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          "Rooms",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        elevation: 0,
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white.withOpacity(0.7),
          tabs: [
            Tab(icon: Icon(Icons.add), text: "Create"),
            Tab(icon: Icon(Icons.login), text: "Join"),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCreateRoomTab(),
                _buildJoinRoomTab(),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: _buildRoomsList(),
          ),
        ],
      ),
    );
  }
}