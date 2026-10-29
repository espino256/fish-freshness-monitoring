class FishSample {
  final double phValue;
  final double voltage;
  final String status;
  final bool ledGreen;
  final bool ledYellow;
  final bool ledRed;
  final int timestamp;

  FishSample({
    required this.phValue,
    this.voltage = 0.0,
    required this.status,
    this.ledGreen = false,
    this.ledYellow = false,
    this.ledRed = false,
    required this.timestamp,
  });

  factory FishSample.fromMap(Map<dynamic, dynamic> map) {
    final rawPh = map['phValue'] ?? map['pH_Value'] ?? map['ph'] ?? 0.0;
    final rawVoltage = map['voltage'] ?? 0.0;
    final rawStatus = map['status']?.toString() ?? 'UNKNOWN';
    final rawTimestamp = map['timestamp'] ?? 0;

    return FishSample(
      phValue: double.tryParse(rawPh.toString()) ?? 0.0,
      voltage: double.tryParse(rawVoltage.toString()) ?? 0.0,
      status: rawStatus,
      ledGreen: map['ledGreen'] == true || rawStatus.toUpperCase() == 'FRESH',
      ledYellow: map['ledYellow'] == true || rawStatus.toUpperCase() == 'MODERATE',
      ledRed: map['ledRed'] == true || rawStatus.toUpperCase() == 'SPOILED',
      timestamp: int.tryParse(rawTimestamp.toString()) ?? 0,
    );
  }
}
