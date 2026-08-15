/**
 * compact-view - keep the pi transcript short.
 *
 * Display-only changes, all undone by the normal tool-expansion toggle
 * (`app.tools.expand`, ctrl+o by default), which pi already propagates to
 * every chat component:
 *
 * 1. One line per *interaction* (a user prompt and everything the agent does
 *    until the next prompt). All thinking and tool calls of the interaction
 *    are consolidated into a single line, anchored at the bottom of the
 *    activity — right above the final answer:
 *
 *        1m 24s · 💻 6 (1✗) ls, echo, cat +3 · 🤖 2 audit, research · 🧠 12s ──
 *
 *    wall-clock time first, then per tool icon × count with failures bound
 *    to their tool and a short hint of what ran, then 🧠 (with its own time
 *    only when it matters), and a rule filling the rest. While the interaction is going the
 *    line updates live and a second line under it shows the current activity
 *    (`⏳ 💻 $ npm test`); it disappears when the turn ends. Interim answer
 *    text is left alone. Thinking text and tool output are not streamed at
 *    all when collapsed — only expanded.
 *
 * pi has no hook for any of this, so components are patched on their
 * prototypes: AssistantMessageComponent.updateContent / .render and
 * ToolExecutionComponent.render (post-process the rendered lines), plus
 * pi-tui Container.addChild to record a parent pointer, since a component
 * needs to look at its chat siblings to know whether it is the last activity
 * of its interaction (and so draws the line) or not (draws nothing). Session, LLM context and the expanded view are
 * untouched. Durations are measured live (thinking: first thinking delta →
 * first non-thinking content; tools: tool_execution_start →
 * tool_execution_end) and persisted per turn as a custom session entry so
 * they survive /reload, restart and resume.
 */

import { AssistantMessageComponent, type ExtensionAPI, type ExtensionUIContext, ToolExecutionComponent } from "@earendil-works/pi-coding-agent";
import { Container, Markdown, Spacer, stripTerminalSequences, Text, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ---- look ----

/** Icon for thinking in the summary line. */
const THINKING_ICON = "🧠";
/** Icon shown in front of the current activity while a run is still going. */
const RUNNING_ICON = "⏳";
/** Separator between the summary's groups. */
const GROUP_GAP = " · ";
/** Rule character that fills the summary line up to the total time. */
const RULE_CHAR = "─";
/** Max distinct hints (command names / file names) shown per tool group; 0 disables. */
const HINTS_PER_TOOL = 3;
/** Show the thinking time only when it is at least this long or this share of the run. */
const THINKING_MIN_MS = 2000;
const THINKING_MIN_SHARE = 0.3;
/** Rule color. "dim" vanished into the background on dark themes; muted stays visible across the width. */
const RULE_FG = "muted";
/**
 * Optional background for the whole run line, e.g. "toolPendingBg" or
 * "customMessageBg", to mark it as metadata rather than output. Off by
 * default: the dim foreground already says "not output", and a bar pulls the
 * eye to the least important line on screen.
 */
const RUN_BG: string | undefined = undefined;
/**
 * Icon shown for a tool in the summary, matched against the tool name in
 * order (first hit wins). Extension tools not listed get TOOL_ICON_DEFAULT.
 * Plain 2-cell emoji only (no VS16) so the terminal and pi agree on width.
 */
const TOOL_ICONS: Array<[RegExp, string]> = [
	[/^bash$/, "💻"],
	[/^read$/, "📖"],
	[/^write$/, "📄"],
	[/^edit$/, "📝"],
	[/^grep$/, "🔍"],
	[/^find$/, "🔎"],
	[/^ls$/, "📁"],
	[/^web|^fetch|_search/, "🌐"],
	[/^delegate/, "🤖"],
	[/^ask$/, "❓"],
];
const TOOL_ICON_DEFAULT = "🧩";
const toolIcon = (name: string): string => TOOL_ICONS.find(([re]) => re.test(name))?.[1] ?? TOOL_ICON_DEFAULT;

let ui: ExtensionUIContext | undefined;
/** True between agent_start and agent_end. */
let agentRunning = false;

const isExpanded = (): boolean => ui?.getToolsExpanded() ?? false;
const fg = (color: string, text: string): string => ui?.theme.fg(color as never, text) ?? text;
const bold = (text: string): string => ui?.theme.bold(text) ?? text;
const muted = (text: string): string => fg("muted", text);

function formatDuration(ms: number): string {
	if (ms < 10_000) return `${Math.max(0.1, ms / 1000).toFixed(1)}s`;
	if (ms < 60_000) return `${Math.round(ms / 1000)}s`;
	const m = Math.floor(ms / 60_000);
	return `${m}m ${Math.round((ms - m * 60_000) / 1000)}s`;
}

/** `left` then a muted rule filling to `right` (flush right), inside `pad`, truncated to width. */
/**
 * The last column is never painted. pi and the terminal can disagree by one
 * cell on an emoji's width; a line that lands one cell past the edge wraps,
 * shifts every row below it and leaves a stale copy of the line on screen.
 */
const EDGE_MARGIN = 1;

function ruleLine(width: number, pad: number, left: string, right: string): string {
	const rightWidth = visibleWidth(right);
	const inner = width - pad * 2 - EDGE_MARGIN;
	// Keep at least a short rule visible even when the left part is long.
	const minRule = 4;
	const maxLeft = Math.max(1, inner - minRule - 1 - (rightWidth ? rightWidth + 1 : 0));
	const leftText = truncateToWidth(left, maxLeft, "…");
	const ruleWidth = Math.max(minRule, inner - visibleWidth(leftText) - 1 - (rightWidth ? rightWidth + 1 : 0));
	const line = " ".repeat(pad) + leftText + " " + fg(RULE_FG, RULE_CHAR.repeat(ruleWidth)) + (rightWidth ? " " + right : "") + " ".repeat(pad);
	return RUN_BG && ui ? ui.theme.bg(RUN_BG as never, line) : line;
}

// ---- timings ----

interface Timing {
	start?: number;
	end?: number;
}
const durationOf = (t: Timing | undefined): number | undefined =>
	t?.start !== undefined && t.end !== undefined ? t.end - t.start : undefined;
/** Finished duration, or elapsed-so-far for a live timing. */
const elapsedOf = (t: Timing | undefined): number | undefined =>
	t?.start === undefined ? undefined : (t.end ?? Date.now()) - t.start;

/** Keyed by assistant message timestamp so timings survive chat rebuilds within a session. */
const thinkingTimings = new Map<number, Timing>();
/** Keyed by toolCallId. */
const toolTimings = new Map<string, Timing>();

// Durations are measured live and would be lost on /reload or restart, so finished
// ones are written to the session as custom entries (TUI-only, never sent to the
// model) and read back on session_start. One entry per turn keeps the file small.

const TIMING_ENTRY = "compact-view-timings";
/** Persisted value: `[startEpochMs, durationMs]`; older entries are a bare durationMs. */
type PersistedTiming = number | [number, number];
interface TimingEntry {
	thinking?: Record<string, PersistedTiming>; // assistant message timestamp -> timing
	tools?: Record<string, PersistedTiming>; // toolCallId -> timing
}
const persisted = (t: Timing): PersistedTiming => [t.start!, t.end! - t.start!];
const unpersist = (v: PersistedTiming): Timing => (Array.isArray(v) ? { start: v[0], end: v[0] + v[1] } : { start: 0, end: v });
let pendingEntry: TimingEntry = {};
let appendEntry: ((customType: string, data: unknown) => void) | undefined;

function flushTimings(ctx?: any): void {
	if (!pendingEntry.thinking && !pendingEntry.tools) return;
	const entry = pendingEntry;
	pendingEntry = {};
	try {
		appendEntry?.(TIMING_ENTRY, entry);
	} catch {
		// The captured `pi` is stale once the session was replaced/reloaded mid-turn
		// (pi throws on any API call then). The event ctx is always current, so
		// write straight through its session manager instead of dropping the timings.
		try {
			ctx?.sessionManager?.appendCustomEntry?.(TIMING_ENTRY, entry);
		} catch {
			// Display-only data; losing one turn of durations is fine.
		}
	}
}

function restoreTimings(entries: Iterable<any>): void {
	for (const entry of entries) {
		if (entry?.type !== "custom" || entry.customType !== TIMING_ENTRY) continue;
		const data = entry.data as TimingEntry | undefined;
		for (const [key, v] of Object.entries(data?.thinking ?? {})) thinkingTimings.set(Number(key), unpersist(v));
		for (const [key, v] of Object.entries(data?.tools ?? {})) toolTimings.set(key, unpersist(v));
	}
}

function trackThinking(message: any, isStreaming: boolean): void {
	const key: number | undefined = message?.timestamp;
	if (typeof key !== "number") return;
	const content: any[] = message.content ?? [];
	const hasThinking = content.some((c) => c.type === "thinking" && c.thinking?.trim());
	if (!hasThinking) return;
	let t = thinkingTimings.get(key);
	if (!t) {
		t = {};
		thinkingTimings.set(key, t);
	}
	if (t.start === undefined) t.start = isStreaming ? Date.now() : undefined;
	if (t.start === undefined || t.end !== undefined) return;
	const lastThinking = content.map((c) => c.type).lastIndexOf("thinking");
	const doneThinking =
		!isStreaming || content.slice(lastThinking + 1).some((c) => c.type === "toolCall" || (c.type === "text" && c.text?.trim()));
	if (doneThinking) {
		t.end = Date.now();
		(pendingEntry.thinking ??= {})[String(key)] = persisted(t);
	}
}

// ---- siblings ----
// pi-tui components don't know their parent; record it on addChild so a chat
// component can look at the siblings around it.

const PARENT = Symbol.for("compact-view.parent");

function patchContainer(): void {
	const proto = Container.prototype as any;
	const originalAddChild = (proto.__compactViewOriginalAddChild ??= proto.addChild);
	proto.addChild = function (this: any, child: any) {
		if (child && typeof child === "object" && Object.isExtensible(child)) child[PARENT] = this;
		return originalAddChild.call(this, child);
	};
}

function siblings(component: any): { list: any[]; index: number } | undefined {
	const list: any[] | undefined = component?.[PARENT]?.children;
	if (!list) return undefined;
	const index = list.indexOf(component);
	return index === -1 ? undefined : { list, index };
}

const isVisibleBlock = (c: any): boolean =>
	(c?.type === "text" && c.text?.trim()) || (c?.type === "thinking" && c.thinking?.trim());
const visibleBlocks = (message: any): any[] => (message?.content ?? []).filter(isVisibleBlock);
const hasThinking = (c: any): boolean => visibleBlocks(c?.lastMessage).some((b) => b.type === "thinking");

/** A collapsed (non-expanded, image-free) tool block — running or finished. */
function isCompactTool(c: any): boolean {
	return c instanceof ToolExecutionComponent && !(c as any).expanded && ((c as any).imageComponents?.length ?? 0) === 0 && !(c as any).hideComponent;
}
/** Something the summary accounts for: a collapsed tool, or a message with thinking. */
const isActivity = (c: any): boolean => isCompactTool(c) || (c instanceof AssistantMessageComponent && hasThinking(c));
/** Neither activity nor a boundary: answer text, empty messages, spacers, status texts, self-rendered tools. */
const isTransparent = (c: any): boolean =>
	c instanceof AssistantMessageComponent || c instanceof ToolExecutionComponent || c instanceof Spacer || c instanceof Text;
/** Starts a new interaction: user messages and everything else pi puts in the chat. */
const isBoundary = (c: any): boolean => !isActivity(c) && !isTransparent(c);

/**
 * The anchor of an interaction is its last activity — the component that draws
 * the consolidated line. Cheap: for anything but the last activity the walk
 * stops at the very next activity.
 */
function isAnchor(component: any): boolean {
	if (isExpanded()) return false;
	const s = siblings(component);
	if (!s) return true;
	for (let j = s.index + 1; j < s.list.length; j++) {
		const c = s.list[j];
		if (isActivity(c)) return false;
		if (isBoundary(c)) return true;
	}
	return true;
}

// ---- interaction summary ----

interface ToolGroup {
	count: number;
	errors: number;
	hints: string[]; // distinct, in order of first appearance
}
interface Summary {
	thinking: number; // thinking blocks seen
	thinkingMs: number;
	tools: Map<string, ToolGroup>; // icon -> group
	totalMs: number; // wall clock when every start is known, else the sum of durations
	running: boolean;
	/** Current activity while running: "thinking" or a tool title. */
	activity?: string;
	/** The agent is still working on this interaction (it's the last one and a turn is in flight). */
	live: boolean;
}

/** Total up everything from the start of `anchor`'s interaction to the anchor. */
function summarizeInteraction(anchor: any): Summary {
	const sum: Summary = { thinking: 0, thinkingMs: 0, tools: new Map(), totalMs: 0, running: false, live: false };
	const s = siblings(anchor);
	const list = s ? s.list : [anchor];
	let sumMs = 0;
	let minStart = Infinity;
	let maxEnd = -Infinity;
	let wall = true;
	const account = (t: Timing | undefined, live: boolean) => {
		const ms = live ? elapsedOf(t) : durationOf(t);
		if (ms === undefined) return;
		sumMs += ms;
		if (t?.start) {
			minStart = Math.min(minStart, t.start);
			maxEnd = Math.max(maxEnd, live ? Date.now() : t.end!);
		} else wall = false;
	};
	// Find the interaction's start, then account chronologically.
	let first = s ? s.index : 0;
	while (first > 0 && !isBoundary(list[first - 1])) first--;
	for (let i = first; i <= (s ? s.index : 0); i++) {
		const c: any = list[i];
		if (isCompactTool(c)) {
			const icon = toolIcon(String(c.toolName ?? ""));
			let group = sum.tools.get(icon);
			if (!group) sum.tools.set(icon, (group = { count: 0, errors: 0, hints: [] }));
			group.count++;
			const finished = c.result !== undefined && !c.isPartial;
			if (finished && c.result?.isError) group.errors++;
			const hint = resultHint(c) ?? toolHint(String(c.toolName ?? ""), c.args);
			if (hint && !group.hints.includes(hint)) group.hints.push(hint);
			account(toolTimings.get(c.toolCallId), !finished);
			if (!finished) {
				sum.running = true;
				sum.activity = `${icon} ${toolTitle(c)}`;
			}
		} else if (c instanceof AssistantMessageComponent && hasThinking(c)) {
			sum.thinking++;
			const t = thinkingTimings.get(c.lastMessage?.timestamp);
			const live = c.isStreaming && t?.end === undefined;
			const before = sumMs;
			account(t, live);
			sum.thinkingMs += sumMs - before;
			if (live) {
				sum.running = true;
				sum.activity = "thinking";
			}
		}
	}
	sum.totalMs = wall && minStart !== Infinity ? maxEnd - minStart : sumMs;
	// Live = a turn is running and no later interaction (boundary) exists after the anchor.
	if (agentRunning) {
		sum.live = true;
		for (let i = (s ? s.index : 0) + 1; i < list.length; i++) {
			if (isBoundary(list[i])) {
				sum.live = false;
				break;
			}
		}
	}
	return sum;
}

/**
 * Hint taken from a finished tool's result details when that beats the args:
 * delegate tools report `details.tasks[{id,name}]`, so names replace bare ids
 * (`🤖 visual-demo` instead of `🤖 t26`) and stay consistent across spawn/wait/status.
 */
function resultHint(c: any): string | undefined {
	const tasks = c.result?.details?.tasks;
	if (!String(c.toolName ?? "").startsWith("delegate") || !Array.isArray(tasks) || tasks.length === 0) return undefined;
	const names = tasks.map((t: any) => t?.name || t?.label || t?.id).filter(Boolean);
	return names.length ? names.join(", ") : undefined;
}

/** Short "what ran" hint for a call: bash → command name, file tools → basename, grep/find → pattern. */
function toolHint(name: string, args: any): string | undefined {
	if (!args || typeof args !== "object") return undefined;
	const base = (p: unknown) => (typeof p === "string" && p ? p.replace(/\/+$/, "").split("/").pop() || p : undefined);
	switch (name) {
		case "bash": {
			const cmd = typeof args.command === "string" ? args.command.trim() : "";
			// Skip env assignments and a leading `cd dir &&`; take the first word of the real command.
			const rest = cmd.replace(/^(?:cd\s+\S+\s*&&\s*)?(?:[A-Za-z_][A-Za-z0-9_]*=\S*\s+)*/, "");
			const word = rest.split(/\s+/)[0]?.replace(/^\.\//, "");
			return word || undefined;
		}
		case "read":
		case "write":
		case "edit":
		case "ls":
			return base(args.path);
		case "grep":
		case "find":
			return typeof args.pattern === "string" ? args.pattern : undefined;
		case "webfetch": {
			try {
				return new URL(String(args.url)).hostname.replace(/^www\./, "");
			} catch {
				return undefined;
			}
		}
		case "delegate":
			return Array.isArray(args.tasks) ? args.tasks.map((t: any) => t?.label ?? t?.id).filter(Boolean).join(", ") || undefined : undefined;
		case "delegate_wait":
		case "delegate_status":
			return Array.isArray(args.ids) && args.ids.length ? args.ids.join(", ") : name.replace(/^delegate_/, "");
		case "delegate_steer":
			return typeof args.id === "string" ? `steer ${args.id}` : "steer";
		default: {
			// Searches: the query, quoted and clipped. Anything else: the tool name itself.
			if (typeof args.query === "string" && args.query) {
				const q = args.query.trim();
				return `"${q.length > 24 ? q.slice(0, 23) + "…" : q}"`;
			}
			return toolIcon(name) === TOOL_ICON_DEFAULT ? name : undefined;
		}
	}
}

/** First non-blank line of pi's own tool rendering, stripped — `$ cmd`, `edit path`, ... */
function toolTitle(c: any): string {
	const original = (ToolExecutionComponent.prototype as any).__compactViewOriginalRender;
	if (!original) return String(c.toolName ?? "");
	const lines: string[] = original.call(c, 200);
	const line = lines.find((l) => stripTerminalSequences(l).trim() !== "");
	return line ? stripTerminalSequences(line).trim() : String(c.toolName ?? "");
}

function renderSummary(sum: Summary, width: number, pad: number): string[] {
	const groups: string[] = [];
	// Wall-clock time first, always — the one featured number.
	if (sum.totalMs > 0) groups.push(bold(formatDuration(sum.totalMs)));
	for (const [icon, g] of sum.tools) {
		const hints = HINTS_PER_TOOL > 0 ? g.hints : [];
		// A count of 1 next to a hint says nothing — `📖 sample.txt` is enough.
		let text = g.count === 1 && hints.length ? icon : `${icon} ${bold(String(g.count))}`;
		if (g.errors > 0) text += ` ${fg("error", `(${g.errors}✗)`)}`;
		if (hints.length) {
			const shown = hints.slice(0, HINTS_PER_TOOL).join(", ");
			const more = g.count - Math.min(hints.length, HINTS_PER_TOOL);
			text += ` ${muted(shown + (more > 0 && hints.length > HINTS_PER_TOOL ? ` +${more}` : ""))}`;
		}
		groups.push(text);
	}
	if (sum.thinking > 0) {
		// Thinking last — least actionable. Its own time only when it matters (long, or a big share).
		const show =
			sum.thinkingMs > 0 &&
			(sum.thinkingMs >= THINKING_MIN_MS || sum.thinkingMs >= THINKING_MIN_SHARE * sum.totalMs) &&
			formatDuration(sum.thinkingMs) !== formatDuration(sum.totalMs);
		groups.push(fg("accent", THINKING_ICON) + (show ? ` ${bold(formatDuration(sum.thinkingMs))}` : ""));
	}
	const lines = [ruleLine(width, pad, groups.join(muted(GROUP_GAP)), "")];
	// Second line for the whole turn: what is happening right now. Kept (as a
	// bare ⏳) between steps too, so the line count only grows while streaming —
	// pi does a full clear+redraw whenever content shrinks.
	if (sum.live) {
		const activity = sum.activity === "thinking" ? "thinking…" : sum.activity;
		const text = activity ? `${RUNNING_ICON} ${fg("warning", activity)}` : RUNNING_ICON;
		lines.push(truncateToWidth(" ".repeat(pad) + text, width - EDGE_MARGIN, "…"));
	}
	return lines;
}

// ---- thinking ----

/** Wraps a thinking Markdown component: the interaction line when its message is the anchor, else nothing. */
class ThinkingWindow {
	constructor(
		private readonly inner: Markdown,
		private readonly pad: number,
		private readonly owner: any,
	) {}

	render(width: number): string[] {
		if (isExpanded()) return this.inner.render(width);
		if (!isAnchor(this.owner)) return [];
		return renderSummary(summarizeInteraction(this.owner), width, this.pad);
	}

	invalidate(): void {
		this.inner.invalidate();
	}
}

const isBlankLine = (l: string | undefined): boolean => l !== undefined && stripTerminalSequences(l).trim() === "";

function patchAssistantMessage(): void {
	const proto = AssistantMessageComponent.prototype as any;
	// Keep the pristine methods across /reload so a re-import re-patches with the new code.
	const originalUpdateContent = (proto.__compactViewOriginalUpdateContent ??= proto.updateContent);
	proto.updateContent = function (this: any, message: any, isStreaming: boolean = this.isStreaming) {
		originalUpdateContent.call(this, message, isStreaming);
		trackThinking(message, this.isStreaming);
		const children: any[] = this.contentContainer?.children ?? [];
		for (let i = 0; i < children.length; i++) {
			const child = children[i];
			// Thinking blocks are the only Markdown children rendered with a default italic style.
			if (child instanceof Markdown && (child as any).defaultTextStyle?.italic === true) {
				children[i] = new ThinkingWindow(child, this.outputPad ?? 1, this);
			}
		}
	};

	// Lets pi's setToolsExpanded() reach us like any other expandable chat component.
	// Everything reads the live state at render time, so a re-render is all that's needed.
	proto.setExpanded ??= function (this: any, _expanded: boolean) {
		if (this.lastMessage) this.updateContent(this.lastMessage);
	};

	const originalRender = (proto.__compactViewOriginalRender ??= proto.render);
	proto.render = function (this: any, width: number): string[] {
		const lines: string[] = originalRender.call(this, width);
		if (isExpanded() || lines.length === 0) return lines;
		const blocks = visibleBlocks(this.lastMessage);
		const hasText = blocks.some((b) => b.type === "text");
		if (!hasThinking(this)) return lines;
		const anchor = isAnchor(this);
		// Thinking-only message that isn't the anchor: nothing to show at all.
		if (!anchor && !hasText) return [];
		// Its thinking rendered nothing (line is drawn elsewhere): the blank(s) above the text collapse to one.
		if (!anchor) return collapseLeadingBlanks(lines);
		return lines;
	};
}

/** Collapse leading blank lines to one, keeping their escape-only content (OSC 133 zone markers). */
function collapseLeadingBlanks(lines: string[]): string[] {
	let i = 0;
	let carry = "";
	while (i < lines.length - 1 && isBlankLine(lines[i])) carry += lines[i++];
	return i <= 1 ? lines : [carry, ...lines.slice(i)];
}

// ---- tools ----

function patchToolExecution(): void {
	const proto = ToolExecutionComponent.prototype as any;
	const originalRender = (proto.__compactViewOriginalRender ??= proto.render);
	proto.render = function (this: any, width: number): string[] {
		if (this.expanded || (this.imageComponents?.length ?? 0) > 0 || this.hideComponent) return originalRender.call(this, width);
		// Only the interaction's last activity draws the line — and pi's (possibly
		// huge) block is never rendered while collapsed.
		if (!isAnchor(this)) return [];
		const pad: number = this.contentBox?.paddingX ?? 1;
		return ["", ...renderSummary(summarizeInteraction(this), width, pad)];
	};
}

export default function (pi: ExtensionAPI): void {
	patchContainer();
	patchAssistantMessage();
	patchToolExecution();
	// Capture the UI context for theme + expansion state; hidden with -p or in RPC mode.
	appendEntry = (customType, data) => pi.appendEntry(customType, data);
	pi.on("session_start", (_event, ctx) => {
		ui = ctx.hasUI ? ctx.ui : undefined;
		restoreTimings(ctx.sessionManager.getEntries());
	});
	pi.on("tool_execution_start", (event) => {
		toolTimings.set(event.toolCallId, { start: Date.now() });
	});
	pi.on("tool_execution_end", (event) => {
		const t = toolTimings.get(event.toolCallId);
		if (!t?.start) return;
		t.end = Date.now();
		(pendingEntry.tools ??= {})[event.toolCallId] = persisted(t);
	});
	pi.on("turn_end", (_event, ctx) => flushTimings(ctx));
	pi.on("agent_start", () => {
		agentRunning = true;
	});
	pi.on("agent_end", (_event, ctx) => {
		agentRunning = false;
		flushTimings(ctx);
	});
}
