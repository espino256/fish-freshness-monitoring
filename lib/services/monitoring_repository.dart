import 'package:firebase_database/firebase_database.dart';
import '../models/telemetry.dart';

class MonitoringRepository {
  Stream<List<Telemetry>> watchHistory() => FirebaseDatabase.instance
      .ref('readings')
      .orderByChild('timestamp')
      .limitToLast(500)
      .onValue
      .map((event) {
        final value = event.snapshot.value;
        if (value == null) return <Telemetry>[];
        if (value is! Map) {
          throw const FormatException('Invalid reading collection.');
        }
        final rows = value.entries
            .map((e) => Telemetry.parse(e.key.toString(), e.value))
            .toList();
        rows.sort((a, b) => b.timestamp.compareTo(a.timestamp));
        return rows;
      });

  Stream<List<Telemetry>> watchLive() =>
      FirebaseDatabase.instance.ref('telemetry').onValue.map((event) {
        final value = event.snapshot.value;
        if (value == null) return <Telemetry>[];
        if (value is! Map) {
          throw const FormatException('Invalid live collection.');
        }
        final rows = value.entries
            .map((e) => Telemetry.parse(e.key.toString(), e.value))
            .toList();
        rows.sort((a, b) => a.deviceId.compareTo(b.deviceId));
        return rows;
      });
}
