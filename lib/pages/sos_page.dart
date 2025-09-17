// pages/sos_page.dart
import 'package:flutter/material.dart';

class SOSPage extends StatelessWidget {
  final List<Map<String, dynamic>> sosLogs;
  final bool mySOSActive;
  final VoidCallback onToggleSOS;

  const SOSPage({
    super.key,
    required this.sosLogs,
    required this.mySOSActive,
    required this.onToggleSOS,
  });

  @override
  Widget build(BuildContext context) {
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
                mySOSActive ? "Stop SOS" : "Send SOS",
                style: const TextStyle(color: Colors.white, fontSize: 18),
              ),
              onPressed: onToggleSOS,
            ),
          ),

          const Divider(),

          // Logs list
          Expanded(
            child: sosLogs.isEmpty
                ? const Center(child: Text("No SOS alerts yet"))
                : ListView.builder(
              itemCount: sosLogs.length,
              itemBuilder: (context, index) {
                final log = sosLogs[index];
                return ListTile(
                  leading: Icon(
                    Icons.sos,
                    color: log["active"] ? Colors.red : Colors.grey,
                  ),
                  title: Text(log["username"] ?? log["user_id"]),
                  subtitle: Text(log["timestamp"]),
                  trailing: log["active"]
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
