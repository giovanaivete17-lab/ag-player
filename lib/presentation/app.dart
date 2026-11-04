import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

class AgPlayerApp extends StatelessWidget {
  const AgPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD6AD55);
    return MaterialApp(
      title: 'AG Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF090B10),
        colorScheme: ColorScheme.fromSeed(
          seedColor: gold,
          brightness: Brightness.dark,
          surface: const Color(0xFF141821),
        ),
        useMaterial3: true,
        cardTheme: CardThemeData(
          color: const Color(0xFF171C26),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF292F3B)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF171C26),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
