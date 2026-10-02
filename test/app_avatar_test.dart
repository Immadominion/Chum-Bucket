import 'package:chumbucket/shared/widgets/app_components/app_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Size> _avatarSize(WidgetTester tester, Size screen) async {
  tester.view.physicalSize = screen;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ScreenUtilInit(
      designSize: const Size(390, 844),
      minTextAdapt: true,
      splitScreenMode: true,
      builder:
          (_, _) => const MaterialApp(
            home: Scaffold(
              body: Center(child: AppAvatar(initials: 'ad', size: 40)),
            ),
          ),
    ),
  );
  return tester.getSize(find.byType(Container).first);
}

void main() {
  group('AppAvatar is a circle on every screen shape (m5)', () {
    for (final screen in const [
      Size(390, 844), // the design size
      Size(320, 568), // small phone
      Size(1024, 768), // landscape tablet
      Size(390, 400), // split screen
    ]) {
      testWidgets('$screen', (tester) async {
        final size = await _avatarSize(tester, screen);
        expect(size.width, closeTo(size.height, 0.001));
      });
    }
  });

  test('avatars decode at drawn size, not source size', () {
    final provider = avatarImageProvider(
      'assets/images/ai_gen/profile_images/1.png',
      logicalSize: 40,
      devicePixelRatio: 3,
    );
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).width, 120);
    expect(provider.imageProvider, isA<AssetImage>());

    final remote = avatarImageProvider(
      'https://example.com/a.png',
      logicalSize: 400,
      devicePixelRatio: 3,
    ) as ResizeImage;
    expect(remote.width, 512);
    expect(remote.imageProvider, isA<NetworkImage>());
  });
}
