# Experimental AquaSense inference

For the current photo/ROI workflow, descriptor formulas and latest checks, see
[the image-inspection redesign report](AI_INSPECTION_ROI_REDESIGN.md). Platform
results below describe the earlier integration unless otherwise dated.

## What the application does

The camera/gallery pipeline calls `AiInferenceService.analyze` asynchronously.
`compute()` is used only for image decoding, the existing quality checks, and
RGB tensor preparation. It never owns a model or native interpreter.

The UI displays selected anatomy, actual model filename, a SHA-256 identity in
place of an invented version number, inference status, runtime, and raw
`Output 0`, `Output 1`, `Output 2` scores. A finite softmax distribution is a
numerical check, not proof of freshness or calibrated confidence. Confirmed
Fresh/Moderate/Spoiled classification and saving remain disabled. No scores are
sent to Firebase or recorded as freshness, HSV, or pH measurements.

Selecting another part/model or opening a new image clears earlier results.
Invalid images do not load a model. Missing/changed assets, unsupported
operators, runtime failures, wrong tensor contracts and invalid outputs produce
explicit diagnostic statuses while confirmed freshness stays Inconclusive.

## Exact model identities

All five binaries were preserved. The original `fish_freshness_model.tflite`
remains registered, but is not assigned to an anatomical region.

| Selected part | Export | SHA-256 |
| --- | --- | --- |
| Gills | aquasense_gills_model.tflite | adfa10b697c409a7b1848945acef11b59d726bda15f8ed7e0d2d557a9e9225dd |
| Eyes | aquasense_eyes_model.tflite | 2c774dd79cfcd95e4d97a110e7eaaea6eb07306b01e9d97a0fc57f371792b5af |
| Skin / Scales (default) | aquasense_scales_model.tflite | 2a5fbddbe50471aaac627eb2bcd4e87d690103bd02795dbaf7db08c4f05ee494 |
| Explicit Scales candidate | aquasense_scales_finetuned_model.tflite | d1dcf791f02e38696e912e37a4e8a648ec6dc17a3fd8ba6685bd7e99304a5d7e |

The loader verifies each asset hash before use. Replacing a model requires an
intentional audit and catalogue update. No automatic candidate substitution or
cross-part model fallback is allowed.

Each new file has float32 input `[1,224,224,3]`, float32 output `[1,3]`, and ends
with softmax. Each contains 67 standard version-1 operations: MUL ×1, ADD ×11,
CONV_2D ×35, DEPTHWISE_CONV_2D ×17, MEAN ×1, FULLY_CONNECTED ×1, SOFTMAX ×1.
There are no custom/Flex operators. The new gills/eyes files are 8,901,272 bytes;
both scales files are 8,901,916 bytes, with different hashes/weights.

Reproduce the structural audit with `python tools/inspect_tflite.py MODEL_PATH`.

## Notebook evidence and remaining limits

The supplied files were inspected without executing their training cells:

- `docs/ai_training/AquaSense_WholeFish_Freshness_Training.ipynb`
- `docs/ai_training/AquaSense_Model_Validation.ipynb`

The training loaders explicitly use RGB decode, `tf.image.resize` to 224×224
(default bilinear), float32 casts, and no external normalization. Gills and
Eyes/Scales loaders use the same convention. The graphs independently confirm
MUL `0.007843137718737125` then ADD `-1.0`, equivalent to `x/127.5-1`.
The app supplies 0–255 RGB floats and does not apply that transformation twice.
Its resampler uses half-pixel coordinates and retains fractional pixel values,
instead of rounding resized images to uint8. Existing EXIF orientation handling
is retained; exact JPEG decoding/EXIF parity still needs real-image fixtures.

The notebooks explicitly declare `FRESH=0`, `MODERATE=1`, `SPOILED=2` in their
training/evaluation code. This documents the training convention. The local
exports have no embedded label files, and the hash-bearing export report and
corresponding `.keras` files were not supplied to tie that convention to these
exact binaries, particularly the fine-tuned candidate. The UI therefore retains
index-only output labels as requested.

Validation notebook cell 87 converts four named `.keras` files with
`converter.optimizations=[]`, checks float32 tensor shapes, and records a
synthetic constant-input Keras/TFLite comparison. Its recorded maximum absolute
differences are approximately 5.19e-6 (gills), 1.07e-6 (eyes), 7.75e-6 (scales),
and 5.72e-6 (candidate). These are notebook-recorded synthetic checks, not new
local executions or real-image parity evidence.

The reported Gills test-split accuracy of 72.93% is a preliminary baseline with
confirmed fish-level leakage. It is not independent-fish performance or a
scientifically validated accuracy claim. No production confidence cutoff is
introduced. Independent fish-level validation, wrong-part/non-fish rejection,
species/capture coverage, confidence calibration and acceptance criteria remain
required before confirmed labels can be enabled.

## Runtime implementation and setup

The API was checked against the installed source of `flutter_litert` **4.2.0**,
which is pinned in `pubspec.yaml`. See the
[official package repository](https://github.com/google-ai-edge/flutter_litert).

- Native: assets are loaded on the main isolate, hash-checked and cached.
  Each inference worker constructs, invokes and closes its own CPU Interpreter
  using `Isolate.run`; no native pointer is shared with `compute()` or another
  isolate. Interpreter options are disposed in `finally`. Loading cached bytes
  into a fresh interpreter costs more startup time than retaining one worker,
  but keeps ownership and failure cleanup explicit for single-image analysis.
- Browser: the package's asynchronous `LiteRtInterpreter` uses LiteRT.js 2.6.0
  with CPU/WASM. Loaded models are cached, requests serialized and resources
  released after in-flight work completes. Model initialization has a timeout
  and abandoned late loads are disposed.
  LiteRT.js requires static signatures. The exports' concrete shapes are batch
  one, but their shape signatures contain a dynamic batch (`-1`). Passing them
  directly caused `Invalid typed array length: -12` in an actual Chrome run.
  The browser now binds those signatures to their existing batch-one dimensions
  in a byte copy held in memory. No asset, weight or operation is overwritten.
  Only signature metadata can change; unsupported dynamic dimensions are rejected.
  All four copies were independently compared with the original models on Python
  LiteRT 2.4.0 using an identical synthetic RGB tensor: maximum output difference
  was exactly `0.0` for each. Dart unit tests compare the entire resulting byte
  hashes against the independent Python implementation and verify unchanged
  original hashes. Each export changes exactly 272 signature bytes in the copy.
  The static-dimension restriction is documented in
  [Google's LiteRT.js guide](https://developers.google.com/edge/litert/web/get_started).
- The default web loader requires access to `cdn.jsdelivr.net` for its pinned
  JavaScript/WASM files. Offline/restricted deployments need self-hosted runtime
  files configured through `configureLiteRtWebLoader` before the first load.
  A browser lacking the required runtime displays Runtime unavailable.
- Android uses the package's default bundled CPU runtime. No Android device or
  emulator was available; Android execution must still be verified.

## Reproducible checks

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
# Run the real-model integration app in Chrome, including console test output:
flutter run -d chrome -t integration_test/experimental_ai_test.dart --no-web-resources-cdn
# On an attached Android device/emulator:
flutter test integration_test/experimental_ai_test.dart -d DEVICE_ID
# Chrome CI can alternatively use ChromeDriver and Flutter's integration driver:
flutter drive --driver=test_driver/integration_test.dart --target=integration_test/experimental_ai_test.dart -d chrome
```

The platform suite uses no test doubles. It requires each actual bundled model
to load, infer twice on an RGB fixture, produce a finite distribution and remain
Inconclusive. It emits `AQUASENSE_INFERENCE` records only after execution succeeds.
These are synthetic execution checks, not fish-recognition validation.

## Real-image Keras reference comparison

No original real-image input plus corresponding Keras output/tensor fixture was
supplied. Notebook plot montages are not identical original inputs and are not
used to fabricate parity results. The optional platform parity test is skipped
explicitly until fixtures are supplied.

In the original training environment, with the corresponding real image and
saved Keras model, export a reference without modifying any model:

```powershell
python tools/export_ai_reference.py --keras PATH_TO_MODEL.keras --tflite assets/models/aquasense_gills_model.tflite --image REAL_IMAGE.png --output assets/ai_reference/gills
```

Copy the output directory into the Flutter project if exported in Colab. Register
it in `pubspec.yaml`, keeping the manifest's asset keys project-relative. Then run
the platform suite with
`--dart-define=AQUASENSE_AI_REFERENCE_ASSET=assets/ai_reference/gills/reference.json`.
The test verifies the model/image/tensor hashes, compares preprocessing to the
saved TensorFlow tensor, and runs the exact same real-image float32 tensor
against the platform runtime and reference Keras scores. Numerical tolerances
are separate from scientific acceptance criteria.

## Verification results

`flutter pub get` completed. Final `flutter analyze` reported no issues and
`flutter test` passed all **97** unit/widget tests. This includes real asset/hash
checks, preprocessing, per-part routing, explicit candidate selection,
softmax/type/shape rejection, load/runtime failures, recovery/disposal, and the
existing authentication, camera controls, pH, history and reporting regressions.
The full unit/widget suite has no skipped tests.

The actual app compiled and launched with `flutter run -d chrome` (headless for
this session). Separately, the real-model integration app executed all four
exports twice in Chrome 157 using flutter_litert 4.2.0 / LiteRT.js 2.6.0 / WASM.
All four execution/repeatability checks passed, first using a 241×173 synthetic
RGB image through the application preprocessing path. A fresh final Chrome run
then used the same 224×224 synthetic RGB fixture as the original Python CPU
checks. All four models passed numerical comparison against those original-file
reference scores; their observed float32 scores matched the Python values below.
The optional real-image Keras parity test was explicitly skipped because no
reference fixtures were supplied. The suite's extra teardown test count is
framework housekeeping, not a fifth model.

| Model | Output 0 | Output 1 | Output 2 | Final Chrome result |
| --- | --- | --- | --- | --- |
| Gills | 0.6140145659446716 | 0.05207594111561775 | 0.3339095413684845 | PASS |
| Eyes | 0.959062933921814 | 0.02609533816576004 | 0.014841724187135696 | PASS |
| Original Scales | 0.6892409324645996 | 0.10791781544685364 | 0.20284128189086914 | PASS |
| Fine-tuned candidate | 0.5372974872589111 | 0.2518008053302765 | 0.21090169250965118 | PASS |

These are actual synthetic-fixture execution scores, not real-fish predictions,
class names, accuracy values or calibrated confidence estimates.

Independent Python CPU checks passed for all four original files and their
in-memory batch-one copies, with exactly zero output difference. Dart's full-byte
hash comparison against those independent copies passed for all four exports.

An attempted standalone Flutter browser-test harness was blocked before model
execution by SDK CanvasKit `.js`/`.wasm` URLs returning 404 on Windows. The SDK
source converts request paths to Windows paths but checks a slash-separated
prefix. Verification therefore uses the integration app launcher above; no SDK
files were edited. The initial direct LiteRT.js dynamic-signature failure was
resolved by the tested in-memory batch-one binding.

Android inference remains **pending**: `flutter devices` listed Windows, Chrome
and Edge only, and `flutter emulators` reported no emulators. No Android, iOS,
physical ESP32/pH, production Firebase or Google OAuth integration pass is claimed.
The reference exporter was syntax/CLI checked only; Keras inference from original
real-image inputs remains pending for the `.keras` files and reference images.

## Exact implementation files changed or added

Application and dependencies:

- `pubspec.yaml`
- `pubspec.lock`
- `lib/models/visual_inspection.dart`
- `lib/models/experimental_ai.dart`
- `lib/services/visual_inspection_service.dart`
- `lib/services/ai_inference_service.dart`
- `lib/services/ai/ai_runtime.dart`
- `lib/services/ai/ai_runtime_native.dart`
- `lib/services/ai/ai_runtime_web.dart`
- `lib/services/ai/batch_one_model.dart`
- `lib/screens/camera_screen.dart`

Tests and tooling:

- `test/ai_inference_service_test.dart`
- `test/batch_one_model_test.dart`
- `test/camera_visual_inspection_test.dart`
- `test/support/fake_ai_runtime.dart`
- `integration_test/experimental_ai_test.dart`
- `integration_test/support/ai_platform_checks.dart`
- `test_driver/integration_test.dart`
- `tools/inspect_tflite.py`
- `tools/export_ai_reference.py`

Documentation:

- `README.md`
- `docs/AI_MODEL_REQUIREMENTS.md`
- `docs/EXPERIMENTAL_AI_INTEGRATION.md`

The four new model files and two notebooks were supplied by the user; none was
overwritten. Pre-existing generated Windows changes and earlier workflow edits
were retained. Firebase/authentication, ESP32 transport, pH policy, history,
firmware and database/storage rules were not rewritten by this integration.

## Subsequent UI audit

See [the experimental inspection UI audit](EXPERIMENTAL_AI_UI_AUDIT.md) for the
later presentation changes, navigation rename, additional safeguards/tests and
fresh platform verification. The model identities and inference implementation
documented above remain unchanged by that UI work.
