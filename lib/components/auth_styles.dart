// auth_styles.dart - Centralized styling
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AuthStyles {
  static const double borderRadius = 12.0;
  static const double spacing = 16.0;
  static const double largeSpacing = 32.0;
  static const EdgeInsets pageContentPadding = EdgeInsets.all(24.0);
  static const EdgeInsets formPadding = EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0);

  static InputDecoration inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: Colors.grey.shade50,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: Colors.blue, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadius),
        borderSide: BorderSide(color: Colors.red, width: 2),
      ),
    );
  }

  static ButtonStyle primaryButtonStyle = ElevatedButton.styleFrom(
    minimumSize: Size(double.infinity, 56),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    ),
    elevation: 2,
  );

  static ButtonStyle secondaryButtonStyle = OutlinedButton.styleFrom(
    minimumSize: Size(double.infinity, 56),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(borderRadius),
    ),
  );

  static TextStyle headlineStyle = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.bold,
    color: Colors.grey.shade800,
  );

  static TextStyle subtitleStyle = TextStyle(
    fontSize: 16,
    color: Colors.grey.shade600,
  );
}