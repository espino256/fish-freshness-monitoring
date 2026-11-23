# Experimental AI inspection UI audit

Historical report, superseded for presentation and measurements by the
[ROI redesign report](AI_INSPECTION_ROI_REDESIGN.md). Its previous N/A-only
measurement behavior and test counts below describe the earlier UI task.

Date: 2026-11-22 (Asia/Manila).

## Findings and changes

The active camera route correctly calls `AiInferenceService.analyze`. Its model
selection and cross-part guard were reviewed before editing:

| Selection | Model asset |
| --- | --- |
| Gills | `assets/models/aquasense_gills_model.tflite` |
| Eyes | `assets/models/aquasense_eyes_model.tflite` |
| Skin / Scales default | `assets/models/aquasense_scales_model.tflite` |
| Explicit fine-tuned Scales candidate | `assets/models/aquasense_scales_finetuned_model.tflite` |

The original `assets/models/fish_freshness_model.tflite` remains preserved and
unassigned. The candidate is never substituted automatically for the original
Scales model. Existing routing tests and actual Chrome checks cover all four
exports, including checks against the original CPU reference outputs.

The old result panel placed model details and scores in one dense text block.
It also retained freshness-colored rendering branches despite confirmed
classification being disabled. The result card now:

- Always presents the final freshness state as neutral **Inconclusive**, even if
  a caller accidentally supplies an unsupported freshness outcome. This UI guard
  is intentionally explicit; accepting a future validated classifier requires
  deliberate review rather than an incidental model output enabling labels.
- Separates **Why Inconclusive**, **Image checks**, **Experimental AI results**,
  and unavailable image measurements.
- Shows selected anatomy, inference status, model filename, hash-based version,
  expandable/selectable full SHA-256, runtime and recorded inference duration.
- Preserves `Output 0`, `Output 1`, `Output 2` exactly in tensor index order.
  Raw numeric values have consistent formatting and neutral teal bars for valid
  distributions. Scores are not sorted, renamed as classes, or displayed as
  calibrated freshness confidence.
- Shows no fabricated zero outputs when inference is unavailable. Non-finite
  raw scores display `N/A`; invalid distributions have no probability bars.
- Explains that passing a softmax numerical check does not validate freshness,
  and identifies the known Gills fish-level evaluation leakage without claiming
  independent-fish accuracy.
- Keeps all five unavailable legacy image measurements as `N/A`, and explains
  that pH belongs to the separate sensor workflow.

The sidebar and mobile navigation now read **Camera & AI Inspection**, matching
the screen title. The desktop sidebar was widened within the existing Soft UI
layout to fit the label. Real legacy HSV utilities and history displays were not
renamed or rewritten.

Existing revision/mounted guards and input disabling during work were preserved.
Part/model/image changes clear old predictions; part/model changes now clear
old operation messages as well. Regression tests cover indexed score clearing,
candidate changes, canceled replacement images and late completion after the
camera screen is disposed. The late-completion test controls the asynchronous
result directly so it does not depend on decoder or platform file-I/O timing.

## Integrity and measurement-write safeguards

A before/after SHA-256 snapshot verifies that all five `.tflite` files retain
their original bytes. The inference service, synchronous image-quality service,
RGB float32 preprocessing, model catalogue, runtime adapters, in-memory browser
batch binding, package manifests/lockfile and existing Firebase/write services
also retain their original bytes for this UI task.

The result widget has no save callback or persistence dependency. The active
camera screen still has no experimental-result Firebase write path or verified
save action, including when `canSave` is true. Existing history, authentication,
ESP32 transport and sensor writes were not changed. No experimental score is
converted into pH, hue, saturation, brightness or a stored freshness label.

## Verification

| Check | Final status | Evidence |
| --- | --- | --- |
| `flutter pub get` | PASSED | Completed; dependency files retain baseline hashes |
| `flutter analyze` | PASSED | No issues found |
| `flutter test` | PASSED | All 109 tests passed; no skipped unit/widget tests |
| Chrome 157 real-model integration | PASSED | All four exports inferred twice and rendered through the new result card |
| Original CPU reference / repeatability | PASSED | Chrome scores matched the existing original-model reference values |
| Asset and protected-source integrity | PASSED | All five models, preprocessing, catalogue, runtimes and existing services are byte-identical to baseline |
| `git diff --check` | PASSED | No whitespace errors |
| Android inference | PENDING | No connected Android device or available emulator |
| Real-image Keras parity | PENDING / SKIPPED | Optional integration test explicitly skipped; matching fixtures absent |

There are no unresolved final test failures. A timing-dependent draft of the new
late-completion regression test was replaced with a controlled pending-result
test double and now passes in the complete suite.

Chrome executed all four real models through the unchanged inference pipeline
and rendered each result with the new widget. Its original reference-score,
repeatability, indexed display, Inconclusive and five-`N/A` assertions passed.
The integration framework's extra teardown count is not a fifth model test.
These synthetic-fixture checks establish execution, not scientifically validated
fish recognition or freshness performance.

`flutter devices` reports Windows, Chrome and Edge. `flutter emulators` reports
no available emulators. Android inference is therefore pending; no Android pass
is claimed. The Chrome check uses the established integration-app launcher,
not the standalone Windows browser harness with the earlier SDK CanvasKit issue:

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d chrome -t integration_test/experimental_ai_test.dart --no-web-resources-cdn
```

Unit/widget coverage includes disabled freshness outcomes, stable output index
order, invalid/missing scores, model identities, candidate selection, full hash
display, navigation at 320/768/1280 pixels, result layout at those widths with
1.6× text scaling, stale result/message clearing and disposal during inference.
Test doubles are confined to UI/unit checks; Chrome tests execute real models.

## Limitations and remaining validation

- Output names remain indexed. No class mapping was inferred from filenames,
  alphabetical order, the maximum score, or the synthetic test images. Exact
  per-export label provenance must be established from original training/export
  artifacts before assigning any freshness meanings.
- Verified mapping alone is insufficient to enable confirmed classifications.
  Independent fish-level evaluation, species/capture coverage, wrong-part and
  unsuitable-image rejection, calibration and acceptance criteria remain needed.
  The known Gills leakage prevents treating its preliminary baseline as
  independent-fish performance.
- Original real images, corresponding `.keras` models and canonical tensor/output
  references are still needed for the optional real-image parity checks.
- Physical ESP32/pH, live Firebase/Google OAuth and native Android device checks
  were not repeated by this UI audit. Existing regression tests remain the
  verification of those unchanged code paths, not live-service certification.
- The existing Chrome runtime needs its pinned JavaScript/WASM resources from
  the CDN, or a separately configured self-hosted deployment.

## Exact files changed or added in this UI task

- `lib/screens/app_shell.dart`
- `lib/screens/camera_screen.dart`
- `lib/widgets/experimental_inspection_details.dart` (new)
- `test/app_shell_navigation_test.dart` (new)
- `test/camera_visual_inspection_test.dart`
- `test/experimental_inspection_details_test.dart` (new)
- `integration_test/support/ai_platform_checks.dart`
- `docs/EXPERIMENTAL_AI_UI_AUDIT.md` (new)
- `docs/EXPERIMENTAL_AI_INTEGRATION.md` (link to this subsequent audit)

Earlier uncommitted integration work and user-supplied models/notebooks were
retained. The list above is scoped to this subsequent UI audit.
