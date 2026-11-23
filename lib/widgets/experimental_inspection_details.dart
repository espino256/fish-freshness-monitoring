import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../models/experimental_ai.dart';
import '../models/visual_inspection.dart';
import 'inspection_card.dart';

/// Verified conclusions, experimental outputs and pixel descriptors stay separate.
class ExperimentalInspectionDetails extends StatelessWidget {
  const ExperimentalInspectionDetails({
    super.key,
    required this.result,
    this.simulated = false,
  });
  final VisualInspectionResult result;
  final bool simulated;

  @override
  Widget build(BuildContext context) {
    final ai = result.experimentalAi;
    final leaders = ai?.leadingOutputIndices ?? const <int>[];
    final named = leaders.length == 1
        ? ai!.model.classNameForOutput(leaders.single)
        : null;
    final metrics = result.measurements;
    return Column(
      key: const Key('experimental-inspection-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InspectionHeading(
          icon: Icons.assignment_outlined,
          title: 'Inspection results',
          subtitle: 'Verified outcome, experimental AI and image measurements',
        ),
        const SizedBox(height: 16),
        if (simulated)
          const Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: Text('SIMULATED TARGET · component-test image'),
          ),
        Text(
          'Selected fish part: ${result.part.label}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final verified = _VerifiedResult(part: result.part);
            final experimental = _ExperimentalPrediction(ai: ai);
            if (constraints.maxWidth < 760 ||
                MediaQuery.textScalerOf(context).scale(1) > 1.4) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [verified, const SizedBox(height: 14), experimental],
              );
            }
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: verified),
                  const SizedBox(width: 16),
                  Expanded(child: experimental),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        _Panel(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.label_outline, color: AppColors.teal),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  named == null
                      ? 'Named output unavailable — class mapping unverified.'
                      : 'Named output: $named',
                  key: const Key('named-output'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                Icons.analytics_outlined,
                'Experimental AI results',
              ),
              const SizedBox(height: 12),
              if (ai != null)
                _AiDiagnostics(ai: ai)
              else
                const Text('Raw output scores: unavailable'),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const _SectionTitle(Icons.tune, 'Image-analysis measurements'),
        const SizedBox(height: 4),
        const Text(
          'Calculated from a manually selected fish-part ROI. Pixel descriptors, not freshness conclusions or TFLite input features.',
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final largeText = MediaQuery.textScalerOf(context).scale(1) > 1.3;
            final minimumWidth = largeText ? 230.0 : 160.0;
            final columns = ((constraints.maxWidth + 10) / (minimumWidth + 10))
                .floor()
                .clamp(1, 5);
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            final cards = <(IconData, String, String, String)>[
              (
                Icons.palette_outlined,
                'Mean Hue (H)',
                formatImageMeasurement(result.hue, unit: '°'),
                'Circular hue · degrees',
              ),
              (
                Icons.water_drop_outlined,
                'Saturation (S)',
                formatImageMeasurement(result.saturation, decimals: 2),
                'Mean saturation · 0–1',
              ),
              (
                Icons.brightness_6_outlined,
                'Brightness (V)',
                formatImageMeasurement(result.value, decimals: 2),
                'Pixel brightness · 0–1',
              ),
              (
                Icons.color_lens_outlined,
                'Red Sector',
                formatImageMeasurement(result.redFraction, percentage: true),
                'Share of valid hue samples',
              ),
              (
                Icons.crop_free,
                'Usable Area',
                formatImageMeasurement(result.usableFraction, percentage: true),
                'Usable / eligible ROI pixels',
              ),
            ];
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (var i = 0; i < cards.length; i++)
                  SizedBox(
                    width: width,
                    child: _Metric(
                      icon: cards[i].$1,
                      label: cards[i].$2,
                      value: cards[i].$3,
                      note: cards[i].$4,
                      index: i,
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 12),
        Text(
          metrics?.reason ??
              'Image descriptors are unavailable for this image.',
          key: const Key('metrics-reason'),
        ),
        if (metrics?.bounds case final bounds?)
          Text(
            'ROI: x ${bounds.left}, y ${bounds.top}, ${bounds.width} × ${bounds.height} pixels.',
          ),
        if (metrics?.usableFraction != null)
          Text(
            'Usable pixels: ${metrics!.usablePixels} / ${metrics.eligiblePixels}. '
            'Chromatic hue samples: ${metrics.huePixels}.',
            key: const Key('metrics-counts'),
          ),
        const SizedBox(height: 16),
        _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(Icons.info_outline, 'Inspection notes'),
              const SizedBox(height: 8),
              Text(result.reason, key: const Key('inspection-reason')),
              const SizedBox(height: 8),
              const Text(
                'The ROI is selected by the user; fish anatomy is not automatically verified. '
                'Brightness is an image value, not a physical illumination measurement. '
                'pH comes only from the separate sensor workflow.',
              ),
              const SizedBox(height: 8),
              const Text(
                'Experimental scores and HSV descriptors are not saved as confirmed pH or freshness measurements.',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VerifiedResult extends StatelessWidget {
  const _VerifiedResult({required this.part});
  final FishPart part;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          Icons.verified_user_outlined,
          'Freshness Classification',
        ),
        const SizedBox(height: 6),
        const Text('Verified Result', style: TextStyle(color: AppColors.muted)),
        const SizedBox(height: 16),
        const Text(
          'INCONCLUSIVE',
          key: Key('verified-freshness'),
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.navyDeep,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Verified freshness classification is not available for this inspection.',
        ),
        const SizedBox(height: 10),
        const Text(
          'Exact output-to-class provenance and adequate independent validation are still required.',
          key: Key('freshness-interpretation-reason'),
        ),
        if (part == FishPart.gills) ...[
          const SizedBox(height: 10),
          const Text(
            'Gills evaluation has known fish-level leakage. Independent-fish performance remains unverified.',
            key: Key('gills-validation-limit'),
          ),
        ],
      ],
    ),
  );
}

class _ExperimentalPrediction extends StatelessWidget {
  const _ExperimentalPrediction({required this.ai});
  final ExperimentalAiResult? ai;

  @override
  Widget build(BuildContext context) {
    final indices = ai?.leadingOutputIndices ?? const <int>[];
    final names = indices.map((i) => ai!.model.classNameForOutput(i)).toList();
    final heading = indices.isEmpty
        ? 'Prediction unavailable'
        : names.every((n) => n != null)
        ? names.join(' / ')
        : 'Class mapping unverified — ${indices.map((i) => 'Output $i').join(' / ')}';
    return _Panel(
      accent: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionTitle(
            Icons.science_outlined,
            'Experimental Prediction',
          ),
          const SizedBox(height: 16),
          Text(
            heading,
            key: const Key('experimental-prediction'),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: AppColors.navy,
            ),
          ),
          const SizedBox(height: 10),
          if (indices.isNotEmpty)
            Text(
              'Model score: ${(ai!.scores[indices.first] * 100).toStringAsFixed(2)}%',
              key: const Key('experimental-model-score'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            )
          else
            Text(ai?.status.label ?? 'Choose an image to begin.'),
          const SizedBox(height: 12),
          const Text(
            'Experimental AI prediction only. Not independently validated.',
          ),
          const SizedBox(height: 8),
          const Text(
            'The score is a model output, not calibrated freshness confidence. It does not change the verified result.',
          ),
        ],
      ),
    );
  }
}

class _AiDiagnostics extends StatelessWidget {
  const _AiDiagnostics({required this.ai});
  final ExperimentalAiResult ai;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final identity = _ModelInformation(ai: ai);
      final scores = _OutputScores(ai: ai);
      if (constraints.maxWidth < 760 ||
          MediaQuery.textScalerOf(context).scale(1) > 1.4) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [identity, const SizedBox(height: 16), scores],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: identity),
          const SizedBox(width: 16),
          Expanded(child: scores),
        ],
      );
    },
  );
}

class _ModelInformation extends StatelessWidget {
  const _ModelInformation({required this.ai});
  final ExperimentalAiResult ai;
  @override
  Widget build(BuildContext context) => InspectionCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InspectionHeading(
          icon: Icons.memory_outlined,
          title: 'Model details',
        ),
        const SizedBox(height: 14),
        Text(
          'Inference status: ${ai.status.label}',
          key: const Key('ai-status'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Text('Model: ${ai.model.filename}', key: const Key('ai-model')),
        const SizedBox(height: 6),
        Text('Version: ${ai.model.version}', key: const Key('ai-version')),
        if (ai.model.isCandidate)
          const Text(
            'Separate fine-tuned candidate; not the default Scales model.',
          ),
        ExpansionTile(
          key: ValueKey('model-hash-${ai.model.name}'),
          tilePadding: EdgeInsets.zero,
          title: const Text('Full model identity (SHA-256)'),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: SelectableText(
                ai.model.sha256,
                key: const Key('ai-full-hash'),
              ),
            ),
          ],
        ),
        if (ai.runtime != null) Text('Runtime: ${ai.runtime}'),
        if (ai.inferenceMicroseconds case final duration?
            when duration >= 0) ...[
          const SizedBox(height: 8),
          Text('Inference time: ${(duration / 1000).toStringAsFixed(1)} ms'),
        ],
        const SizedBox(height: 12),
        Text(
          ai.message,
          key: const Key('ai-message'),
          style: const TextStyle(height: 1.5),
        ),
      ],
    ),
  );
}

class _OutputScores extends StatelessWidget {
  const _OutputScores({required this.ai});
  final ExperimentalAiResult ai;
  @override
  Widget build(BuildContext context) => InspectionCard(
    padding: const EdgeInsets.all(18),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const InspectionHeading(
          icon: Icons.bar_chart_rounded,
          title: 'Output distribution',
        ),
        const SizedBox(height: 14),
        const Text(
          'Raw output scores',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text(
          'Index order is preserved. Scores are not calibrated freshness confidence.',
        ),
        const SizedBox(height: 12),
        if (ai.scores.isEmpty)
          const Text('Raw output scores: unavailable')
        else ...[
          for (var i = 0; i < ai.scores.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F8F8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Output $i: ${ai.scores[i].isFinite ? ai.scores[i].toStringAsPrecision(7) : 'N/A'}',
                    key: Key('ai-output-$i'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (ai.hasValidDistribution) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        key: Key('ai-score-bar-$i'),
                        value: ai.scores[i],
                        minHeight: 8,
                        color: AppColors.teal,
                        backgroundColor: AppColors.line,
                        semanticsLabel: 'Output $i raw model score',
                        semanticsValue: ai.scores[i].toStringAsPrecision(7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${(ai.scores[i] * 100).toStringAsFixed(2)}% model score',
                      style: const TextStyle(
                        color: AppColors.teal,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          Text(
            'Softmax distribution check: ${ai.hasValidDistribution ? 'passed' : 'failed'}',
          ),
          const SizedBox(height: 6),
          const Text(
            'This checks numerical consistency only; it does not validate freshness.',
          ),
        ],
      ],
    ),
  );
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
    required this.note,
    required this.index,
  });
  final IconData icon;
  final String label, value, note;
  final int index;

  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.teal.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: AppColors.teal, size: 24),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          key: Key('image-metric-$index'),
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: AppColors.navy,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          note,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.muted,
            height: 1.4,
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.accent = false});
  final Widget child;
  final bool accent;
  @override
  Widget build(BuildContext context) =>
      InspectionCard(accent: accent, child: child);
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: AppColors.teal, size: 21),
      const SizedBox(width: 9),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: AppColors.navy,
          ),
        ),
      ),
    ],
  );
}
