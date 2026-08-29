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
})
```

On machines without an NVIDIA GPU, omit this widget from your wibar.
