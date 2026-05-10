import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DriveSettings extends ChangeNotifier {
  double _sensitivity = 0.5;
  String _userName = '';
  String _userEmail = '';
  bool batterySaver = true;
  bool wifiOnly = true;
  String serverIp = '192.168.1.100';
  late SharedPreferences _prefs;

  double get sensitivity => _sensitivity;
  String get userName => _userName;
  String get userEmail => _userEmail;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _sensitivity = _prefs.getDouble('sensitivity') ?? 0.5;
    batterySaver = _prefs.getBool('batterySaver') ?? true;
    wifiOnly = _prefs.getBool('wifiOnly') ?? true;
    serverIp = _prefs.getString('serverIp') ?? '192.168.1.100';
    _userName = _prefs.getString('userName') ?? '';
    _userEmail = _prefs.getString('userEmail') ?? '';
    notifyListeners();
  }

  void setSensitivity(double value) {
    _sensitivity = value;
    _prefs.setDouble('sensitivity', value);
    notifyListeners();
  }

  void setBatterySaver(bool value) {
    batterySaver = value;
    _prefs.setBool('batterySaver', value);
    notifyListeners();
  }

  void setWifiOnly(bool value) {
    wifiOnly = value;
    _prefs.setBool('wifiOnly', value);
    notifyListeners();
  }

  void updateServerIp(String newIp) {
    serverIp = newIp;
    _prefs.setString('serverIp', newIp);
    notifyListeners();
  }

  void updateProfile(String name, String email) {
    _userName = name;
    _userEmail = email;
    _prefs.setString('userName', name);
    _prefs.setString('userEmail', email);
    notifyListeners();
  }
}
