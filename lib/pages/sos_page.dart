// pages/sos_page.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class SOSPage extends StatefulWidget {
  final String roomCode;
  final List<Map<String, dynamic>> sosLogs; // live/current logs
  final bool mySOSActive;
  final VoidCallback onToggleSOS;

  const SOSPage({
    super.key,
    required this.roomCode,
    required this.sosLogs,
    required this.mySOSActive,
    required this.onToggleSOS,
  });

  @override
  State<SOSPage> createState() => _SOSPageState();
}

class _SOSPageState extends State<SOSPage> {
  List<Map<String, dynamic>> _pastLogs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchPastSOSLogs();
  }

  Future<void> _fetchPastSOSLogs() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";

    try {
      final res = await http.get(Uri.parse("$server/sos_logs/${widget.roomCode}"));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _pastLogs = List<Map<String, dynamic>>.from(data["sos_logs"]);
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _mergeLogs() {
    // merge past + current, avoid duplicates by _id if exists
    final all = [..._pastLogs];
    for (var live in widget.sosLogs) {
      if (!_pastLogs.any((p) => p["_id"] == live["_id"])) {
        all.insert(0, live); // prepend live logs so they appear first
      }
    }
    return all;
  }

  @override
  Widget build(BuildContext context) {
    final allLogs = _mergeLogs();

    return Scaffold(
      appBar: AppBar(title: const Text("SOS")),
      body: Column(
        children: [
          // Fixed SOS button
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.sos, color: Colors.white, size: 32),
              label: Text(
                widget.mySOSActive ? "Stop SOS" : "Send SOS",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              onPressed: widget.onToggleSOS,
            ),
          ),

          const Divider(),

          // Logs list
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : allLogs.isEmpty
                ? const Center(child: Text("No SOS alerts yet"))
                : ListView.builder(
              itemCount: allLogs.length,
              itemBuilder: (context, index) {
                final log = allLogs[index];
                return ListTile(
                  leading: Icon(
                    Icons.sos,
                    color: log["active"] == true ? Colors.red : Colors.grey,
                  ),
                  title: Text(log["username"] ?? log["user_id"] ?? "Unknown User"),
                  subtitle: Text(log["timestamp"] ?? ""),
                  trailing: log["active"] == true
                      ? const Text("ACTIVE", style: TextStyle(color: Colors.red))
                      : const Text("CLEARED", style: TextStyle(color: Colors.green)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
