# MacLib implementation notes

This project uses the official [MacLib repository](https://github.com/biggaboy212/Maclib), [documentation](https://brady-xyz.gitbook.io/maclib-ui-library), and latest-release source.

MacLib's hierarchy is `Window -> TabGroup -> Tab -> Section -> Element`. Sections use `Side = "Left"` or `"Right"`.

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
