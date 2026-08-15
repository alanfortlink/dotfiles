# delegate

Run a prompt in a fresh pi session with its own context window, without blocking the parent.

**Unopinionated by construction.** There are no predefined agents, no personas, no system prompts of ours, and no defaults of our own. The caller describes the subagent inline and every field is handed straight to `createAgentSession`. Anything omitted falls back to exactly what plain pi would do.

```
~/.pi/agent/extensions/delegate/
├── index.ts       # the four tools, /delegate, alt+g, UI wiring
├── tasks.ts       # task registry, scheduler, provider gate, persistence
└── inspector.ts   # the live overlay
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

Returns task ids (`t1`, `t2`, …) immediately.

| field | passed to | meaning |
|---|---|---|
| `prompt` | `session.prompt()` | what the subagent is asked to do (required) |
| `systemPrompt` | `systemPromptOverride` | replaces its system prompt; omit to keep pi's |
| `appendSystemPrompt` | `appendSystemPromptOverride` | appends instead of replacing |
| `cwd` | `cwd` | working directory |
| `model` | `model` | `"provider/modelId"` |
| `thinkingLevel` | `thinkingLevel` | `off … max` |
| `tools` | `tools` | allowlist |
| `excludeTools` | `excludeTools` | denylist |
| `noTools` | `noTools` | `"all"` or `"builtin"` |
| `maxTurns` | — | hard stop after N turns; no limit when omitted |
| `label` | — | display name in the inspector only |

Top level: `cwd` as a default for every task in the call.

There is no `agent` field, no agent directory, and no scope/trust setting. If you want a reviewer, write a reviewer's prompt.

### `delegate_wait` — read results

```jsonc
{ "ids": ["t1", "t2"], "waitMs": 120000 }
```

Returns finished output immediately. A result is bounded once, at 16 000 characters, when the task settles; anything longer ends with `[output truncated: N more characters were produced but not kept]` stating exactly what was lost. With no `ids`, covers everything still in flight.

If you are hitting that cap often, the subagent's prompt is asking for a document rather than an answer — that is what the cap is telling you.

**In an interactive terminal it will not park.** While the root agent sits inside a tool call its session is streaming, and pi routes everything you type into the steering queue (`interactive-mode.ts`: `if (session.isStreaming) → prompt(text, { streamingBehavior: "steer" })`). So a blocking wait takes the terminal away from you. Instead:

- by default (`interactiveWaitMs: 0`) it does not wait at all — it reports what is running and returns;
- if you set a grace period, only the first wait spends it; repeats while the same work is still running return instantly, so a polling model cannot hold the terminal;
- the reply tells the agent to end its turn and stop polling.

The default is 0 because a grace period only pays off if a task can finish inside it, and a subagent is typically still inside its first API call — so the wait bought nothing and cost you your prompt. The completion push closes the loop instead. Raise `interactiveWaitMs` if you would rather collect very short tasks inline.

In `print`/`json`/`rpc` mode there is nobody at the keyboard, so `waitMs` is honoured in full (up to 600 s).

### `delegate_status` — check progress (never blocks)

```jsonc
{ "ids": ["t1"], "activity": 5 }
```

Answers "how is it going?" without collecting results or waiting. With no `ids`, covers everything in flight plus the last few finished. `activity` is how many recent lines to show per task (default 5, `0` for none).

```
delegate: 2 running, 1 queued, 0 finished

[t1] cli-flag — running
  2 turns · 41s · ↑12480 ↓612 · $0.0231 · anthropic/claude-sonnet-4-5
  → grep parseConfig
  → edit src/cli.ts
  ! edit failed: file is read-only
  “I will add the flag, then update the README.” (still writing)

[t3] third one, queued behind the pro… — queued
  0 turns · 43s
  · queued (anthropic at cap 2)
```

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

## The inspector — `alt+g` or `/delegate`

A live overlay of **this session's** tasks. This is where a **human** steers or kills an individual subagent.

```
┌──────────────────────────────────────────────┐
│ delegate                                      │
├──────────────────────────────────────────────┤
│ ❯ ▶ t3 callsites          anthropic · 2 turns│
│      → grep parseConfig                       │
│   ✓ t2 Review the uncommitted…  · 4 turns    │
│   ⊘ t1 killed                                 │
├──────────────────────────────────────────────┤
│ ↑/↓ move · enter open · s steer · x kill · esc│
└──────────────────────────────────────────────┘
```

| key | list | transcript |
|---|---|---|
| `↑`/`↓`, `k`/`j` | move | scroll (`k` older, `j` newer) |
| `ctrl+u` / `ctrl+d` | — | half page |
| `pageup` / `pagedown` | — | full page |
| `gg` / `G` | first / last task | top / back to the live tail |
| `enter` | open the transcript | — |
| `s` | steer | steer |
| `x` | kill | kill |
| `c` | clear finished tasks | — |
| `esc`/`q` | close | release the pin, then back to the list |

**Scoping.** The state file at `~/.pi/agent/delegate-state.json` is shared machine-wide, so every task record is tagged with the session that spawned it. The inspector, the below-editor widget and all four tools only ever see the **current session's** tasks — other sessions' history never leaks in, even after a restart or a `/new`/`/resume` switch. `c` (or `/delegate-clear`) drops this session's finished tasks from view and from the file; running tasks are kept.

**Scrolling up pins the view.** The transcript follows live output until you scroll back, at which point it holds an absolute line and incoming output extends the log below without moving what you are reading — the footer switches from `live` to `paused, esc to follow`. Press `esc`, `G`, or scroll back down to the bottom to resume following; `esc` again leaves the task.

Opening a task shows what it is actually doing, updating live:

```
┌──────────────────────────────────────────────┐
│ delegate · t1 (cli-flag)                      │
├──────────────────────────────────────────────┤
│ prompt Add a --json flag to src/cli.ts        │
│ model anthropic/claude-sonnet-4-5  1 turn 8s  │
│                                               │
│ · started on anthropic/claude-sonnet-4-5      │
│ → grep parseConfig                            │
│ → edit src/cli.ts                             │
│ ! edit failed: file is read-only              │
│ ## Plan                                       │
│                                               │
│ - add the flag                                │
│ - update `README.md`                          │
│ Now editing the parser…                       │
│ ▍                                             │
└──────────────────────────────────────────────┘
```

Assistant prose is rendered with pi's own markdown renderer (memoized, so a redraw per streamed token doesn't re-parse the transcript). `▍` marks text still arriving. Tool calls show as `→`, failed ones as `!`; successful tool results are omitted, since what the agent does next says more than the payload.

Tasks with no `label` are named by the first 32 characters of their prompt.

## The main screen

While tasks run there is exactly one delegate surface, below the editor:

```
delegate 2 running, 1 queued  ·  alt+g to inspect
  ▶ t3 parser     writing…
  ▶ t4 searcher   → grep parseConfig
  · t5 reviewer   queued (anthropic at cap 2)
```

One line per task, capped at 5 with `… N more`, and deliberately terse: a subagent's
prose never appears here. A running task shows its current tool call, or `writing…`
while it is producing text — read the text itself in the inspector. Nothing is written
to the footer; the block above is the whole surface.

## Concurrency

One process-wide gate per provider, so nested delegation (a subagent that itself delegates) is braked by the same counter. This is the one place the extension imposes a limit of its own; everything else is passthrough. Config at `~/.pi/agent/delegate.json`, re-read live:

```json
{
  "providerConcurrency": { "anthropic": 2, "openai": 2, "google": 2 },
  "localConcurrency": 8,
  "defaultConcurrency": 2,
  "localProviders": ["ollama", "vllm"],
  "interactiveWaitMs": 0
}
```

A provider not listed in `providerConcurrency` gets `localConcurrency` if its id matches a `localProviders` entry, else `defaultConcurrency`. Tasks over the cap queue (shown as `queued`); nothing is dropped. Raise the numbers if you want more parallelism — set them very high to effectively disable the gate.

`interactiveWaitMs` is the longest a `delegate_wait` may hold an interactive turn. `0` (the default) hands the terminal back instantly, always.

## Lifecycle

- **Completion push** — when the last in-flight task settles, one message is delivered to the parent (`followUp`, so it lands cleanly mid-stream) naming the ids to read. Suppressed for anything the parent already collected.
- **Shutdown** — closing pi kills running subagent sessions rather than orphaning them.
- **Durability** — task records persist to `~/.pi/agent/delegate-state.json` (atomic tmp+rename). Ids are per session — every session starts at `t1` — and continue from the session's highest persisted id so fresh ids never collide with restored ones. Writes merge with other sessions' records instead of replacing them. Finished tasks stay readable across a restart *of the same session*; anything in flight is restored as `killed` / `stopReason: "lost"`, since in-memory sessions cannot be resumed. Last 30 settled tasks retained per session.
- **Failure** — an unresolvable `model` or a session that fails to start settles that task as `failed`; other tasks are unaffected.

## Not included

- No git worktree isolation for parallel writes into one repo (relies on pi's `withFileMutationQueue`, same-process only).
- No spend cap — `maxTurns` bounds turns, not dollars.
- No stale-progress detection: a task wedged inside one API call runs until you kill it from the inspector.
- Live progress is inspector/widget-only, never streamed into the parent's context. That is inherent to non-blocking: the runtime stops accepting `onUpdate` once the tool call returns.
