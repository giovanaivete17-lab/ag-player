import 'package:flutter/material.dart';

const Color agBlack = Color(0xFF000000);
const Color agPanel = Color(0xFF0F1115);
const Color agPanelLine = Color(0xFF23262D);
const Color agGold = Color(0xFFD4AF37);

ThemeData agTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: agGold,
    brightness: Brightness.dark,
  ).copyWith(
    primary: agGold,
    onPrimary: Colors.black,
    surface: agBlack,
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: agBlack,
    canvasColor: agBlack,
    appBarTheme: const AppBarTheme(
      backgroundColor: agBlack,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
  );
}
