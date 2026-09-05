# nvidia-widget

## AwesomeWM API docs — use the local mirror, not the website

Do NOT look up AwesomeWM API documentation on awesomewm.org by default. This
repo is checked out as a submodule of `awesomewm-config`, which carries a
condensed local mirror at `../../.claude-docs/` (relative to this repo root):

- Start at `../../.claude-docs/00-INDEX.md` — a TOC mirroring
  <https://awesomewm.org/apidoc/> with local paths and upstream URLs.
- Coverage: all `awful.*` and `wibox.*`, `beautiful`, `gears.color`/`gears.shape`,
  core objects, and the documentation guides.
- Search it with `rg -i 'keyword' ../../.claude-docs/` before reasoning from memory.
- Only fetch awesomewm.org for pages the index marks as not mirrored, or when a
  local page looks stale — and fix the local page when that happens.

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
