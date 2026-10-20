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

Only a package's own source counts: `lib/`, `ios/`, `macos/`, `darwin/`, and
`android/`, with comments removed. A README, CHANGELOG, example, or test
that mentions `UiKitView` proves nothing. For a federated plugin, the
endorsed implementation package (`default_package`) is scanned too.

Ranking within each kind: packages with a release in the last 12 months
first, then pub.dev points, then 30-day downloads. Older ones are marked
`stale`, because Liquid Glass and Material 3 Expressive APIs change with
every OS release. A brand-new release that pub.dev hasn't analyzed yet shows
`? pts`.

## Install

```sh
dart pub global activate native_trend
```

## iOS: Liquid Glass

```sh
native_trend find --platform ios --link CLAUDE.md
```

```
use  adaptive_platform_ui               160 pts   15137 dl/30d  native view + glass API
       no macos support
use  cupertino_native_better            160 pts   11639 dl/30d  native view + glass API
...
use  cupertino_native                   150 pts    2732 dl/30d  native view, system controls
       stale: no release since 2025-09-08
skip liquid_glass_widgets               160 pts  104238 dl/30d  plugin without a native view
skip liquid_glass_renderer                ? pts   30268 dl/30d  Flutter-drawn imitation (no native code)
```

Each plugin's source is scanned for a platform view (`UiKitView`) and the iOS
26 glass API (`UIGlassEffect`, `.glassEffect`). The official `cupertino_ui`
package is checked on every run: today neither it nor Flutter's Cupertino
library implements Liquid Glass
([flutter#170310](https://github.com/flutter/flutter/issues/170310)), and the
context file switches its "Flutter status" when that changes.

## macOS: Liquid Glass

```sh
native_trend find --platform macos --link CLAUDE.md
```

```
use  cupertino_native_better            160 pts   11639 dl/30d  native view + glass API
use  cupertino_native_plus              160 pts    1718 dl/30d  native view + glass API
use  native_macos                       160 pts       0 dl/30d  native view + glass API
...
skip liquidify                          150 pts     553 dl/30d  plugin without a native view
skip liquid_glass_widgets               160 pts  104238 dl/30d  plugin for other platforms only
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
use  material_ui                          ? pts 2270516 dl/30d  official flutter.dev package
use  material_3_expressive              160 pts    3274 dl/30d  Flutter-drawn, built on material_ui
use  m3e_buttons                        160 pts    3042 dl/30d  Flutter-drawn, built on material_ui
...
use  expressive_loading_indicator       160 pts   12860 dl/30d  Flutter-drawn
       stale: no release since 2025-08-01
```

`material_ui` is checked on every run. Today it defines
`StyleVariant.material3Expressive` but `ThemeData` doesn't accept it yet, so
the context file tells the assistant to use only the official color scheme
(`DynamicSchemeVariant.expressive`) and packages for the rest. When
`ThemeData` gets the option, the context switches to the official opt-in
automatically. Only `ThemeData` counts: `IconButton` already has a
`styleVariant` of its own.

## Audit your dependencies

```sh
native_trend audit
```

```
ios
  ok   cupertino_native                   native view, system controls
  skip liquid_glass_renderer              Flutter-drawn imitation (no native code)
       instead: adaptive_platform_ui, cupertino_native_better
  skip glassmorphism                      Flutter-drawn imitation (no native code)
       instead: adaptive_platform_ui, cupertino_native_better
android
  ok   material_ui                        official flutter.dev package
macos
  ...
```

`audit` reads the hosted `dependencies` in `pubspec.yaml` (not
`dev_dependencies` or SDK packages) and checks each one that appears in a
platform's ranking or looks relevant on its own: "glass" in its name,
description, or topics for iOS and macOS, "expressive" or "m3e" for Android.
So an imitation that pub.dev search doesn't surface is still caught.
Dependencies that should be replaced (imitations, plugins without a native
view or for other platforms only, and discontinued packages) get two
alternatives. The exit code is 1 when there is one, so it can run in CI. It
writes no files.

## Your project

`find` and `audit` read the project in `--dir`:

- **Platforms.** Without `--platform`, they use the `ios/`, `android/`, and
  `macos/` folders present. `find` falls back to `ios` when there are none,
  `audit` to all three.
- **Fit notes.** Each candidate is annotated when it lacks a platform the
  project builds for (`no android support`), or when its Flutter or Dart
  floor is above the project's `environment` (`needs Flutter 3.47.0+,
  project allows 3.35.0`). Notes don't change the ranking.

## Options

`find`:

- `--platform ios|android|macos|all`: repeatable or comma separated, e.g.
  `--platform ios,macos`. One context file per platform. Default: the
  project's platforms (see above).
- `--dir <path>`: project root (default `.`)
- `--out <path>`: output file, with a single platform only (default
  `.ai/native_trend_<platform>.md`)
- `--link <file>`: add a one-line pointer to each output in `CLAUDE.md`,
  `AGENTS.md`, or any other file your assistant reads. Repeatable.
- `--pages <n>`: pub.dev search pages per query (default 3, 10 results each)
- `--json`: print JSON (below) instead of text. Context files are still
  written; progress goes to stderr.
- `--no-cache`: don't read or write the archive cache.

`audit`: `--platform` (default: the project's platforms, or all three),
`--dir`, `--pages`, `--json`, `--no-cache`.

`native_trend --version` prints the version.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Done |
| 1 | `audit` found a dependency to replace |
| 64 | Bad usage |
| 66 | `audit`: no `pubspec.yaml` in `--dir` |
| 69 | pub.dev unreachable after retries |
| 78 | `cache`: no cache directory (`HOME` unset) |

Requests time out after 30 seconds (2 minutes for archives) and are retried
three times, with 1, 2, and 4 second backoff, on network errors, HTTP 429
(honoring `Retry-After`), and 5xx. A package that still fails is skipped
with a message; only failing searches end the run.

### JSON

`find --json`:

```json
{
  "schema": 1,
  "tool": "native_trend",
  "version": "0.4.0",
  "checkedAt": "2026-10-21T00:00:00.000Z",
  "results": [
    {
      "platform": "ios",
      "output": ".ai/native_trend_ios.md",
      "officialSupport": false,
      "candidates": [
        {
          "name": "some_glass_plugin",
          "version": "1.2.0",
          "kind": "nativeGlass",
          "label": "native view + glass API",
          "usable": true,
          "points": 160,
          "likes": 40,
          "downloads30Days": 5000,
          "publisher": "example.com",
          "platforms": ["android", "ios"],
          "published": "2026-10-01T00:00:00.000Z",
          "stale": false,
          "implementation": null,
          "notes": ["no macos support"],
          "description": "..."
        }
      ]
    }
  ]
}
```

- `officialSupport`: for `ios` and `macos`, whether `cupertino_ui` has
  Liquid Glass; for `android`, whether material_ui's `ThemeData` accepts
  `styleVariant`. `null` when the check failed.
- `kind`: `nativeGlass`, `nativeSystem`, `noNativeView`, `otherPlatform`,
  `notPlugin` (iOS, macOS); `official`, `nativeView`, `onMaterialUi`,
  `flutterDrawn` (Android). Candidates are in ranking order.
- `points`: `null` while pub.dev hasn't analyzed the release.
- `implementation`: the scanned implementation package of a federated
  plugin.

`audit --json`:

```json
{
  "schema": 1,
  "tool": "native_trend",
  "version": "0.4.0",
  "checkedAt": "2026-10-21T00:00:00.000Z",
  "clean": false,
  "results": [
    {
      "platform": "ios",
      "findings": [
        {
          "name": "glassmorphism",
          "ok": false,
          "kind": "notPlugin",
          "label": "Flutter-drawn imitation (no native code)",
          "discontinued": false,
          "replacedBy": null,
          "alternatives": ["adaptive_platform_ui", "cupertino_native_better"]
        }
      ]
    }
  ]
}
```

`kind` and `label` are `null` for a discontinued dependency. New fields may
be added within `schema` 1; renames or removals bump it.

## Cache

Plugin sources come from the package archives on pub.dev, kept in
`~/Library/Caches/native_trend` on macOS, `~/.cache/native_trend` on Linux
(`$XDG_CACHE_HOME/native_trend` when set), and `%LOCALAPPDATA%\native_trend`
on Windows. A published version never changes, so a cached archive is never
refetched, and only the newest archive of each package is kept.

```sh
native_trend cache path    # print the folder
native_trend cache clean   # delete it
```

native_trend 0.3.0 used `~/.cache/native_trend` on macOS too; delete that
folder after upgrading.

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

## Library

The CLI is a thin layer over the library:

```dart
final api = PubApi(http.Client(), cache: defaultCacheDir());
final result = await TrendFinder(api, project: Project.read(Directory('.')))
    .find('ios');
print(renderText(result.ranked));
```
