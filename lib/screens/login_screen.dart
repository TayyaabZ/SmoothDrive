import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/drive_settings.dart';
import 'permissions_screen.dart';
import 'registration_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String text, Color color) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text), backgroundColor: color));
  }

  Future<void> _submit() async {
    if (_isLoading) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    final serverIp = context.read<DriveSettings>().serverIp;
    final url = Uri.parse('http://$serverIp:3000/api/login');
    try {
      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'email': _emailController.text.trim(),
              'password': _passwordController.text,
            }),
          )
          .timeout(const Duration(seconds: 6));
      if (!mounted) {
        return;
      }
      if (response.statusCode == 200) {
        var ok = false;
        var name = '';
        var email = '';
        final data = jsonDecode(response.body);
        if (data is Map) {
          ok = data['status'] == 'ok';
          final nameVal = data['name'];
          final emailVal = data['email'];
          if (nameVal is String) {
            name = nameVal;
          }
          if (emailVal is String) {
            email = emailVal;
          }
        }
        if (ok) {
          final prefs = await SharedPreferences.getInstance();
          final enteredEmail = _emailController.text.trim();
          final enteredPassword = _passwordController.text;
          await prefs.setString('saved_email', enteredEmail);
          await prefs.setString('saved_password', enteredPassword);

          if (!mounted) return;
          context.read<DriveSettings>().updateProfile(
                name,
                email.isEmpty ? enteredEmail : email,
              );
          _showMessage('Login successful', Colors.green);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const PermissionsScreen()),
          );
        } else {
          _showMessage('Connection failed', Colors.red);
        }
      } else if (response.statusCode == 401) {
        _showMessage('Invalid email or password', Colors.red);
      } else {
        _showMessage('Connection failed', Colors.red);
      }
    } catch (_) {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final savedEmail = prefs.getString('saved_email') ?? '';
      final savedPassword = prefs.getString('saved_password') ?? '';
      final enteredEmail = _emailController.text.trim();
      final enteredPassword = _passwordController.text;
      if (savedEmail.isNotEmpty &&
          enteredEmail == savedEmail &&
          enteredPassword == savedPassword) {
        if (!mounted) return;
        _showMessage('Login successful', Colors.green);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const PermissionsScreen()),
        );
      } else {
        if (!mounted) return;
        _showMessage('Connection failed', Colors.red);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 48),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'Smooth',
                        style: GoogleFonts.inter(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      TextSpan(
                        text: 'Drive',
                        style: GoogleFonts.inter(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFFB300),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Welcome back',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 48),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    hintText: 'Email',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _submit,
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Color(0xFFFFB300),
                            ),
                          ),
                        )
                      : Text(
                          'Login',
                          style: GoogleFonts.inter(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Don't have an account? ",
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const RegistrationScreen(),
                          ),
                        );
                      },
                      child: Text(
                        'Sign Up',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFFFB300),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}