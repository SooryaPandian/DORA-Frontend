import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'room_page.dart';
import 'login_page.dart';

class RegisterPage extends StatefulWidget {
  @override
  _RegisterPageState createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  void _register() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";

    if (_username.text.isEmpty || _password.text.isEmpty) return;

    final res = await http.post(
      Uri.parse("$server/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "username": _username.text,
        "password": _password.text,
      }),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await prefs.setString("user_id", data["user_id"]);
      await prefs.setString("username", data["username"]);
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RoomPage()),
      );
    } else {
      final err = jsonDecode(res.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err["error"] ?? "Registration failed")),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  void _checkUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey("user_id")) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => RoomPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Register"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => LoginPage()),
              );
            },
            child: Text("Login", style: TextStyle(color: Colors.black)),
          )
        ],
      ),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _username,
              decoration: InputDecoration(labelText: "Username"),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: "Password"),
            ),
            SizedBox(height: 20),
            ElevatedButton(onPressed: _register, child: Text("Register"))
          ],
        ),
      ),
    );
  }
}
