## 0.4.0

- Fix: the Android context said material_ui's official Expressive opt-in was available and told assistants to write `ThemeData(styleVariant: ...)`, which doesn't compile. The check matched `IconButton`'s own `styleVariant` field (in material_ui 1.7.0 and later); it now looks only at `ThemeData`.
- More accurate classification: only a package's own source files (`lib/`, `ios/`, `macos/`, `darwin/`, `android/`) are scanned, with comments removed, instead of the whole archive including README, CHANGELOG, `example/`, and `test/`.
- Federated plugins are classified by their endorsed implementation package (`default_package`), which holds the native code.
- iOS and macOS: a native plugin for other platforms only is now labeled "plugin for other platforms only" instead of "Flutter-drawn imitation".
- The official `cupertino_ui` package is checked on every iOS and macOS run, and the context's "Flutter status" changes when it gets Liquid Glass.
- Packages with no release in 12 months are marked `stale` and ranked after fresh ones of the same kind. Releases pub.dev hasn't analyzed yet show `? pts`.
- Project fit: candidates are annotated when they lack a platform the project in `--dir` builds for, or need a newer Flutter or Dart than its `environment` allows.
- `find --platform` takes several platforms (`ios,macos`, repeated, or `all`) and writes one context file each. **Behavior change:** without `--platform`, `find` uses the project's `ios/`, `android/`, and `macos/` folders (ios when there are none) and `audit` checks only those (all three when there are none).
- `audit` also checks dependencies that look relevant by name, description, or topics, so imitations pub.dev search doesn't surface are caught. SDK dependencies such as `flutter` are skipped.
- `--json` for `find` and `audit`, with a documented schema.
- Network: 30 s timeouts (2 min for archives), three retries with backoff on network errors, 429 (honoring `Retry-After`), and 5xx, and a clear message with exit code 69 when pub.dev can't be reached. One failing package is skipped instead of ending the run.
- Faster first run: up to four packages download at once.
- Cache: only the newest archive of each package is kept, plus `native_trend cache path` and `cache clean`. **Behavior change:** the macOS default moved to `~/Library/Caches/native_trend`; delete `~/.cache/native_trend` after upgrading.
- `--pages` (default raised from 2 to 3 search pages per query) and `--version`.
- **Breaking (library):** the top-level `search`, `fetchPackage`, and `fetchArchiveText` are replaced by the `PubApi` class (`search`, `fetchPackage`, `fetchSourceText`), and the orchestration that lived in `bin/` is the new `TrendFinder` class. `Kind` gains `otherPlatform`, so exhaustive `switch` statements need the new case. `pubspecDependencies` leaves out SDK packages. `styleVariantWired` expects source containing `class ThemeData`. New: `Project`, `TrendResult`, `AuditResult`, `readTar`, `packageSourceText`, `stripComments`, `mapPool`, `cleanCache`, `packageVersion`.

## 0.3.0

- macOS: `find --platform macos` for Liquid Glass with real AppKit views. Plugins are scanned for `AppKitView` and the macOS glass API (`NSGlassEffectView`, `.glassEffect`), and the result goes to `.ai/native_trend_macos.md`.
- New `macos-glass` Claude Code skill.
- New `audit` command: checks `pubspec.yaml` dependencies against the rankings for iOS, Android, and macOS (or the `--platform` values given), suggests replacements, and exits with 1 when a dependency should be replaced.
- Package archives are cached in the user cache directory, so repeat runs skip the downloads. Turn it off with `--no-cache`.
- Fix: iOS classification no longer counts a macOS `AppKitView` as a native iOS view.
- Library: `classifyGlass` takes a `platform`; new `renderMacosGlassContext`, `fetchArchiveText(cache:)`, `defaultCacheDir`, `pubspecDependencies`, `auditDependencies`, and `renderAudit`.

## 0.2.0

- Android: `find --platform android` for Material 3 Expressive. Checks the official `material_ui` package first (and whether its `ThemeData` accepts `styleVariant` yet), then ranks Flutter-drawn component packages, preferring ones built on `material_ui`.
- New `material-expressive` Claude Code skill.
- **Breaking:** the default output is now `.ai/native_trend_<platform>.md`; the iOS file moved from `.ai/native_trend.md` to `.ai/native_trend_ios.md`.
- iOS context now notes that the official `cupertino_ui` package has no Liquid Glass yet.
- Library: `classify` is now `classifyGlass`, `isIosPlugin` is now `isPluginFor`, `renderContext` is now `renderGlassContext`.

## 0.1.0

- `find`: searches pub.dev for Liquid Glass packages, detects real native views and the iOS 26 glass API in plugin sources, ranks them by pub.dev scores, and writes an AI context file (`--link` to CLAUDE.md/AGENTS.md).
- Claude Code plugin with a `liquid-glass` skill that applies the chosen package.
