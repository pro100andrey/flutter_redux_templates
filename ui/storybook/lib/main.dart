import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:localization/localization.dart';
import 'package:storybook_flutter/storybook_flutter.dart';
import 'package:ui/scrolls/custom_scroll_behavior.dart';
import 'package:ui/theme/common.dart';

import 'stories/buttons.dart';
import 'stories/inputs.dart';
import 'stories/logos.dart';
import 'stories/pages.dart';

void main() {
  runApp(const StoryBookApp());
}

class StoryBookApp extends StatelessWidget {
  const StoryBookApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        scrollBehavior: CustomScrollBehavior(),
        theme: lightTheme(),
        home: Storybook(
          wrapperBuilder: (context, child) => Container(child: child),
          plugins: initializePlugins(
            contentsSidePanel: true,
            knobsSidePanel: true,
            enableThemeMode: false,
            initialDeviceFrameData: DeviceFrameData(
              isFrameVisible: false,
              device: Devices.android.bigPhone,
            ),
          ),
          stories: [
            ...logos,
            ...buttons,
            ...inputs,
            ...pages,
          ],
        ),
        localizationsDelegates: const [
          S.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: S.delegate.supportedLocales,
      );
}
