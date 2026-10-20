---
name: macos-glass
description: Apply macOS 26 Liquid Glass to a Flutter macOS app using a plugin that embeds real native AppKit views, chosen from live pub.dev data and applied per Apple's guidelines. Use when the user wants Liquid Glass, glass toolbars, sidebars, or native AppKit buttons, switches, or controls in a Flutter macOS app.
---

# Liquid Glass for Flutter on macOS

Flutter draws its own widgets on macOS, so nothing it draws gets Liquid Glass. Use a plugin that embeds real AppKit views with `AppKitView`, never a BackdropFilter or shader imitation. For iOS, use the `liquid-glass` skill.

1. From the Flutter project root, run:
   ```
   dart pub global activate native_trend
   dart pub global run native_trend find --platform macos --link CLAUDE.md
   ```
   This writes `.ai/native_trend_macos.md` and adds a one-line pointer to `CLAUDE.md` (creating it if missing). Mention both files to the user.
2. Read `.ai/native_trend_macos.md`. It is newer than your training data. Trust it over memory.
3. Show the user the recommended package and the top two alternatives, including platforms and last release date. If the app also targets iOS, say which ones cover both. Let the user pick before you change anything.
4. `flutter pub add <package>`.
5. Learn the package's real API before writing code:
   - Read its README (including any Limitations section) and `example/`. Both are in the pub cache after step 4 (`flutter pub cache list`, or `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\<package>-<version>` on Windows, `~/.pub-cache/hosted/pub.dev/...` elsewhere).
   - Check the source for anything the README leaves unclear: parameter defaults, the minimum macOS version, and what the package renders on other platforms.
   - Use only widget names and parameters you saw.
6. Map the change before editing:
   - Find the app root (`MaterialApp`, `CupertinoApp`, `MacosApp`) and whether the package needs its own app widget, a `builder` wrapper, or window setup in `macos/Runner/MainFlutterWindow.swift`.
   - Find the navigation and control widgets in `lib/`: `AppBar`, `ToolBar`, `MacosWindow`, `Sidebar`, `NavigationRail`, toolbars, buttons, switches, sliders, segmented controls, and hand-rolled blurred bars (`BackdropFilter`, `ImageFilter.blur`).
   - A package with a real `NSToolbar` puts the toolbar in the window's title bar. Tell the user what moves there, and that a Flutter-drawn title bar or toolbar should go.
   - Get confirmation on what to convert.
7. Convert only the navigation and control layer:
   - If the package falls back on other platforms by itself, use its widgets everywhere. Tell the user what Windows, Linux, and the web will look like.
   - Otherwise, use the native widget on macOS only and keep the current widget elsewhere:
     ```dart
     defaultTargetPlatform == TargetPlatform.macOS ? NativeWidget(...) : existingWidget
     ```
     Use `defaultTargetPlatform` (from `package:flutter/foundation.dart`), not `dart:io` `Platform`, which throws on web.
   - Native views don't take Flutter gestures or keyboard focus, and each one costs an extra surface. Keep them out of long lists, and don't wrap them in `GestureDetector` expecting it to fire.
8. Follow Apple's rules from the context file:
   - No glass on content (lists, cards, images).
   - No glass stacked on glass.
   - Remove the app's own title bar, toolbar, and sidebar backgrounds and blurs. Leave the package's material options at their defaults.
9. macOS deployment target: if the package states a minimum, check `MACOSX_DEPLOYMENT_TARGET` in `macos/Runner.xcodeproj/project.pbxproj` and raise it only if lower. If `macos/Podfile` exists, match its `platform :osx` line too. Don't create a Podfile. Leave `pod install` to the user's next build.
10. Run `flutter analyze` and fix what it reports. Update `test/` files your change broke (the template `widget_test.dart` usually is); native views render their Flutter fallback in widget tests. Tell the user that glass appears only in a build made with Xcode 26 or later running on macOS 26 or later; older macOS shows the same controls without glass.
