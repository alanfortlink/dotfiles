/**
 * Task registry, scheduler, and persistence for `delegate`.
 *
 * The unit of work is a TASK: one agent, one prompt, one `createAgentSession`.
 * Tasks are flat and independent - there is no batch, no DAG, no parent/child
 * bookkeeping. Ordering is the parent agent's job (it spawns, waits, spawns
 * again with the previous output in the prompt).
 *
 * Concurrency is bounded per model provider by a single process-wide gate.
 * Subagents cannot delegate further: the delegate extension is filtered out of
 * their sessions, because a nested instance would share this module's registry
 * and listener state with the parent.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import {
	DefaultResourceLoader,
	SessionManager,
	createAgentSession,
	getAgentDir,
} from "@earendil-works/pi-coding-agent";
import type { Model } from "@earendil-works/pi-ai";

const CONFIG_PATH = path.join(os.homedir(), ".pi", "agent", "delegate.json");
const STATE_PATH = path.join(os.homedir(), ".pi", "agent", "delegate-state.json");
/** This extension's own directory, used to keep delegate out of subagent sessions. */
const EXT_DIR = path.dirname(fileURLToPath(import.meta.url));
/**
 * Herdr's Pi integration describes the interactive Pi process occupying a real
 * Herdr pane. Delegate tasks are headless, in-process sessions, so loading the
 * integration in them would incorrectly publish those sessions as pane agents.
 */
const HERDR_AGENT_STATE_EXT = path.join(getAgentDir(), "extensions", "herdr-agent-state.ts");

function includeInSubagent(extension: any): boolean {
	const extensionPath = path.resolve(String(extension.resolvedPath ?? extension.path ?? ""));
	// Prefix match with a separator so a sibling like "delegate-tools/" is not
	// swept up too. The Herdr exclusion is intentionally an exact file match.
	return (
		extensionPath !== EXT_DIR &&
		!extensionPath.startsWith(EXT_DIR + path.sep) &&
		extensionPath !== HERDR_AGENT_STATE_EXT
	);
}

/** Activity lines kept per task for the sidebar transcript. */
const FEED_LIMIT = 300;
/** Streaming-text tail kept per task (characters). */
const STREAM_LIMIT = 4000;
/** Settled tasks retained in memory and on disk. */
const RETENTION = 30;
/** Final output stored per task (characters). */
const OUTPUT_LIMIT = 16000;

// ---- config ----

export interface DelegateConfig {
	providerConcurrency: Record<string, number>;
	localConcurrency: number;
	defaultConcurrency: number;
	localProviders: string[];
	/**
	 * Longest a delegate_wait may block the parent turn in an interactive
	 * terminal. While the parent is inside a tool call the session is streaming,
	 * so everything the human types becomes a steering message instead of a
	 * normal turn - parking here takes the terminal away from them.
	 *
	 * Defaults to 0: hand the terminal back immediately. A grace period only pays
	 * off if a task can finish inside it, and in practice a subagent is still
	 * inside its first API call at that point - so waiting bought nothing and cost
	 * the user their prompt. The completion push is what closes the loop instead.
	 * Raise it if you would rather collect very short tasks inline.
	 */
	interactiveWaitMs: number;
	/** Open the sidebar (unfocused) automatically when tasks are spawned. Off by default: the widget is the default surface, the sidebar appears only on alt+g / /delegate. */
	autoShowSidebar: boolean;
}

const DEFAULT_CONFIG: DelegateConfig = {
	providerConcurrency: { anthropic: 2, openai: 2, google: 2 },
	localConcurrency: 8,
	defaultConcurrency: 2,
	localProviders: ["ollama", "llama", "llamacpp", "lmstudio", "kobold", "vllm"],
	interactiveWaitMs: 0,
	autoShowSidebar: false,
};

let configCache: { mtime: number; config: DelegateConfig } | null = null;

export function loadConfig(): DelegateConfig {
	try {
		const stat = fs.statSync(CONFIG_PATH);
		if (configCache && configCache.mtime === stat.mtimeMs) return configCache.config;
		const parsed = JSON.parse(fs.readFileSync(CONFIG_PATH, "utf-8")) as Partial<DelegateConfig>;
		const config: DelegateConfig = {
			providerConcurrency: { ...DEFAULT_CONFIG.providerConcurrency, ...(parsed.providerConcurrency ?? {}) },
			localConcurrency: parsed.localConcurrency ?? DEFAULT_CONFIG.localConcurrency,
			defaultConcurrency: parsed.defaultConcurrency ?? DEFAULT_CONFIG.defaultConcurrency,
			localProviders: [...DEFAULT_CONFIG.localProviders, ...(parsed.localProviders ?? [])],
			interactiveWaitMs: Math.max(0, Number(parsed.interactiveWaitMs ?? DEFAULT_CONFIG.interactiveWaitMs)) || 0,
			autoShowSidebar: parsed.autoShowSidebar ?? DEFAULT_CONFIG.autoShowSidebar,
		};
		configCache = { mtime: stat.mtimeMs, config };
		return config;
	} catch {
		return DEFAULT_CONFIG;
	}
}

/** Clamp a cap to a sane integer >= 1 (a zero/garbage config value must not deadlock the gate). */
function toCap(v: unknown): number {
	const n = Math.floor(Number(v));
	return Number.isFinite(n) && n >= 1 ? n : 1;
}

function providerCap(providerId: string, cfg: DelegateConfig): number {
	if (providerId in cfg.providerConcurrency) return toCap(cfg.providerConcurrency[providerId]);
	const lower = providerId.toLowerCase();
	if (cfg.localProviders.some((p) => lower.includes(p.toLowerCase()))) return toCap(cfg.localConcurrency);
	return toCap(cfg.defaultConcurrency);
}

// ---- per-provider gate (process-wide) ----

/**
 * Counting semaphore. A released slot is handed directly to a waiter inside the
 * same synchronous step, so an acquirer arriving between the release and the
 * waiter's resumption cannot barge in and push the count negative.
 */
class Gate {
	private available: number;
	private waiters: Array<() => void> = [];
	constructor(private cap: number) {
		this.available = cap;
	}
	get capValue(): number {
		return this.cap;
	}
	get waiting(): number {
		return this.waiters.length;
	}
	get inUse(): number {
		return this.cap - this.available;
	}
	/** Apply a live config edit. Growing the cap immediately admits queued waiters. */
	setCap(next: number): void {
		if (next === this.cap) return;
		this.available += next - this.cap;
		this.cap = next;
		this.drain();
	}
	/**
	 * Returns true with a slot held, or false if the signal aborted while
	 * queued (no slot is held then - do not release). A kill must not have to
	 * wait for a running task to finish before it takes effect.
	 */
	async acquire(signal?: AbortSignal): Promise<boolean> {
		if (signal?.aborted) return false;
		if (this.available > 0) {
			this.available--;
			return true;
		}
		return await new Promise<boolean>((resolve) => {
			const waiter = () => {
				signal?.removeEventListener("abort", onAbort);
				resolve(true);
			};
			const onAbort = () => {
				const i = this.waiters.indexOf(waiter);
				// Not found means drain() already handed us the slot; the waiter
				// callback resolves true and the caller keeps (and releases) it.
				if (i < 0) return;
				this.waiters.splice(i, 1);
				resolve(false);
			};
			this.waiters.push(waiter);
			signal?.addEventListener("abort", onAbort, { once: true });
		});
	}
	release(): void {
		this.available++;
		this.drain();
	}
	private drain(): void {
		while (this.available > 0 && this.waiters.length > 0) {
			this.available--;
			this.waiters.shift()!();
		}
	}
}

const gates = new Map<string, Gate>();

/**
 * While anything is queued, poll the config so a raised cap admits waiters
 * without needing a new spawn ("re-read live" would otherwise only be true of
 * the file, not of the gates). Stops itself once no gate has waiters.
 */
let gateRefreshTimer: ReturnType<typeof setInterval> | null = null;

function ensureGateRefresh(): void {
	if (gateRefreshTimer) return;
	gateRefreshTimer = setInterval(() => {
		const cfg = loadConfig();
		for (const [provider, gate] of gates) gate.setCap(providerCap(provider, cfg));
		if (![...gates.values()].some((g) => g.waiting > 0)) {
			clearInterval(gateRefreshTimer!);
			gateRefreshTimer = null;
		}
	}, 2000);
	(gateRefreshTimer as any).unref?.();
}

function gateFor(provider: string): Gate {
	const cap = providerCap(provider, loadConfig());
	const existing = gates.get(provider);
	if (existing) {
		existing.setCap(cap);
		return existing;
	}
	const gate = new Gate(cap);
	gates.set(provider, gate);
	return gate;
}

export function gateSnapshot(): Array<{ provider: string; inUse: number; cap: number; waiting: number }> {
	return [...gates.entries()].map(([provider, g]) => ({
		provider,
		inUse: g.inUse,
		cap: g.capValue,
		waiting: g.waiting,
	}));
}

// ---- tasks ----

export type TaskStatus = "queued" | "running" | "done" | "failed" | "killed";

export interface TaskUsage {
	input: number;
	output: number;
	cacheRead: number;
	cacheWrite: number;
	cost: number;
	turns: number;
}

/** One line of a subagent's visible activity, kept so both the sidebar and the model can see progress. */
export interface Activity {
	at: number;
	kind: "note" | "tool" | "toolResult" | "text";
	text: string;
	toolName?: string;
	isError?: boolean;
}

export interface Task {
	id: string;
	/** The pi session that spawned this task. Tasks never leak across sessions. */
	sessionId: string;
	/** Optional caller-supplied name, for display only. */
	label?: string;
	prompt: string;
	cwd: string;
	status: TaskStatus;
	provider?: string;
	model?: string;
	createdAt: number;
	startedAt?: number;
	finishedAt?: number;
	/** Completed LLM turns. */
	turns: number;
	usage: TaskUsage;
	output: string;
	errorMessage?: string;
	/** Non-fatal note (e.g. a model spec that could not be resolved). Never an error. */
	warning?: string;
	stopReason?: string;
	/** Bounded activity log (tool calls, assistant text, lifecycle) for the sidebar and delegate_status. */
	feed: Activity[];
	/** Bounded tail of the text currently streaming from the model. */
	stream: string;
	/** Steering messages accepted so far. */
	steered: string[];
	/** Resolves when the task settles. Never rejects. */
	promise: Promise<Task>;
	/** True for a record rebuilt from disk after a restart. */
	restored?: boolean;

	// internals
	session?: any;
	controller: AbortController;
	pendingSteer: string[];
}

/**
 * Everything a task is. These map 1:1 onto `createAgentSession` options plus the
 * prompt; nothing here is defaulted, rewritten, or added to. Omit a field and the
 * subagent gets whatever plain pi would give it.
 */
export interface TaskSpec {
	prompt: string;
	/** Replaces the subagent's system prompt entirely. Omit to keep pi's own. */
	systemPrompt?: string;
	/** Appended to the subagent's system prompt instead of replacing it. */
	appendSystemPrompt?: string;
	cwd?: string;
	model?: string;
	thinkingLevel?: string;
	tools?: string[];
	excludeTools?: string[];
	noTools?: "all" | "builtin";
	/** Hard stop after this many LLM turns. No limit when unset. */
	maxTurns?: number;
	/** Display name for the sidebar. Has no effect on the subagent. */
	label?: string;
}

/** Snapshot of the spawning context. Captured at spawn time so the runner never touches a turn-scoped object. */
export interface SpawnEnv {
	cwd: string;
	model: Model<any> | undefined;
	provider?: string;
	modelRegistry?: { find: (provider: string, modelId: string) => Model<any> | undefined };
	/** Owning session, stamped on the task so queries can stay session-scoped. */
	sessionId?: string;
}

const tasks = new Map<string, Task>();
let seq = 0;

/** The pi session whose tasks this extension instance owns. Empty until session_start. */
let currentSession = "";

/**
 * Bind this extension instance to a pi session. On a change, the in-memory map
 * (which holds the previous session's tasks) is dropped - those records are on
 * disk and only their own session may ever see them again. Records from other
 * sessions never surface here.
 */
export function setSession(sessionId: string): void {
	// Reset the shutdown latch even on the early return: /resume into the
	// CURRENTLY ACTIVE session runs the full shutdown (latching it) and then
	// re-enters with the identical id - leaving it latched would persist every
	// still-running task as "killed" for the rest of the session.
	shutdownMarked = false;
	if (sessionId === currentSession) return;
	currentSession = sessionId;
	tasks.clear();
	seq = 0;
}

const changeListeners = new Set<() => void>();
const settleListeners = new Set<(task: Task) => void>();

export function onChange(cb: () => void): () => void {
	changeListeners.add(cb);
	return () => changeListeners.delete(cb);
}
export function onSettle(cb: (task: Task) => void): () => void {
	settleListeners.add(cb);
	return () => settleListeners.delete(cb);
}
function emitChange(): void {
	for (const cb of changeListeners) {
		try {
			cb();
		} catch {
			/* a listener must never break a task */
		}
	}
}

/** Tasks have no names of their own, so fall back to a slice of the prompt. */
export function displayName(t: Task): string {
	// Collapse whitespace either way: a caller-supplied label may contain
	// newlines, and every consumer renders the name into a single frame row.
	const source = t.label ?? t.prompt;
	const oneLine = source.replace(/\s+/g, " ").trim();
	if (t.label) return oneLine || "(empty label)";
	return oneLine.length > 32 ? `${oneLine.slice(0, 32)}…` : oneLine || "(empty prompt)";
}

export function getTask(id: string): Task | undefined {
	const t = tasks.get(id);
	return t && t.sessionId === currentSession ? t : undefined;
}
export function listTasks(): Task[] {
	return [...tasks.values()].filter((t) => t.sessionId === currentSession).sort((a, b) => a.createdAt - b.createdAt);
}
export function isSettled(t: Task): boolean {
	return t.status === "done" || t.status === "failed" || t.status === "killed";
}
export function activeTasks(): Task[] {
	return listTasks().filter((t) => !isSettled(t));
}

function pushFeed(t: Task, kind: Activity["kind"], text: string, extra: Partial<Activity> = {}): void {
	t.feed.push({ at: Date.now(), kind, text, ...extra });
	if (t.feed.length > FEED_LIMIT) t.feed.splice(0, t.feed.length - FEED_LIMIT);
}

/** The most recent thing worth showing on one line (live text beats a finished tool call). */
export function currentActivity(t: Task): string {
	if (t.status === "running" && t.stream.trim()) {
		return t.stream.trim().replace(/\s+/g, " ").split("\n").pop() ?? "";
	}
	const last = t.feed.at(-1);
	return last ? last.text.replace(/\s+/g, " ") : "";
}

// ---- model resolution (passthrough) ----

function resolveModel(spec: string | undefined, env: SpawnEnv): { model: Model<any> | undefined; warning?: string } {
	if (!spec) return { model: env.model };
	// Split on the FIRST slash only: model ids may themselves contain slashes
	// (e.g. "openrouter/deepseek/deepseek-chat").
	const slash = spec.indexOf("/");
	const [providerId, modelId] =
		slash >= 0 ? [spec.slice(0, slash), spec.slice(slash + 1)] : [env.provider ?? env.model?.provider, spec];
	if (!providerId) {
		return { model: env.model, warning: `Could not resolve model "${spec}" (no provider); using the session model.` };
	}
	if (env.model?.provider === providerId && env.model.id === modelId) return { model: env.model };
	if (env.modelRegistry?.find) {
		const m = env.modelRegistry.find(providerId, modelId!);
		if (!m) throw new Error(`Cannot resolve model "${providerId}/${modelId}": unknown model for provider "${providerId}"`);
		return { model: m };
	}
	return {
		model: env.model,
		warning: `Could not resolve model "${providerId}/${modelId}" (no model registry available); inheriting the session model.`,
	};
}

/** Provider a task will run on, for gating and display. Never throws. */
function plannedProvider(spec: TaskSpec, env: SpawnEnv): string {
	try {
		return resolveModel(spec.model, env).model?.provider ?? "unknown";
	} catch {
		return "unknown";
	}
}

/** Fold one message's usage into a running tally. */
function addUsage(into: TaskUsage, u: any): void {
	if (!u) return;
	into.input += u.input || 0;
	into.output += u.output || 0;
	into.cacheRead += u.cacheRead || 0;
	into.cacheWrite += u.cacheWrite || 0;
	into.cost += u.cost?.total || 0;
	into.turns++;
}

/** Squash any tool result into one short line. */
function summarize(result: any): string {
	const text =
		typeof result === "string"
			? result
			: (result?.content?.find?.((c: any) => c.type === "text")?.text ?? result?.error ?? JSON.stringify(result ?? ""));
	const oneLine = String(text).replace(/\s+/g, " ").trim();
	return oneLine.length > 120 ? `${oneLine.slice(0, 120)}...` : oneLine;
}

/** One-line summary of a tool call for the activity feed. */
function briefArgs(args: any): string {
	if (!args || typeof args !== "object") return "";
	for (const key of ["command", "file_path", "path", "pattern", "query", "url", "id"]) {
		const v = args[key];
		if (typeof v === "string" && v.trim()) return v.length > 70 ? `${v.slice(0, 70)}...` : v;
	}
	return "";
}

// ---- spawn ----

export function spawn(spec: TaskSpec, env: SpawnEnv): Task {
	const id = `t${++seq}`;
	const task: Task = {
		id,
		sessionId: env.sessionId ?? currentSession,
		label: spec.label,
		prompt: spec.prompt,
		cwd: spec.cwd ?? env.cwd,
		status: "queued",
		provider: plannedProvider(spec, env),
		createdAt: Date.now(),
		turns: 0,
		usage: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, turns: 0 },
		output: "",
		feed: [],
		stream: "",
		steered: [],
		promise: Promise.resolve(null as any),
		controller: new AbortController(),
		pendingSteer: [],
	};
	tasks.set(id, task);
	task.promise = run(task, spec, env);
	emitChange();
	persistState();
	return task;
}

function settle(task: Task, status: Exclude<TaskStatus, "queued" | "running">, patch: Partial<Task> = {}): Task {
	task.status = status;
	task.finishedAt = Date.now();
	Object.assign(task, patch);
	if (task.output.length > OUTPUT_LIMIT) {
		const dropped = task.output.length - OUTPUT_LIMIT;
		task.output = `${task.output.slice(0, OUTPUT_LIMIT)}\n\n[output truncated: ${dropped} more characters were produced but not kept]`;
	}
	task.session = undefined;
	task.stream = "";
	pruneTasks();
	persistState();
	emitChange();
	for (const cb of settleListeners) {
		try {
			cb(task);
		} catch {
			/* ignore */
		}
	}
	return task;
}

async function run(task: Task, spec: TaskSpec, env: SpawnEnv): Promise<Task> {
	const signal = task.controller.signal;
	const maxTurns = spec.maxTurns;

	// Yield one microtask so a task can never settle synchronously inside
	// spawn(): a bad model spec on the first task would otherwise fire a
	// premature "all settled" push before its siblings even exist.
	await Promise.resolve();

	// Resolve the model before queueing so a bad `model` fails fast.
	let model: Model<any> | undefined;
	let modelWarning: string | undefined;
	try {
		const r = resolveModel(spec.model, env);
		model = r.model;
		modelWarning = r.warning;
	} catch (err) {
		return settle(task, "failed", { errorMessage: (err as Error).message });
	}
	task.model = model ? `${model.provider}/${model.id}` : undefined;
	task.provider = model?.provider ?? "unknown";

	const gate = gateFor(task.provider);
	if (gate.inUse >= gate.capValue) {
		pushFeed(task, "note", `queued (${task.provider} at cap ${gate.capValue})`);
		ensureGateRefresh();
	}
	emitChange();
	// A kill while queued settles immediately (no slot is held on the abort path).
	if (!(await gate.acquire(signal))) {
		return settle(task, "killed", { stopReason: "aborted", errorMessage: "killed while queued" });
	}

	// A kill may have landed between the slot grant and this resumption.
	if (signal.aborted) {
		gate.release();
		return settle(task, "killed", { stopReason: "aborted", errorMessage: "killed before starting" });
	}

	task.status = "running";
	task.startedAt = Date.now();
	pushFeed(task, "note", `started on ${task.model ?? "session model"}`);
	emitChange();

	let session: any;
	try {
		// Straight passthrough: every option comes from the caller. A field the
		// caller left out is left out here too, so the subagent falls back to
		// exactly what pi would do on its own - with two exceptions: the delegate
		// extension itself is filtered to prevent nesting, and Herdr's agent-state
		// integration is filtered because these headless, in-process sessions do
		// not occupy Herdr panes.
		const loaderOpts: any = {
			cwd: task.cwd,
			agentDir: getAgentDir(),
			extensionsOverride: (base: any) => ({
				...base,
				extensions: (base.extensions ?? []).filter(includeInSubagent),
			}),
		};
		if (spec.systemPrompt !== undefined) loaderOpts.systemPromptOverride = () => spec.systemPrompt;
		if (spec.appendSystemPrompt !== undefined) {
			loaderOpts.appendSystemPromptOverride = (base: string[]) => [...base, spec.appendSystemPrompt as string];
		}
		const resourceLoader = new DefaultResourceLoader(loaderOpts);
		try {
			await resourceLoader.reload();
		} catch {
			/* fall back to defaults */
		}
		const sessionOpts: any = {
			cwd: task.cwd,
			resourceLoader,
			sessionManager: SessionManager.inMemory(task.cwd),
		};
		if (model) sessionOpts.model = model;
		if (spec.tools) sessionOpts.tools = spec.tools;
		if (spec.excludeTools) sessionOpts.excludeTools = spec.excludeTools;
		if (spec.noTools) sessionOpts.noTools = spec.noTools;
		if (spec.thinkingLevel) sessionOpts.thinkingLevel = spec.thinkingLevel;
		session = (await createAgentSession(sessionOpts)).session;
	} catch (err) {
		gate.release();
		return settle(task, "failed", { errorMessage: `Failed to start subagent session: ${(err as Error).message}` });
	}

	task.session = session;
	// Deliver anything steered while the session was still starting.
	for (const msg of task.pendingSteer.splice(0)) {
		void session.steer(msg).catch(() => {});
		task.steered.push(msg);
		pushFeed(task, "note", `steered: ${msg}`);
	}

	// `session.abort()` only cancels an ACTIVE run - it is a no-op during
	// session startup and prompt preflight. The turn_start re-check below
	// closes that window: an abort that landed while no run was active is
	// re-applied as soon as the first run begins.
	const onAbort = () => {
		void session.abort();
	};
	signal.addEventListener("abort", onAbort, { once: true });

	// maxTurns is enforced on its own counter - never on UI state, so it cannot
	// be silently disabled by a display bug. `turn_start` is exact: the run is
	// stopped as the (maxTurns + 1)-th turn begins, and a clean finish at
	// exactly maxTurns is not misreported as an overrun.
	let startedTurns = 0;
	let hitMaxTurns = false;
	const unsubscribe = session.subscribe((event: any) => {
		switch (event.type) {
			case "turn_start": {
				startedTurns++;
				// A kill that arrived before this run was active was a no-op then;
				// apply it now that there is a run to cancel.
				if (signal.aborted) void session.abort();
				if (maxTurns && startedTurns > maxTurns && !hitMaxTurns) {
					hitMaxTurns = true;
					pushFeed(task, "note", `maxTurns (${maxTurns}) exceeded - aborting`);
					void session.abort();
				}
				break;
			}
			case "turn_end": {
				task.turns++;
				if (task.stream.trim()) pushFeed(task, "text", task.stream.trim());
				task.stream = "";
				// Accumulate as we go, so tokens and cost are visible while the task is
				// still running. Recomputed authoritatively from the messages on settle.
				addUsage(task.usage, event.message?.usage);
				emitChange();
				break;
			}
			case "tool_execution_start": {
				const brief = briefArgs(event.args);
				pushFeed(task, "tool", `${event.toolName}${brief ? ` ${brief}` : ""}`, { toolName: event.toolName });
				emitChange();
				break;
			}
			case "tool_execution_end": {
				// Only failures are worth a line of their own; successes are implied
				// by the next thing the subagent does.
				if (event.isError) {
					pushFeed(task, "toolResult", `${event.toolName} failed: ${summarize(event.result)}`, {
						toolName: event.toolName,
						isError: true,
					});
					emitChange();
				}
				break;
			}
			case "message_update": {
				if (event.assistantMessageEvent?.type === "text_delta") {
					task.stream += event.assistantMessageEvent.delta;
					if (task.stream.length > STREAM_LIMIT) task.stream = task.stream.slice(-STREAM_LIMIT);
					emitChange();
				}
				break;
			}
		}
	});

	try {
		// A kill that landed while the session was being created never had a run
		// to cancel; don't start one.
		if (signal.aborted) {
			return settle(task, "killed", { stopReason: "aborted", errorMessage: "killed before starting" });
		}
		await session.prompt(spec.prompt);

		const messages: any[] = session.messages ?? [];
		let output = "";
		let stopReason: string | undefined;
		let errorMessage: string | undefined;
		// The live tally from turn_end was an estimate; the messages are the record.
		task.usage = { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, turns: 0 };
		for (let i = messages.length - 1; i >= 0; i--) {
			const msg = messages[i];
			if (msg.role !== "assistant") continue;
			if (!stopReason && msg.stopReason) stopReason = msg.stopReason;
			if (!errorMessage && msg.errorMessage) errorMessage = msg.errorMessage;
			if (!output) {
				for (const part of msg.content ?? []) {
					if (part.type === "text" && part.text) {
						output = part.text;
						break;
					}
				}
			}
			if (msg.usage) addUsage(task.usage, msg.usage);
		}

		// The user's kill outranks the maxTurns limiter when both raced the same
		// turn boundary - a deliberate kill must never be reported as max_turns.
		if (signal.aborted) {
			return settle(task, "killed", { output, stopReason: "aborted", errorMessage: "killed by user" });
		}
		if (hitMaxTurns) {
			return settle(task, "failed", {
				output,
				stopReason: "max_turns",
				errorMessage: `Exceeded maxTurns (${maxTurns}). Partial output preserved.`,
			});
		}
		if (stopReason === "error" || stopReason === "aborted" || errorMessage) {
			return settle(task, "failed", { output, stopReason, errorMessage: errorMessage ?? output ?? "subagent error" });
		}
		return settle(task, "done", {
			output: output || "(no output)",
			stopReason,
			warning: modelWarning,
		});
	} catch (err) {
		if (signal.aborted) return settle(task, "killed", { stopReason: "aborted", errorMessage: "killed by user" });
		return settle(task, "failed", { errorMessage: `Subagent error: ${(err as Error).message}` });
	} finally {
		unsubscribe();
		signal.removeEventListener("abort", onAbort);
		try {
			// Delegate tasks are one-shot unless they are still being steered. Once
			// prompt() settles, dispose immediately: abort residual work, invalidate
			// extension contexts, detach listeners, and release session resources.
			session.dispose();
		} catch {
			/* cleanup is best-effort; the provider slot must still be released */
		}
		gate.release();
	}
}

// ---- control ----

export function killTask(id: string): boolean {
	const t = getTask(id);
	if (!t || isSettled(t)) return false;
	pushFeed(t, "note", "kill requested");
	t.controller.abort();
	emitChange();
	return true;
}

export function killAll(): number {
	let n = 0;
	for (const t of activeTasks()) if (killTask(t.id)) n++;
	return n;
}

export type SteerOutcome = "delivered" | "queued" | "settled" | "unknown";

export async function steerTask(id: string, message: string): Promise<SteerOutcome> {
	const t = getTask(id);
	if (!t) return "unknown";
	if (isSettled(t)) return "settled";
	if (!t.session || typeof t.session.steer !== "function") {
		t.pendingSteer.push(message);
		pushFeed(t, "note", `steer queued: ${message}`);
		emitChange();
		return "queued";
	}
	await t.session.steer(message);
	t.steered.push(message);
	pushFeed(t, "note", `steered: ${message}`);
	emitChange();
	return "delivered";
}

/**
 * Wait for the given tasks (default: everything still in flight) to settle,
 * up to `waitMs`. Resolves as soon as the last one finishes.
 */
export async function waitFor(ids: string[], waitMs: number, signal?: AbortSignal): Promise<Task[]> {
	const targets = ids.map((id) => getTask(id)).filter((t): t is Task => t !== undefined);
	if (targets.length === 0 || waitMs <= 0) return targets;
	const pending = targets.filter((t) => !isSettled(t));
	if (pending.length === 0) return targets;
	// An already-aborted signal never fires its abort event; without this check
	// the wait would sit out the full waitMs.
	if (signal?.aborted) return targets;

	await new Promise<void>((resolve) => {
		let finished = false;
		const timer = setTimeout(() => finish(), waitMs);
		const finish = () => {
			if (finished) return;
			finished = true;
			clearTimeout(timer);
			signal?.removeEventListener("abort", finish);
			resolve();
		};
		signal?.addEventListener("abort", finish, { once: true });
		Promise.all(pending.map((t) => t.promise)).then(finish, finish);
	});
	return targets;
}

// ---- persistence ----

interface PersistedTask {
	id: string;
	sessionId: string;
	label?: string;
	prompt: string;
	cwd: string;
	status: TaskStatus;
	provider?: string;
	model?: string;
	createdAt: number;
	finishedAt?: number;
	turns: number;
	usage: TaskUsage;
	output: string;
	errorMessage?: string;
	stopReason?: string;
}

/**
 * Ids the extension instance still needs readable (settled but not yet read
 * by the model). Without the exemption, a >RETENTION-task wave prunes the
 * oldest results before the completion push's ids can be delegate_wait'ed.
 */
let pruneExempt: (id: string) => boolean = () => false;

export function setPruneExempt(fn: (id: string) => boolean): void {
	pruneExempt = fn;
}

function pruneTasks(): void {
	const settled = listTasks().filter(isSettled);
	if (settled.length <= RETENTION) return;
	for (const t of settled.slice(0, settled.length - RETENTION)) {
		if (!pruneExempt(t.id)) tasks.delete(t.id);
	}
}

/**
 * Sticky between persistState(true) and the next setSession: a settle landing
 * in that window calls persistState() again, and without the latch it would
 * re-serialize still-in-flight siblings as `running`, clobbering the
 * killed-marking that shutdown just wrote.
 */
let shutdownMarked = false;

/**
 * Persist this session's records. With `markInFlightKilled`, anything still
 * queued/running is written as killed - used at session shutdown/switch, where
 * killAll() has fired but the async settles would land only after the session
 * (and its map) is gone, so the truth has to reach disk now.
 */
export function persistState(markInFlightKilled = false): void {
	if (markInFlightKilled) shutdownMarked = true;
	const markKilled = markInFlightKilled || shutdownMarked;
	try {
		const records: PersistedTask[] = listTasks().map((t) => {
			const lost = markKilled && !isSettled(t);
			return {
				id: t.id,
				sessionId: t.sessionId,
				label: t.label,
				prompt: t.prompt,
				cwd: t.cwd,
				status: lost ? ("killed" as TaskStatus) : t.status,
				provider: t.provider,
				model: t.model,
				createdAt: t.createdAt,
				finishedAt: t.finishedAt ?? (lost ? Date.now() : undefined),
				turns: t.turns,
				usage: t.usage,
				// Bounded for the state file; the annotation keeps the truncation honest
				// after a restart (the in-memory 16k bound does not survive one).
				// A restored output is already bounded AND annotated - truncating it
				// again would slice the note off and replace the count with a lie.
				output:
					!t.restored && t.output.length > 4096
						? `${t.output.slice(0, 4096)}\n\n[output truncated for persistence: ${t.output.length - 4096} more characters were produced but not kept]`
						: t.output,
				errorMessage: lost ? "killed: the pi session closed or switched while this task was running" : t.errorMessage,
				stopReason: lost ? "shutdown" : t.stopReason,
			};
		});
		// Merge with the shared file instead of replacing it: this session owns its
		// own records, and concurrent or past sessions own the rest. A record with
		// no sessionId is legacy - preserved untouched so it is never destroyed.
		let others: PersistedTask[] = [];
		let diskMine: PersistedTask[] = [];
		try {
			const existing = JSON.parse(fs.readFileSync(STATE_PATH, "utf-8")) as {
				version?: number;
				tasks?: PersistedTask[];
			};
			if (existing && Array.isArray(existing.tasks)) {
				others = existing.tasks.filter((r) => r.sessionId !== currentSession);
				diskMine = existing.tasks.filter((r) => r.sessionId === currentSession);
			}
		} catch {
			/* no prior state */
		}
		let mine = records;
		if (shutdownMarked) {
			// After shutdown this instance no longer owns the session's disk
			// records: a /reload has re-imported the module, and the fresh instance
			// may already have spawned or cleared records under the same session
			// id. A stale instance's late settles may UPDATE records still on disk
			// but must never re-add cleared ones or drop the fresh instance's.
			const onDisk = new Set(diskMine.map((r) => r.id));
			mine = records.filter((r) => onDisk.has(r.id));
			const updated = new Set(mine.map((r) => r.id));
			others = [...others, ...diskMine.filter((r) => !updated.has(r.id))];
		}
		const merged = [...others, ...mine];
		// Per-process tmp name: two pi processes sharing one tmp path can rename
		// each other's half-written payloads. (The read-merge-write itself is
		// still last-writer-wins for the narrow window between read and rename.)
		const tmp = `${STATE_PATH}.${process.pid}.tmp`;
		// Ids are per session (t1, t2, … restart in every session), so no file-wide counter.
		fs.writeFileSync(tmp, JSON.stringify({ version: 5, tasks: merged }), { encoding: "utf-8", mode: 0o600 });
		fs.renameSync(tmp, STATE_PATH);
	} catch {
		/* best-effort; never fail a task over persistence */
	}
}

/**
 * Drop this session's settled tasks from memory and the shared state file.
 * Tasks still in flight are kept. Returns how many were cleared.
 */
export function clearHistory(): number {
	const cleared = listTasks().filter(isSettled);
	for (const t of cleared) tasks.delete(t.id);
	persistState();
	emitChange();
	return cleared.length;
}

let restoredFor: string | null = null;

/**
 * Rebuild task records after a restart. In-memory subagent sessions cannot be
 * resumed, so anything that was in flight is restored as `killed` with a `lost`
 * stop reason - the parent is told the truth instead of waiting forever.
 *
 * Only records belonging to the current session are restored: the shared state
 * file holds every session's history, and each session sees just its own.
 * Legacy records (no sessionId) are left alone - they predate session scoping.
 *
 * The id counter continues from this session's highest persisted id, so fresh
 * tasks never reuse an id that still refers to a persisted record. Ids are
 * per session: every session starts at t1.
 */
export function restoreState(): void {
	if (!currentSession) return; // session not named yet; nothing belongs to us
	if (restoredFor === currentSession) return;
	restoredFor = currentSession;
	let parsed: { version?: number; tasks?: PersistedTask[] } | null = null;
	try {
		parsed = JSON.parse(fs.readFileSync(STATE_PATH, "utf-8"));
	} catch {
		return;
	}
	if (!parsed || !Array.isArray(parsed.tasks)) return;

	let maxId = 0;
	for (const r of parsed.tasks) {
		if (r.sessionId !== currentSession) continue;
		const lost = r.status === "queued" || r.status === "running";
		const task: Task = {
			id: r.id,
			sessionId: r.sessionId,
			label: r.label,
			prompt: r.prompt ?? "",
			cwd: r.cwd,
			status: lost ? "killed" : r.status,
			provider: r.provider,
			model: r.model,
			createdAt: r.createdAt,
			finishedAt: r.finishedAt ?? Date.now(),
			turns: r.turns ?? 0,
			usage: r.usage ?? { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, turns: 0 },
			output: r.output ?? "",
			errorMessage: lost
				? "lost: pi restarted before this task finished (subagent sessions cannot be resumed)"
				: r.errorMessage,
			stopReason: lost ? "lost" : r.stopReason,
			feed: [],
			stream: "",
			steered: [],
			promise: Promise.resolve(null as any),
			controller: new AbortController(),
			pendingSteer: [],
			restored: true,
		};
		task.promise = Promise.resolve(task);
		tasks.set(task.id, task);
		const n = Number.parseInt(r.id.replace(/^t/, ""), 10);
		if (Number.isFinite(n)) maxId = Math.max(maxId, n);
	}
	seq = Math.max(seq, maxId);
	pruneTasks();
	persistState();
	emitChange();
}
