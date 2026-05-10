# SmoothDrive 🚗

A crowdsourced road hazard detection and navigation app built with Flutter. SmoothDrive uses your phone's accelerometer, gyroscope, and GPS to automatically detect potholes and speed bumps while you drive, pins them on a live map, and syncs them to a shared server so every user benefits from a collective hazard map.

---

## Features

- **Real-time hazard detection** — Fuses accelerometer Z-axis impact spikes with gyroscope pitch rate data to classify road hazards as potholes or speed bumps automatically while driving
- **Live hazard map** — Detected hazards are pinned on an interactive dark map in real time during your drive
- **Approach warning** — Vibrates and displays a banner when you are within 50 metres of a known hazard ahead
- **Crowdsourced sync** — Hazards are synced to a shared Python server over your local network. All users see each other's hazards on the global map
- **Route preview** — Enter a destination or tap the map to drop a pin, and the app draws your route and highlights every known hazard along the way before you leave
- **Drive history** — Every session is saved locally with pothole and speed bump counts, duration, and a summary dialog
- **Secure authentication** — Register and log in with bcrypt-hashed passwords stored on the server
- **Offline-first** — Hazards are written to local SQLite immediately and synced when connectivity is available
- **Haptic feedback** — Single vibration for potholes, double vibration for speed bumps so you feel the classification without looking at the screen

---

## Screenshots

> Add your screenshots here

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter (Dart) |
| Sensor fusion | `sensors_plus` — accelerometer + gyroscope |
| Location | `geolocator` |
| Maps | `flutter_map` + CartoDB dark tiles |
| Routing | OSRM public routing API |
| Geocoding | Nominatim (OpenStreetMap) |
| Local storage | `sqflite` (SQLite) |
| Backend | Python 3 — stdlib `http.server` |
| Server database | SQLite with Haversine deduplication |
| Auth | bcrypt password hashing |
| State management | `provider` + `ValueNotifier` |

---

## How It Works

### Hazard Detection

During an active drive, the app samples the accelerometer at 50 Hz. When the Z-axis magnitude crosses a configurable sensitivity threshold, it checks the gyroscope pitch rate at that moment. A high pitch rate (above 0.8 rad/s) indicates a raised surface — classified as a **speed bump**. A low pitch rate indicates a sharp impact — classified as a **pothole**. A 1500ms cooldown prevents duplicate detections from the same bump.

### Server-side Deduplication

When hazards are synced to the server, each incoming report is compared against every existing hazard using the Haversine formula. If a new report lands within 15 metres of an existing hazard of the same type, the server merges them by averaging the coordinates and incrementing the hit count. This keeps the map clean as more drivers report the same spots.

### Approach Warning

The GPS position stream fires every 5 metres. On each update, the app calculates the distance to every hazard in the global list using `Geolocator.distanceBetween`. If any hazard is within 50 metres and 30 seconds have passed since the last warning, a banner appears and the phone vibrates twice.

---

## Getting Started

### Prerequisites

- Flutter SDK `^3.11`
- Python 3.8+
- Both devices on the same WiFi network

### Backend Setup

```bash
cd your_project_folder
pip install bcrypt
python server.py
```

The server prints its local IP on startup:

```
Server is running on port 3000...
Type this IP in settings: 192.168.1.x
```

### Flutter App Setup

```bash
flutter pub get
flutter run
```

Open the app, go to **Settings**, and enter the server IP printed above. Register an account and you are ready to drive.

---

## Project Structure

```
lib/
├── main.dart
├── models/
│   └── road_hazard.dart
├── screens/
│   ├── login_screen.dart
│   ├── registration_screen.dart
│   ├── permissions_screen.dart
│   ├── main_dashboard_screen.dart
│   ├── active_drive_screen.dart
│   ├── drive_history_screen.dart
│   ├── route_preview_screen.dart
│   └── settings_screen.dart
├── services/
│   ├── database_service.dart
│   ├── sync_service.dart
│   └── drive_settings.dart
└── widgets/
    └── session_summary_dialog.dart
server.py
```

---

## API Reference

| Method | Endpoint | Description |
|---|---|---|
| `POST` | `/api/register` | Register a new user |
| `POST` | `/api/login` | Authenticate and return user info |
| `POST` | `/api/sync` | Upload a batch of hazards from a device |
| `GET` | `/api/hazards` | Fetch all global hazards |

---

## Configuration

All settings are accessible in-app under the Settings screen:

| Setting | Description |
|---|---|
| Server IP | IP address of the machine running `server.py` |
| Detection sensitivity | Threshold for impact detection (0.5 — 2.0g) |
| WiFi only sync | Restricts hazard sync to WiFi connections only |
| Battery saver | Increases GPS distance filter to reduce battery usage |

---

## Authors

- **Anood Tayyeba Imtiaz** — 01-135232-010
- **Tayyab Zahoor** — 01-135232-070

BSIT 6th Sem — Mobile Application Development
