import 'dart:typed_data';

import 'package:aqua_sense/models/experimental_ai.dart';
import 'package:aqua_sense/services/ai/ai_runtime.dart';
import 'package:aqua_sense/services/ai/batch_one_model.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Independently computed by Python's schema reader and CPU inference check.
  const expected = {
    ExperimentalFishModel.gills:
        '58aec2d04c71fa7d2bcf1af577de60fa5e2a867b675e1846f3d6c1c246c4fb64',
    ExperimentalFishModel.eyes:
        'b9c692da0780fb3fa5a485be8421db77b193b7ac1f4038e6ac35d27a1a1e95b2',
    ExperimentalFishModel.scales:
        '3bb45ef2c30f4bf87bc5799aa00658790163238bd99e6591753df5f66f00045b',
    ExperimentalFishModel.scalesFinetuned:
        '8e4643b79187f2ce1c4c3f460a1df973b14703df78f9481e4c7cda23609e72a8',
  };
  for (final model in ExperimentalFishModel.values) {
    test(
      '${model.filename} batch binding matches independent reference and preserves original',
      () async {
        final original = await loadModelBytes(model);
        final bound = specializeBatchOne(original);
        expect(sha256.convert(original).toString(), model.sha256);
        expect(sha256.convert(bound).toString(), expected[model]);
        expect(bound.length, original.length);
        expect(
          Iterable<int>.generate(
            bound.length,
          ).where((i) => bound[i] != original[i]).length,
          272,
        );
        // Binding is idempotent; no weights change on repeated preparation.
        expect(
          sha256.convert(specializeBatchOne(bound)).toString(),
          expected[model],
        );
      },
    );
  }
  test('batch specialization rejects invalid model bytes', () {
    expect(
      () => specializeBatchOne(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
  });
}
