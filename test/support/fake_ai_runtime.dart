import 'dart:typed_data';

import 'package:aqua_sense/services/ai/ai_runtime.dart';

/// Test double only. Never used by the application or platform inference tests.
class FakeAiRuntime implements AiRuntime {
  List<double> scores = [0.2, 0.3, 0.5];
  List<int> shape = [1, 3];
  Object? failure;
  Future<void> Function()? onRun;
  int calls = 0;
  int disposals = 0;
  Float32List? lastInput;

  @override
  Future<AiTensorOutput> run(Float32List input) async {
    calls++;
    lastInput = input;
    await onRun?.call();
    if (failure case final error?) throw error;
    return AiTensorOutput(
      scores: scores,
      shape: shape,
      runtime: 'Injected test double',
      inferenceMicroseconds: 0,
    );
  }

  @override
  Future<void> dispose() async {
    disposals++;
  }
}
