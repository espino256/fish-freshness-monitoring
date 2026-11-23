import 'visual_inspection.dart';

class VisualInspectionHistoryRecord {
  const VisualInspectionHistoryRecord({
    required this.id,
    required this.part,
    required this.timestamp,
    required this.classification,
    required this.imageUsable,
    required this.width,
    required this.height,
    required this.experimentalModel,
    required this.inferenceStatus,
    this.meanHue,
    this.meanSaturation,
    this.meanValue,
    this.redFraction,
    this.usableFraction,
  });

  final String id;
  final FishPart part;
  final DateTime timestamp;
  final String classification;
  final bool imageUsable;
  final int width;
  final int height;
  final String experimentalModel;
  final String inferenceStatus;
  final double? meanHue;
  final double? meanSaturation;
  final double? meanValue;
  final double? redFraction;
  final double? usableFraction;

  factory VisualInspectionHistoryRecord.fromFirebase(String id, Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'Visual inspection record must be an object.',
      );
    }
    final data = Map<String, dynamic>.from(value);
    final partValue = data['part'];
    final part = FishPart.values.where((item) => item.name == partValue);
    final timestamp = data['timestamp'];
    final classification = data['classification'];
    final imageUsable = data['imageUsable'];
    final width = data['width'];
    final height = data['height'];
    final experimentalModel = data['experimentalModel'];
    final inferenceStatus = data['inferenceStatus'];
    if (part.isEmpty ||
        timestamp is! num ||
        !timestamp.isFinite ||
        timestamp <= 0 ||
        classification is! String ||
        imageUsable is! bool ||
        width is! num ||
        height is! num ||
        experimentalModel is! String ||
        inferenceStatus is! String) {
      throw const FormatException(
        'Visual inspection record has invalid required fields.',
      );
    }

    double? optionalNumber(String key) {
      final value = data[key];
      return value is num && value.isFinite ? value.toDouble() : null;
    }

    return VisualInspectionHistoryRecord(
      id: id,
      part: part.first,
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestamp.toInt(),
        isUtc: true,
      ),
      classification: classification,
      imageUsable: imageUsable,
      width: width.toInt(),
      height: height.toInt(),
      experimentalModel: experimentalModel,
      inferenceStatus: inferenceStatus,
      meanHue: optionalNumber('meanHue'),
      meanSaturation: optionalNumber('meanSaturation'),
      meanValue: optionalNumber('meanValue'),
      redFraction: optionalNumber('redFraction'),
      usableFraction: optionalNumber('usableFraction'),
    );
  }
}
