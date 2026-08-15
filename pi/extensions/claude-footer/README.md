# pi-claude-footer

A pi extension that replaces pi's default two-line status bar (footer) with a
single-line, Claude Code-style footer, colored via the active theme's tokens:

```
~/repos/dotfiles (main) · deepseek-v4-flash · high        $0.03 · ↑1.2k ↓3.4k · 12.3%/200k
```

## Layout

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ~/repos/dotfiles (main) · deepseek-v4-flash · high    $0.03 · ↑1.2k ↓3.4k · 12.3%/200k │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
   ^left (cwd dim, branch accent, model bold accent)  ^padding  ^right (stats)
```

Everything lives on one line:

- **Left side**: `~`-relative cwd in `dim` (home replaced with `~`, mirroring
  pi's own `formatCwdForFooter`), then the git branch in `accent` (a
  highlight; `detached` included), then the model id in **bold accent** — the
  session identity — prefixed with a muted `(provider) ` when more than one
  provider is available. When the model supports reasoning, the active
  thinking level follows, colored by its theme token
  (`thinkingMinimal`…`thinkingMax`, mirroring the editor border color); `off`
  is dim.
- **Right side** (right-aligned): segments joined by a dim ` · `:
  - `$<cost>` only when cumulative cost > 0 (`>= $0.01` → 2 decimals,
    `>= $0.0005` → 3 decimals, otherwise up to 6 decimals, escalating
    further only when needed so a positive cost never displays as `$0`;
    trailing zeros stripped) — shown in `muted`;
  - `↑<input>` and `↓<output>` token counts via `formatTokens` (`1.2k`, `34k`,
    `5.6M`), each shown only when that counter is > 0 — accent arrows with
    dim numbers;
  - `<percent>%/<window>` always shown (window via `formatTokens`): the
    percentage is `accent` while healthy, `warning` when > 70%, `error` when
    > 90% (unknown `?` renders dim), with the window size in dim.

All colors come from theme tokens (`theme.fg`), so they adapt when the active
pi theme changes (dark/light, including the Omarchy theme sync extension).

## Design decisions

- **One line.** The default footer uses two lines (cwd/model + stats). This
  extension merges them into a single line with the cwd/model on the left and
  the stats right-aligned, minimizing vertical space.
- **Per-segment styling.** Every right-side segment is wrapped in its own
  `theme.fg()` call. ANSI color codes end with a reset, which would kill an
  outer `dim` wrapper (the default footer dims parts independently for exactly
  this reason); the left side is built from individually styled chunks for the
  same reason. All colors reference theme tokens, so the footer follows
  dark/light theme switches.
- **Truncation keeps the stats.** When `left + right + 1` exceeds the terminal
  width, the **left** side is truncated first (with `…`) so token/cost/context
  stats stay visible; only if the left becomes empty or the line still
  overflows is the right side truncated. All lines are guaranteed to fit within
  `width` (pi's `truncateToWidth` is ANSI-aware and never exceeds the limit).
- **Statuses on their own line, only when present.** Text set via
  `ctx.ui.setStatus()` appears on a second dim line, sorted by key, sanitized
  (control characters collapsed, repeated spaces trimmed). No statuses → no
  second line, keeping the footer at exactly one line in the common case.
- **Fresh model display.** `model_select` and `thinking_level_select` events
  update the footer immediately (re-render on every model/thinking level
  cycle), and the footer is re-installed on each `session_start` so it always
  uses the current session's context.
- **TUI only.** The footer is only installed when `ctx.mode === "tui"`.

## Install

The extension is a TypeScript module loaded from pi's extensions directory.
Symlink this directory into `~/.pi/agent/extensions/` (an existing pi install
is required to resolve the `@earendil-works/*` imports):

```sh
ln -sfn ~/repos/dotfiles/pi/extensions/claude-footer \
  ~/.pi/agent/extensions/claude-footer
```

Restart pi (or `/reload`) and the footer switches to the single-line layout.

## Typechecking

```
npx -p typescript@5.7 tsc -p tsconfig.json --noUnusedLocals --noUnusedParameters
```

`tsconfig.json` resolves `@earendil-works/*` and `typebox` through
machine-specific absolute paths (matching the sibling `ask/` extension), so
the paths must be edited per machine before typechecking. Do not try to
restructure it to relative paths — there is no `node_modules` in this repo to
resolve against. The extension itself needs no build step: pi loads `index.ts`
directly.

## Known limitations

- **Theme switches are captured at install time.** The footer factory receives
  the `Theme` instance when it is created (per session start). A mid-session
  `/theme` switch replaces the global theme object, but the custom footer keeps
  its captured instance until the next `session_start` (upstream pi behavior
  for all custom footers, not specific to this extension).
