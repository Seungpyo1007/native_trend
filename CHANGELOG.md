## 0.2.0

- Android: `find --platform android` for Material 3 Expressive. Checks the official `material_ui` package first (and whether its `ThemeData` accepts `styleVariant` yet), then ranks Flutter-drawn component packages, preferring ones built on `material_ui`.
- New `material-expressive` Claude Code skill.
- **Breaking:** the default output is now `.ai/native_trend_<platform>.md`; the iOS file moved from `.ai/native_trend.md` to `.ai/native_trend_ios.md`.
- iOS context now notes that the official `cupertino_ui` package has no Liquid Glass yet.
- Library: `classify` is now `classifyGlass`, `isIosPlugin` is now `isPluginFor`, `renderContext` is now `renderGlassContext`.

## 0.1.0

- `find`: searches pub.dev for Liquid Glass packages, detects real native views and the iOS 26 glass API in plugin sources, ranks them by pub.dev scores, and writes an AI context file (`--link` to CLAUDE.md/AGENTS.md).
- Claude Code plugin with a `liquid-glass` skill that applies the chosen package.
