/**
 * `delegate` - run a prompt in a fresh pi session with its own context window,
 * without blocking the parent.
 *
 * Deliberately unopinionated. There are no predefined agents, no personas, no
 * injected prompts, and no defaults of our own: the caller supplies the prompt
 * and (optionally) system prompt, model, tools, and cwd, which are passed
 * straight to `createAgentSession`. Anything omitted falls back to whatever
 * plain pi would use.
 *
 * The model gets four tools: spawn tasks, check on them, read them, steer them.
 * The human gets a sidebar (`alt+g` or `/delegate`): a right-docked panel that
 * lists the main session plus every subagent, shows the selected one's live
 * transcript, and can steer or kill any of them. It stays visible while the
 * editor keeps focus, so you can watch subagents and keep typing.
 *
 * Tasks are flat and independent. Sequencing is the parent agent's job: spawn,
 * read the result, spawn the next step. There is no DAG, no batch, and no
 * parent/child bookkeeping - concurrency is bounded by one process-wide
 * per-provider gate. Subagents cannot delegate further (the delegate extension
 * is kept out of their sessions).
 */

import { getMarkdownTheme, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Container, Markdown, Spacer, Text, type OverlayHandle } from "@earendil-works/pi-tui";
import { Type } from "typebox";
import { MIN_SIDEBAR_COLS, Sidebar } from "./sidebar.ts";
import {
	activeTasks,
	clearHistory,
	displayName,
	gateSnapshot,
	getTask,
	isSettled,
	killAll,
	killTask,
	listTasks,
	loadConfig,
	onChange,
	onSettle,
	persistState,
	restoreState,
	setPruneExempt,
	setSession,
	spawn,
	steerTask,
	waitFor,
	type SpawnEnv,
	type Task,
} from "./tasks.ts";

const DEFAULT_WAIT_MS = 120_000;
const MAX_WAIT_MS = 600_000;
/**
 * Per-task output is bounded once, at storage time in tasks.ts, which appends an
 * honest count of what it dropped. Trimming again here would clip that notice off
 * and replace it with a smaller, wrong number - so this path does not re-truncate.
 */
/** Tasks listed in the below-editor widget before it collapses into "… N more". */
const WIDGET_ROWS = 5;
/** Hard cap on the hint shown next to a task in the widget. */
const HINT_WIDTH = 34;

// ---- schemas ----

const TaskSpecSchema = Type.Object({
	prompt: Type.String({ description: "The prompt sent to the subagent." }),
	systemPrompt: Type.Optional(
		Type.String({ description: "Replaces the subagent's system prompt. Omit to leave pi's own system prompt in place." }),
	),
	appendSystemPrompt: Type.Optional(
		Type.String({ description: "Appended to the subagent's system prompt instead of replacing it." }),
	),
	cwd: Type.Optional(Type.String({ description: "Working directory (default: the caller's cwd)." })),
	model: Type.Optional(Type.String({ description: 'Model as "provider/modelId" (default: the caller\'s model).' })),
	thinkingLevel: Type.Optional(StringEnum(["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const)),
	tools: Type.Optional(Type.Array(Type.String(), { description: "Allowlist of tool names. Omit for pi's defaults." })),
	excludeTools: Type.Optional(Type.Array(Type.String(), { description: "Tool names to disable." })),
	noTools: Type.Optional(
		StringEnum(["all", "builtin"] as const, { description: '"all" starts with no tools; "builtin" drops pi\'s built-ins.' }),
	),
	maxTurns: Type.Optional(
		Type.Integer({
			minimum: 1,
			description:
				'Hard stop after this many LLM turns, with stopReason "max_turns" and partial output kept. No limit when omitted. OMIT for implementation, research, review, or multi-step tasks - they routinely need 30-100+ turns and hitting this limit fails the task. Only set it for deliberately cheap, bounded lookups (e.g. 15-30 for a single-file read-and-report).',
		}),
	),
	label: Type.Optional(Type.String({ description: "Short name shown in the sidebar. No effect on the subagent." })),
});

const DelegateParams = Type.Object({
	tasks: Type.Array(TaskSpecSchema, { minItems: 1, description: "Tasks to run. They all start concurrently." }),
	cwd: Type.Optional(Type.String({ description: "Working directory for every task here (a task's own cwd wins)." })),
});

const WaitParams = Type.Object({
	ids: Type.Optional(Type.Array(Type.String(), { description: "Task ids to wait for. Default: every unfinished task." })),
	waitMs: Type.Optional(
		Type.Integer({
			minimum: 0,
			maximum: MAX_WAIT_MS,
			description: `Max ms to block (default ${DEFAULT_WAIT_MS}). Returns as soon as the tasks finish. 0 peeks without waiting.`,
		}),
	),
});

const SteerParams = Type.Object({
	id: Type.String({ description: "Task id to steer" }),
	message: Type.String({ description: "Correction or extra constraint to inject mid-run" }),
});

const StatusParams = Type.Object({
	ids: Type.Optional(Type.Array(Type.String(), { description: "Task ids to report on. Default: all in flight, plus the last few finished." })),
	activity: Type.Optional(
		Type.Integer({
			minimum: 0,
			maximum: 50,
			description: "Recent activity lines to show per task (tool calls and what it is saying). Default 5, 0 for none.",
		}),
	),
});

interface DelegateDetails {
	tasks: Array<{
		id: string;
		name: string;
		status: Task["status"];
		prompt: string;
		output: string;
		errorMessage?: string;
		stopReason?: string;
		model?: string;
		usage: Task["usage"];
	}>;
}

function toDetails(tasks: Task[]): DelegateDetails {
	return {
		tasks: tasks.map((t) => ({
			id: t.id,
			name: displayName(t),
			status: t.status,
			prompt: t.prompt,
			output: t.output,
			errorMessage: t.errorMessage,
			stopReason: t.stopReason,
			model: t.model,
			usage: t.usage,
		})),
	};
}

function truncate(s: string, max: number): string {
	return s.length <= max ? s : `${s.slice(0, max)}...`;
}

function succeeded(t: Task): boolean {
	return t.status === "done";
}

/** The block of text the parent model reads back for a finished task. */
function report(t: Task): string {
	const status = succeeded(t) ? "completed" : `${t.status}${t.stopReason ? ` (${t.stopReason})` : ""}`;
	// Already bounded (and annotated) by tasks.ts on settle.
	const body = t.output || t.errorMessage || "(no output)";
	return `### [${t.id}] ${displayName(t)} — ${status}\n\n${body}`;
}

function statusLine(t: Task): string {
	const detail =
		t.status === "running" || t.status === "queued"
			? [`${t.turns} turn${t.turns === 1 ? "" : "s"}`, elapsed(t), widgetHint(t)].filter(Boolean).join(", ")
			: (t.stopReason ?? "");
	return `  ${t.status.padEnd(7)} ${t.id} (${displayName(t)})${detail ? ` — ${detail}` : ""}`;
}

/**
 * One short hint per task for the main screen. Never the subagent's prose: what it
 * is *saying* belongs in the sidebar, not above the prompt. Tool calls are fine -
 * they say where it is without dumping output.
 */
function widgetHint(t: Task): string {
	if (t.status === "queued") {
		const note = t.feed.at(-1);
		return note?.text.startsWith("queued") ? truncate(note.text, HINT_WIDTH) : "queued";
	}
	if (t.stream.trim()) return "writing…";
	const last = t.feed.at(-1);
	if (!last) return "";
	// One widget row per task; a newline in a tool arg would break the layout.
	const text = last.text.replace(/\s+/g, " ").trim();
	switch (last.kind) {
		case "tool":
			return truncate(`→ ${text}`, HINT_WIDTH);
		case "toolResult":
			return truncate(`! ${text}`, HINT_WIDTH);
		case "text":
			return "writing…";
		default:
			return truncate(text, HINT_WIDTH);
	}
}

function elapsed(t: Task): string {
	const ms = (t.finishedAt ?? Date.now()) - (t.startedAt ?? t.createdAt);
	return ms < 1000 ? `${ms}ms` : ms < 60_000 ? `${Math.round(ms / 1000)}s` : `${Math.floor(ms / 60_000)}m${String(Math.round((ms % 60_000) / 1000)).padStart(2, "0")}s`;
}

/** A progress block for one task: where it is, what it costs, and what it is doing right now. */
function statusBlock(t: Task, activityLines: number): string {
	const bits = [`${t.turns} turn${t.turns === 1 ? "" : "s"}`, elapsed(t)];
	if (t.usage.input || t.usage.output) bits.push(`↑${t.usage.input} ↓${t.usage.output}`);
	if (t.usage.cost) bits.push(`$${t.usage.cost.toFixed(4)}`);
	if (t.model) bits.push(t.model);

	const lines = [`[${t.id}] ${displayName(t)} — ${t.status}${t.stopReason ? ` (${t.stopReason})` : ""}`, `  ${bits.join(" · ")}`];
	if (t.errorMessage) lines.push(`  error: ${truncate(t.errorMessage, 200)}`);
	if (t.warning) lines.push(`  warning: ${truncate(t.warning, 200)}`);

	if (activityLines > 0) {
		const recent = t.feed.slice(-activityLines).map((a) => {
			const prefix = a.kind === "tool" ? "→ " : a.kind === "toolResult" ? "! " : a.kind === "text" ? "“" : "· ";
			const suffix = a.kind === "text" ? "”" : "";
			return `  ${prefix}${truncate(a.text.replace(/\s+/g, " "), 160)}${suffix}`;
		});
		const live = t.status === "running" && t.stream.trim();
		if (live) recent.push(`  “${truncate(t.stream.trim().replace(/\s+/g, " "), 160)}” (still writing)`);
		if (recent.length) lines.push(...recent);
		else if (t.status === "queued") lines.push("  (queued, no activity yet)");
	}
	return lines.join("\n");
}

export default function (pi: ExtensionAPI) {
	restoreState();

	/** Session-scoped UI handle. Captured here so background tasks never touch a turn-scoped ctx. */
	let ui: any = null;
	let hasUI = false;
	let sidebar: Sidebar | null = null;
	let sidebarHandle: OverlayHandle | null = null;
	/** Set at session_shutdown so a mid-creation overlay removes itself on arrival. */
	let sidebarShutdown = false;
	/** Resize hook (pi-tui exposes no resize event; stdout does). */
	let onResize: (() => void) | null = null;
	// The overlay's visible() gate hides the panel on narrow terminals without
	// flipping isHidden(), so renderability must be checked separately - or the
	// widget stays suppressed for a panel nobody can see.
	const sidebarVisible = () => sidebarHandle !== null && !sidebarHandle.isHidden() && (sidebar?.canRender() ?? false);
	/** The session this extension instance is bound to (set on session_start). */
	let mySession = "";
	/** Tasks that settled since the last completion push. */
	const unreported: Task[] = [];
	/** Task ids the parent has already read via delegate_wait; they need no push. */
	const reported = new Set<string>();
	/** Task ids a completion push has named; kept readable until actually read. */
	const announced = new Set<string>();
	/**
	 * Task ids delegate_wait calls are blocked on right now, counted per id -
	 * pi executes tools in parallel by default, so two waits can overlap on the
	 * same id and a Set would forget the second wait when the first returns.
	 */
	const awaiting = new Map<string, number>();
	const awaitingAdd = (id: string) => awaiting.set(id, (awaiting.get(id) ?? 0) + 1);
	const awaitingRemove = (id: string) => {
		const n = awaiting.get(id) ?? 0;
		if (n <= 1) awaiting.delete(id);
		else awaiting.set(id, n - 1);
	};
	/** Consecutive delegate_wait calls that returned nothing new. Caps how long a polling loop can hold the terminal. */
	let emptyWaits = 0;

	// The widget is rebuilt from a live stream of token deltas - throttle it so a
	// chatty subagent can't drive a redraw per token.
	let widgetTimer: ReturnType<typeof setTimeout> | null = null;
	const refreshUI = () => {
		sidebar?.refresh();
		if (!ui || !hasUI || widgetTimer) return;
		widgetTimer = setTimeout(() => {
			widgetTimer = null;
			drawWidget();
		}, 100);
	};

	/**
	 * The single delegate surface in the main UI: one themed block below the
	 * editor. Deliberately terse - a task gets one line, and a subagent's prose
	 * never lands here. Open the sidebar (alt+g) to read what it is actually saying.
	 */
	const drawWidget = () => {
		if (!ui || !hasUI) return;
		const active = activeTasks();
		try {
			// The sidebar is the delegate surface while it is up; the widget only
			// covers for it when it is hidden.
			if (active.length === 0 || sidebarVisible()) {
				ui.setWidget("delegate", undefined);
				return;
			}
			ui.setWidget(
				"delegate",
				(_tui: any, theme: any) => {
					// Settled tasks leave the rows below but stay in the tally, so the
					// header accounts for everything spawned this session, not just what
					// is still moving.
					const all = listTasks();
					const count = (s: Task["status"]) => all.filter((t) => t.status === s).length;
					const tally: string[] = [theme.fg("accent", `${count("running")} running`)];
					if (count("queued")) tally.push(theme.fg("muted", `${count("queued")} queued`));
					if (count("done")) tally.push(theme.fg("success", `${count("done")} done`));
					if (count("failed")) tally.push(theme.fg("error", `${count("failed")} failed`));
					if (count("killed")) tally.push(theme.fg("muted", `${count("killed")} killed`));
					const head =
						theme.fg("toolTitle", theme.bold("delegate ")) +
						tally.join(theme.fg("dim", ", ")) +
						theme.fg("dim", "  ·  alt+g for the sidebar");

					const rows = active.slice(0, WIDGET_ROWS).map((t) => {
						const icon = t.status === "running" ? theme.fg("warning", "▶") : theme.fg("dim", "·");
						const hint = widgetHint(t);
						return (
							`  ${icon} ${theme.fg("accent", t.id)} ${theme.fg("text", truncate(displayName(t), 28))}` +
							(hint ? `  ${theme.fg("dim", hint)}` : "")
						);
					});
					if (active.length > WIDGET_ROWS) {
						rows.push(theme.fg("muted", `  … ${active.length - WIDGET_ROWS} more`));
					}
					return new Text([head, ...rows].join("\n"), 0, 0);
				},
				{ placement: "belowEditor" },
			);
		} catch {
			/* UI is best-effort */
		}
	};

	// Completion push: when the last in-flight task settles, tell the parent once.
	// `followUp` is required while the agent is streaming - without it this throws
	// and the notification is lost exactly when the parent is busy enough to need it.
	//
	// Tasks a delegate_wait is blocked on right now are NOT announced but are
	// kept in `unreported`: that wait normally reports them itself, but if its
	// turn is aborted the results never reach the model, and the next flush
	// announces them instead of losing them forever.
	const flushSettled = () => {
		if (activeTasks().length > 0) return;
		const held = unreported.filter((t) => awaiting.has(t.id));
		const settled = unreported.filter((t) => !awaiting.has(t.id) && !reported.has(t.id));
		unreported.length = 0;
		unreported.push(...held);
		if (settled.length === 0) return;
		// Announced ids stay exempt from retention pruning until read, so the
		// push never names an id delegate_wait can no longer resolve.
		for (const t of settled) announced.add(t.id);
		const ok = settled.filter(succeeded).length;
		const ids = settled.map((t) => t.id).join(", ");
		try {
			pi.sendUserMessage(
				`[delegate] ${settled.length} task(s) settled — ${ok}/${settled.length} succeeded (${ids}). ` +
					`Read them with delegate_wait({ ids: [${settled.map((t) => `"${t.id}"`).join(", ")}] }) and report back.`,
				{ deliverAs: "followUp" },
			);
		} catch {
			/* best-effort push */
		}
	};

	// Listener registration is deferred to session_start: this factory ALSO runs
	// when a subagent session loads extensions (the delegate extension is
	// filtered out of the subagent's final set only afterwards), and a factory
	// that registered listeners here would leak one pair per spawn onto the
	// shared module sets. A filtered-out instance never receives session_start,
	// so it never touches them at all.
	let unsubChange: (() => void) | null = null;
	let unsubSettle: (() => void) | null = null;

	const registerListeners = () => {
		unsubChange?.();
		unsubSettle?.();
		// Keep unread results readable: exempt from retention pruning anything
		// settled under this instance that the model has not read yet.
		setPruneExempt(
			(id) =>
				!reported.has(id) && (announced.has(id) || awaiting.has(id) || unreported.some((t) => t.id === id)),
		);
		unsubChange = onChange(refreshUI);
		unsubSettle = onSettle((task) => {
			// Ignore tasks that are not this session's (defense against any shared
			// module state reaching a foreign instance).
			if (!mySession || task.sessionId !== mySession) return;
			unreported.push(task);
			flushSettled();
		});
	};

	pi.on("session_start", async (_event, ctx) => {
		ui = ctx.ui;
		hasUI = ctx.hasUI;
		// Bind the task registry to this session so the sidebar, the widget and
		// every tool only ever see this session's own runs - never the history of
		// other sessions that share the machine-wide state file.
		mySession =
			ctx.sessionManager?.getSessionId?.() ??
			ctx.sessionManager?.getSessionFile?.() ??
			process.env.PI_SESSION_ID ??
			"";
		setSession(mySession);
		registerListeners();
		restoreState();
		refreshUI();
	});

	// Don't leave subagent sessions running behind a closing app, a /new, a
	// /resume, or a /reload: in-memory subagent sessions cannot outlive the
	// extension instance that owns them.
	pi.on("session_shutdown", async () => {
		killAll();
		// killAll only aborts; the settles land asynchronously, after this
		// session's registry is gone. Write the truth to disk now so a later
		// restore reports these as deliberately killed, not mysteriously lost.
		persistState(true);
		unsubChange?.();
		unsubSettle?.();
		unsubChange = null;
		unsubSettle = null;
		if (widgetTimer) {
			clearTimeout(widgetTimer);
			widgetTimer = null;
		}
		try {
			// Remove OUR overlay entry specifically - never pop the topmost, which
			// after a long session may belong to another extension.
			sidebarShutdown = true;
			sidebarHandle?.hide();
			sidebarHandle = null;
			sidebar = null;
			if (onResize) {
				process.stdout.removeListener("resize", onResize);
				onResize = null;
			}
			ui?.setWidget("delegate", undefined);
		} catch {
			/* going away anyway */
		}
	});

	// ---- delegate ----

	pi.registerTool({
		name: "delegate",
		label: "Delegate",
		description: [
			"Run a prompt in one or more fresh pi sessions, each with its own context window. NON-BLOCKING: returns task ids immediately.",
			"Every field is passed straight to the subagent session; anything you omit falls back to whatever this session would use.",
			"You define each subagent inline (prompt, and optionally systemPrompt, tools, model) - there are no predefined agents to pick from.",
			"After spawning, END YOUR TURN: you are notified automatically when the tasks settle, and the user stays free to talk to you meanwhile.",
			"Live progress is shown in the sidebar (alt+g or /delegate), not streamed into your context.",
		].join(" "),
		promptSnippet: "Run prompts in separate subagent sessions (non-blocking; returns task ids)",
		promptGuidelines: [
			"Use delegate when work splits into parts that benefit from their own context window (parallel investigation, a second pair of eyes, anything that would flood this context).",
			"Write the subagent's instructions yourself in `prompt` (and `systemPrompt` if it needs a different role). Restrict `tools` when a task should not be able to write.",
			"delegate does not block. After spawning, tell the user what you started and END YOUR TURN. Do not immediately call delegate_wait to sit and watch: while you are inside a tool call the user cannot talk to you normally (their messages get queued as steering). A [delegate] notification arrives on its own when the work settles, and then you read it with delegate_wait.",
			"For sequential work, spawn one step; when its result arrives, spawn the next with the previous output quoted in the prompt. There are no dependencies between tasks.",
			"Spawn everything that can run at once in a single delegate call rather than one call per task.",
		],
		parameters: DelegateParams,

		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const env: SpawnEnv = {
				cwd: ctx.cwd,
				model: ctx.model,
				provider: (ctx as any).provider,
				modelRegistry: ctx.modelRegistry as any,
			};

			emptyWaits = 0; // new work: the next wait gets its grace period back
			const spawned = params.tasks.map((spec) => spawn({ ...spec, cwd: spec.cwd ?? params.cwd }, env));

			// Surface the work as it starts: open the sidebar (without stealing
			// the keyboard) so the user watches progress without asking for it.
			if (ctx.mode === "tui" && ctx.hasUI && loadConfig().autoShowSidebar) {
				try {
					showSidebar(false);
				} catch {
					/* UI is best-effort */
				}
			}

			const caps = gateSnapshot()
				.filter((g) => g.waiting > 0)
				.map((g) => `${g.provider} ${g.inUse}/${g.cap} (+${g.waiting} queued)`);

			return {
				content: [
					{
						type: "text",
						text:
							`delegate: spawned ${spawned.length} task${spawned.length > 1 ? "s" : ""} — ${spawned.map((t) => `${t.id} (${displayName(t)})`).join(", ")}.\n` +
							(caps.length ? `Waiting on provider capacity: ${caps.join("; ")}.\n` : "") +
							`These run in the background. Tell the user what you started, then END YOUR TURN — do not call delegate_wait now. ` +
							`A [delegate] message will arrive when they settle; read the results with delegate_wait then. ` +
							`Progress is visible in the sidebar (alt+g or /delegate), not in your context.`,
					},
				],
				details: toDetails(spawned),
			};
		},

		renderCall(args, theme) {
			let text =
				theme.fg("toolTitle", theme.bold("delegate ")) +
				theme.fg("accent", `${args.tasks?.length ?? 0} task${(args.tasks?.length ?? 0) === 1 ? "" : "s"}`);
			for (const t of (args.tasks ?? []).slice(0, 6)) {
				text += `\n  ${theme.fg("accent", t.label ?? "task")} ${theme.fg("dim", truncate(t.prompt.replace(/\s+/g, " "), 60))}`;
			}
			if ((args.tasks?.length ?? 0) > 6) text += `\n  ${theme.fg("muted", `… +${args.tasks.length - 6} more`)}`;
			return new Text(text, 0, 0);
		},

		renderResult(result) {
			const t = result.content[0];
			return new Text(t?.type === "text" ? t.text : "(no output)", 0, 0);
		},
	});

	// ---- delegate_wait ----

	pi.registerTool({
		name: "delegate_wait",
		label: "Wait",
		description: [
			"Read the results of delegate tasks. Returns finished output immediately.",
			"In an interactive session it does NOT wait for unfinished work at all - it reports what is still running and hands the turn straight back, so the user keeps control of the terminal.",
			"You are notified automatically when tasks settle, so you never need to poll.",
		].join(" "),
		promptSnippet: "Read results from delegate tasks",
		promptGuidelines: [
			"Call delegate_wait when you are told tasks have settled, or when you specifically need a result before continuing.",
			"If it reports tasks are still running, END YOUR TURN. Do not call it again in a loop - a [delegate] notification will arrive when they finish, and the user cannot talk to you while you sit in a tool call.",
		],
		parameters: WaitParams,

		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			// While the parent is inside a tool call its session is streaming, and
			// pi routes everything the human types into the steering queue. So in an
			// interactive terminal, never block for long: check, report, hand back.
			// The grace period is spent once: a first call may briefly catch a
			// fast task, but a model that ignores the instruction and polls in a
			// loop gets immediate returns rather than holding the terminal hostage.
			const interactive = ctx.mode === "tui";
			const requestedWait = params.waitMs ?? DEFAULT_WAIT_MS;
			const grace = emptyWaits === 0 ? loadConfig().interactiveWaitMs : 0;
			const waitMs = interactive ? Math.min(requestedWait, grace) : requestedWait;
			// An empty ids array carries no information; treat it like an omitted one.
			const idsProvided = params.ids !== undefined && params.ids.length > 0;
			let requested = idsProvided ? params.ids! : activeTasks().map((t) => t.id);

			// A bare delegate_wait after everything settled must return the
			// results, not one-line status summaries: default to the most recent
			// settled tasks (details never reach the model, only this text does).
			if (!idsProvided && requested.length === 0) {
				requested = listTasks()
					.filter(isSettled)
					.slice(-5)
					.map((t) => t.id);
			}
			if (requested.length === 0) {
				return {
					content: [{ type: "text", text: "No delegate tasks have been spawned." }],
					details: toDetails([]),
				};
			}

			const missing = requested.filter((id) => !getTask(id));
			const known = requested.filter((id) => getTask(id));

			// Claim these ids so the completion push stays quiet about work this
			// call is about to report itself.
			for (const id of known) awaitingAdd(id);
			let tasks: Task[];
			try {
				tasks = await waitFor(known, waitMs, signal);
			} finally {
				for (const id of known) awaitingRemove(id);
			}

			const done = tasks.filter(isSettled);
			const pending = tasks.filter((t) => !isSettled(t));
			const ok = done.filter(succeeded).length;

			// If the turn was aborted while we waited, this result is discarded
			// and the model never sees these outputs: leave them unreported so
			// the completion push announces them instead of losing them forever.
			if (signal?.aborted) {
				flushSettled();
				return { content: [{ type: "text", text: "(aborted)" }], details: toDetails(tasks) };
			}

			// The parent has these results now, so suppress the completion push for them.
			// Prune only ids that are gone from BOTH the task map and `unreported` -
			// an id still held in `unreported` could be re-announced if forgotten here.
			if (reported.size > 500) {
				const held = new Set(unreported.map((t) => t.id));
				for (const id of reported) if (!getTask(id) && !held.has(id)) reported.delete(id);
			}
			for (const t of done) {
				reported.add(t.id);
				announced.delete(t.id);
			}
			emptyWaits = done.length > 0 ? 0 : emptyWaits + 1;

			const parts: string[] = [];
			if (missing.length) {
				parts.push(
					`Unknown task id(s): ${missing.join(", ")}. They never existed, aged out of the retained history, or were lost to a restart.`,
				);
			}
			if (done.length) {
				parts.push(`delegate: ${ok}/${done.length} succeeded\n\n${done.map(report).join("\n\n---\n\n")}`);
			}
			if (pending.length) {
				parts.push(
					`Still running:\n${pending.map(statusLine).join("\n")}\n\n` +
						(interactive
							? "END YOUR TURN NOW — tell the user what is still in flight and stop. Do NOT call delegate_wait again: " +
								"you will receive a [delegate] message automatically when these settle, and while you sit in a tool call " +
								"the user cannot talk to you (their messages get queued as steering instead)."
							: `Still unfinished after ${waitMs}ms. Call delegate_wait again to keep waiting.`),
				);
			}

			// Only a throw marks a tool result as failed; a returned `isError` is ignored.
			if (missing.length > 0 && done.length === 0 && pending.length === 0) {
				throw new Error(
					`Unknown task id(s): ${missing.join(", ")}. Known ids: ${listTasks().map((t) => t.id).join(", ") || "(none)"}.`,
				);
			}
			return { content: [{ type: "text", text: parts.join("\n\n") || "(nothing to report)" }], details: toDetails(tasks) };
		},

		renderCall(args, theme) {
			const ids = args.ids?.length ? args.ids.join(", ") : "all";
			return new Text(
				theme.fg("toolTitle", theme.bold("delegate_wait ")) +
					theme.fg("accent", ids) +
					theme.fg("muted", ` ${args.waitMs ?? DEFAULT_WAIT_MS}ms`),
				0,
				0,
			);
		},

		renderResult(result, { expanded }, theme) {
			const details = result.details as DelegateDetails | undefined;
			if (!details || details.tasks.length === 0) {
				const t = result.content[0];
				return new Text(t?.type === "text" ? t.text : "(no output)", 0, 0);
			}
			const ok = details.tasks.filter((t) => t.status === "done").length;
			const icon = ok === details.tasks.length ? theme.fg("success", "✓") : theme.fg("warning", "◐");
			const head = `${icon} ${theme.fg("toolTitle", theme.bold("delegate "))}${theme.fg("accent", `${ok}/${details.tasks.length}`)}`;

			if (!expanded) {
				let text = head;
				for (const t of details.tasks) {
					const ti = t.status === "done" ? theme.fg("success", "✓") : theme.fg("error", "✗");
					text += `\n  ${ti} ${theme.fg("accent", t.id)} ${theme.fg("dim", `(${t.name})`)} ${theme.fg("muted", truncate(t.output.replace(/\s+/g, " "), 80))}`;
				}
				return new Text(`${text}\n${theme.fg("muted", "(Ctrl+O to expand)")}`, 0, 0);
			}

			const container = new Container();
				container.addChild(new Text(head, 0, 0));
			for (const t of details.tasks) {
				const ti = t.status === "done" ? theme.fg("success", "✓") : theme.fg("error", "✗");
				container.addChild(new Spacer(1));
				container.addChild(
					new Text(`${theme.fg("accent", t.id)} ${theme.fg("dim", `(${t.name})`)} ${ti} ${theme.fg("muted", t.status)}`, 0, 0),
				);
				container.addChild(new Text(theme.fg("muted", "Prompt: ") + theme.fg("dim", truncate(t.prompt, 200)), 0, 0));
				if (t.output.trim()) {
					container.addChild(new Spacer(1));
					container.addChild(new Markdown(t.output.trim(), 0, 0, getMarkdownTheme()));
				}
				if (t.errorMessage) container.addChild(new Text(theme.fg("error", t.errorMessage), 0, 0));
			}
			return container;
		},
	});

	// ---- delegate_steer ----

	pi.registerTool({
		name: "delegate_steer",
		label: "Steer",
		description: [
			"Inject a message into a running subagent without cancelling it.",
			"It lands after the subagent's current tool calls finish, before its next LLM call.",
			"Only works while the task is running; settled tasks report back as such.",
		].join(" "),
		promptSnippet: "Send a mid-run correction to a running subagent",
		promptGuidelines: [
			"Use delegate_steer to correct a running task ('also cover the auth module') instead of killing and respawning it.",
		],
		parameters: SteerParams,

		async execute(_toolCallId, params) {
			const outcome = await steerTask(params.id, params.message);
			if (outcome === "unknown") {
				throw new Error(
					`Unknown task id "${params.id}". Active: ${activeTasks().map((t) => t.id).join(", ") || "(none)"}.`,
				);
			}
			const text = {
				delivered: `Steered ${params.id}.`,
				queued: `${params.id} has not started its session yet; the message is queued and will be delivered when it does.`,
				settled: `${params.id} already finished; nothing to steer. Call delegate_wait to read its result.`,
				unknown: "",
			}[outcome];
			return {
				content: [{ type: "text", text }],
				details: toDetails([getTask(params.id)].filter((t): t is Task => t !== undefined)),
			};
		},

		renderCall(args, theme) {
			return new Text(
				theme.fg("toolTitle", theme.bold("delegate_steer ")) +
					theme.fg("accent", args.id ?? "?") +
					theme.fg("dim", ` ${truncate(args.message ?? "", 60)}`),
				0,
				0,
			);
		},

		renderResult(result) {
			const t = result.content[0];
			return new Text(t?.type === "text" ? t.text : "(no output)", 0, 0);
		},
	});

	// ---- delegate_status ----

	pi.registerTool({
		name: "delegate_status",
		label: "Status",
		description: [
			"Check on running delegate tasks without waiting for them: status, turns, tokens, cost, elapsed time,",
			"and the most recent things each subagent did (tool calls) and said (streaming text).",
			"Always returns immediately. Use this to answer 'how is it going?' - use delegate_wait to read final results.",
		].join(" "),
		promptSnippet: "Check progress of running subagent tasks (never blocks)",
		promptGuidelines: [
			"Use delegate_status when the user asks how delegated work is going, or when you want to see progress without collecting results. It never blocks, so it is always safe to call.",
		],
		parameters: StatusParams,

		async execute(_toolCallId, params) {
			const activityLines = params.activity ?? 5;
			const all = listTasks();
			// An empty ids array carries no information; treat it like an omitted one.
			const idsProvided = params.ids !== undefined && params.ids.length > 0;
			const targets = idsProvided
				? params.ids!.map((id) => getTask(id)).filter((t): t is Task => t !== undefined)
				: [...activeTasks(), ...all.filter(isSettled).slice(-3)];

			const missing = idsProvided ? params.ids!.filter((id) => !getTask(id)) : [];
			if (missing.length > 0 && targets.length === 0) {
				throw new Error(`Unknown task id(s): ${missing.join(", ")}. Known ids: ${all.map((t) => t.id).join(", ") || "(none)"}.`);
			}
			if (targets.length === 0) {
				return {
					content: [
						{ type: "text", text: all.length === 0 ? "No delegate tasks have been spawned." : "No delegate tasks in flight." },
					],
					details: toDetails([]),
				};
			}

			const running = targets.filter((t) => t.status === "running").length;
			const queued = targets.filter((t) => t.status === "queued").length;
			const header = `delegate: ${running} running, ${queued} queued, ${targets.filter(isSettled).length} finished`;
			const caps = gateSnapshot()
				.filter((g) => g.waiting > 0)
				.map((g) => `${g.provider} ${g.inUse}/${g.cap} (+${g.waiting} queued)`);

			const parts = [header];
			if (caps.length) parts.push(`At provider capacity: ${caps.join("; ")}.`);
			if (missing.length) parts.push(`Unknown task id(s): ${missing.join(", ")}.`);
			parts.push(targets.map((t) => statusBlock(t, activityLines)).join("\n\n"));
			if (running + queued > 0) {
				parts.push("Still working. End your turn rather than polling — you are notified when they settle.");
			}

			return { content: [{ type: "text", text: parts.join("\n\n") }], details: toDetails(targets) };
		},

		renderCall(args, theme) {
			return new Text(
				theme.fg("toolTitle", theme.bold("delegate_status")) +
					theme.fg("accent", ` ${args.ids?.join(", ") ?? "all"}`),
				0,
				0,
			);
		},

		renderResult(result) {
			const t = result.content[0];
			return new Text(t?.type === "text" ? t.text : "(no output)", 0, 0);
		},
	});

	// ---- sidebar ----

	/**
	 * The sidebar overlay is created once per session and toggled with
	 * setHidden, so its state (selection, scroll position, markdown cache)
	 * survives hide/show. It is non-capturing: showing it never steals the
	 * keyboard - focus moves into it only via handle.focus().
	 */
	let sidebarOpening = false;

	const showSidebar = (focus: boolean): void => {
		if (!ui || !hasUI) return;
		if (sidebarHandle && sidebar) {
			sidebarHandle.setHidden(false);
			sidebar.selectFirstActive();
			if (focus) sidebarHandle.focus();
			drawWidget();
			return;
		}
		if (sidebarOpening) return;
		sidebarOpening = true;
		// The custom() promise is left pending for the life of the session on
		// purpose: its done() callback tears down the TOPMOST overlay, which
		// after a whole session may be someone else's. Shutdown removes the
		// sidebar via its own handle instead (handle.hide() splices exactly
		// this entry), and the pending promise dies with the instance.
		const custom = ui.custom(
			(tui: any, theme: any, _kb: any, _done: (v: null) => void) => {
				sidebar = new Sidebar(tui, (c: string, t: string) => theme.fg(c, t), {
					steer: async (task: Task) => {
						const message = await ui.input(`Steer ${task.id} (${displayName(task)}):`, "instruction");
						if (!message) return undefined;
						const outcome = await steerTask(task.id, message);
						return outcome === "delivered"
							? `steered ${task.id}`
							: outcome === "queued"
								? `queued for ${task.id} (not started)`
								: `${task.id}: ${outcome}`;
					},
					kill: (task: Task) => {
						killTask(task.id);
					},
					clear: () => clearHistory(),
					focusEditor: () => sidebarHandle?.unfocus(),
					hide: () => {
						sidebarHandle?.unfocus();
						sidebarHandle?.setHidden(true);
						drawWidget();
					},
				});
				return sidebar;
			},
			{
				overlay: true,
				overlayOptions: {
					anchor: "top-right",
					width: "36%",
					minWidth: 34,
					nonCapturing: true,
					// Too narrow a terminal and the panel would bury the chat.
					visible: (termWidth: number) => termWidth >= 80,
				},
				onHandle: (handle: OverlayHandle) => {
					sidebarOpening = false;
					// A shutdown can land in the microtask between custom() and the
					// overlay actually being pushed; remove it as soon as it exists.
					if (sidebarShutdown) {
						handle.hide();
						return;
					}
					sidebarHandle = handle;
					sidebar?.selectFirstActive();
					if (focus) handle.focus();
					drawWidget();
					// Narrowing under the width gate hides the panel per-frame, but
					// nothing else re-evaluates the widget handoff or releases the
					// panel's focus/restore state - without this, typing after a
					// narrow+widen cycle can silently land back in the sidebar
					// (where `x` kills tasks), and the widget stays suppressed for a
					// panel nobody can see.
					if (!onResize) {
						onResize = () => {
							if (sidebar && !sidebar.canRender()) sidebarHandle?.unfocus();
							drawWidget();
						};
						process.stdout.on("resize", onResize);
					}
				},
			},
		);
		// Never resolves in normal operation (see above); swallow factory errors.
		void Promise.resolve(custom).catch(() => {
			sidebar = null;
			sidebarHandle = null;
			sidebarOpening = false;
		});
	};

	/** Editor-side toggle: hidden -> show (focused), visible -> hide. */
	const toggleSidebar = (ctx: any): void => {
		if (ctx.mode !== "tui" || !ctx.hasUI) {
			ctx.ui.notify(
				listTasks().length ? listTasks().map(statusLine).join("\n") : "No delegate tasks have been spawned.",
				"info",
			);
			return;
		}
		// Checked directly (not via sidebar.canRender) so the FIRST press on a
		// narrow terminal explains itself instead of creating an invisible panel.
		if ((process.stdout.columns ?? MIN_SIDEBAR_COLS) < MIN_SIDEBAR_COLS) {
			ctx.ui.notify(`Terminal too narrow for the delegate sidebar (needs ${MIN_SIDEBAR_COLS} columns).`, "info");
			return;
		}
		if (sidebarVisible()) {
			sidebarHandle!.unfocus();
			sidebarHandle!.setHidden(true);
			drawWidget();
			return;
		}
		showSidebar(true);
	};

	pi.registerCommand("delegate", {
		description: "Toggle the delegate sidebar (live subagent transcripts, steer, kill)",
		handler: async (_args, ctx) => {
			toggleSidebar(ctx);
		},
	});

	pi.registerShortcut("alt+g", {
		description: "Toggle the delegate sidebar",
		handler: (ctx) => {
			toggleSidebar(ctx);
		},
	});

	pi.registerCommand("delegate-clear", {
		description: "Clear this session's finished delegate task history (running tasks are kept)",
		handler: async (_args, ctx) => {
			const n = clearHistory();
			ctx.ui.notify(n > 0 ? `Cleared ${n} finished delegate task(s).` : "No finished delegate tasks to clear.", "info");
		},
	});
}
