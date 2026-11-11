
import 'package:firebase_database/firebase_database.dart'; 
import 'ph_measurement_history_service.dart';

class PhMeasurementHistoryService {
  PhMeasurementHistoryService({
    FirebaseDatabase? database,
  }) : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  DatabaseReference get _fishSamples =>
      _database.ref('FishSamples');

  /// Saves one confirmed pH measurement.
  ///
  /// A fish/session ID must be supplied from a real
  /// collection session. Never generate a fake ID.
  Future<String> saveMeasurement({
    required double phValue,
    required String status,
    required String fishOrSessionId,
    String source = 'ESP32',
  }) async {
    if (!phValue.isFinite ||
        phValue < 0 ||
        phValue > 14) {
      throw ArgumentError(
        'pH must be between 0 and 14.',
      );
    }

    final sessionId = fishOrSessionId.trim();

    if (sessionId.isEmpty) {
      throw ArgumentError(
        'Fish/session ID cannot be empty.',
      );
    }

    final cleanStatus = status.trim().toUpperCase();

    if (cleanStatus.isEmpty) {
      throw ArgumentError(
        'Measurement status cannot be empty.',
      );
    }

    final recordRef =
        _fishSamples.child('measurement_history').push();

    final recordId = recordRef.key;

    if (recordId == null) {
      throw StateError(
        'Unable to create measurement record ID.',
      );
    }

    final measurement = <String, Object>{
      'measurement_record_id': recordId,
      'fish_or_session_id': sessionId,
      'phValue': phValue,
      'status': cleanStatus,
      'timestamp': ServerValue.timestamp,
      'source': source,
    };

    // Atomically update both database paths.
    await _fishSamples.update({
      'measurement_history/$recordId': measurement,
      'current_reading/phValue': phValue,
      'current_reading/status': cleanStatus,
      'current_reading/fish_or_session_id': sessionId,
      'current_reading/measurement_record_id': recordId,
      'current_reading/timestamp': ServerValue.timestamp,
    });

    return recordId;
  }

  /// Reads saved measurement history.
  Future<List<Map<String, dynamic>>> getHistory() async {
    final snapshot = await _fishSamples
        .child('measurement_history')
        .get();

    if (!snapshot.exists || snapshot.value == null) {
      return [];
    }

    final raw = snapshot.value;

    if (raw is! Map) {
      throw StateError(
        'Unexpected measurement history format.',
      );
    }

    final records = <Map<String, dynamic>>[];

    for (final entry in raw.entries) {
      if (entry.value is Map) {
        final record = Map<String, dynamic>.from(
          entry.value as Map,
        );

        record.putIfAbsent(
          'measurement_record_id',
          () => entry.key.toString(),
        );

        records.add(record);
      }
    }

    records.sort((a, b) {
      final aTime = (a['timestamp'] as num?)?.toInt() ?? 0;
      final bTime = (b['timestamp'] as num?)?.toInt() ?? 0;

      return bTime.compareTo(aTime);
    });

    return records;
  }
}
