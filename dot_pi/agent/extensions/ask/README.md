# ask

Let the model put structured questions to you and block until you answer. Modelled on Claude Code's `AskUserQuestion`.

```
~/.pi/agent/extensions/ask/
├── index.ts    # the tool, the overlay component, renderCall/renderResult
├── test.ts     # headless harness: drives the component with raw keystrokes
└── tsconfig.json
```

pi auto-discovers `extensions/<name>/index.ts`, so nothing needs installing.

**Unopinionated by construction.** There are no question templates, no canned option sets, no personas. The model writes the questions and the options; this extension renders them, collects what you picked, and reports it back verbatim.

## The tool

One tool, `ask`. Parameters:

```jsonc
{
  "questions": [                       // 1-4, asked in order
    {
      "question": "Which authentication method should the service use?",
      "header": "Auth method",         // short chip label, truncated to 12 columns
      "multiSelect": false,            // optional, default false
      "options": [                     // 2-4 choices
        { "label": "OAuth 2.0", "description": "Delegate to an external identity provider." },
        { "label": "Session cookies", "description": "Server-side sessions, cookie carries the id." },
        { "label": "Signed JWTs", "description": "Stateless, but revocation gets awkward." }
      ]
    }
  ]
}
```

| field | meaning |
|---|---|
| `question` | the full question text, shown above the options |
| `header` | short label for the tab bar chip; collapsed to one line and truncated to 12 columns |
| `multiSelect` | `false` (default) picks exactly one; `true` picks any number |
| `options[].label` | the choice |
| `options[].description` | optional single line under the label |

**"Other" is always appended**, as the last row of every question, whether or not the model asked for it. Selecting it turns that row into a text field in place — the SDK's `Input` component, with its own cursor and standard editing keys — and whatever you type becomes the answer. The model cannot suppress it, and it should never spend an option slot on its own "something else" entry.

All model-supplied strings are whitespace-collapsed before rendering, so a newline smuggled into a label cannot split a rendered line in two.

`executionMode` is `sequential`: the dialog never has to share the terminal with another tool call.

## UI

Single-select, one question:

```
────────────────────────────────────────────────────────────────────────
 Which authentication method should the service use?

❯ ( ) 1. OAuth 2.0
      Delegate to an external identity provider.
  ( ) 2. Session cookies
      Server-side sessions, cookie carries the id.
  ( ) 3. Signed JWTs
      Stateless, but revocation gets awkward.
  ( ) 4. Other (write your own)

 ↑↓/jk move • Space select • Enter confirm & continue • 1-4 jump • Esc
 cancel
────────────────────────────────────────────────────────────────────────
```

Multi-select:

```
────────────────────────────────────────────────────────────────────────
 Which observability features should be enabled at launch?

  [x] 1. Structured logs
      JSON lines to stdout.
  [ ] 2. Metrics
      Prometheus endpoint on :9090.
❯ [x] 3. Traces
      OTLP export to the collector.
  [ ] 4. Other (write your own)

 ↑↓/jk move • Space toggle • Enter confirm • 1-4 jump • Esc cancel
────────────────────────────────────────────────────────────────────────
```

Choosing `Other` replaces that row with a text field, in place:

```
────────────────────────────────────────────────────────────────────────
 Which authentication method should the service use?

  ( ) 1. OAuth 2.0
         Delegate to an external identity provider.
  ( ) 2. Session cookies
         Server-side sessions, cookie carries the id.
  ( ) 3. Signed JWTs
         Stateless, but revocation gets awkward.
❯ ( ) 4. > mTLS between services

 Type your answer • Enter submit • Esc back to the options
────────────────────────────────────────────────────────────────────────
```

More than one question adds a tab bar, and a `✓ Submit` tab at the end. `□` is unanswered, `■` answered:

```
────────────────────────────────────────────────────────────────────────
  ■ Auth method   □ Rollout t...   ✓ Submit

 Where should the rollout land first?

❯ [ ] 1. Staging only
  [ ] 2. Internal users
      Employees, behind a flag.
  [ ] 3. 10% of production
  [ ] 4. Other (write your own)

 ↑↓/jk move • Tab/←→ question • Space toggle • Enter confirm • 1-4 jump
 • Esc cancel
────────────────────────────────────────────────────────────────────────
```

## Keys

In the option list:

| key | effect |
|---|---|
| `↑` / `k` | move the cursor up, wrapping to the bottom |
| `↓` / `j` | move the cursor down, wrapping to the top |
| `1`…`9` | jump to that row and act on it: like `Enter` in single-select, like `Space` in multi-select |
| `Space` (single-select) | select the row under the cursor and stay on the question |
| `Enter` (single-select) | select the row under the cursor and move on |
| `Space` (multi-select) | toggle the row under the cursor |
| `Enter` (multi-select) | confirm the checked set and move on |
| `Space` on the `Other` row | turn that row into a text field (or clear it when it already holds text) |
| `Enter` on the `Other` row | confirm the stored free text and move on (with a hint if nothing was written) |
| `Space` on a filled `Other` row | clear the free text again |
| `Tab` / `→` | next question (or the Submit tab); only with more than one question |
| `Shift+Tab` / `←` | previous question |
| `Esc` | cancel the whole dialog |

In the `Other` text field (a pi `Input`, so the usual line-editing keys work — word motion, kill/yank, undo):

| key | effect |
|---|---|
| any character | typed into the field, including `Space` and digits |
| `Enter` | submit the text and confirm the question, moving on |
| `Esc` | discard the draft, restore whatever was stored, and go back to the options |

On the Submit tab:

| key | effect |
|---|---|
| `Enter` | submit, if every question is answered; otherwise it names what is still open |
| `Tab` / `Shift+Tab` / `←→` | go back to a question |
| `Esc` | cancel |

## Behaviour worth knowing

- **`Space` never leaves the question, `Enter` does.** In single-select, `Space` sets the choice and keeps you on the options so you can change your mind or read the descriptions; `Enter` sets it and moves on. Digit keys behave like `Enter` in single-select and like `Space` in multi-select. **`Enter` never opens the `Other` text field — only `Space` does.** `Space` on `Other` opens the field (or clears it when it already holds text); `Enter` on `Other` confirms the stored free text and moves on, and shows a hint when nothing was written yet. Inside the field, `Enter` records the text and confirms the question in one step, exactly like `Enter` anywhere else in the dialog.
- **One question submits immediately.** Choosing with `Enter` (single-select) or confirming (multi-select) ends the dialog; there is no Submit tab.
- **Several questions advance automatically.** Answering one jumps to the next unanswered question, or to Submit when that was the last one. You can also move around freely with Tab.
- **A selection is not an answer until `Enter`.** Toggling boxes or `Space`-selecting does not answer the question — `Enter` does. Tabbing away without confirming keeps your checkboxes but leaves the question marked `□`, and the Submit tab will say so.
- **Multi-select requires at least one selection.** `Enter` with nothing checked shows *"Pick at least one option, or choose Other and write your own answer"* and does not advance. There is deliberately no "none of these" button: if none of the options fit, that is a real answer with a reason, so write it into `Other`.
- **Free text in multi-select is added alongside the checked options,** not instead of them. In single-select it replaces the selection.
- **`Esc` in the option list cancels everything**, including questions already answered. The model is told plainly:

  > User cancelled - no questions were answered. Do not ask again about this. Choose the most reasonable option yourself, say which assumption you made, and continue.

- **Aborting the agent** (ctrl+c, `/abort`) closes the dialog and reads as a cancel — the tool honours the abort signal it is given rather than leaving a dead overlay on screen.
- **No UI, no question.** In `print`, `json` and `rpc` modes there is nobody to answer, so `ask` throws (which pi reports to the model as a tool error) rather than returning an empty answer.

## What the model reads back

```
User answered:

1. [Auth method] Which authentication method should the service use?
   chose: 2. Session cookies

2. [Telemetry] Which observability features should be enabled at launch? (multi-select)
   chose: 1. Structured logs | free text: "profiling endpoint"
```

Every question is echoed with its header, the exact option index and label chosen, and free text explicitly marked. `details` carries the same thing structurally:

```jsonc
{
  "cancelled": false,
  "answers": [
    {
      "header": "Auth method",
      "question": "Which authentication method should the service use?",
      "multiSelect": false,
      "choices": [{ "label": "Session cookies", "index": 2, "custom": false }]
    }
  ]
}
```

`index` is the 1-based position in the rendered list, and `null` for free text (`custom: true`).

In the transcript the call renders as `ask 2 questions (Auth method, Telemetry)` and the result as one `✓ header: choice` line per question, with `(wrote)` marking free text.

## Tests

```
node test.ts
```

pi loads extensions with jiti, so the harness loads `index.ts` with the same loader, hands it a stub `ExtensionAPI` to capture the tool, stubs `ctx.ui.custom` to hand back the live component, then feeds raw key sequences into `handleInput()` and asserts on `render(width)`. No model, no terminal.

It covers single-select picking with `Enter` and with `Space` (which must not submit), `j`/`k` and digit shortcuts, the inline `Other` field (typed spaces, focus marker, discarded drafts), wrap-around navigation, multi-select toggling on and off, the empty-confirm refusal, `Other` in both modes (`Space` opens the editor, `Enter` never does), `Esc` inside the field vs in the list, tab-bar navigation and the Submit tab, the abort signal, non-interactive modes, and hostile input (newlines and 200-character labels). Every state is re-rendered at widths 20/34/60/72/120 and checked for lines that exceed the width or contain a newline.

Typecheck against the real SDK types:

```
npx -p typescript@5.7 tsc -p tsconfig.json --noUnusedLocals --noUnusedParameters
```

`tsconfig.json` points `@earendil-works/*` and `typebox` at the globally installed pi, so this is checked against the same `.d.ts` files pi itself ships.
