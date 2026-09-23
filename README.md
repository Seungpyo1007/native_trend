# native_trend

Flutter's Cupertino library doesn't draw iOS 26 Liquid Glass
([flutter#170310](https://github.com/flutter/flutter/issues/170310)). pub.dev
has about 20 packages that claim to. Most of them imitate glass with shaders.
Only a few embed real native iOS views, which is the only way to get Apple's
actual effect.

`native_trend` searches pub.dev, scans each plugin's source for native views
(`UiKitView`) and the iOS 26 glass API (`UIGlassEffect`, `.glassEffect`),
ranks the native ones by pub.dev's own scores, and writes the result to a file
your AI coding assistant reads.

## Find

```sh
dart pub global activate native_trend
native_trend find --link CLAUDE.md
```

```
native adaptive_platform_ui             160 pts   11477 dl/30d  native view + glass API
native cupertino_native_better          160 pts    7393 dl/30d  native view + glass API
...
native native_glass_navbar              150 pts    1465 dl/30d  native view, system controls
skip   liquid_glass_widgets             160 pts   74887 dl/30d  Flutter-drawn imitation (no native code)
skip   liquid_glass_renderer            150 pts   25481 dl/30d  Flutter-drawn imitation (no native code)
```

| Kind | Meaning |
| --- | --- |
| native view + glass API | Embeds a native view and calls the iOS 26 glass API directly. |
| native view, system controls | Embeds native system controls (tab bar, nav bar), which get glass from the iOS 26 SDK. |
| plugin without a native view | Has native code but no platform view. Skipped. |
| Flutter-drawn imitation | Pure Dart or shaders. Skipped. |

Discontinued packages are dropped. Everything else (points, likes,
downloads, publisher) comes from pub.dev as-is.

`.ai/native_trend.md` holds the ranking, Apple's Liquid Glass rules, and notes
on applying it. `--link` adds a pointer to that file in `CLAUDE.md`,
`AGENTS.md`, or any other file your assistant reads.

Options: `--dir <project root>`, `--out <path>` (default `.ai/native_trend.md`).

## Apply with Claude Code

This repository is also a Claude Code plugin with a `liquid-glass` skill. The
skill runs `find`, lets you pick a package, reads its README, converts only
your navigation and control widgets (behind an iOS-only branch when the package has no fallback), and
applies Apple's rules.

```
/plugin marketplace add Seungpyo1007/native_trend
/plugin install native-trend@native-trend
```

Glass only shows in iOS builds made with Xcode 26 or later.

## Roadmap

Android (Material 3 Expressive with native views) comes next.
