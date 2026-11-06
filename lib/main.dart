import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';

import 'data/settings_store.dart';
import 'presentation/screens/home_screen.dart';
import 'presentation/theme.dart';

const agWhite = Colors.white;
const agRed = Color(0xFFE53935);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (d) {
    ErrorLog.add(d.exceptionAsString());
    FlutterError.presentError(d);
  };
  PlatformDispatcher.instance.onError = (e, s) {
    ErrorLog.add(e.toString());
    return true;
  };
  MediaKit.ensureInitialized();
  await SettingsStore.load();
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
          onSurface: Color(0xFF000000),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: agWhite,
          foregroundColor: Color(0xFF000000),
          elevation: 0,
        ),
        iconTheme: const IconThemeData(color: Color(0xFF000000)),
        sliderTheme: const SliderThemeData(
          activeTrackColor: agRed,
          thumbColor: agRed,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}
