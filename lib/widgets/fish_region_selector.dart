import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

import '../core/app_theme.dart';
import '../models/image_region.dart';
import '../models/visual_inspection.dart';
import 'inspection_card.dart';

/// Rectangle selection in the actual displayed image, with keyboard controls.
class FishRegionSelector extends StatefulWidget {
  const FishRegionSelector({
    super.key,
    required this.bytes,
    required this.width,
    required this.height,
    required this.part,
    required this.busy,
    required this.onChanged,
    required this.onApply,
    required this.onRotate,
    required this.onChangeImage,
  });
  final Uint8List bytes;
  final int width, height;
  final FishPart part;
  final bool busy;
  final VoidCallback onChanged, onRotate, onChangeImage;
  final ValueChanged<ImageRegion> onApply;

  @override
  State<FishRegionSelector> createState() => _FishRegionSelectorState();
}

class _FishRegionSelectorState extends State<FishRegionSelector>
    with AutomaticKeepAliveClientMixin<FishRegionSelector> {
  ImageRegion _region = const ImageRegion(0.15, 0.15, 0.85, 0.85);
  Offset? _anchor;

  // Scrolling to the results must not silently replace a user's draft ROI.
  @override
  bool get wantKeepAlive => true;

  void _change(ImageRegion region) {
    setState(() => _region = region);
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final pixels = _region.pixels(widget.width, widget.height);
    return InspectionCard(
      key: const Key('image-roi-panel'),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Fish image preview · ${widget.part.label}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              Text('${widget.width} × ${widget.height} pixels'),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final ratio = widget.width / widget.height;
              final width = math.min(constraints.maxWidth, 380 * ratio);
              final height = width / ratio;
              Offset normalized(Offset local) => Offset(
                (local.dx / width).clamp(0, 1),
                (local.dy / height).clamp(0, 1),
              );
              return Center(
                child: SizedBox(
                  width: width,
                  height: height,
                  child: Semantics(
                    label:
                        'Draw a rectangle around only the ${widget.part.label}. Keyboard region controls are below.',
                    child: GestureDetector(
                      key: const Key('roi-image-gesture'),
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: widget.busy
                          ? null
                          : (details) {
                              _anchor = normalized(details.localPosition);
                              _change(
                                ImageRegion(
                                  _anchor!.dx,
                                  _anchor!.dy,
                                  _anchor!.dx,
                                  _anchor!.dy,
                                ),
                              );
                            },
                      onPanUpdate: widget.busy
                          ? null
                          : (details) {
                              final end = normalized(details.localPosition);
                              final start = _anchor!;
                              _change(
                                ImageRegion(
                                  math.min(start.dx, end.dx),
                                  math.min(start.dy, end.dy),
                                  math.max(start.dx, end.dx),
                                  math.max(start.dy, end.dy),
                                ),
                              );
                            },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              widget.bytes,
                              fit: BoxFit.contain,
                              gaplessPlayback: true,
                              errorBuilder: (_, _, _) => const Center(
                                child: Text('Image preview unavailable.'),
                              ),
                            ),
                            IgnorePointer(
                              child: CustomPaint(
                                painter: _RegionPainter(_region),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Outline only the visible ${widget.part.label.toLowerCase()}; exclude background. '
            'The rectangle is a manual selection, not verified anatomy or automatic segmentation.',
          ),
          if (pixels != null)
            Text(
              'Draft ROI: x ${pixels.left}, y ${pixels.top}, ${pixels.width} × ${pixels.height} pixels',
              key: const Key('roi-pixel-bounds'),
            ),
          ExpansionTile(
            title: const Text('Adjust region with keyboard or sliders'),
            tilePadding: EdgeInsets.zero,
            children: [
              const Text('Horizontal region (left to right)'),
              RangeSlider(
                key: const Key('roi-horizontal'),
                values: RangeValues(_region.left, _region.right),
                labels: RangeLabels(
                  '${(_region.left * 100).round()}%',
                  '${(_region.right * 100).round()}%',
                ),
                onChanged: widget.busy
                    ? null
                    : (v) => _change(
                        ImageRegion(
                          v.start,
                          _region.top,
                          v.end,
                          _region.bottom,
                        ),
                      ),
              ),
              const Text('Vertical region (top to bottom)'),
              RangeSlider(
                key: const Key('roi-vertical'),
                values: RangeValues(_region.top, _region.bottom),
                labels: RangeLabels(
                  '${(_region.top * 100).round()}%',
                  '${(_region.bottom * 100).round()}%',
                ),
                onChanged: widget.busy
                    ? null
                    : (v) => _change(
                        ImageRegion(
                          _region.left,
                          v.start,
                          _region.right,
                          v.end,
                        ),
                      ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const Key('apply-roi'),
                onPressed: widget.busy || !_region.isValid
                    ? null
                    : () => widget.onApply(_region),
                icon: const Icon(Icons.crop),
                label: const Text('Apply region & analyze'),
              ),
              OutlinedButton.icon(
                onPressed: widget.busy ? null : widget.onRotate,
                icon: const Icon(Icons.rotate_right),
                label: const Text('Rotate image'),
              ),
              TextButton.icon(
                onPressed: widget.busy ? null : widget.onChangeImage,
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('Change image'),
              ),
            ],
          ),
          const Text(
            'ROI controls the five image descriptors only. AI keeps its existing full-image RGB input.',
          ),
        ],
      ),
    );
  }
}

class _RegionPainter extends CustomPainter {
  const _RegionPainter(this.region);
  final ImageRegion region;

  @override
  void paint(Canvas canvas, Size size) {
    if (!region.isValid) return;
    final rect = Rect.fromLTRB(
      region.left * size.width,
      region.top * size.height,
      region.right * size.width,
      region.bottom * size.height,
    );
    final shade = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(rect);
    canvas.drawPath(
      shade,
      Paint()..color = Colors.black.withValues(alpha: 0.40),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = AppColors.aqua
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_RegionPainter oldDelegate) =>
      oldDelegate.region != region;
}
