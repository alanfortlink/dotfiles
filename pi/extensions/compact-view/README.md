# pi-compact-view

Keeps the pi transcript short. Display-only; the session and what the model
sees are unchanged.

- **One line per interaction.** An interaction is a user prompt and
  everything the agent does until the next prompt. All of its thinking and
  tool calls are consolidated into a single line, anchored at the bottom of
  the activity — right above the final answer (interim answer text is left
  alone):

  ```text
   1m 24s · 💻 6 (1✗) ls, echo, cat +3 · 🤖 2 audit, research · 🧠 12s ────

   All 3 delegates finished. Results: …
  ```

  Wall-clock time first (bold; falls back to the sum of durations when
  starts are unknown); then per tool: icon (`💻 bash`, `📖 read`,
  `📄 write`, `📝 edit`, `🔍 grep`, `🔎 find`, `📁 ls`, `🌐 web*`, `🤖
  delegate*`, `❓ ask`, `🧩` other extension tools — `TOOL_ICONS`), bold
  count (dropped when it's 1 and there's a hint), failures bound to their
  tool as `(2✗)` in the error color, up to `HINTS_PER_TOOL` muted hints of
  what ran (command names, file basenames, grep patterns, hostnames, quoted
  search queries, delegate task names taken from the result so spawn/wait/
  status agree; unknown tools show their name) with `+n` for the rest; then
  🧠 last, with its own (bold) time only when ≥ 2s or ≥ 30% of the
  interaction; a muted `─` rule fills the line, stopping one cell short of
  the edge (pi and the terminal can disagree on an emoji's width, and a line
  that wraps leaves a stale copy of itself on screen). While the turn is
  running the line updates live and a second line under it shows the current
  activity (`⏳ thinking…` / `⏳ 💻 $ npm test`, bare `⏳` between steps so
  the line count only grows); it goes away at `agent_end`.
  Thinking text and tool output are **not streamed** while collapsed. No
  background bars by default (`RUN_BG` to opt in) — bold/colored text only.

`ctrl+o` (pi's `app.tools.expand`) shows everything in full, exactly as before,
and collapses again on the next press. Thinking hide/show (`/settings` →
hide thinking) still works on top of this.

## How

pi has no hook for any of this, so `AssistantMessageComponent.updateContent`
/ `.render` and `ToolExecutionComponent.render` (exported from the pi package)
are patched on their prototypes at load, plus pi-tui's `Container.addChild`
to record a parent pointer. At render time a component looks at its chat
siblings: if any later sibling before the next user message is an activity
(a collapsed tool, or a message with thinking) it renders nothing; otherwise
it is the interaction's *anchor* and renders the consolidated line for
everything since the previous user message. Thinking Markdown children are
wrapped in a component that does the same. Durations are measured live
(thinking: first thinking delta → first non-thinking content; tools:
`tool_execution_start` → `tool_execution_end`) and persisted once per turn as
a `compact-view-timings` custom session entry (`[start, ms]` per item; TUI-only,
never sent to the model), restored on `session_start` so they survive `/reload`, restart and
`--resume`. Expanded state comes from `ctx.ui.getToolsExpanded()` at render
time. Tune the constants at the top of `index.ts`.

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
