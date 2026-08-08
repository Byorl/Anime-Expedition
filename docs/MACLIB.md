# MacLib implementation notes

This project uses the public [Byorl Maclib fork](https://github.com/Byorl/Maclib), based on the [original MacLib repository](https://github.com/biggaboy212/Maclib). The runtime loads `src/maclib.lua` directly from the fork.

The hierarchy is `Window -> TabGroup -> Tab -> SubTabGroup -> SubTab -> Section -> Element`. Subtabs support one-column and two-column layouts while retaining independent scrolling and section ownership.

The config registry restores controls with their public setters:

| Control | Setter |
|---|---|
| Toggle | `UpdateState(boolean)` |
| Slider | `UpdateValue(number)` |
| Input | `UpdateText(string)` |
| Dropdown | `UpdateSelection(value)` |
| Keybind | `Bind(EnumItem)` |
| Colorpicker | `SetColor` and `SetAlpha` |

The custom config layer avoids two problems observed in MacLib's built-in config implementation:

1. Its inspected toggle loader checks the saved state for truthiness, which can skip a saved `false`.
2. Built-in option loads are individually spawned, so callback ordering is nondeterministic.

This project instead applies every registered flag in sorted order and uses defaults for flags added after an older config was created.

MacLib's `Window:GlobalSetting` API is used for `UI Blur` and `Hide Private Info`. Blur defaults off; private user information is redacted by default. Window scaling is handled by `UIManager` rather than writing directly from the slider callback, so one render-step writer owns `Window:SetScale` and viewport fitting stays responsive on phones. The UI-size control uses Maclib's `LiteralPercent` and stepped-slider support, so `75%` means exactly `75` and drag coordinates remain stable while the window changes scale.
