import 'package:flutter/material.dart';

class SOSPage extends StatelessWidget {
  final List<Map<String, dynamic>> alerts;
  final Map<String, String> usernames;

  const SOSPage({super.key, required this.alerts, required this.usernames});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("SOS Alerts")),
      body: alerts.isEmpty
          ? const Center(child: Text("No SOS alerts"))
          : ListView.builder(
        itemCount: alerts.length,
        itemBuilder: (ctx, i) {
          final alert = alerts[i];
          final userId = alert["user_id"];
          final username = usernames[userId] ?? "Unknown";
          final time = alert["timestamp"]?.toString() ?? "";

          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: const Icon(Icons.sos, color: Colors.red),
              title: Text("$username raised SOS"),
              subtitle: Text(time),
            ),
          );
        },
      ),
    );
  }
}
