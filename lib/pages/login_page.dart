import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'room_page.dart';
import 'register_page.dart';

class LoginPage extends StatefulWidget {
  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();

  void _login() async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";

    if (_username.text.isEmpty || _password.text.isEmpty) return;

    final res = await http.post(
      Uri.parse("$server/login"),
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
        SnackBar(content: Text(err["error"] ?? "Login failed")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Login"),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => RegisterPage()),
              );
            },
            child: Text("Register", style: TextStyle(color: Colors.white)),
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
            ElevatedButton(onPressed: _login, child: Text("Login"))
          ],
        ),
      ),
    );
  }
}
