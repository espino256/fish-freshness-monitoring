# AquaSense image inspection: ROI descriptors and experimental UI

Updated 2026-11-23 (Asia/Manila). This report describes the latest redesign;
earlier integration/audit reports retain their historical test results.

## Behavior and scope

The camera page uses the existing AquaSense teal palette, rounded panels and
responsive typography. Its order is image/part controls, actual oriented photo
with manual ROI controls, separate verified and experimental result cards,
named-output availability, model diagnostics and index-ordered score bars,
five descriptor cards, and inspection notes. ESP32-CAM stream, connection,
resolution, flash and capture controls remain available below the inspection.
The existing navigation already reads **Camera & AI Inspection**.

The existing dashboard styling was used. The user subsequently identified
`docs/reference/aquasense_dashboard_reference.png` as the primary visual
reference, but both the file and its parent directory were absent when checked.
Exact matching against that image remains pending its availability; it has not
been inspected or copied into the app. Portrait and landscape photos preserve
proportions.

The verified card always displays **INCONCLUSIVE**, including if a caller
accidentally supplies another outcome. Its supporting text is:
“Verified freshness classification is not available for this inspection.”
The experimental card can show the highest valid indexed model score, including
all equal top-score ties in their original index order. This does not name a
freshness class or promote a verified conclusion. It states:
“Experimental AI prediction only. Not independently validated.”

Invalid/missing distributions show no fabricated predictions. Diagnostics
include the actual filename, hash-based version, full selectable SHA-256,
runtime, status, recorded duration and failure message. Scores retain tensor
order as Output 0, Output 1, Output 2. Bars require a completed, finite,
in-range three-value distribution summing to one within 1e-5. That tolerance is
for floating-point arithmetic, not a scientific acceptance threshold.

## Manual ROI workflow

1. Select Gills, Eyes, or Skin / Scales. Scales defaults to its original export;
   the fine-tuned candidate requires an explicit model selection.
2. Import a JPEG/PNG or capture an ESP32-CAM still. Existing whole-image
   acquisition checks precede experimental inference. Until a region is
   explicitly applied, descriptor cards remain N/A.
3. Draw a rectangle around only the selected anatomy and exclude background.
   Keyboard-accessible horizontal/vertical range sliders provide an alternative.
   The initial centered rectangle is a **draft**, never an automatic analysis.
4. Choose **Apply region & analyze**. All descriptor pixels come from that ROI.
   Rotating uses the original bytes; EXIF orientation is baked first, then
   explicit clockwise quarter-turns. Preview, descriptors and model preparation
   share the same decode/orientation path.
5. Editing a region immediately clears prior scores and descriptors. Changing
   part or model clears them and resets the draft, while retaining the photo.
   Rotation clears the applied ROI and reruns AI with descriptors unavailable.
   Choosing another image clears the previous photo/results even if canceled.

The draft is retained while scrolling. The progress indicator stays visible
during work, and model/part/ROI controls are disabled while work is running.
Revision and mounted guards reject late results after a selection is invalidated
or the screen is disposed.

Selection is manual and unverified: no fish detection, wrong-part rejection or
automatic segmentation is claimed. A user can still select background. No
algorithm here establishes that an outlined area is actually fish anatomy.

## Pixel processing and formulas

`ImageRegion` stores a normalized rectangle in the **oriented** image. Coordinates
must be finite, between 0 and 1, with positive area. Pixel bounds use floor for
left/top and ceil for exclusive right/bottom, bounded by image dimensions.
No full-image HSV fallback occurs. Regions smaller than 16 x 16 source pixels
are rejected. An optional binary mask must have exactly width x height entries
in oriented coordinates; nonzero entries are eligible, and entries outside the
ROI are excluded. The UI currently supplies a rectangle, not a segmentation mask.

For actual normalized RGB channels r,g,b in [0,1], let M=max(r,g,b), m=min(r,g,b)
and d=M-m. V=M. S is zero if M=0, otherwise d/M. For d=0, hue is undefined;
otherwise standard max-channel HSV conversion yields H in [0,360) degrees.
Channel normalization uses the decoded image's channel range, including 16-bit
PNG pixels, rather than assuming every source channel is 8-bit.

All eligible pixels are visited for HSV; there is no HSV sampling grid.

- **Usable pixels** are fully opaque, have V >= 0.08, and are not near-white
  glare (V > 0.98 together with S < 0.20).
- **Saturation / brightness** are arithmetic means of S / V across usable
  pixels. Grayscale/low-saturation pixels can contribute to these means.
- **Hue samples** are usable pixels with a defined hue and S >= 0.10.
  Mean hue is atan2(sum(sin(H)),sum(cos(H))) modulo 360. At least 50 hue
  samples are required. A resultant length per sample below 1e-6 is treated as
  numerical cancellation/ambiguous hue; hue remains N/A.
- **Red Sector** is count(H in [0,35] or [325,360)) divided by the number of
  hue samples. Boundaries 35 and 325 are included; 360 wraps to zero.
  Low-saturation/undefined hue never contributes to this denominator. At
  least 50 hue samples are required. A meaningful red fraction can still exist
  when the circular mean cancels.
- **Usable Area** is usable pixels / eligible ROI-and-mask pixels, not the share
  of the whole photograph occupied by fish. Zero eligible pixels yield N/A.
  Fewer than 50 usable samples leave means/red/hue unavailable and explain why;
  a defined usable-area ratio can still be reported.

A focus/detail proxy calculates variance of the four-neighbor discrete
Laplacian of normalized luminance (0.2126r+0.7152g+0.0722b). It samples ROI
interior coordinates every two pixels, or every four above 500,000 ROI pixels.
The center and four neighbors must all satisfy the mask/exposure/opacity checks,
preventing mask boundaries from creating artificial detail. At least 50 focus
samples and variance >= 0.0001 are required to report descriptors; otherwise
all five cards are N/A with a retake/region explanation. Flat surfaces can fail
alongside blurred images; texture can pass even if other defects exist.

These explicit acquisition/mask/detail defaults are engineering heuristics,
**not independently validated blur detectors or freshness acceptance criteria**.
Existing whole-image mean-luminance checks (0.08..0.96), detail variance >= 0.002,
JPEG/PNG-only decoding, 10 MiB encoded limit, single-frame restriction and
100 x 100 through 16-megapixel size bounds are retained. Failed image checks
prevent model execution. Corrupt/unsupported images yield safe reasons and N/A.

Displayed H is degrees, S/V are 0..1 with two decimals, and fractions are
percentages. Non-finite/missing values display N/A. V is pixel brightness, not
physical illumination. None of these descriptors is pH or a freshness verdict.

## AI input, routing and integrity

ROI descriptors are independent of model input. The models continue receiving
the complete oriented image through the existing half-pixel bilinear resize,
RGB float32 [1,224,224,3] in 0..255. Embedded rescaling x/127.5-1 is not applied
again. ROI does not crop the tensor or inject HSV features. Changing orientation
can change the model input, as expected; changing only the ROI does not.

`AiInferenceService`, runtime adapters and the browser's in-memory batch-one
signature binding were retained byte-for-byte. No interpreter is created inside
`compute()`; pure preview/measurement/tensor preparation can use it. Runtime
serialization, hash checks, error reporting and disposal remain intact.

All original binaries were compared with the before-edit SHA-256 snapshot:

| Selection | Original file | SHA-256, unchanged |
| --- | --- | --- |
| Gills | aquasense_gills_model.tflite | adfa10b697c409a7b1848945acef11b59d726bda15f8ed7e0d2d557a9e9225dd |
| Eyes | aquasense_eyes_model.tflite | 2c774dd79cfcd95e4d97a110e7eaaea6eb07306b01e9d97a0fc57f371792b5af |
| Scales default | aquasense_scales_model.tflite | 2a5fbddbe50471aaac627eb2bcd4e87d690103bd02795dbaf7db08c4f05ee494 |
| Scales candidate | aquasense_scales_finetuned_model.tflite | d1dcf791f02e38696e912e37a4e8a648ec6dc17a3fd8ba6685bd7e99304a5d7e |
| Preserved, unassigned | fish_freshness_model.tflite | c2f3f4aa6555bedc811d87d756441b3f49979e73620737392227308d41a5b44c |

The four assigned exports retain float32 output [1,3] with softmax. No accuracy
equivalence between the original and fine-tuned candidate is implied.
`pubspec.yaml` and `pubspec.lock` are unchanged by this redesign.

## Class mapping evidence and scientific limits

Both actual local notebooks were inspected:

- `docs/ai_training/AquaSense_WholeFish_Freshness_Training.ipynb`
- `docs/ai_training/AquaSense_Model_Validation.ipynb`

Their training/evaluation code declares FRESH=0, MODERATE=1, SPOILED=2.
This is evidence of a training convention, not sufficient provenance for each
exact bundled export. No supplied per-export hash-linked class-map manifest,
matching saved Keras model and real-image reference tensor/output bind those
declarations to all four binaries, particularly the fine-tuned candidate.
The exports have no embedded accepted label map. **Named predictions remain
disabled for every model.** `classNameForOutput` returns null; neither filenames,
alphabetical ordering, a test image nor the largest score can enable a name.

The Gills split has confirmed fish-level leakage. Its reported 72.93% baseline
is not independently validated performance. Before naming outputs, supply
trustworthy model-specific export provenance and reference fixtures. Before any
verified freshness classification, establish independent-fish splits and
external evaluation, species/acquisition coverage, wrong-part/non-fish rejection,
calibration, justified acceptance criteria and explicit deployment authorization.
HSV mask/focus choices also require empirical review for actual capture devices.

## Persistence safeguards

The inspection screen and result widgets have no measurement-write callback,
Firebase database/storage dependency or experimental save action, including
when `canSave` is true. Real HSV descriptors are ephemeral inspection data;
neither they nor AI outputs are turned into confirmed freshness/pH records.
Existing Firebase/authentication, ESP32 transport, pH services, history readers,
security rules and legacy HSV utilities were left unchanged. Unit/widget tests
exercise inspection with no initialized Firebase and verify no demo image records
are appended. This does not claim a live production Firebase/security-rule test.

## Calculation and execution evidence

The unit fixture is deliberately synthetic, not a fish/reference-validation
image. It is 256 x 256 with gray background and a central 128 x 128 four-pixel
checker alternating RGB(200,20,20) and RGB(20,120,20), 8,192 pixels of each.
Applying ROI [.25,.25,.75,.75] excludes the background and gives:

| Actual calculated field | Value |
| --- | --- |
| Eligible / usable / hue samples | 16,384 / 16,384 / 16,384 |
| Circular mean hue | 59.99999999999677 degrees |
| Mean saturation | 0.8666666666666398 |
| Mean value | 0.6274509803920173 |
| Red fraction | 0.5 |
| Usable fraction | 1.0 |
| Focus variance | 0.02496856320056101 |

The equal red/green hue directions average circularly to 60 degrees. Mean S is
(.9+5/6)/2; mean V is 160/255. Red is 8192/16384. The displayed cards are
60.0 degrees, 0.87, 0.63, 50.0%, 100.0%. These are test calculations, never
application defaults or scientific freshness claims.

Chrome's actual Gills inference on that encoded fixture produced raw outputs
[0.7848068475723267, 0.11210815608501434, 0.10308495908975601]. The ROI and no-ROI
calls produced identical outputs; actual descriptors matched the unit calculation.
Output 0 remains an unnamed index, despite its larger score.

## Verification status

- PASSED: `flutter pub get` with installed `flutter_litert` 4.2.0.
- PASSED: `flutter analyze`: no issues found.
- PASSED: `flutter test --reporter expanded`: **128 tests passed**, zero failures.
  The separate local visual-render check also passed.
- PASSED: Chrome integration app, command:
  `flutter run -d chrome -t integration_test/experimental_ai_test.dart --web-browser-flag=--headless=new --web-port=5020 --no-web-resources-cdn`.
  Five substantive execution checks passed: all four real models (two runs each,
  CPU reference score parity, identity, numerical output checks, UI and disposal)
  plus real ROI+AI isolation. Runner reports +6 including teardown, ~1 skipped.
- PASSED: original model SHA-256 preservation, unchanged runtime/service code,
  RGB input contract and all routes, separately selectable candidate.
- PASSED: ROI/HSV, masks, EXIF/rotation, invalid/corrupt images, provenance
  enforcement, Inconclusive isolation, stale clearing and responsive component
  layouts at 320/768/1280 pixels; local visual render inspected.
- PENDING: real-image Keras parity test, explicitly skipped. Saved Keras models,
  exact original images/tensors and hash-linked output fixtures were not supplied.
- PENDING: exact visual comparison with `docs/reference/aquasense_dashboard_reference.png`;
  the specified file/directory is not present in this workspace.
- PENDING: Android inference and physical UI: `flutter devices --machine` lists
  Windows/Chrome/Edge, and `flutter emulators` reports no emulators.
- PENDING: live ESP32/pH hardware, production Firebase/OAuth and independent fish
  evaluation; no such integration pass is claimed by unit/widget/Chrome tests.
- FAILED: no unresolved failures after final verification; development test and
  browser fixture-import errors were corrected before the final runs.

Raw local check records are in ignored `build/qa/roi_*.txt` and
`build/qa/roi_integrity.json`. The QA render uses explicitly labeled test-double
scores and a synthetic image solely to inspect layout, not to validate inference.

## Exact files for this redesign

Modified existing source/tests:

- `lib/models/experimental_ai.dart`
- `lib/models/visual_inspection.dart`
- `lib/screens/camera_screen.dart`
- `lib/services/visual_inspection_service.dart`
- `lib/widgets/experimental_inspection_details.dart`
- `test/camera_visual_inspection_test.dart`
- `test/experimental_inspection_details_test.dart`
- `integration_test/support/ai_platform_checks.dart`

Added source/tests:

- `lib/models/image_region.dart`
- `lib/services/image_region_analysis_service.dart`
- `lib/widgets/fish_region_selector.dart`
- `test/fish_region_selector_test.dart`
- `test/image_region_analysis_test.dart`
- `test/support/region_fixture.dart`

Documentation:

- `README.md`
- `docs/AI_MODEL_REQUIREMENTS.md`
- `docs/EXPERIMENTAL_AI_INTEGRATION.md`
- `docs/EXPERIMENTAL_AI_UI_AUDIT.md` (historical report labeled as superseded)
- `docs/AI_INSPECTION_ROI_REDESIGN.md` (this report)

Pre-existing uncommitted integration/models/notebooks/generated files were
preserved. Temporary QA scripts/logs/renders live only under ignored build/qa.
