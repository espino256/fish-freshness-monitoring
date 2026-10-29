import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import '../models/telemetry.dart';
import '../models/fish_sample.dart';
import 'gill_analysis_service.dart';

/// Synthetic telemetry/image fixtures for component tests. There are no local
/// identities or authentication methods. Production does not install DemoScope.
class DemoSession extends ChangeNotifier {
  bool enabled = false, autoTelemetry = false;
  String reason = '';
  double ph = 6.3;
  int _sequence = 0;
  Timer? _timer;
  final List<Telemetry> records = [];
  final List<VisualAnalysisRecord> images = [];
  final Map<int, bool> leds = {27: true, 25: false, 26: false};
  bool manualLeds = false;

  late final Stream<List<Telemetry>> live = _watch(
    () => records.isEmpty ? [] : [records.first],
  );
  late final Stream<List<Telemetry>> history = _watch(
    () => List.unmodifiable(records),
  );
  late final Stream<List<VisualAnalysisRecord>> analyses = _watch(
    () => List.unmodifiable(images),
  );
  Stream<List<T>> _watch<T>(List<T> Function() read) => Stream.multi((sink) {
    void update() => sink.add(read());
    update();
    addListener(update);
    sink.onCancel = () => removeListener(update);
  });

  void enable({String message = 'Synthetic component-test data.'}) {
    enabled = true;
    reason = message;
    if (records.isEmpty) {
      for (final value in [7.4, 6.8, 6.3]) {
        _append(value);
      }
    }
    notifyListeners();
  }

  void _append(double value) {
    final adc = (value / 14 * 3200 + 400).clamp(1, 4094).toDouble();
    records.insert(
      0,
      Telemetry(
        id: 'demo-${_sequence++}',
        deviceId: 'DEMO-ESP32',
        ph: value,
        adcRaw: adc,
        measuredVoltage: adc * 3.3 / 4095,
        timestamp: DateTime.now().toUtc(),
      ),
    );
    if (records.length > 500) records.removeLast();
  }

  void setPh(double value) {
    classifyPh(value); // Domain validation before mutation.
    ph = value;
    manualLeds = false;
    final pin = switch (classifyPh(ph)) {
      FishStatus.fresh => 27,
      FishStatus.moderate => 25,
      FishStatus.spoiled => 26,
    };
    for (final key in leds.keys) {
      leds[key] = key == pin;
    }
    _append(ph);
    notifyListeners();
  }

  void toggleLed(int pin) {
    if (!leds.containsKey(pin)) return;
    manualLeds = true;
    leds[pin] = !leds[pin]!;
    notifyListeners();
  }

  void refresh() => setPh(ph);
  void setAutomatic(bool value) {
    autoTelemetry = value;
    _timer?.cancel();
    if (value && enabled) {
      _timer = Timer.periodic(
        const Duration(seconds: 5),
        (_) => setPh((6.8 + math.sin(_sequence / 3) * 0.9).clamp(0, 14)),
      );
    }
    notifyListeners();
  }

  void clearHistory() {
    records.clear();
    images.clear();
    refresh();
  }

  void saveAnalysis(String sampleId, GillAnalysis result) {
    images.insert(
      0,
      VisualAnalysisRecord(
        id: 'demo-image-${_sequence++}',
        sampleId: sampleId,
        meanHue: result.hue,
        classification: result.classification,
        timestamp: DateTime.now().toUtc(),
      ),
    );
    if (images.length > 500) images.removeLast();
    notifyListeners();
  }

  /// Synthetic calibration target, visibly labeled in the viewer. It is not a
  /// real fish photograph or inspection result.
  Uint8List cameraFrame({
    int width = 640,
    int height = 480,
    bool flash = false,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(22, 49, 62));
    final cx = width ~/ 2, cy = height ~/ 2;
    for (var y = cy - 110; y < cy + 110; y++) {
      for (var x = cx - 110; x < cx + 110; x++) {
        if (x < 0 || y < 0 || x >= width || y >= height) continue;
        final stripe = ((x + y) ~/ 12).isEven;
        image.setPixelRgb(
          x,
          y,
          flash ? 235 : (stripe ? 195 : 165),
          stripe ? 35 : 25,
          42,
        );
      }
    }
    return img.encodeJpg(image, quality: 85);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class DemoScope extends InheritedNotifier<DemoSession> {
  const DemoScope({
    super.key,
    required DemoSession session,
    required super.child,
  }) : super(notifier: session);
  static DemoSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DemoScope>()?.notifier;
}
