import 'visual_inspection.dart';

/// Identity of the inspected exports. No class-index meanings are assumed.
enum ExperimentalFishModel {
  gills(
    FishPart.gills,
    'aquasense_gills_model.tflite',
    'adfa10b697c409a7b1848945acef11b59d726bda15f8ed7e0d2d557a9e9225dd',
  ),
  eyes(
    FishPart.eyes,
    'aquasense_eyes_model.tflite',
    '2c774dd79cfcd95e4d97a110e7eaaea6eb07306b01e9d97a0fc57f371792b5af',
  ),
  scales(
    FishPart.skinScales,
    'aquasense_scales_model.tflite',
    '2a5fbddbe50471aaac627eb2bcd4e87d690103bd02795dbaf7db08c4f05ee494',
  ),
  scalesFinetuned(
    FishPart.skinScales,
    'aquasense_scales_finetuned_model.tflite',
    'd1dcf791f02e38696e912e37a4e8a648ec6dc17a3fd8ba6685bd7e99304a5d7e',
  );

  const ExperimentalFishModel(this.part, this.filename, this.sha256);
  final FishPart part;
  final String filename;
  final String sha256;
  String get assetPath => 'assets/models/$filename';
  String get version => 'SHA-256 ${sha256.substring(0, 12)}';
  bool get isCandidate => this == scalesFinetuned;

  /// Training conventions lack a supplied hash-linked record for each export.
  /// No named output is enabled by filename, score, or presumed class order.
  String? classNameForOutput(int index) => null;

  static ExperimentalFishModel forPart(FishPart part) => switch (part) {
    FishPart.gills => gills,
    FishPart.eyes => eyes,
    FishPart.skinScales => scales,
  };
}

enum ExperimentalAiStatus {
  running('Running'),
  completed('Inference completed'),
  qualityRejected('Not run: image checks failed'),
  modelUnavailable('Model unavailable'),
  runtimeUnavailable('Runtime unavailable'),
  invalidOutput('Invalid model output'),
  failed('Inference failed'),
  disposed('Inspection closed');

  const ExperimentalAiStatus(this.label);
  final String label;
}

/// Diagnostic scores only. Deliberately has no freshness or pH fields.
class ExperimentalAiResult {
  ExperimentalAiResult({
    required this.model,
    required this.status,
    required this.message,
    List<double> scores = const [],
    this.runtime,
    this.inferenceMicroseconds,
  }) : scores = List.unmodifiable(scores);

  final ExperimentalFishModel model;
  final ExperimentalAiStatus status;
  final String message;
  final List<double> scores;
  final String? runtime;
  final int? inferenceMicroseconds;

  /// Numerical consistency only; this is never scientific validation.
  bool get hasValidDistribution =>
      status == ExperimentalAiStatus.completed &&
      scores.length == 3 &&
      scores.every((s) => s.isFinite && s >= 0 && s <= 1) &&
      (scores.fold<double>(0, (sum, s) => sum + s) - 1).abs() <= 1e-5;

  List<int> get leadingOutputIndices {
    if (!hasValidDistribution) {
      return const [];
    }
    final maximum = scores.reduce((a, b) => a > b ? a : b);
    return List.unmodifiable([
      for (var i = 0; i < scores.length; i++)
        if (scores[i] == maximum) i,
    ]);
  }
}
