import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'screens/login_screen.dart';
import 'services/drive_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = DriveSettings();
  await settings.init();
  runApp(
    ChangeNotifierProvider.value(
      value: settings,
      child: const SmoothDriveApp(),
    ),
  );
}

class SmoothDriveApp extends StatelessWidget {
  const SmoothDriveApp({super.key});

  static const _scaffoldBg = Color(0xFF121212);
  static const _primaryAmber = Color(0xFFFFB300);
  static const _surfaceColor = Color(0xFF1E1E1E);

  @override
  Widget build(BuildContext context) {
    final textTheme = GoogleFonts.interTextTheme(
      ThemeData.dark().textTheme.apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );

    return MaterialApp(
      title: 'SmoothDrive',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: _primaryAmber,
        scaffoldBackgroundColor: _scaffoldBg,
        colorScheme: const ColorScheme.dark(
          primary: _primaryAmber,
          secondary: _primaryAmber,
          surface: _surfaceColor,
          onPrimary: Colors.black,
          onSecondary: Colors.black,
          onSurface: Colors.white,
        ),
        textTheme: textTheme,
        cardTheme: const CardThemeData(color: _surfaceColor),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.transparent, 
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: _scaffoldBg,
          foregroundColor: Colors.white,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          elevation: 0,
        ),
     
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: _surfaceColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        ),
    
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: _primaryAmber,
            foregroundColor: Colors.black,
            minimumSize: const Size.fromHeight(56), 
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 4,
            shadowColor: _primaryAmber.withValues(alpha: 0.5), 
          ),
        ),
      ),
      home: const LoginScreen(),
    );
  }
}
