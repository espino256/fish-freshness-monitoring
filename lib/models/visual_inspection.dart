import 'experimental_ai.dart';
import 'image_region.dart';

enum FishPart {
  gills('Gills'),
  eyes('Eyes'),
  skinScales('Skin / Scales');

  const FishPart(this.label);
  final String label;
}

enum VisualFreshness { fresh, moderate, spoiled, inconclusive }

extension VisualFreshnessLabel on VisualFreshness {
  String get label => switch (this) {
    VisualFreshness.fresh => 'Fresh',
    VisualFreshness.moderate => 'Moderate',
    VisualFreshness.spoiled => 'Spoiled',
    VisualFreshness.inconclusive => 'Inconclusive',
  };
}

class VisualInspectionResult {
  const VisualInspectionResult({
    required this.part,
    required this.width,
    required this.height,
    required this.isImageUsable,
    required this.reason,
    this.outcome = VisualFreshness.inconclusive,
    this.experimentalAi,
    this.measurements,
  });

  final FishPart part;
  final int width;
  final int height;

  /// Passed basic image checks only; does not establish a fish part is present.
  final bool isImageUsable;
  final String reason;
  final VisualFreshness outcome;
  final ExperimentalAiResult? experimentalAi;
  final ImageRegionMeasurements? measurements;
  String get classification => outcome.label;

  /// Experimental diagnostics never promote a confirmed freshness outcome.
  VisualInspectionResult withExperimentalAi(ExperimentalAiResult result) =>
      VisualInspectionResult(
        part: part,
        width: width,
        height: height,
        isImageUsable: isImageUsable,
        reason: reason,
        experimentalAi: result,
        measurements: measurements,
      );

  double? get hue => measurements?.meanHue;
  double? get saturation => measurements?.meanSaturation;
  double? get value => measurements?.meanValue;
  double? get redFraction => measurements?.redFraction;
  double? get usableFraction => measurements?.usableFraction;
}

/// Formats optional image measurements without displaying NaN or Infinity.
String formatImageMeasurement(
  double? value, {
  bool percentage = false,
  String unit = '',
  int decimals = 1,
}) {
  if (value == null || !value.isFinite) return 'N/A';
  final scaled = percentage ? value * 100 : value;
  if (!scaled.isFinite) return 'N/A';
  return '${scaled.toStringAsFixed(decimals)}${percentage ? '%' : unit}';
}
