# LayoutRR — window layout save/restore for Hyprland (omarchy 4)

## Usage

- **Save**: `CTRL+ALT+L` or `layout-save` → `~/.config/hypr/layout-data.lua`
  (previous copy kept as `layout-data.lua.bak`). Also regenerates
  `layout-rules.lua` (static rules for splash apps: Steam/Discord).
- **Restore**: automatic ~3 s after login (`hyprland.start` hook in
  `layout.lua`), only if no spec app is already open. Manually:
  `layout-boot` — adopts the windows that already exist, launches only the
  missing ones, rebuilds each workspace's dwindle tree, verifies. Re-running
  is safe (a session that already matches is a no-op).
  Flags: `--dry-run` (plan only), `--file PATH` (other spec), `--boot`
  (boot code path incl. freshness guard), `--force` (skip that guard),
  `--reset` (forget a stuck run, move windows out of `special:layoutrr`).
  Both wrappers exit non-zero when the call did not run.
- **Knobs**: `~/.config/hypr/layout-overrides.lua` — launch commands per
  class, class aliases, per-workspace URLs for Chrome slots, splash classes,
  ignore list, timeouts, tolerance. Re-read on every save/restore.
- **Logs**: `~/.local/state/layout-rr/restore.log` (previous real run in
  `restore.prev.log`; dry runs go to `restore.dry.log`, guard/error skips to
  `restore.skipped.log`), `save.log`. Notifications: one at the end
  ("restored N/M", problem classes named).
- **Troubleshooting**: read `restore.log` — the plan tells you whether each
  row was adopted or launched (and with which command); `claimed … (tag|
  seq-new|class-fallback)` tells you how the window was recognised;
  `FAILED`/`MISSING_APP` name the row; the verification table shows what is
  off (`geom … want …`, `fullscreen=`, `ws=`). Typical fixes: add/adjust the
  class's entry in `commands` (an app that hands off to a running instance
  needs `no_pid_rules` or a "new process" flag like ghostty's
  `--gtk-single-instance=false`); add an `aliases` entry after an app-id
  change; re-save if the layout in the spec is simply stale.
- **Testing without touching the boot spec**:
  `layout-save --file /tmp/x.lua && layout-boot --dry-run --file /tmp/x.lua`
  then `layout-boot --file /tmp/x.lua`.
- **Caveats**: `hyprctl reload` wipes all Lua state, so a restore in flight is
  abandoned; on the next config evaluation any windows left in
  `special:layoutrr` are moved to their monitor's active workspace (notified).
  Re-run `layout-boot` afterwards. If the bar isn't up yet at boot, sizes
  settle after it appears (tree shape is right).

---

Requirements for the rewrite of `~/.config/hypr/layout.lua` (implemented,
see Usage above). This section defines what "works" means so it can be
reviewed against something concrete.

## 0. Context (facts, verify before relying on them)

- Hyprland 0.56.2, Lua config (omarchy 4). Entry: `~/.config/hypr/hyprland.lua`
  → `require("hypr.layout")`, `require("hypr.layout-rules")`. The `*.conf`
  files in `~/.config/hypr/` are hyprlang leftovers and are NOT loaded.
- API stubs: `/usr/share/hypr/stubs/hl.meta.lua`. Wiki:
  `wiki.hypr.land/Configuring/Advanced-and-Cool/Expanding-functionality/`
  (events, timers), `.../Basics/Dispatchers/` (`hl.dsp.exec_cmd(cmd, rules)`),
  `.../Basics/Window-Rules/` (static/dynamic effects, tags),
  `.../Layouts/Custom-Layouts/`.
- Relevant primitives that exist today and the current code does not use:
  - `hl.exec_cmd(cmd, rules)` — window rules applied to the spawned process's
    window by PID (`workspace = "<ws> silent"`, `float`, `move`, `size`,
    `monitor`, `tag = "+x"`, `no_initial_focus`). Fails when the process
    forks/hands off (Chrome second window, some wrapper scripts).
  - `hl.on("window.open", fn(w))` (rules applied), `window.open_early`,
    `window.class`, `window.close`, `window.move_to_workspace`,
    `workspace.special_active`, `monitor.added`, `config.reloaded`.
  - `hl.timer(fn, {timeout, type="oneshot"|"repeat"})`, `hl.get_windows({class=..., workspace=..., mapped=...})`,
    `hl.get_window("address:...")`, `w.pid`, `w.tags`, `w.initial_class`.
  - `hl.notification.create{}` (compositor OSD) in addition to `notify-send`.
- Layout: dwindle with `force_split = 2`; two 4K monitors at scale 1.5
  (HDMI-A-1 at 0x0, DP-1 at 2560x0). Special workspaces: `special:scratchpad`,
  `special:scratch2..4`.
- Existing entry points that must keep working: keybind CTRL+ALT+L →
  `LayoutRR.save()` (bindings.lua), CLI wrappers `~/.local/bin/layout-save`
  and `~/.local/bin/layout-boot [--force]` (thin `hyprctl dispatch` shims),
  boot trigger via `hl.on("hyprland.start")` inside layout.lua.
- Files: `layout-data.lua` (generated spec), `layout-rules.lua` (generated
  static rules for splash apps). Both under `~/repos/dotfiles` git.

## 1. Goals

G1. After login the desktop looks like it did when I last pressed CTRL+ALT+L:
    same apps, same workspaces/monitors, same tiled arrangement and sizes,
    same floating geometry, same active workspace per monitor.
G2. Restore is deterministic and idempotent: running it again on an already
    (partially) restored session converges to the saved layout without
    launching duplicates. "Flaky" is defined as any run that ends in a
    different state than the previous run from the same starting state.
G3. Every run is observable: a log file that explains what it decided, what
    it waited for, what timed out and what ended up different from the spec.
G4. Failures are contained: one app failing to start, missing, or renamed
    never blocks the rest, never leaves a special workspace open, never
    leaves the session focused on a staging area.

## 2. Save (`LayoutRR.save(opts?)`)

S1. Capture every mapped, non-hidden top-level window (`w.mapped and not
    w.hidden`, workspace name non-empty). Skip layer surfaces and windows with
    empty class. Per window record: `class`, `initial_class`, `title` (info
    only), `ws` (name), `mon`, `floating`, `pinned`, `fullscreen` (int),
    `x,y,w,h` (ints, from `w.at`/`w.size`), `pid` (info only).
S2. Capture per-monitor state: active workspace name, active special
    workspace name (or nil). Capture the focused window index. These are used
    to end restore in the same visual state (R14).
S3. Deterministic ordering: rows sorted by (workspace, x, y, class). The
    order is the dwindle re-insertion order on restore, so it must be stable
    across identical saves.
S4. Output `layout-data.lua` as `return { version = 2, monitors = {...},
    windows = {...} }`. Regenerated files carry the "AUTO-GENERATED" header.
    Before overwriting, copy the previous file to `layout-data.lua.bak`
    (one level of undo).
S5. Regenerate `layout-rules.lua` for splash-screen apps (`SPLASHY` set,
    today `steam`, `discord`): anchored class match → `workspace <ws> silent`
    (+ float/size when floating). Unchanged behaviour, keep it.
S6. Hand-edited configuration never lives in generated files. All user knobs
    live in one user-owned file `~/.config/hypr/layout-overrides.lua`
    (create with documented defaults if missing, never overwrite):
    - `commands`: class → launch command (today's `resolve_cmd` fixed table)
    - `aliases`: saved class → class the app maps with now
    - `urls`: workspace → URL substituted for `{url}` (google-chrome slots)
    - `splashy`: set of classes handled by static rules
    - `ignore`: classes never saved/restored — exact names or Lua patterns
      (default `^steam_app_%d+$`: games can't be relaunched)
    - `timeouts`: per-window / total, `tolerance_px`
S7. `save` accepts `{ file = path }` so tests can save to a scratch file
    without touching the boot spec. CLI: `layout-save [--file PATH]`.
S8. Feedback: one low-urgency notification "saved N windows (M workspaces)".
    Errors (cannot write, zero windows) → critical notification, non-zero
    exit for the CLI where possible.

## 3. Restore (`LayoutRR.restore(opts?)`)

Opts: `{ force = bool, dry_run = bool, file = path, boot = bool }`.
CLI: `layout-boot [--force] [--dry-run] [--file PATH]`.

### Preconditions / guards
R1. Exactly one restore in flight. A second call while running notifies
    "restore already running" and returns. State must be reset on completion,
    timeout, error and cancellation so a stuck flag can never wedge future
    runs (wrap the whole engine in a driver that guarantees `finish()`).
R2. Boot run (`boot = true`): start only when the session is "fresh": no
    mapped window whose class is in the spec (splashy excluded) — otherwise
    skip with a notification. Manual runs always proceed (adoption below makes
    that safe); `--force` only exists to override the boot guard when called
    from the CLI.
R3. Wait for readiness before doing anything: all monitors named in the spec
    present (`hl.get_monitors()`), bounded by `timeouts.monitors` (default 15
    s); after timeout continue and map missing monitors to the focused
    monitor (log it). Do not rely on a fixed `sleep 3`.
R4. `dry_run`: print the full plan (per window: adopt/launch, command, target,
    monitor fallback) to the log and a notification, launch nothing, move
    nothing.

### Window acquisition
R5. Adopt before launch. For every spec row, first try to claim an existing,
    unclaimed, mapped window with the same class (or alias). Rows for the same
    class are matched greedily in spec order against candidates sorted by
    (workspace == target first, then x, y) so re-runs pick the window already
    in the right place. Only rows left unmatched get launched.
R6. Launch with rules. Use `hl.exec_cmd(cmd, rules)` with at least
    `tag = "+layoutrr-<id>"` and `workspace = "<staging> silent"` (see R8) so
    the compositor itself files the new window and identifies it; where the
    PID rule cannot work (any process that hands off to a running instance —
    Chrome ≥2nd window; verify per app in `commands`, allow a per-class
    `pid_rules = false` flag) fall back to: launch one at a time and claim the
    first new mapped window of that class that appeared after the launch.
R7. Detect arrivals with events, not polling: `hl.on("window.open")` (and
    `window.class` for apps whose class is set late) claim windows; a
    per-row watchdog `hl.timer` enforces `timeouts.window` (default 30 s) and
    marks the row FAILED without stopping the run. Subscriptions and timers
    created by a run are removed at `finish()`.
R8. Staging: newly launched windows land in a hidden special workspace
    (`special:layoutrr`) — never on whatever workspace the user is looking
    at — until placement. If a window ignores the rule and appears elsewhere,
    claim it anyway (class/tag match) and move it.
R9. Chrome: one `google-chrome` slot per (workspace, index) opens
    `urls[ws]` (blank if unset). Because slots are indistinguishable by
    class, launch Chrome windows strictly one at a time and claim by "new
    address since launch". Preserve this even if everything else is parallel.
R10. Splashy classes (Steam/Discord) are launched (`commands`) but placed by
    the static rules only; they are excluded from adoption/placement/verify
    (they may still be counted in the summary as "static").

### Placement
R11. Placement starts per workspace as soon as ALL rows for that workspace
    are resolved (claimed or FAILED); workspaces are placed sequentially, in
    spec order, normal workspaces before specials. Do not wait for the whole
    session if one app is slow — but never place a workspace with a window
    still pending, since dwindle order depends on insertion order.
R12. Tiled arrangement is reproduced by insertion order: make the target
    workspace active on its monitor (specials: toggle on that monitor only),
    move claimed windows in spec order, focus following each move so the
    next window splits from the previous one; check split orientation
    against the spec (H/V from relative positions of the two windows) and
    `togglesplit` when it disagrees. Then a bounded measure-and-correct
    resize loop (max `timeouts.resize_passes`, default 6; stop early when
    every tiled window is within `tolerance_px`, default 4). Waits between
    steps use short `hl.timer`s (state machine / continuation style), never
    busy loops, and each step re-reads live window handles by address (never
    trusts stale handles).
R13. Floating windows: `float`, then `move` + `resize` absolute; `pinned` and
    `fullscreen` restored last. Floating windows are placed after the tiled
    ones of that workspace so they don't take part in the split sequence.
R14. End state: every special workspace opened by the run is closed unless
    the spec says it was open on that monitor at save time; each monitor's
    active workspace is set to the saved one; focus goes to the saved focused
    window if it exists, else the first tiled window on the saved active
    workspace of the focused monitor. Staging workspace must be empty and
    hidden (leftover unclaimed windows are moved to the saved active
    workspace and reported).
R15. Total run bounded by `timeouts.total` (default 120 s); on expiry the
    run performs R14 and reports what is missing.

### Verification & reporting
R16. After R14 compare live state to spec per row: workspace, monitor,
    floating, and geometry (within tolerance). Result classes: OK,
    MISMATCH(what), FAILED(launch timeout), MISSING_APP (command not found /
    process exited without a window), STATIC. Log a table; notification
    summary "restored 9/9" (low) or "restored 7/9 — see log" (normal, with
    the two problem classes named).
R17. Log file `~/.local/state/layout-rr/restore.log` (truncated at run start,
    previous kept as `restore.prev.log`): timestamped lines for guard
    decisions, plan, each launch (command + rules), each claim (address, how
    matched), each move/resize/togglesplit, timeouts, verification table,
    total duration. `save` logs to `save.log` similarly. Never spam
    notifications; one at start (boot only) and one at end.
R18. Every callback/timer body is wrapped so a Lua error is logged, notified
    once, and still triggers `finish()` (R1/R14) — a thrown error may not
    leave the run half-done with a special workspace open.

## 4. Non-functional

N1. Pure Lua inside the compositor; no external daemons, no polling of
    `hyprctl` from shell. The `~/.local/bin` wrappers stay thin.
N2. Reload-safe: `hyprctl reload` re-evaluates layout.lua. Requirement:
    (a) `hyprland.start` hook registers once per config evaluation and the
    boot restore is triggered at most once per session (guard with a global
    flag on `LayoutRR`), (b) if a reload happens mid-run, the run must either
    survive (state kept in the persistent global) or be cleanly abandoned
    with `finish()` semantics — verify which happens and document it.
    `hyprctl configerrors` must be clean after every edit.
N3. Idempotence test: with the session already matching the spec, `layout-boot`
    launches nothing and ends with all rows OK; moving one window elsewhere
    and rerunning brings it back; closing one window and rerunning relaunches
    only that one.
N4. Determinism test: two consecutive `layout-save` calls with no user action
    in between produce byte-identical `layout-data.lua`.
N5. Performance: a re-run on a fully restored session finishes in < 5 s; a
    cold boot restore in the time apps take to start plus < 10 s overhead.
N6. Cleanup: remove the dead `exec-once … layout-boot` from `autostart.conf`
    and the legacy `layout.json` / `layout-rules.conf` (unused hyprlang era)
    so there is a single boot trigger. Do not touch other `.conf` files.
N7. Code layout: `layout.lua` may be split into `layout/` modules
    (`require("hypr.layout")` must keep working; `layout/init.lua`). Keep the
    header comment: what it does, how to test, where the log is.
N8. Docs: this file gets a short "Usage" section at the top (save keybind,
    CLI flags, overrides file, log location, troubleshooting: what to check
    when a window ends up wrong) once the implementation lands. Update
    `~/.local/bin/layout-boot`/`layout-save` help text.

## 5. Out of scope

- Restoring browser tabs/URLs beyond the per-slot URL map.
- Window groups (tabbed groups), scrolling/master layouts, sessions per
  monitor profile (single spec only, `layout-data.lua`).
- Contributing anything upstream (Hyprland/omarchy) — work around gaps
  locally.

## 6. Acceptance checklist (for the reviewer)

- [ ] `hyprctl reload && hyprctl configerrors` clean.
- [ ] `layout-save --file /tmp/x.lua` twice → identical files (N4).
- [ ] `layout-boot --dry-run --file /tmp/x.lua` prints a plan, changes nothing.
- [ ] `layout-boot --file /tmp/x.lua` on the live session: launches nothing,
      summary all OK, ends on the same workspace/focus it started (N3, R14).
- [ ] Move a ghostty window to workspace 5, rerun → it is back, no duplicates.
- [ ] Close one ghostty, rerun → exactly one ghostty launched, split/size
      within tolerance (R12).
- [ ] Simulate a missing app (`commands` entry pointing at a bogus binary):
      run completes, row FAILED/MISSING_APP, everything else OK, no special
      workspace left open (G4, R15–R18).
- [ ] Log contains plan, claims, verification table (R17).
- [ ] No timers/subscriptions leak between runs (inspect code; rerun 3× and
      confirm no duplicate notifications or moves).
- [ ] Boot guard: with browser open, `layout-boot` (no --force, boot=true
      path) skips; manual `layout-boot` adopts.
- [ ] Reboot test is the user's — but the code path for `boot = true` must be
      exercised by calling `LayoutRR.restore({ boot = true, file = ... })`
      via `hyprctl dispatch` after the guard has been satisfied.
