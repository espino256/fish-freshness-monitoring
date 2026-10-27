class FishSample {
  const FishSample({
    required this.id,
    required this.fishType,
    required this.details,
    required this.collectedAt,
    required this.operatorName,
    required this.remarks,
  });

  final String id;
  final String fishType;
  final String details;
  final DateTime collectedAt;
  final String operatorName;
  final String remarks;

  FishSample copyWith({
    String? fishType,
    String? details,
    DateTime? collectedAt,
    String? operatorName,
    String? remarks,
  }) => FishSample(
    id: id,
    fishType: fishType ?? this.fishType,
    details: details ?? this.details,
    collectedAt: collectedAt ?? this.collectedAt,
    operatorName: operatorName ?? this.operatorName,
    remarks: remarks ?? this.remarks,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'fishType': fishType,
    'details': details,
    'collectedAt': collectedAt.toIso8601String(),
    'operatorName': operatorName,
    'remarks': remarks,
  };

  factory FishSample.fromJson(Map<String, dynamic> json) => FishSample(
    id: json['id'] as String,
    fishType: json['fishType'] as String,
    details: json['details'] as String? ?? '',
    collectedAt: DateTime.parse(json['collectedAt'] as String),
    operatorName: json['operatorName'] as String? ?? '',
    remarks: json['remarks'] as String? ?? '',
  );

  static String createId(DateTime now) {
    final date =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    final suffix = now.microsecondsSinceEpoch.toRadixString(36).toUpperCase();
    return 'FS-$date-$suffix';
  }
}

class SensorReading {
  const SensorReading({
    required this.id,
    required this.ph,
    required this.timestamp,
    this.sampleId,
    this.deviceId,
  });

  final String id;
  final double ph;
  final DateTime timestamp;
  final String? sampleId;
  final String? deviceId;

  factory SensorReading.fromFirebase(String id, Object? value) {
    if (value is! Map) {
      throw const FormatException('Reading must be a JSON object.');
    }
    final data = Map<String, dynamic>.from(value);
    final phValue = data['ph'];
    final timestampValue = data['timestamp'];
    if (phValue is! num || timestampValue is! num) {
      throw const FormatException('Reading requires numeric ph and timestamp.');
    }
    final ph = phValue.toDouble();
    if (!ph.isFinite || ph < 0 || ph > 14) {
      throw const FormatException('Reading pH must be between 0 and 14.');
    }
    return SensorReading(
      id: id,
      ph: ph,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestampValue.toInt(),
        isUtc: true,
      ),
      sampleId: data['sampleId'] as String?,
      deviceId: data['deviceId'] as String?,
    );
  }
}

class VisualAnalysisRecord {
  const VisualAnalysisRecord({
    required this.id,
    required this.sampleId,
    required this.meanHue,
    required this.classification,
    required this.timestamp,
    this.storagePath,
  });

  final String id;
  final String sampleId;
  final double meanHue;
  final String classification;
  final DateTime timestamp;
  final String? storagePath;

  factory VisualAnalysisRecord.fromFirebase(String id, Object? value) {
    if (value is! Map) {
      throw const FormatException('Analysis record must be a JSON object.');
    }
    final data = Map<String, dynamic>.from(value);
    final hue = data['meanHue'];
    final timestamp = data['timestamp'];
    final sampleId = data['sampleId'];
    final classification = data['classification'];
    if (hue is! num ||
        timestamp is! num ||
        sampleId is! String ||
        classification is! String) {
      throw const FormatException(
        'Analysis record requires hue, timestamp, sample ID and classification.',
      );
    }
    return VisualAnalysisRecord(
      id: id,
      sampleId: sampleId,
      meanHue: hue.toDouble(),
      classification: classification,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
      storagePath: data['storagePath'] as String?,
    );
  }
}

class DeviceImageUpload {
  const DeviceImageUpload({
    required this.id,
    required this.sampleId,
    required this.storagePath,
    required this.timestamp,
    required this.deviceId,
  });

  final String id;
  final String sampleId;
  final String storagePath;
  final DateTime timestamp;
  final String deviceId;

  factory DeviceImageUpload.fromFirebase(String id, Object? value) {
    if (value is! Map) {
      throw const FormatException('Device image upload must be an object.');
    }
    final data = Map<String, dynamic>.from(value);
    final sampleId = data['sampleId'];
    final storagePath = data['storagePath'];
    final timestamp = data['timestamp'];
    final deviceId = data['deviceId'];
    final safeSampleId =
        sampleId is String &&
        RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(sampleId);
    final expectedPathPrefix = safeSampleId ? 'samples/$sampleId/images/' : '';
    if (sampleId is! String ||
        !safeSampleId ||
        storagePath is! String ||
        !storagePath.startsWith(expectedPathPrefix) ||
        !RegExp(
          r'^samples/[A-Za-z0-9_-]{1,100}/images/[A-Za-z0-9_-]+\.jpg$',
        ).hasMatch(storagePath) ||
        timestamp is! num ||
        !timestamp.isFinite ||
        deviceId is! String ||
        deviceId.isEmpty) {
      throw const FormatException(
        'Device image upload requires a matching sample, storage path, '
        'timestamp, and device ID.',
      );
    }
    return DeviceImageUpload(
      id: id,
      sampleId: sampleId,
      storagePath: storagePath,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
      deviceId: deviceId,
    );
  }
}

class DeviceStatus {
  const DeviceStatus({
    required this.id,
    required this.online,
    required this.lastSeen,
    this.deviceName,
  });

  final String id;
  final bool online;
  final DateTime? lastSeen;
  final String? deviceName;

  factory DeviceStatus.fromFirebase(String id, Object? value) {
    if (value is! Map) {
      throw const FormatException('Device status must be a JSON object.');
    }
    final data = Map<String, dynamic>.from(value);
    final online = data['online'];
    final timestamp = data['lastSeen'];
    if (online is! bool || timestamp is! num) {
      throw const FormatException(
        'Device status requires boolean online and numeric lastSeen.',
      );
    }
    return DeviceStatus(
      id: id,
      online: online,
      lastSeen: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
      deviceName: data['deviceName'] as String?,
    );
  }
}
