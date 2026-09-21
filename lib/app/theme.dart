import 'package:flutter/material.dart';

/// 全局主题。车把模式要在户外强光下可读，因此整体用深色高对比。
const Color kAppBackground = Color(0xFF121212);
const Color kAppSurface = Color(0xFF1E1E1E);
const Color kAppAccent = Color(0xFF4CAF50);
const Color kAppWarning = Color(0xFFFFB300);

ThemeData buildAppTheme() => ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kAppAccent,
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: kAppBackground,
    );
