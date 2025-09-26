// auth_service.dart - Business logic separation
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
class AuthService {
  static Future<Map<String, dynamic>> login(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";

    final res = await http.post(
      Uri.parse("$server/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await prefs.setString("user_id", data["user_id"]);
      await prefs.setString("username", data["username"]);
      return {"success": true, "data": data};
    } else {
      final err = jsonDecode(res.body);
      return {"success": false, "error": err["error"] ?? "Login failed"};
    }
  }

  static Future<Map<String, dynamic>> register(String username, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final server = prefs.getString("server_ip") ?? "";

    final res = await http.post(
      Uri.parse("$server/register"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({"username": username, "password": password}),
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      await prefs.setString("user_id", data["user_id"]);
      await prefs.setString("username", data["username"]);
      return {"success": true, "data": data};
    } else {
      final err = jsonDecode(res.body);
      return {"success": false, "error": err["error"] ?? "Registration failed"};
    }
  }

  static Future<bool> isUserLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey("user_id");
  }
}
