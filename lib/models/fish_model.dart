class FishSample {
  final double phValue;
  final String status;
  final int timestamp;

  FishSample({
    required this.phValue,
    required this.status,
    required this.timestamp,
  });

  factory FishSample.fromMap(Map<dynamic, dynamic> map) {
    return FishSample(
      phValue: double.tryParse(map['pH_Value'].toString()) ?? 0.0,
      status: map['status']?.toString() ?? 'UNKNOWN',
      timestamp: int.tryParse(map['timestamp'].toString()) ?? 0,
    );
  }
}