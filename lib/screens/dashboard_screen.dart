import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../models/fish_model.dart';
import '../services/firebase_service.dart'; // I-import ang Firebase service

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  _DashboardScreenState createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Color _getStatusColor(String status) {
    switch (status.toUpperCase()) {
      case 'FRESH':
        return const Color(0xFF10B981); // Green
      case 'MODERATE':
        return const Color(0xFFF59E0B); // Amber / Yellow
      case 'SPOILED':
        return const Color(0xFFEF4444); // Red
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('FFMS Live Laboratory Monitor'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: StreamBuilder<DatabaseEvent>(
        // Ginagamit na ngayon ang watchFishFreshness() galing sa FirebaseService
        stream: FirebaseService.watchFishFreshness(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(
              child: Text(
                'Awaiting hardware telemetry data...\nCheck ESP32 connection.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
            );
          }

          // Parse data gamit ang FishSample model
          Map<dynamic, dynamic> rawData =
              snapshot.data!.snapshot.value as Map<dynamic, dynamic>;
          FishSample sample = FishSample.fromMap(rawData);
          Color statusColor = _getStatusColor(sample.status);

          return Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Live pH Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Text(
                          'Current pH Level (Bangus Spec)',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          sample.phValue.toStringAsFixed(2),
                          style: const TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Freshness Status Card
                Card(
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      children: [
                        const Text(
                          'Fish Freshness Status',
                          style: TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 32),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Text(
                            sample.status,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ),
                      ],
                    ),
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