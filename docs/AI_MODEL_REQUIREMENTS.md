# AI model requirements

## Inspection of the bundled file (2026-11-22)

The binary was inspected directly using `python tools/inspect_tflite.py`. It is
registered correctly in `pubspec.yaml`. It has not been replaced or modified.

| Property | Observed value |
| --- | --- |
| File | `assets/models/fish_freshness_model.tflite` |
| Size | 9,542,724 bytes |
| SHA-256 | `c2f3f4aa6555bedc811d87d756441b3f49979e73620737392227308d41a5b44c` |
| Identifier / schema | `TFL3` / 3 |
| Description | `MLIR Converted.` |
| Subgraphs / tensors / operations | 1 / 180 / 68 |
| Input | `serving_default_input_layer_1:0`, FLOAT32 `[1,224,224,3]`, signature `[-1,224,224,3]` |
| Output | `StatefulPartitionedCall_1:0`, FLOAT32 `[1,3]`, signature `[-1,3]` |
| Input/output quantization | No scales or zero points; float tensors |
| Operators | MUL ×1, ADD ×11, CONV_2D ×35, DEPTHWISE_CONV_2D ×17, MEAN ×1, FULLY_CONNECTED ×2, SOFTMAX ×1 |
| Operator versions | All version 1; no custom or Flex operators |
| Final operator | SOFTMAX |
| Metadata entries | `min_runtime_version` (string `1.6.0`), `CONVERSION_METADATA` (contains string `2.21.0`) |
| Semantic metadata / labels | No `TFLITE_METADATA`, appended ZIP, or accompanying label files |
| Proven trained fish parts | None supplied |
| Scientific evaluation / acceptance criteria | None supplied |

Tensor names contain `mobilenetv2_1.00_224`, consistent with a MobileNetV2-based
network. This is an architectural inference, not evidence of its training data.
The three output positions cannot be assigned Fresh, Moderate, or Spoiled from
their count, filename, tensor names, or softmax activation.

## Preprocessing findings

The graph starts with MUL by `0.007843137718737125` (approximately `1/127.5`)
and ADD of `-1.0`. Thus this transformation is already inside the model:
`y = x * 0.007843137718737125 - 1`.
For values 0–255 it produces approximately -1–1. Do not apply this transformation
again in a future client. Raw 0–255 float pixels are a plausible input convention,
but the graph alone does not prove what the training loader actually supplied.

The tensor dimensions establish a 224×224, three-channel input, using the
NHWC convention of the built-in convolution operators. RGB versus BGR, resize
algorithm, crop/region selection, aspect-ratio handling, alpha/background handling,
and the training-time preprocessing pipeline are undocumented. There is no
in-graph resize. These details must be recovered and checked against reference
inputs and outputs from the training pipeline before deployment.

Google documents the distinction between semantic metadata, label files, and
normalization in its [LiteRT metadata specification](https://developers.google.com/edge/litert/conversion/tensorflow/metadata).
Structural inspection follows the [TensorFlow schema](https://github.com/tensorflow/tensorflow/blob/v2.20.0/tensorflow/compiler/mlir/lite/schema/schema.fbs).

## Runtime compatibility check

The model successfully loaded, allocated tensors, and executed with
`ai-edge-litert==2.4.0` on Windows x64, Python 3.14.4, using the CPU/XNNPACK
runtime. Three synthetic float32 inputs (all zero, all 255, and a 0–255 ramp)
each produced finite `[1,3]` outputs. Their sums were respectively
`0.9999999403953552`, `1.0`, and `1.0`. Repeating each invocation gave a maximum
absolute output difference of `0.0` (six invocations total).

This establishes execution on that desktop runtime only. It does not validate
freshness labels, confidence calibration, accuracy, fish-part recognition, real
images, Android/iOS deployment, or Flutter integration. The embedded minimum
runtime string is descriptive metadata, not a substitute for target testing.

Reproduce structural inspection without Python dependencies:

```powershell
python tools/inspect_tflite.py
```

Optional runtime check, using dependencies isolated under the ignored build folder:

```powershell
python -m pip install --target build/model_audit/runtime ai-edge-litert==2.4.0 numpy
python -c "import sys,runpy; sys.path.insert(0,'build/model_audit/runtime'); sys.argv=['tools/inspect_tflite.py','--smoke-test']; runpy.run_path('tools/inspect_tflite.py',run_name='__main__')"
```

The inspection utility reads selected schema-v3 fields; it is not a complete
FlatBuffer verifier. Its optional smoke check executes real inference but does
not map output positions to labels or invent an acceptance threshold.

## Application behavior after experimental integration

`VisualInspectionService.inspect` does not load or invoke the original file.
The camera now calls `AiInferenceService` for experimental inference with the four
new named per-part exports. Confirmed freshness remains Inconclusive. Gills,
Eyes, and Skin / Scales are manual selections, not detections. No part has a
scientifically validated deployed classifier. Missing or unsupported models
cannot trigger an alternate classifier or heuristic fallback. See
[the experimental integration report](EXPERIMENTAL_AI_INTEGRATION.md) for current
model identities, notebook findings, platform execution and test results.

The service's existing exposure/detail limits are basic acquisition checks, not
scientifically validated model acceptance criteria, blur detection, or evidence
that a fish is present. The later [ROI redesign](AI_INSPECTION_ROI_REDESIGN.md)
calculates real HSV pixel descriptors only after a manual region is applied;
missing or unsuitable measurements remain `null` and render as `N/A`.
These are not verified anatomy or freshness measurements. No image-derived pH,
confidence, HSV freshness label, or saved
classification is fabricated. The historical HSV service and existing history
utilities remain in the repository; they are not used by the active camera route.

The subsequent experimental integration uses the installed `flutter_litert`
4.2.0 package, pinned to the inspected API. It does not enable confirmed freshness
classifications. The original model audited above is not substituted for any
of the named Gills, Eyes, or Scales exports.

## Required before classification can be enabled

1. Obtain the training/export source, provenance, permission to deploy, and the
   exact ordered class-index map tied to this model's SHA-256. Confirm whether
   these three outputs mean the requested freshness classes at all.
2. Document trained species and fish parts. Train separate models or validate
   explicit multi-part coverage. A manual selection is not evidence that the
   selected anatomy is present. Do not reuse a gill model for eyes or skin
   without independent evidence.
3. Recover the full preprocessing pipeline and reference image/tensor/output
   fixtures; compare export and target-device results, including the embedded
   rescaling layer and channel order.
4. Supply an independently held-out, representative dataset with scientifically
   grounded freshness reference labels. Document splits that avoid leakage
   between images from the same fish/session, class support, confusion matrices,
   per-class performance and uncertainty, species, lighting and capture conditions.
5. Establish and validate acceptance/abstention criteria, confidence calibration,
   wrong-part/non-fish rejection and unsuitable/out-of-distribution image handling.
   Do not choose a confidence cutoff simply because it looks plausible.
6. Integrate only the verified part-to-model mappings. Keep Inconclusive for
   unsupported parts, missing/corrupt assets, preprocessing or inference errors,
   unexpected shapes, non-finite/invalid outputs, and failed acceptance criteria.
   Add reference-fixture tests and real Android/iOS inference tests before release.

## Earlier workflow verification before experimental integration

On 2026-11-22, using Flutter 3.41.8 / Dart 3.11.5:

- `flutter analyze`: no issues found.
- `flutter test`: all 71 tests passed, with no skipped tests.
- Added/updated unit tests cover abstention for every part, corrupt/small/oversized
  inputs, exposure/detail rejection, 16-bit PNG handling, and optional/non-finite
  measurement formatting. Widget tests exercise actual gallery callbacks with
  local test files, each manual part selection at 320 pixels, reason visibility,
  five `N/A` metrics, selection changes, cancellation, corrupt previews,
  oversized uploads, and unreadable uploads replacing earlier results.
- Existing authentication, pH, camera controls, history, and reporting tests pass.
- `git diff --check`: passed. The bundled model's SHA-256 is unchanged.

Real Firebase/Google OAuth, physical ESP32/pH hardware, native gallery dialogs,
and Android/iOS model inference were not exercised. No trained-part or scientific
freshness validation could be run because the required labels, dataset, and
criteria are absent. The synthetic runtime check above is separate from the
Flutter suite and does not supply that missing evidence.
