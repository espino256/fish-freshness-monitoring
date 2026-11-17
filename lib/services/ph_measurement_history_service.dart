
import 'package:firebase_database/firebase_database.dart'; 

class PhMeasurementHistoryService {
  PhMeasurementHistoryService({
    FirebaseDatabase? database,
  }) : _database = database ?? FirebaseDatabase.instance;

  final FirebaseDatabase _database;

  /// Confirmed, user-associated measurements live outside device telemetry.
  ///
  /// ESP32 firmware owns `/telemetry` and `/readings`; it must never be
  /// overwritten when an inspector records a measurement against a sample.
  DatabaseReference get _measurementHistory =>
      _database.ref('measurement_history');

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

    final recordRef = _measurementHistory.push();

    final recordId = recordRef.key;

    if (recordId == null) {
      throw StateError(
        'Unable to create measurement record ID.',
      );
    }

    final measurement = <String, Object>{
      'measurementId': recordId,
      'fishOrSessionId': sessionId,
      'ph': phValue,
      'status': cleanStatus,
      'timestamp': ServerValue.timestamp,
      'source': source,
    };

    // A confirmed record is immutable. Do not write the legacy FishSamples
    // current_reading path: it is intentionally denied by the current rules
    // and is not the ESP32's live telemetry source.
    await recordRef.set(measurement);

    return recordId;
  }

  /// Reads saved measurement history.
  Future<List<Map<String, dynamic>>> getHistory() async {
    final snapshot = await _measurementHistory.get();

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
          'measurementId',
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
