import 'package:aqua_sense/models/image_region.dart';
import 'package:aqua_sense/models/visual_inspection.dart';
import 'package:aqua_sense/widgets/fish_region_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  testWidgets('scrolling to results retains the unapplied manual ROI draft', (
    tester,
  ) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    final bytes = img.encodePng(img.Image(width: 200, height: 100));
    var applied = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            controller: controller,
            children: [
              FishRegionSelector(
                bytes: bytes,
                width: 200,
                height: 100,
                part: FishPart.gills,
                busy: false,
                onChanged: () {},
                onApply: (_) => applied++,
                onRotate: () {},
                onChangeImage: () {},
              ),
              const SizedBox(height: 2000),
              const Text('End of inspection'),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Adjust region with keyboard or sliders'));
    await tester.pumpAndSettle();
    tester
        .widget<RangeSlider>(find.byKey(const Key('roi-horizontal')))
        .onChanged!(const RangeValues(.2, .8));
    await tester.pump();
    final draft = tester
        .widget<Text>(find.byKey(const Key('roi-pixel-bounds')))
        .data;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    controller.jumpTo(0);
    await tester.pump();
    expect(
      tester.widget<Text>(find.byKey(const Key('roi-pixel-bounds'))).data,
      draft,
    );
    expect(applied, 0);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'portrait and landscape preview preserve aspect ratio at three widths',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final width in [320.0, 768.0, 1280.0]) {
        for (final size in [(120, 240), (240, 120)]) {
          tester.view.physicalSize = Size(width, 1200);
          final bytes = img.encodePng(
            img.Image(width: size.$1, height: size.$2),
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: FishRegionSelector(
                    bytes: bytes,
                    width: size.$1,
                    height: size.$2,
                    part: FishPart.gills,
                    busy: false,
                    onChanged: () {},
                    onApply: (_) {},
                    onRotate: () {},
                    onChangeImage: () {},
                  ),
                ),
              ),
            ),
          );
          final actual = tester.getSize(
            find.byKey(const Key('roi-image-gesture')),
          );
          expect(
            actual.width / actual.height,
            closeTo(size.$1 / size.$2, 1e-9),
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        }
      }
    },
  );

  testWidgets(
    'drag and sliders only draft ROI until apply; rotation and change callbacks work',
    (tester) async {
      var changes = 0, rotations = 0, imageChanges = 0;
      ImageRegion? applied;
      final bytes = img.encodePng(img.Image(width: 200, height: 100));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FishRegionSelector(
                bytes: bytes,
                width: 200,
                height: 100,
                part: FishPart.eyes,
                busy: false,
                onChanged: () => changes++,
                onApply: (r) => applied = r,
                onRotate: () => rotations++,
                onChangeImage: () => imageChanges++,
              ),
            ),
          ),
        ),
      );
      expect(applied, isNull);
      final image = find.byKey(const Key('roi-image-gesture'));
      final top = tester.getTopLeft(image);
      final size = tester.getSize(image);
      final gesture = await tester.startGesture(
        top + Offset(size.width * .1, size.height * .2),
      );
      await gesture.moveTo(top + Offset(size.width * .6, size.height * .8));
      await gesture.moveTo(top + Offset(size.width * .7, size.height * .9));
      await gesture.up();
      await tester.pump();
      expect(changes, greaterThan(0));
      expect(applied, isNull);
      await tester.ensureVisible(find.byKey(const Key('apply-roi')));
      await tester.tap(find.byKey(const Key('apply-roi')));
      expect(applied!.isValid, isTrue);
      expect(applied!.right, closeTo(.7, .01));
      await tester.ensureVisible(
        find.text('Adjust region with keyboard or sliders'),
      );
      await tester.tap(find.text('Adjust region with keyboard or sliders'));
      await tester.pumpAndSettle();
      tester
          .widget<RangeSlider>(find.byKey(const Key('roi-horizontal')))
          .onChanged!(const RangeValues(.2, .8));
      await tester.pump();
      await tester.ensureVisible(find.byKey(const Key('apply-roi')));
      await tester.tap(find.byKey(const Key('apply-roi')));
      expect(applied!.left, .2);
      expect(applied!.right, .8);
      await tester.ensureVisible(find.text('Rotate image'));
      await tester.tap(find.text('Rotate image'));
      await tester.ensureVisible(find.text('Change image'));
      await tester.tap(find.text('Change image'));
      expect(rotations, 1);
      expect(imageChanges, 1);
    },
  );
}
