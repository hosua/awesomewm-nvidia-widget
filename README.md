# nvidia-widget

AwesomeWM wibar widget showing NVIDIA GPU stats (utilization, and optionally
temperature, power draw, VRAM, and an arc gauge) via `nvidia-smi`.

## Dependencies

- NVIDIA proprietary driver with `nvidia-smi` on PATH

## Install

```bash
git submodule add https://github.com/hosua/awesomewm-nvidia-widget.git \
  ~/.config/awesome/hosuas-awesome-widgets/nvidia-widget
```

```lua
local nvidia_widget = require("hosuas-awesome-widgets.nvidia-widget.nvidia-widget")

-- in your wibar setup:
nvidia_widget({
    refresh_rate = 1,            -- seconds
    popup_bg = "#2E3440",
    popup_border_color = "#4C566A",
    show_icon = true,
    show_temp = true,
    show_power = true,
    show_vram = true,
    show_arc = true,
    arc_bg = "#ffffff11",        -- arc background rings
    arc_color = nil,             -- arc foreground (default: beautiful.fg_normal)
    popup_fg = nil,              -- popup text (default: beautiful.fg_normal)
    icon_color = nil,            -- recolor gpu.svg (e.g. "#333333" for light bars)
})
```

On machines without an NVIDIA GPU, omit this widget from your wibar.

## Click-off dismissal

Clicking anywhere off the open popup — an app window or the desktop —
closes it without swallowing the click, and opening another widget's
popup closes this one. Clicks landing on the wibar itself can't be
observed by a widget in AwesomeWM v4.3 and leave the popup open
(clicking the widget's own icon still toggles it). Implemented by
`popup-click-off.lua`, a copy shared and kept in sync across all the
widget repos.
