import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/focus/input_mode_tracker.dart';
import 'package:plezy/navigation/main_screen_scope.dart';
import 'package:plezy/providers/download_provider.dart';
import 'package:plezy/providers/multi_server_provider.dart';
import 'package:plezy/theme/mono_theme.dart';
import 'package:provider/provider.dart';

/// Pumps [tab] under the ancestors every library tab requires: [provider], an
/// [InputModeTracker], a [MainScreenFocusScope] and a [NestedScrollView] whose
/// overlap absorber handle the tabs look up. Sizes the view to [size] logical
/// pixels at [devicePixelRatio] (raise it to emulate a phone, whose form
/// factor is derived from the physical diagonal) and restores it when the
/// test ends. Settling is left to the caller.
///
/// [theme] replaces the standard dark theme; [frame] wraps the scroll view in
/// what the libraries screen puts round it under the redesign.
Future<void> pumpLibraryTab(
  WidgetTester tester, {
  required MultiServerProvider provider,
  required Widget tab,
  DownloadProvider? downloads,
  Size size = const Size(1280, 720),
  double devicePixelRatio = 1,
  VoidCallback? focusSidebar,
  ThemeData? theme,
  Widget Function(Widget body)? frame,
}) async {
  tester.view.devicePixelRatio = devicePixelRatio;
  tester.view.physicalSize = size * devicePixelRatio;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MultiServerProvider>.value(value: provider),
        if (downloads != null) ChangeNotifierProvider<DownloadProvider>.value(value: downloads),
      ],
      child: InputModeTracker(
        child: MaterialApp(
          theme: theme ?? monoTheme(dark: true),
          home: MainScreenFocusScope(
            focusSidebar: focusSidebar ?? () {},
            sideNavigationWidth: 0,
            child: Scaffold(
              body: (frame ?? (body) => body)(
                NestedScrollView(
                  headerSliverBuilder: (context, _) => [
                    SliverOverlapAbsorber(
                      handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
                      // Nothing under the redesign's frame, as the screen draws
                      // no app bar there: a pixel here would stand between the
                      // filters and the posters.
                      sliver: SliverToBoxAdapter(child: SizedBox(height: frame == null ? 1 : 0)),
                    ),
                  ],
                  body: tab,
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Frames a library tab needs to issue its debounced request and apply the
/// response, for tabs whose loading never quiesces enough for `pumpAndSettle`.
Future<void> pumpRequestFrames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 500));
}
