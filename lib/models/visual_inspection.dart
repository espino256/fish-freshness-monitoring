enum FishPart {
  gills('Gills'),
  eyes('Eyes'),
  skinScales('Skin / scales');

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
  });

  final FishPart part;
  final int width;
  final int height;
  final bool isImageUsable;
  final String reason;
  final VisualFreshness outcome;
  String get classification => outcome.label;

  // Legacy HSV fields are deliberately unavailable in the new workflow.
  // They remain only so legacy presentation code cannot mistake a missing
  // model result for a numeric prediction.
  double get hue => double.nan;
  double get saturation => double.nan;
  double get value => double.nan;
  double get redFraction => double.nan;
  double get usableFraction => double.nan;
}
