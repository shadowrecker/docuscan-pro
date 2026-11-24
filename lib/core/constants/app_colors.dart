import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary Brand Colors
  static const Color primary = Color(0xFF1A73E8);
  static const Color primaryLight = Color(0xFF4D9EFF);
  static const Color primaryDark = Color(0xFF0D47A1);

  // Secondary Colors
  static const Color secondary = Color(0xFF34A853);
  static const Color accent = Color(0xFFFBBC04);
  static const Color error = Color(0xFFEA4335);

  // Text Colors
  static const Color textPrimary = Color(0xFF1F1F1F);
  static const Color textSecondary = Color(0xFF5F6368);
  static const Color textTertiary = Color(0xFF9AA0A6);
  static const Color textOnPrimary = Colors.white;

  // Background Colors
  static const Color backgroundLight = Color(0xFFF8F9FA);
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceLight = Colors.white;
  static const Color surfaceDark = Color(0xFF1E1E1E);

  // Feature Colors
  static const Color scanning = Color(0xFF1A73E8);
  static const Color ocr = Color(0xFF34A853);
  static const Color pdfEdit = Color(0xFFEA4335);
  static const Color convert = Color(0xFFFBBC04);
  static const Color sign = Color(0xFF9C27B0);
  static const Color merge = Color(0xFFFF6D00);
  static const Color compress = Color(0xFF00BCD4);
  static const Color protect = Color(0xFF607D8B);
  static const Color qrCode = Color(0xFF795548);

  // Annotation Colors
  static const List<Color> annotationColors = [
    Color(0xFFFFEB3B), // Yellow highlight
    Color(0xFF4CAF50), // Green highlight
    Color(0xFF2196F3), // Blue highlight
    Color(0xFFFF9800), // Orange highlight
    Color(0xFFF44336), // Red highlight
    Color(0xFF9C27B0), // Purple highlight
    Colors.black,
    Colors.white,
  ];

  // Scan Filter Colors
  static const Color filterOriginal = Colors.transparent;
  static const Color filterGrayscale = Color(0xFF9E9E9E);
  static const Color filterBW = Color(0xFF212121);
  static const Color filterEnhanced = Color(0xFF1565C0);
}
