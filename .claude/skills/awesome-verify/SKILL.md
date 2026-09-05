---
name: awesome-verify
description: Checkpoint AwesomeWM changes against the live window manager - restart awesome, confirm a clean startup, and visually verify the change with zoomed screenshots before committing. Use after ANY edit to AwesomeWM config, theme, or widget code (rc.lua, theme.lua, widget repos), before committing or pushing such changes, and whenever the user reports the red "errors during startup" screen.
---

# Awesome Verify

Awesome loads the entire config tree at startup; one nil index anywhere (a
missing `require`, a typo'd theme key) paints the red error overlay across
every monitor. "It compiles" and "it looks right in the editor" prove nothing —
check every rendering-affecting change against the running WM before it gets
committed.

## Checkpoint sequence

1. **Syntax gate** — catches parse errors without touching the WM:

   ```bash
   luac -p path/to/changed-file.lua
   ```

2. **Restart the WM**:

   ```bash
   awesome-client 'awesome.restart()'; sleep 3
   ```

   The `org.freedesktop.DBus.Error.NoReply` this prints is expected — the
   dbus connection drops during restart. It is not a failure.

3. **Confirm clean startup**:

   ```bash
   awesome-client 'return tostring(awesome.startup_errors)'
   ```

   `"nil"` means clean. Anything else is the same traceback the red screen
   shows — it names the failing file:line; fix and restart again.

4. **Visually verify the change.** Get the geometry of the thing you changed
   from awesome itself, then screenshot and zoom that region:

   ```bash
   # geometry of a client (also works for wibar/widget coords)
   awesome-client 'for _, c in ipairs(client.get()) do local g = c:geometry()
     return string.format("%d %d %d %d", g.x, g.y, g.width, g.height) end'

   # crop the region and magnify 4-5x so details are inspectable
   import -window root -crop WxH+X+Y - | magick - -scale 400% /tmp/verify.png
   ```

   Read the png and actually look at it. Watch for a trap: clients on
   *other tags* share screen coordinates with visible ones — screenshotting a
   hidden client's coords captures whatever is actually on screen there. Pick
   a client you can confirm is visible (floating windows are usually on top),
   or filter by `c.screen.selected_tag`.

5. Only after 1–4 pass: commit.

## Gotchas

- **Awesome runs `~/.config/awesome`, not your worktree.** When editing in a
  git worktree or a widget repo checkout elsewhere, the running WM won't see
  the change until the real checkout has it (bump the submodule / pull the
  branch there). Restarting without deploying verifies the *old* code.
- For widget repos with unit tests (e.g. crypto-widget's
  `lua5.3 tests/test-env-config.lua`), run those too — but they never replace
  the live restart, which is the only thing that exercises the render path.
- Screenshots of tooltips/popups need the mouse over the widget; use `xdotool
  mousemove X Y` first if available, or verify those interactively with the
  user.
