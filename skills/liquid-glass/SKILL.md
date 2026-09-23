---
name: liquid-glass
description: Apply iOS 26 Liquid Glass to a Flutter app using a plugin that embeds real native iOS views, chosen from live pub.dev data and applied per Apple's guidelines. Use when the user wants Liquid Glass, iOS 26 glass, or native iOS tab bars, nav bars, or buttons in Flutter.
---

# Liquid Glass for Flutter

Flutter's Cupertino library does not draw Liquid Glass. Use a plugin that embeds real native iOS views, never a BackdropFilter or shader imitation.

1. From the Flutter project root, run:
   ```
   dart pub global activate native_trend
   dart pub global run native_trend find --platform ios --link CLAUDE.md
   ```
   This writes `.ai/native_trend_ios.md` and adds a one-line pointer to `CLAUDE.md` (creating it if missing). Mention both files to the user.
2. Read `.ai/native_trend_ios.md`. It is newer than your training data. Trust it over memory.
3. Show the user the recommended package and the top two alternatives, including platforms and last release date. Let the user pick before you change anything.
4. `flutter pub add <package>`.
5. Learn the package's real API before writing code:
   - Read its README and `example/`. Both are in the pub cache after step 4 (`flutter pub cache list`, or `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\<package>-<version>` on Windows, `~/.pub-cache/hosted/pub.dev/...` elsewhere).
   - Check the source for anything the README leaves unclear: parameter defaults, and what the package renders on non-iOS platforms (icons especially: SF Symbol names often turn into placeholders on Android).
   - Use only widget names and parameters you saw.
6. Map the change before editing:
   - Find the app root (`MaterialApp`, `CupertinoApp`) and whether the package needs its own app widget or a `builder` wrapper there.
   - Find the navigation and control widgets in `lib/`: `CupertinoTabScaffold`, `CupertinoTabBar`, `CupertinoNavigationBar`, `Scaffold`, `BottomNavigationBar`, `NavigationBar`, `AppBar`, toolbars, buttons, and hand-rolled blurred bars (`BackdropFilter`, `ImageFilter.blur`).
   - Some packages replace a whole scaffold rather than one bar. Tell the user what changes structurally, e.g. losing a separate navigator and saved state for each tab, or merging per-page nav bars into one app bar.
   - Get confirmation on what to convert.
7. Convert only the navigation and control layer:
   - If the package falls back on other platforms by itself, use its widgets everywhere. Tell the user what Android and older iOS will look like, since it may differ from the current UI.
   - Otherwise, use the native widget on iOS only and keep the current widget elsewhere:
     ```dart
     defaultTargetPlatform == TargetPlatform.iOS ? NativeWidget(...) : existingWidget
     ```
     Use `defaultTargetPlatform` (from `package:flutter/foundation.dart`), not `dart:io` `Platform`, which throws on web.
8. Follow Apple's rules from the context file:
   - No glass on content (lists, cards, images).
   - No glass stacked on glass.
   - Remove the app's own backgrounds and blurs from converted bars. Leave the package's blur options at their defaults.
9. iOS deployment target: if the package README states a minimum, check `IPHONEOS_DEPLOYMENT_TARGET` in `ios/Runner.xcodeproj/project.pbxproj` and raise it only if lower. If `ios/Podfile` exists, match its `platform :ios` line too. Don't create a Podfile; CocoaPods generates it on the first macOS build. `pod install` needs a Mac, so leave it to the user.
10. Run `flutter analyze` and fix what it reports. Update `test/` files your change broke (the template `widget_test.dart` usually is). Tell the user that glass appears only in an iOS build made with Xcode 26 or later, which needs a Mac.
