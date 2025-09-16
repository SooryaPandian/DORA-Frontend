// server_page.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'register_page.dart'; // Assuming you have this page

class ServerPage extends StatefulWidget {
  const ServerPage({super.key});

  @override
  State<ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends State<ServerPage> {
  String? serverAddress;

  @override
  void initState() {
    super.initState();
    _loadServerAddress();
  }

  // Load saved address on startup
  Future<void> _loadServerAddress() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey("server_ip")) {
      setState(() {
        serverAddress = prefs.getString("server_ip");
      });
    }
  }

  Future<void> _scanQR() async {
    // Navigate to the scanner page and wait for a result.
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerPage()),
    );

    if (result != null && result.isNotEmpty) {
      setState(() {
        serverAddress = result;
      });

      // Save the server IP for later use
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("server_ip", result);

      // Navigate to the next page after a successful scan
      if (mounted) {
        Navigator.pushReplacement(
            context, MaterialPageRoute(builder: (_) => RegisterPage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Connect to Server")),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: serverAddress == null
              ? ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
              textStyle: const TextStyle(fontSize: 16),
            ),
            onPressed: _scanQR,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text("Scan Server QR"),
          )
              : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                "Successfully Connected to:",
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 10),
              Text(
                serverAddress!,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: () {
                      // Continue to next page
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => RegisterPage()),
                      );
                    },
                    child: const Text("Continue"),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton(
                    onPressed: _scanQR,
                    child: const Text("Scan New Server"),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//--- QR Scanner Page ---

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  // Controller for the mobile scanner
  final MobileScannerController controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool isScanCompleted = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Scan Server QR")),
      body: MobileScanner(
        controller: controller,
        // This callback is triggered when a barcode is detected.
        onDetect: (capture) {
          // Prevents the scanner from popping multiple times
          if (isScanCompleted) return;

          final String? code = capture.barcodes.first.rawValue;

          if (code != null) {
            setState(() {
              isScanCompleted = true;
            });
            // Pop the page and return the scanned code
            Navigator.pop(context, code);
          }
        },
      ),
    );
  }
}