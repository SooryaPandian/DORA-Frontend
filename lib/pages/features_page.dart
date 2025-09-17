// pages/features_page.dart
import 'package:flutter/material.dart';

class FeaturesPage extends StatelessWidget {
  const FeaturesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      children: [
        _featureButton(context, Icons.travel_explore, "Travel Plan", () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Travel Plan tapped")),
          );
        }),
        _featureButton(context, Icons.play_arrow, "Start Trip", () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Trip Started")),
          );
        }),
        _featureButton(context, Icons.stop, "End Trip", () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Trip Ended")),
          );
        }),
      ],
    );
  }

  Widget _featureButton(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
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
