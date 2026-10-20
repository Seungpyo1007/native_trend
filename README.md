# native_trend

AI coding assistants learn from old data, and pub.dev has dozens of packages
that claim to bring the latest platform look to Flutter. `native_trend`
checks pub.dev live, picks the packages that actually deliver it, and writes
the result to a file your assistant reads.

| Platform | Trend | What counts |
| --- | --- | --- |
| iOS | Liquid Glass (iOS 26) | Only plugins that embed **real native iOS views**. The OS draws the glass, so Flutter-drawn imitations are skipped. |
| macOS | Liquid Glass (macOS 26) | Same rule with **real AppKit views**. |
| Android | Material 3 Expressive | The **official** flutter.dev `material_ui` first, then Flutter-drawn component packages, preferring ones built on `material_ui`. No pub.dev package renders M3 Expressive with native Android views today, and Material has always been drawn by Flutter. |

pub.dev does the validation. Discontinued packages are dropped, and
everything else (points, likes, downloads, publisher) comes from pub.dev as-is.

## Install

```sh
dart pub global activate native_trend
```

## iOS: Liquid Glass

```sh
native_trend find --platform ios --link CLAUDE.md
```

```
use  adaptive_platform_ui               160 pts   11477 dl/30d  native view + glass API
use  cupertino_native_better            160 pts    7393 dl/30d  native view + glass API
...
use  native_glass_navbar                150 pts    1465 dl/30d  native view, system controls
skip liquid_glass_widgets               160 pts   74887 dl/30d  Flutter-drawn imitation (no native code)
skip liquid_glass_renderer              150 pts   25481 dl/30d  Flutter-drawn imitation (no native code)
```

Each plugin's source is scanned for a platform view (`UiKitView`) and the iOS
26 glass API (`UIGlassEffect`, `.glassEffect`). Neither Flutter's Cupertino
library nor the official `cupertino_ui` package implements Liquid Glass yet
([flutter#170310](https://github.com/flutter/flutter/issues/170310)).

## macOS: Liquid Glass

```sh
native_trend find --platform macos --link CLAUDE.md
```

```
use  cupertino_native_better            160 pts   11639 dl/30d  native view + glass API
use  cupertino_native_plus              160 pts    1718 dl/30d  native view + glass API
use  native_macos                       160 pts       0 dl/30d  native view + glass API
...
use  cupertino_native                   150 pts    2732 dl/30d  native view, system controls
skip liquid_glass_widgets               160 pts  104238 dl/30d  Flutter-drawn imitation (no native code)
```

Each macOS plugin's source is scanned for `AppKitView` and the macOS glass
API (`NSGlassEffectView`, `.glassEffect`). `native_macos` comes from the same
publisher as this tool and doesn't show up in pub.dev's "liquid glass"
search, so it is always checked, then ranked by the same rules as everything
else.

## Android: Material 3 Expressive

```sh
native_trend find --platform android --link CLAUDE.md
```

```
use  material_ui                        160 pts 1178956 dl/30d  official flutter.dev package
use  m3e_core                           160 pts    2132 dl/30d  Flutter-drawn, built on material_ui
use  m3e_buttons                        160 pts    2120 dl/30d  Flutter-drawn, built on material_ui
...
use  expressive_loading_indicator       160 pts   17211 dl/30d  Flutter-drawn
```

`material_ui` is checked on every run. Today it defines
`StyleVariant.material3Expressive` but `ThemeData` doesn't accept it yet, so
the context file tells the assistant to use only the official color scheme
(`DynamicSchemeVariant.expressive`) and packages for the rest. When
`material_ui` wires the option in, the context switches to the official
opt-in automatically.

## Audit your dependencies

```sh
native_trend audit
```

```
ios
  ok   cupertino_native                   native view, system controls
  skip liquid_glass_renderer              Flutter-drawn imitation (no native code)
       instead: adaptive_platform_ui, cupertino_native_better
android
  ok   material_ui                        official flutter.dev package
macos
  ok   cupertino_native                   native view, system controls
  skip liquid_glass_renderer              Flutter-drawn imitation (no native code)
       instead: cupertino_native_better, cupertino_native_plus
```

`audit` reads `dependencies` in `pubspec.yaml`, ranks each platform the same
way `find` does, and reports the dependencies that appear in a ranking.
Dependencies that should be replaced (imitations, plugins without a native
view, and discontinued packages) get two alternatives. The exit code is 1
when there is one, so it can run in CI. It writes no files.

## Options

`find`:

- `--platform ios|android|macos` (default `ios`)
- `--dir <path>`: project root (default `.`)
- `--out <path>`: output file (default `.ai/native_trend_<platform>.md`)
- `--link <file>`: add a one-line pointer to the output in `CLAUDE.md`,
  `AGENTS.md`, or any other file your assistant reads. Repeatable.
- `--no-cache`: don't read or write the archive cache.

`audit`:

- `--platform ios|android|macos`: repeatable (default all three)
- `--dir <path>`: project root (default `.`)
- `--no-cache`

Plugin sources come from the package archives on pub.dev. They are cached in
`~/.cache/native_trend` (`$XDG_CACHE_HOME/native_trend` if set,
`%LOCALAPPDATA%\native_trend` on Windows). A published version never
changes, so the cache is safe to keep; delete the folder to free the space.

## Apply with Claude Code

This repository is also a Claude Code plugin with three skills:

- `liquid-glass`: runs `find --platform ios`, lets you pick a package, reads
  its README and source, and converts only your navigation and control
  widgets (behind an iOS-only branch when the package has no fallback),
  following Apple's rules.
- `macos-glass`: the same for a Flutter macOS app with
  `find --platform macos`, behind a macOS-only branch when needed.
- `material-expressive`: runs `find --platform android`, applies the official
  part first, then converts only the components you choose.

```
/plugin marketplace add Seungpyo1007/native_trend
/plugin install native-trend@native-trend
```

Liquid Glass only shows in iOS and macOS builds made with Xcode 26 or later.
