enum FishStatus { fresh, moderate, spoiled }

FishStatus classifyPh(double ph) {
  if (!ph.isFinite || ph < 0 || ph > 14) {
    throw const FormatException('pH must be between 0 and 14.');
  }
  return ph < 6.5
      ? FishStatus.fresh
      : ph < 7.2
      ? FishStatus.moderate
      : FishStatus.spoiled;
}

class Telemetry {
  const Telemetry({
    required this.id,
    required this.deviceId,
    required this.ph,
    required this.adcRaw,
    required this.measuredVoltage,
    required this.timestamp,
  });
  final String id, deviceId;
  final double ph, adcRaw, measuredVoltage;
  final DateTime timestamp;
  double get nominalVoltage => adcRaw * 3.3 / 4095;
  FishStatus get status => classifyPh(ph);
  bool isStale(DateTime now) =>
      now.difference(timestamp) > const Duration(seconds: 20) ||
      timestamp.isAfter(now.add(const Duration(seconds: 5)));

  factory Telemetry.parse(String id, Object? value) {
    if (value is! Map) throw const FormatException('Invalid telemetry object.');
    double number(String key, double min, double max) {
      final n = value[key];
      if (n is! num || !n.isFinite || n < min || n > max) {
        throw FormatException('Invalid telemetry $key.');
      }
      return n.toDouble();
    }

    final device = value['deviceId'];
    if (device is! String || device.isEmpty) {
      throw const FormatException('Missing device ID.');
    }
    return Telemetry(
      id: id,
      deviceId: device,
      ph: number('ph', 0, 14),
      adcRaw: number('adcRaw', 1, 4094),
      measuredVoltage: number('measuredVoltage', 0, 3.3),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        number('timestamp', 1, 8640000000000000).toInt(),
        isUtc: true,
      ),
    );
  }
}
