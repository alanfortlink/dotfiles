# delegate

Run a prompt in a fresh pi session with its own context window, without blocking the parent.

**Unopinionated by construction.** There are no predefined agents, no personas, no system prompts of ours, and no defaults of our own. The caller describes the subagent inline and every field is handed straight to `createAgentSession`. Anything omitted falls back to exactly what plain pi would do — except that the delegate extension itself is filtered to prevent nesting and Herdr's Pi agent-state integration is filtered because delegated sessions do not occupy terminal panes (see *Nesting* below).

```
~/.pi/agent/extensions/delegate/
├── index.ts       # the four tools, /delegate, alt+g, UI wiring
├── tasks.ts       # task registry, scheduler, provider gate, persistence
└── sidebar.ts     # the right-docked live panel
```

## Tools

### `delegate` — spawn (non-blocking)

```jsonc
{
  "tasks": [
    { "prompt": "Find every call site of parseConfig and report the file:line list.",
      "tools": ["read", "grep", "find", "ls"],
      "label": "callsites" },

    { "prompt": "Review the uncommitted diff for correctness bugs. Be specific.",
      "systemPrompt": "You are a code reviewer. You do not write code, you find defects.",
      "model": "anthropic/claude-sonnet-4-5",
      "maxTurns": 20 }
  ]
}
```

Returns task ids (`t1`, `t2`, …) immediately. Progress shows in the below-editor widget; open the sidebar with `alt+g` when you want the live transcripts.

| field | passed to | meaning |
|---|---|---|
| `prompt` | `session.prompt()` | what the subagent is asked to do (required) |
| `systemPrompt` | `systemPromptOverride` | replaces its system prompt; omit to keep pi's |
| `appendSystemPrompt` | `appendSystemPromptOverride` | appends instead of replacing |
| `cwd` | `cwd` | working directory |
| `model` | `model` | `"provider/modelId"` — split at the **first** slash, so model ids containing `/` work |
| `thinkingLevel` | `thinkingLevel` | `off … max` |
| `tools` | `tools` | allowlist |
| `excludeTools` | `excludeTools` | denylist |
| `noTools` | `noTools` | `"all"` or `"builtin"` |
| `maxTurns` | — | hard stop after N turns; no limit when omitted |
| `label` | — | display name in the sidebar only |

Top level: `cwd` as a default for every task in the call.

There is no `agent` field, no agent directory, and no scope/trust setting. If you want a reviewer, write a reviewer's prompt.

### `delegate_wait` — read results

```jsonc
{ "ids": ["t1", "t2"], "waitMs": 120000 }
```

Returns finished output immediately. A result is bounded once, at 16 000 characters, when the task settles; anything longer ends with `[output truncated: N more characters were produced but not kept]` stating exactly what was lost. (Across a restart the persisted copy is bounded at 4 096 characters, with the same style of annotation.) With no `ids`: everything still in flight, or — when nothing is in flight — the most recent settled tasks, as full results.

If you are hitting that cap often, the subagent's prompt is asking for a document rather than an answer — that is what the cap is telling you.

**In an interactive terminal it will not park.** While the root agent sits inside a tool call its session is streaming, and pi routes everything you type into the steering queue (`interactive-mode.ts`: `if (session.isStreaming) → prompt(text, { streamingBehavior: "steer" })`). So a blocking wait takes the terminal away from you. Instead:

- by default (`interactiveWaitMs: 0`) it does not wait at all — it reports what is running and returns;
- if you set a grace period, only the first wait spends it; repeats while the same work is still running return instantly, so a polling model cannot hold the terminal;
- the reply tells the agent to end its turn and stop polling.

In `print`/`json`/`rpc` mode there is nobody at the keyboard, so `waitMs` is honoured in full (up to 600 s).

If the parent turn is aborted while a wait is collecting results, those results are re-queued for the completion push instead of being silently lost.

### `delegate_status` — check progress (never blocks)

```jsonc
{ "ids": ["t1"], "activity": 5 }
```

Answers "how is it going?" without collecting results or waiting. With no `ids`, covers everything in flight plus the last few finished. `activity` is how many recent lines to show per task (default 5, `0` for none).

### `delegate_steer` — correct a running task

```jsonc
{ "id": "t1", "message": "Also cover the auth module." }
```

Lands after the subagent's current tool calls finish, before its next LLM call. Queued if the session hasn't started yet.

## The intended loop

```
you    "have something map the auth code, and something else check the session diff"
agent   delegate {...}  ->  "started t1, t2"   [turn ends]
you     ... keep talking to the agent normally, it is idle ...
        [t1, t2 settle]  ->  [delegate] 2 task(s) settled — 2/2 succeeded (t1, t2)
agent   delegate_wait {ids:["t1","t2"]}  ->  reports the findings
```

The root agent ends its turn after spawning, so it stays free and your messages start normal turns instead of piling into the steering queue.

Sequencing works the same way — when a result lands, spawn the next step with the previous output quoted in the prompt. There are no dependencies between tasks, so the parent decides what to do when a step half-fails.

## The sidebar — `alt+g` or `/delegate`

A right-docked panel that lists the **main session** plus every delegate task, with the selected one's live transcript underneath. It replaces the old modal popup: it stays visible while you keep typing in the editor, and keyboard focus moves into it only when you ask.

```
                                    ┌─ delegate 2 running · 1 finished ─┐
                                    │   ⌂ main session                  │
                                    │ ❯ ▶ t1 callsites            41s   │
                                    │   ▶ t2 reviewer             12s   │
                                    │   ✓ t3 parser               done  │
                                    ├───────────────────────────────────┤
                                    │ » t1 callsites running            │
                                    │ anthropic/claude… · 3 turns · 41s │
                                    │ → grep parseConfig                │
                                    │ ## Plan                           │
                                    │ - add the flag                    │
                                    │ Now editing the parser…           │
                                    │ ▍                                 │
                                    ├───────────────────────────────────┤
                                    │ j/k switch · s steer · x kill · … │
                                    └───────────────────────────────────┘
```

**Toggling.** `alt+g` (or `/delegate`) from the editor shows the panel and focuses it; if it is already visible, it focuses it. From inside the panel: `esc` or `enter` returns to the main session (the panel stays up, live, unfocused); `q` or `alt+g` hides it entirely. Selecting the `⌂ main session` row and pressing `enter` is the same as `esc` — you are back in your own session.

**Hidden by default.** The panel appears only when you ask (`alt+g` or `/delegate`); until then the below-editor widget is the delegate surface. Set `autoShowSidebar: true` in `delegate.json` if you want spawning tasks to open it automatically (unfocused - it never steals the keyboard).

| key (panel focused) | effect |
|---|---|
| `j`/`k`, `↑`/`↓` | switch between main and each task (transcript follows) |
| `enter` / `esc` | back to the main session; panel stays visible |
| `q` / `alt+g` | hide the panel |
| `ctrl+u`/`ctrl+d`, `pageUp`/`pageDown` | scroll the transcript |
| `gg` / `G` | transcript top / back to the live tail |
| `s` | steer the selected task |
| `x` | kill the selected task |
| `c` | clear finished tasks |

**Scrolling up pins the transcript.** It follows live output until you scroll back, at which point it holds an absolute line and incoming output extends the log below without moving what you are reading — the footer switches to `paused`. `esc` or `G` resumes following; `esc` again returns to the editor.

With `main` selected, the pane shows a session overview: task and token/cost totals plus the first line of each recent result.

Assistant prose is rendered with pi's own markdown renderer (memoized, so a redraw per streamed token doesn't re-parse the transcript). `▍` marks text still arriving. Tool calls show as `→`, failed ones as `!`; successful tool results are omitted, since what the agent does next says more than the payload.

Tasks with no `label` are named by the first 32 characters of their prompt. The panel needs a terminal at least 80 columns wide; below that it hides itself, the below-editor widget takes over, and `alt+g` says why. In a fresh session whose chat is still shorter than the screen, the panel (anchored to the viewport's top-right) can transiently overlap the prompt's right columns — it resolves itself as soon as the transcript fills the screen.

**Scoping.** The state file at `~/.pi/agent/delegate-state.json` is shared machine-wide, so every task record is tagged with the session that spawned it. The sidebar, the below-editor widget and all four tools only ever see the **current session's** tasks — other sessions' history never leaks in, even after a restart or a `/new`/`/resume` switch. `c` (or `/delegate-clear`) drops this session's finished tasks from view and from the file; running tasks are kept.

## The main screen

While tasks run and the sidebar is **hidden**, one compact block sits below the editor:

```
delegate 2 running, 1 queued  ·  alt+g for the sidebar
  ▶ t3 parser     writing…
  ▶ t4 searcher   → grep parseConfig
  · t5 reviewer   queued (anthropic at cap 2)
```

One line per task, capped at 5 with `… N more`, and deliberately terse: a subagent's prose never appears here. While the sidebar is visible the widget is suppressed — there is exactly one delegate surface at a time.

## Concurrency

One process-wide gate per provider. Config at `~/.pi/agent/delegate.json`, re-read live:

```json
{
  "providerConcurrency": { "anthropic": 2, "openai": 2, "google": 2 },
  "localConcurrency": 8,
  "defaultConcurrency": 2,
  "localProviders": ["ollama", "vllm"],
  "interactiveWaitMs": 0,
  "autoShowSidebar": false
}
```

A provider not listed in `providerConcurrency` gets `localConcurrency` if its id matches a `localProviders` entry, else `defaultConcurrency`. Tasks over the cap queue (shown as `queued`); nothing is dropped. While anything is queued, the config is polled every 2 s, so raising a cap admits queued tasks without waiting for a new spawn. Killing a queued task settles it immediately — it does not wait for a slot.

`interactiveWaitMs` is the longest a `delegate_wait` may hold an interactive turn. `0` (the default) hands the terminal back instantly, always.

## Nesting

Subagents **cannot** delegate further: the delegate extension is filtered out of their sessions. A nested delegate instance would share the parent's in-process task registry and listener state — it could read and claim the parent's tasks and push phantom `[delegate]` turns into the subagent.

Herdr's managed `herdr-agent-state.ts` extension is also filtered. A delegate task is a headless, in-process Pi session, not an agent occupying its own Herdr pane; reporting it against the parent's `HERDR_PANE_ID` would pollute Herdr's agent sidebar. Other extensions (custom providers, web tools, …) load exactly as plain Pi would.

## Lifecycle

- **Completion push** — when the last in-flight task settles, one message is delivered to the parent (`followUp`, so it lands cleanly mid-stream) naming the ids to read. Suppressed for anything the parent already collected; results a wait lost to an aborted turn are re-announced rather than dropped.
- **Shutdown** — closing pi, `/new`, `/resume`, and `/reload` all kill running subagent sessions rather than orphaning them (in-memory sessions cannot outlive the extension instance that owns them). Their killed status is written to disk before the switch, so a later `/resume` reports them as deliberately killed, not "lost".
- **Durability** — task records persist to `~/.pi/agent/delegate-state.json` (atomic tmp+rename, per-process tmp names). Ids are per session — every session starts at `t1` — and continue from the session's highest persisted id so fresh ids never collide with restored ones. Writes merge with other sessions' records instead of replacing them. Finished tasks stay readable across a restart *of the same session*; anything in flight when the process dies uncleanly is restored as `killed` / `stopReason: "lost"`. Last 30 settled tasks retained per session. Persisted outputs are bounded at 4 096 characters with an honest truncation note.
- **Failure** — an unresolvable `model` or a session that fails to start settles that task as `failed`; other tasks are unaffected. A kill takes effect wherever the task is: queued (settles instantly), starting up (the run is never started), or mid-run (the run is aborted).
- **Resource lifetime** — after a one-shot task finishes or fails, its `AgentSession` is disposed immediately. Disposal aborts residual work, invalidates extension contexts, detaches listeners, and releases session resources and the provider-concurrency slot. Interactive steering keeps a task alive only while its prompt is still running.

## Not included

- No git worktree isolation for parallel writes into one repo (relies on pi's `withFileMutationQueue`, same-process only).
- No spend cap — `maxTurns` bounds turns, not dollars.
- No stale-progress detection: a task wedged inside one API call runs until you kill it from the sidebar.
- No cross-process merge lock on the state file: two pi processes writing at the same instant are last-writer-wins for the narrow read-merge-write window (per-process tmp files prevent corruption, not lost updates).
- Leaving the panel restores focus to whatever was focused when it was first created (pi-tui's `preFocus`); if you replace the editor component afterwards (e.g. a vim-editor extension), that snapshot can go stale.
- Live progress is sidebar/widget-only, never streamed into the parent's context. That is inherent to non-blocking: the runtime stops accepting `onUpdate` once the tool call returns.
