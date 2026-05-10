import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import 'login_screen.dart';
import '../services/database_service.dart';
import '../services/drive_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final driveSettings = context.watch<DriveSettings>();
    final serverIp = driveSettings.serverIp;
    final userName = driveSettings.userName.isEmpty
        ? 'User'
        : driveSettings.userName;
    final userEmail = driveSettings.userEmail.isEmpty
        ? 'No email'
        : driveSettings.userEmail;
    final ipController = TextEditingController(text: serverIp);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 24),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(
                radius: 24,
                backgroundColor: Color(0xFF1E1E1E),
                child: Icon(Icons.person, color: Color(0xFFFFB300)),
              ),
              title: Text(
                userName,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                userEmail,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: Colors.white70,
                ),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Bump Sensitivity',
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'Adjust accelerometer trigger threshold',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 12),
                Slider(
                  value: driveSettings.sensitivity,
                  activeColor: const Color(0xFFFFB300),
                  inactiveColor: Colors.white12,
                  onChanged: (value) {
                    context.read<DriveSettings>().setSensitivity(value);
                  },
                ),
              ],
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Battery Saver Mode',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      'Reduces background GPS polling',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
                Switch(
                  value: driveSettings.batterySaver,
                  activeThumbColor: const Color(0xFF00E676),
                  onChanged: (value) {
                    context.read<DriveSettings>().setBatterySaver(value);
                  },
                ),
              ],
            ),
          ),

          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              title: Text(
                'Upload over Wi-Fi only',
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              subtitle: Text(
                'Saves mobile data usage',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white70,
                ),
              ),
              value: driveSettings.wifiOnly,
              activeThumbColor: const Color(0xFF00E676),
              onChanged: (value) {
                context.read<DriveSettings>().setWifiOnly(value);
              },
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
            ),
            child: TextField(
              controller: ipController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.white,
              ),
              decoration: InputDecoration(
                labelText: 'Server IP Address',
                labelStyle: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white70,
                ),
                hintText: 'e.g., 192.168.10.5',
                hintStyle: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white38,
                ),
                filled: true,
                fillColor: const Color(0xFF242424),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                driveSettings.updateServerIp(value);
              },
            ),
          ),

          const SizedBox(height: 16),

          TextButton.icon(
            onPressed: () async {
              await DatabaseService().clearHazards();
              if (!context.mounted) {
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: const Color(0xFF00E676),
                  content: Text(
                    'Local cache cleared',
                    style: const TextStyle(color: Colors.black),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.delete_outline),
            label: Text(
              'Clear Local Session Cache',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
            ),
          ),

          const SizedBox(height: 32),

          TextButton.icon(
            onPressed: () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (_) => const LoginScreen(),
                ),
                (route) => false,
              );
            },
            icon: const Icon(Icons.logout),
            label: Text(
              'Log Out',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white54,
            ),
          ),

          const SizedBox(height: 32),

          Center(
            child: Text(
              'SmoothDrive v1.0.0',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: Colors.white24,
              ),
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
