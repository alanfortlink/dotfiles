# pi-compact-view

Keeps the pi transcript short. Display-only; the session and what the model
sees are unchanged.

- **Thinking** streams inside a fixed-height window: the last `THINKING_LINES`
  (4) visual lines, scrolling in place, with a `... (N earlier lines, ctrl+o to
  expand)` hint above. When the message finishes it collapses to one line:
  `Thought for 5.2s` (`Thought` when the timing is unknown, e.g. a session
  recorded before this extension was installed).
- **Tool blocks** are capped at `TOOL_LINES` (10) visual lines while running
  (head kept, `... (N more lines, ctrl+o to expand)` line for the rest). When
  the tool finishes they collapse to one line: the tool title (`$ cmd`,
  `edit path`, ...) with ` · 120ms` appended when the timing is known. Errors
  collapse too, as `title · error · 120ms` on pi's error background.
- **Grouping**: pi puts a blank line above every tool block and every thinking
  block. That line is dropped when the previous chat sibling is a collapsed
  tool or a message that ends in thinking, so `Thought → $ cmd → $ cmd →
  Thought` reads as one tight run. Text keeps its normal spacing.

`ctrl+o` (pi's `app.tools.expand`) shows everything in full, exactly as before,
and collapses again on the next press. Thinking hide/show (`/settings` →
hide thinking) still works on top of this.

## How

pi has no hook for any of this, so `AssistantMessageComponent.updateContent`
/ `.render` and `ToolExecutionComponent.render` (exported from the pi package)
are patched on their prototypes at load, plus pi-tui's `Container.addChild`
to record a parent pointer for the sibling lookup. Thinking Markdown children are wrapped in
a tail-window/summary component; tool render output is sliced or
reduced to its title line. Durations are measured live (thinking: first
thinking delta → first non-thinking content; tools: `tool_execution_start` →
`tool_execution_end`) and persisted once per turn as a `compact-view-timings`
custom session entry (TUI-only, never sent to the model), restored on
`session_start` so they survive `/reload`, restart and `--resume`. Expanded state comes
from `ctx.ui.getToolsExpanded()` at render time. Tune the two constants at the
top of `index.ts`.

## Install

```sh
ln -sfn ~/repos/dotfiles/pi/extensions/compact-view \
  ~/.pi/agent/extensions/compact-view
```

## Test

```sh
PI=~/.local/share/mise/installs/node/25.9.0/lib/node_modules/@earendil-works/pi-coding-agent
node -e '
import { createJiti } from "'$PI'/node_modules/jiti/lib/jiti.mjs";
const P = "'$PI'";
await createJiti(import.meta.url, { alias: {
  "@earendil-works/pi-coding-agent": P + "/dist/index.js",
  "@earendil-works/pi-tui": P + "/node_modules/@earendil-works/pi-tui/dist/index.js",
  "@earendil-works/pi-ai": P + "/node_modules/@earendil-works/pi-ai/dist/compat.js",
  "@earendil-works/pi-agent-core": P + "/node_modules/@earendil-works/pi-agent-core/dist/index.js",
}}).import(process.cwd() + "/test.ts");
' --input-type=module
```
