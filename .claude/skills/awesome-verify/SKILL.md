---
name: awesome-verify
description: Checkpoint AwesomeWM changes against the live window manager - restart awesome, confirm a clean startup, and visually verify the change with zoomed screenshots in a headless Xvfb sandbox (never the user's display, pointer or keyboard) before committing. Use after ANY edit to AwesomeWM config, theme, or widget code (rc.lua, theme.lua, widget repos), before committing or pushing such changes, and whenever the user reports the red "errors during startup" screen.
---

# Awesome Verify

Awesome loads the entire config tree at startup; one nil index anywhere (a
missing `require`, a typo'd theme key) paints the red error overlay across
every monitor. "It compiles" and "it looks right in the editor" prove nothing —
check every rendering-affecting change against the running WM before it gets
committed.

## Never touch the user's display

Do every visual check in a **sandbox**: a second awesome on its own headless
Xvfb display and its own dbus session, started by `sandbox.sh` next to this
file. Never run `xdotool`, `xte`, `ydotool` or any click/keypress/mousemove
against the user's display (`:0` or whatever `$DISPLAY` is), never screenshot
it to inspect a change, and never ask the user to hover something for you.

`sandbox.sh` gets its display number from `Xvfb -displayfd`, so the X server
picks a free one. Never hardcode `:99` and never reuse a display you did not
start: other projects (drawio exports, README screengrabs, another session's
sandbox) may be running at the same time. `sandbox.sh list` shows every X
server in use before you start.

## Checkpoint sequence

1. **Syntax gate** — catches parse errors without touching any WM:

   ```bash
   luac -p path/to/changed-file.lua
   ```

2. **Start a sandbox** — it loads `~/.config/awesome/rc.lua` from disk, so it
   runs exactly the code the user's WM would run after a restart:

   ```bash
   SANDBOX=.claude/skills/awesome-verify/sandbox.sh
   id=$("${SANDBOX}" start)            # prints the display number, e.g. 3
   ```

   `AWESOME_SANDBOX=1` is set inside it: `rc/autostart.lua` and
   `rc/tag_persist.lua` skip themselves, so no app is relaunched and the real
   session's tag state is not overwritten. `start` refuses to run against a
   config without that guard.

3. **Confirm clean startup** inside the sandbox:

   ```bash
   "${SANDBOX}" exec "${id}" -- awesome-client 'return tostring(awesome.startup_errors)'
   ```

   `"nil"` means clean. Anything else is the traceback the red screen would
   show; it names the failing file:line. Fix, `stop`, and `start` again.

4. **Visually verify the change** in the sandbox. Its pointer and keyboard
   are its own, so hover, click and type freely there:

   ```bash
   # where things are: ask the sandboxed awesome, or screenshot the bar first
   "${SANDBOX}" shot "${id}" /tmp/verify-bar.png --crop 1920x26+0+0
   # hover a widget to raise its tooltip, then capture it
   "${SANDBOX}" exec "${id}" -- xdotool mousemove 1220 12
   sleep 2
   "${SANDBOX}" shot "${id}" /tmp/verify-tip.png --crop 800x200+800+0
   # magnify small details 4x before reading them
   magick /tmp/verify-tip.png -scale 400% /tmp/verify-tip-4x.png
   ```

   Read the png and actually look at it. Popups can also be opened from
   code: `"${SANDBOX}" exec "${id}" -- awesome-client '...popup.toggle()'`.

5. **Stop the sandbox**, always, also after a failure:

   ```bash
   "${SANDBOX}" stop "${id}"
   ```

6. **Apply it to the user's session** only after 1–5 pass. Restarting the
   real WM does not touch the pointer and is fine:

   ```bash
   awesome-client 'awesome.restart()'; sleep 3
   awesome-client 'return tostring(awesome.startup_errors)'   # expect "nil"
   ```

   The `org.freedesktop.DBus.Error.NoReply` from the restart is expected.

7. Only then commit.

## Gotchas

- **Awesome runs `~/.config/awesome`, not your worktree.** Both the sandbox
  and the real WM load the real checkout. When editing a widget repo checkout
  elsewhere, deploy it there first (bump the submodule / pull the branch), or
  you are verifying the *old* code.
- The sandbox is one screen (`--size`, default 1920x1080), not the user's
  monitor layout. Per-screen placement bugs still need a look at the real
  session; describe what to check and let the user look.
- Widgets in the sandbox share their on-disk caches and credentials with the
  real session (same widget dirs). A sandbox fetches like a second bar would.
- For widget repos with unit tests (e.g. `./tests/run.sh`), run those too;
  they never replace the sandbox, which is the only thing that exercises the
  render path.
