
import 'package:flutter/material.dart';
import '../services/ph_measurement_history_service.dart';

import '../services/ph_measurement_history_service.dart';

class PhMeasurementScreen extends StatefulWidget {
  const PhMeasurementScreen({
    super.key,
    required this.phReadings,
  });

  /// Connect this stream to the existing ESP32 pH stream.
  final Stream<double> phReadings;

  @override
  State<PhMeasurementScreen> createState() =>
      _PhMeasurementScreenState();
}

class _PhMeasurementScreenState
    extends State<PhMeasurementScreen> {
  final _service = PhMeasurementHistoryService();

  final _sessionController = TextEditingController();

  double? _currentPh;
  String _status = 'UNVERIFIED';
  bool _saving = false;
  String _message = '';

  @override
  void dispose() {
    _sessionController.dispose();
    super.dispose();
  }

  /// This displays the existing ESP32 status.
  ///
  /// Replace this with your actual status from
  /// your ESP32 / Flutter processing logic.
  ///
  /// Do not infer freshness from pH alone.
  String _statusForDisplay(double ph) {
    return 'UNVERIFIED';
  }

  Future<void> _saveMeasurement() async {
    if (_saving) return;

    final ph = _currentPh;

    if (ph == null) {
      setState(() {
        _message = 'No pH reading received yet.';
      });
      return;
    }

    final sessionId = _sessionController.text.trim();

    if (sessionId.isEmpty) {
      setState(() {
        _message = 'Enter the actual fish/session ID.';
      });
      return;
    }

    setState(() {
      _saving = true;
      _message = 'Saving measurement...';
    });

    try {
      final recordId = await _service.saveMeasurement(
        phValue: ph,
        status: _status,
        fishOrSessionId: sessionId,
      );

      if (!mounted) return;

      setState(() {
        _message =
            'Measurement saved successfully.\n'
            'Record ID: $recordId';
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _message = 'Failed to save: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AquaSense pH Recording'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _sessionController,
              decoration: const InputDecoration(
                labelText: 'Fish / Session ID',
                hintText: 'Enter actual fish/session ID',
                border: OutlineInputBorder(),
              ),
            ),

            const SizedBox(height: 24),

            StreamBuilder<double>(
              stream: widget.phReadings,
              builder: (context, snapshot) {
                if (snapshot.hasData) {
                  final ph = snapshot.data!;

                  // Update cached reading after build.
                  WidgetsBinding.instance
                      .addPostFrameCallback((_) {
                    if (!mounted) return;

                    if (_currentPh != ph) {
                      setState(() {
                        _currentPh = ph;
                        _status = _statusForDisplay(ph);
                      });
                    }
                  });
                }

                if (snapshot.hasError) {
                  return Text(
                    'Sensor error: ${snapshot.error}',
                  );
                }

                return Column(
                  children: [
                    const Text(
                      'Current pH',
                      style: TextStyle(fontSize: 20),
                    ),

                    const SizedBox(height: 8),

                    Text(
                      snapshot.hasData
                          ? snapshot.data!
                              .toStringAsFixed(2)
                          : 'Waiting for ESP32...',
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            Text(
              'Status: $_status',
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 30),

            ElevatedButton.icon(
              onPressed:
                  _saving ? null : _saveMeasurement,
              icon: const Icon(Icons.save),
              label: Text(
                _saving
                    ? 'Saving...'
                    : 'Record Measurement',
              ),
            ),

            const SizedBox(height: 20),

            Text(
              _message,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
