/**
 * compact-view - keep the pi transcript short.
 *
 * Display-only changes, all undone by the normal tool-expansion toggle
 * (`app.tools.expand`, ctrl+o by default), which pi already propagates to
 * every chat component:
 *
 * 1. A *run* — consecutive thinking blocks and tool calls, across assistant
 *    messages, up to the answer text — is drawn as ONE line that doubles as
 *    the divider before the answer:
 *
 *        3.7s · 🧠 · 💻 5 (2✗) ls, echo, cat +2 · 📖 sample.txt ─────────
 *
 *    total time first, then 🧠 (with its own time only when it matters),
 *    tool icon × count with failures bound to their tool and a short hint of
 *    what ran, and a rule filling the rest. While the run is going the line updates
 *    live and shows the current activity (`⏳ 💻 $ npm test`). Thinking text
 *    and tool output are not streamed at all when collapsed — only expanded.
 *
 * pi has no hook for any of this, so components are patched on their
 * prototypes: AssistantMessageComponent.updateContent / .render and
 * ToolExecutionComponent.render (post-process the rendered lines), plus
 * pi-tui Container.addChild to record a parent pointer, since a component
 * needs to look at its chat siblings to know whether it starts a run or is
 * absorbed into one. Session, LLM context and the expanded view are
 * untouched. Durations are measured live (thinking: first thinking delta →
 * first non-thinking content; tools: tool_execution_start →
 * tool_execution_end) and persisted per turn as a custom session entry so
 * they survive /reload, restart and resume.
 */

import { AssistantMessageComponent, type ExtensionAPI, type ExtensionUIContext, ToolExecutionComponent } from "@earendil-works/pi-coding-agent";
import { Container, Markdown, stripTerminalSequences, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

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
/** Rule color, one step dimmer than the muted hints (chrome vs content). */
const RULE_FG = "dim";
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
function ruleLine(width: number, pad: number, left: string, right: string): string {
	const rightWidth = visibleWidth(right);
	const inner = width - pad * 2;
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
interface TimingEntry {
	thinking?: Record<string, number>; // assistant message timestamp -> ms
	tools?: Record<string, number>; // toolCallId -> ms
}
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
		for (const [key, ms] of Object.entries(data?.thinking ?? {})) {
			thinkingTimings.set(Number(key), { start: 0, end: ms });
		}
		for (const [key, ms] of Object.entries(data?.tools ?? {})) {
			toolTimings.set(key, { start: 0, end: ms });
		}
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
		(pendingEntry.thinking ??= {})[String(key)] = t.end - t.start;
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

/** A collapsed (non-expanded, image-free) tool block — running or finished. */
function isCompactTool(c: any): boolean {
	return c instanceof ToolExecutionComponent && !(c as any).expanded && ((c as any).imageComponents?.length ?? 0) === 0 && !(c as any).hideComponent;
}
/** An assistant message that starts with thinking (its thinking belongs to a run). */
function startsWithThinking(c: any): boolean {
	return c instanceof AssistantMessageComponent && visibleBlocks((c as any).lastMessage)[0]?.type === "thinking";
}
/** An assistant message whose last visible block is thinking — the run continues after it. */
function endsWithThinking(c: any): boolean {
	if (!(c instanceof AssistantMessageComponent)) return false;
	const blocks = visibleBlocks((c as any).lastMessage);
	return blocks.length > 0 && blocks[blocks.length - 1].type === "thinking";
}
/** An assistant message with nothing visible (tool calls only, or still empty) — invisible to the run logic. */
const isTransparent = (c: any): boolean => c instanceof AssistantMessageComponent && visibleBlocks((c as any).lastMessage).length === 0;
/** Does the run continue *past* this component (so the next sibling is absorbed)? */
const continuesRun = (c: any): boolean => isCompactTool(c) || endsWithThinking(c);

/** True when `component`'s run part is absorbed into a summary drawn by an earlier sibling. */
function absorbedInRun(component: any): boolean {
	if (isExpanded()) return false;
	const s = siblings(component);
	if (!s) return false;
	let i = s.index - 1;
	while (i >= 0 && isTransparent(s.list[i])) i--;
	return i >= 0 && continuesRun(s.list[i]);
}

// ---- run summary ----

interface ToolGroup {
	count: number;
	errors: number;
	hints: string[]; // distinct, in order of first appearance
}
interface RunSummary {
	thinking: number; // thinking blocks seen
	thinkingMs: number;
	tools: Map<string, ToolGroup>; // icon -> group
	totalMs: number;
	running: boolean;
	/** Current activity while running: "thinking" or a tool title. */
	activity?: string;
}

/** Walk the chat from `start` over the run it begins and total it up. */
function summarizeRun(start: any): RunSummary {
	const sum: RunSummary = { thinking: 0, thinkingMs: 0, tools: new Map(), totalMs: 0, running: false };
	const s = siblings(start);
	const list = s ? s.list : [start];
	let i = s ? s.index : 0;
	for (; i < list.length; i++) {
		const c: any = list[i];
		if (isCompactTool(c)) {
			const icon = toolIcon(String(c.toolName ?? ""));
			let group = sum.tools.get(icon);
			if (!group) sum.tools.set(icon, (group = { count: 0, errors: 0, hints: [] }));
			group.count++;
			const finished = c.result !== undefined && !c.isPartial;
			if (finished && c.result?.isError) group.errors++;
			const hint = toolHint(String(c.toolName ?? ""), c.args);
			if (hint && !group.hints.includes(hint)) group.hints.push(hint);
			const t = toolTimings.get(c.toolCallId);
			const ms = finished ? durationOf(t) : elapsedOf(t);
			if (ms !== undefined) sum.totalMs += ms;
			if (!finished) {
				sum.running = true;
				sum.activity ??= `${icon} ${toolTitle(c)}`;
			}
			continue;
		}
		if (isTransparent(c)) continue;
		if (c instanceof AssistantMessageComponent && startsWithThinking(c)) {
			sum.thinking++;
			const t = thinkingTimings.get(c.lastMessage?.timestamp);
			const ms = c.isStreaming ? elapsedOf(t) : durationOf(t);
			if (ms !== undefined) {
				sum.thinkingMs += ms;
				sum.totalMs += ms;
			}
			if (c.isStreaming && t?.end === undefined) {
				sum.running = true;
				sum.activity ??= "thinking";
			}
			if (!endsWithThinking(c)) break; // its text ends the run
			continue;
		}
		break;
	}
	return sum;
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

function renderRunSummary(sum: RunSummary, width: number, pad: number): string {
	const groups: string[] = [];
	// Total time first, always — the one featured number.
	if (sum.totalMs > 0) groups.push(bold(formatDuration(sum.totalMs)));
	if (sum.thinking > 0) {
		// Thinking is just another item; its own time only when it matters (long, or a big share of the run).
		const show = sum.thinkingMs > 0 && (sum.thinkingMs >= THINKING_MIN_MS || sum.thinkingMs >= THINKING_MIN_SHARE * sum.totalMs);
		groups.push(fg("accent", THINKING_ICON) + (show ? ` ${muted(formatDuration(sum.thinkingMs))}` : ""));
	}
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
	if (sum.running && sum.activity) {
		groups.push(`${RUNNING_ICON} ${fg("warning", sum.activity === "thinking" ? "thinking…" : sum.activity)}`);
	}
	return ruleLine(width, pad, groups.join(muted(GROUP_GAP)), "");
}

// ---- thinking ----

/** Wraps a thinking Markdown component: run summary (or nothing, when absorbed) while collapsed. */
class ThinkingWindow {
	constructor(
		private readonly inner: Markdown,
		private readonly pad: number,
		private readonly owner: any,
	) {}

	render(width: number): string[] {
		if (isExpanded()) return this.inner.render(width);
		if (absorbedInRun(this.owner)) return [];
		return [renderRunSummary(summarizeRun(this.owner), width, this.pad)];
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
		const first = blocks[0]?.type;
		const hasText = blocks.some((b) => b.type === "text");
		const absorbed = absorbedInRun(this);
		// Thinking-only message absorbed into an earlier summary: draw nothing at all.
		if (absorbed && first === "thinking" && !hasText) return [];
		// After a run line, keep exactly one blank line above the answer text.
		// Absorbed message (its thinking is on the earlier line, or text-only): the blank(s) above collapse to one.
		if (absorbed && (first === "thinking" || first === "text")) return collapseLeadingBlanks(lines);
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
		// Absorbed into the summary an earlier sibling draws — and no need to render
		// pi's (possibly huge) block at all while collapsed.
		if (absorbedInRun(this)) return [];
		const pad: number = this.contentBox?.paddingX ?? 1;
		// This tool starts a run: pi's blank line above, then one summary line.
		return ["", renderRunSummary(summarizeRun(this), width, pad)];
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
		(pendingEntry.tools ??= {})[event.toolCallId] = t.end - t.start;
	});
	pi.on("turn_end", (_event, ctx) => flushTimings(ctx));
	pi.on("agent_end", (_event, ctx) => flushTimings(ctx));
}
