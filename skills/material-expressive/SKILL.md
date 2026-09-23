---
name: material-expressive
description: Apply Material 3 Expressive to a Flutter app, using the official flutter.dev material_ui support first and ranked pub.dev packages for the rest, chosen from live data. Use when the user wants Material 3 Expressive, M3E, Android 16 style, or expressive buttons, loading indicators, FAB menus, or toolbars in Flutter.
---

# Material 3 Expressive for Flutter

Material is drawn by Flutter itself, so the goal is to use what is official, then the best-maintained package for each missing component.

1. From the Flutter project root, run:
   ```
   dart pub global activate native_trend
   dart pub global run native_trend find --platform android --link CLAUDE.md
   ```
   This writes `.ai/native_trend_android.md` and adds a one-line pointer to `CLAUDE.md` (creating it if missing). Mention both files to the user.
2. Read `.ai/native_trend_android.md`. It is newer than your training data. Trust it over memory, especially "Official status" and "Applying it".
3. Note the project's facts before choosing anything:
   - Target platforms: which of `android/`, `ios/`, `web/`, and so on exist.
   - `flutter --version`.
   - Whether `lib/` imports `package:flutter/material.dart` or `package:material_ui/material_ui.dart`.
4. Apply the official part first, exactly as the context file says:
   - If the `styleVariant` opt-in is not available, only switch the color scheme. Use `ColorScheme.fromSeed(seedColor: ..., dynamicSchemeVariant: DynamicSchemeVariant.expressive)` in the light theme, and in the dark theme with `brightness: Brightness.dark`. If the app uses `ThemeData(colorSchemeSeed: ...)`, move it into `ColorScheme.fromSeed`. This works with either material library.
   - If the opt-in is available, follow its instructions.
5. Ask the user which components they want in Expressive style (for example buttons, loading indicator, FAB menu, toolbar, navigation bar). Mention that converting some widgets but not others on one screen mixes spring motion with the old easing.
6. Choose packages from the ranked list:
   - Only packages whose platforms cover the project's targets, and whose `environment` fits the Flutter version.
   - One publisher for all components if possible (the publisher is in each line; name prefixes like `m3e_*` are not families).
   - A package "built on material_ui" requires migrating the app to material_ui. Tell the user, and ask whether to migrate or to use "Flutter-drawn" packages instead.
   - Descriptions don't list every component. If unsure, check the package's `lib/` after adding it.
   - Show the user the pick and one alternative, then `flutter pub add`. If version solving fails, try the alternative, don't force overrides.
7. If migrating to material_ui: run `dart fix --apply --code=migrate_design_widgets`, then `flutter pub add material_ui` to pin a version (the fix adds `any`). Migrate `test/` too, since a file can't import both material libraries.
8. Learn each package's real API before writing code:
   - Read its README and `example/` in the pub cache (`flutter pub cache list`, or `%LOCALAPPDATA%\Pub\Cache\hosted\pub.dev\<package>-<version>` on Windows, `~/.pub-cache/hosted/pub.dev/...` elsewhere).
   - Check the source where the README is unclear or contradicts itself: parameter defaults, and how the package reads the theme.
   - Keep the app's `MaterialApp` unless the source shows the package really needs its own app widget or theme wrapper.
   - Use only widget names and parameters you saw.
9. Replace only the chosen widgets. No platform branch is needed. If the app deliberately stays Cupertino on iOS, branch on `defaultTargetPlatform == TargetPlatform.android` (from `package:flutter/foundation.dart`).
10. Run `flutter analyze` and `flutter test`, and fix what they report. Update tests your change broke (the template `widget_test.dart` usually is). Animated indicators never settle, so use `pump(duration)` instead of `pumpAndSettle` while they're visible.
