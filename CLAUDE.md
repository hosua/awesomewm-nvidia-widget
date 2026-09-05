# nvidia-widget

## Icon color rule

Icons ship monochrome (currentColor / one flat neutral color) and get their
color at **load time** via AwesomeWM's built-in recolor, driven by a theme or
config color key:

```lua
gears.color.recolor_image(icon_path, color)
```

This is the established pattern across the widgets (`icon_color` handling in
ram/nvidia/pacman/volume/bookmark widgets and `hosua/theme.lua`). Never bake a
theme color into the image file, never edit SVG fill/stroke attributes to
recolor, never ship per-color copies of one icon — a single neutral source
file plus `recolor_image` keeps every icon themeable from one place.

## Verify against the running WM

Before committing any change that affects rendering, run the checkpoint in the
`awesome-verify` skill (`.claude/skills/awesome-verify/SKILL.md`): syntax gate,
`awesome.restart()`, confirm `awesome.startup_errors` is nil, and screenshot
the affected region. This skill is synced across the awesome config repo and
all widget submodules — edit it in one place and re-sync rather than letting
copies diverge.
