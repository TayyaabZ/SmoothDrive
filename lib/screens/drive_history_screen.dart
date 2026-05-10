import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/database_service.dart';

class DriveHistoryScreen extends StatefulWidget {
  const DriveHistoryScreen({super.key});

  @override
  State<DriveHistoryScreen> createState() => _DriveHistoryScreenState();
}

class _DriveHistoryScreenState extends State<DriveHistoryScreen> {
  List<Map<String, dynamic>> _historyList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _isLoading = true;
    });
    final items = await DatabaseService().getSessions();
    if (!mounted) {
      return;
    }
    setState(() {
      _historyList = items;
      _isLoading = false;
    });
  }

  String _formatDate(String iso) {
    final parts = iso.split('T');
    if (parts.isEmpty) {
      return '--/--/----';
    }
    final dateBits = parts[0].split('-');
    if (dateBits.length == 3) {
      return '${dateBits[2]}/${dateBits[1]}/${dateBits[0]}';
    }
    return parts[0];
  }

  String _formatTime(String iso) {
    final parts = iso.split('T');
    if (parts.length < 2) {
      return '--:--';
    }
    final timeBits = parts[1].split(':');
    final hh = timeBits.isNotEmpty ? timeBits[0].padLeft(2, '0') : '00';
    final mm = timeBits.length > 1 ? timeBits[1].padLeft(2, '0') : '00';
    return '$hh:$mm';
  }

  Widget _statItem(String title, String value, Color valueColor) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12,
              color: Colors.white54,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          'Drive History',
          style: GoogleFonts.inter(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    Color(0xFFFFB300),
                  ),
                ),
              ),
            )
          : _historyList.isEmpty
              ? Center(
                  child: Text(
                    'No drives recorded yet.',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  itemCount: _historyList.length,
                  itemBuilder: (context, index) {
                    final item = _historyList[index];
                    final startTime = item['start_time']?.toString() ?? '';
                    final duration = item['duration']?.toString() ?? '0m 0s';
                    final hazardCount =
                        (item['hazard_count'] as num?)?.toInt() ?? 0;
                    final maxImpact =
                        (item['max_impact'] as num?)?.toDouble() ?? 0.0;
                  final potholeCount =
                    (item['pothole_count'] as num?)?.toInt() ?? 0;
                  final bumpCount =
                    (item['speed_bump_count'] as num?)?.toInt() ?? 0;
                    final dateText = _formatDate(startTime);
                    final timeText = _formatTime(startTime);
                    final maxText = maxImpact.toStringAsFixed(1);
                    final maxColor = maxImpact > 15.0
                        ? const Color(0xFFFF5252)
                        : (maxImpact > 8.0 ? Colors.orange : Colors.yellow);

                    return Container(
                      margin: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                dateText,
                                style: GoogleFonts.inter(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              Text(
                                timeText,
                                style: GoogleFonts.inter(
                                  fontSize: 13,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              _statItem('Duration', duration, Colors.white),
                              const SizedBox(width: 12),
                              _statItem(
                                'Hazards Hit',
                                '$hazardCount Hazards',
                                Colors.white,
                              ),
                              const SizedBox(width: 12),
                              _statItem(
                                'Strongest Jolt',
                                maxText,
                                maxColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.warning,
                                      color: Colors.orange,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$potholeCount Potholes',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.waves,
                                      color: Colors.cyan,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      '$bumpCount Speed Bumps',
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
