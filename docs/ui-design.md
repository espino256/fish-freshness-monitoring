# AquaSense Soft UI

The shared design primitives live in `lib/widgets/soft_ui.dart`. Light highlights
at (-5,-5) and slate drop shadows at (6,7) lift panels, inputs and buttons above
the pale blue-gray canvas. Teal indicates primary actions, with green/amber/red
reserved for pH classification. `SoftButton` preserves keyboard/semantics support
through Material InkWell, suppresses duplicate work while busy, and changes its
shadow on press. Cloud write permissions remain enforced by Firebase rules.

Auth screens use `AuthLayout`: one column on phones/tablets and an ocean hero
beside the form at desktop widths. The workspace switches to a sidebar at 1000
pixels. Scrollable content and horizontal history tables keep controls available
on small screens. Notifications float above mobile navigation. A high-contrast
setting strengthens text and field borders.

## Ocean asset

Saved project asset: `assets/images/ocean_water.png` (1672 × 941 PNG).
Created with the built-in image_gen tool, copied into the project and visually
inspected. No remote image service is needed at runtime. This is a decorative,
AI-generated design image, not evidence from an inspection.

Exact generation prompt:

> Use case: photorealistic-natural. Asset type: subtle background image for AquaSense mobile fish freshness monitoring dashboard. Primary request: high-quality dark ocean water viewed from directly above, calm rich deep slate-blue and soft teal water with gentle organic ripples and faint caustic highlights, premium editorial ocean photography. Wide landscape composition with quiet low-contrast center and natural water texture toward edges, no horizon, no boats, no fish, no objects, no text, no logos, no watermark. Lighting soft diffuse evening light, subdued dark nautical palette. Entire image is only water. Intended to sit behind legible light neumorphic interface cards.

`OceanBackdrop` adds a two-pixel blur and slate/teal gradient overlay. Every
primary route uses opaque light surfaces for readable text. Image loading errors
fall back to solid slate. The image is bundled and available offline.

## Interaction verification

Authentication is exclusively Firebase-backed. Login, registration, Google,
password reset and verification have no simulation/guest fallback. Connection
failures show an actionable Snackbar. Successful Firebase authentication opens
the dashboard immediately with its UID and clears authentication routes. Profile
and verification setup run in the background; their failures appear in a dashboard
notice with retry actions. Cloud data still follows the email-verification rules. Settings
cannot switch to a local session; contrast is managed by AppPreferences.

`test/demo_workflows_test.dart` now verifies live-only authentication enforcement,
missing/failed/stalled Firebase initialization, error Snackbars, active forms,
password reset/Google failure behavior, four-field registration and responsive
renders. Separate component tests inject synthetic sensor/image fixtures directly
without signing in any local user. These fixtures never participate in the
production authentication gate. Real external OAuth accounts and physical
ESP32 hardware still require integration testing.
