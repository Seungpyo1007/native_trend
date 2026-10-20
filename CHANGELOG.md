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
