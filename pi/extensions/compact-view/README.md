# pi-compact-view

Keeps the pi transcript short. Display-only; the session and what the model
sees are unchanged.

- **One line per run, and it is the divider.** A run is a stretch of thinking
  blocks and tool calls (across assistant messages; tool-call-only messages
  are transparent) up to the answer text. Instead of one block per call you
  get one line that doubles as the rule, with the answer hanging directly
  under it:

  ```text
   3.3s · 🧠 · 💻 6 (1✗) ls, echo, false +3 · 📖 sample.txt ─────────────

   Now some tool calls:
  ```

  Total time first (bold, the one featured number); 🧠 as just another item,
  with its own time only when ≥ 2s or ≥ 30% of the run; per tool: icon (`💻
  bash`, `📖 read`, `📄 write`, `📝 edit`, `🔍 grep`, `🔎 find`, `📁 ls`, `🌐
  web*`, `🤖 delegate*`, `❓ ask`, `🧩` other extension tools — `TOOL_ICONS`),
  bold count (dropped when it's 1 and there's a hint), failures bound to
  their tool as `(2✗)` in the error color, up to `HINTS_PER_TOOL` muted hints
  of what ran (command names, file basenames, grep patterns, hostnames,
  quoted search queries, delegate labels/ids; unknown tools show their name)
  with `+n` for the rest; a dim `─` rule fills the line. One blank line, then
  the answer. While the run is going the line updates live and ends with the
  current activity (`⏳ thinking…` / `⏳ 💻 $ npm test`). Thinking text and
  tool output are **not streamed** while collapsed. No background bars —
  bold/colored text only.

`ctrl+o` (pi's `app.tools.expand`) shows everything in full, exactly as before,
and collapses again on the next press. Thinking hide/show (`/settings` →
hide thinking) still works on top of this.

## How

pi has no hook for any of this, so `AssistantMessageComponent.updateContent`
/ `.render` and `ToolExecutionComponent.render` (exported from the pi package)
are patched on their prototypes at load, plus pi-tui's `Container.addChild`
to record a parent pointer. At render time a component looks at its chat
siblings: if the previous one continues a run (a collapsed tool, or a message
ending in thinking) it is *absorbed* and renders nothing; otherwise it *starts*
a run, walks forward over the run's members and renders the summary. Thinking
Markdown children are wrapped in a component that does the same. Durations are measured live
(thinking: first thinking delta → first non-thinking content; tools:
`tool_execution_start` → `tool_execution_end`) and persisted once per turn as
a `compact-view-timings` custom session entry (TUI-only, never sent to the
model), restored on `session_start` so they survive `/reload`, restart and
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
