import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'presentation/screens/home_screen.dart';

const agWhite = Colors.white;
const agBlackText = Color(0xFF000000);
const agRed = Color(0xFFE53935);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const AgPlayerApp());
}

class AgPlayerApp extends StatelessWidget {
  const AgPlayerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AG Player',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: agWhite,
        colorScheme: const ColorScheme.light(
          primary: agRed,
          secondary: agRed,
          surface: agWhite,
          onSurface: agBlackText,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: agWhite,
          foregroundColor: agBlackText,
          elevation: 0,
        ),
        iconTheme: const IconThemeData(color: agBlackText),
        sliderTheme: const SliderThemeData(
          activeTrackColor: agRed,
          thumbColor: agRed,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
