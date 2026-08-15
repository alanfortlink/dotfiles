/**
 * compact-view - keep the pi transcript short.
 *
 * Display-only changes, all undone by the normal tool-expansion toggle
 * (`app.tools.expand`, ctrl+o by default), which pi already propagates to
 * every chat component:
 *
 * 1. A *run* — consecutive thinking blocks and tool calls, across assistant
 *    messages, up to the answer text — is drawn as ONE summary line instead of
 *    one block per call:
 *
 *        🧠 3.2s  💻 4  📝 2  ❌ 1                                   12.4s
 *
 *    (thinking time, tool icon × count, error count, total time). While the
 *    run is going the line updates live and shows the current activity
 *    (`⏳ $ npm test`). Thinking text and tool output are not streamed at all
 *    when collapsed — only when expanded.
 *
 * 2. A muted rule separates the run from the answer text that follows it —
 *    the "done thinking, now answering" boundary.
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
import { Container, Markdown, Spacer, stripTerminalSequences, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ---- look ----

/** Icon for thinking in the summary line. */
const THINKING_ICON = "🧠";
/** Icon shown in front of the current activity while a run is still going. */
const RUNNING_ICON = "⏳";
/** Icon + count for tools that returned an error. */
const ERROR_ICON = "❌";
/** Separator between the summary's groups. */
const GROUP_GAP = "  ";
/** Separator drawn between a run and the answer text that follows it. */
const SEPARATOR_CHAR = "─";
/** Separator width in cells; 0 = full width (minus padding). */
const SEPARATOR_WIDTH = 0;
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
	if (ms < 1000) return `${Math.round(ms)}ms`;
	if (ms < 10_000) return `${(ms / 1000).toFixed(1)}s`;
	if (ms < 60_000) return `${Math.round(ms / 1000)}s`;
	const m = Math.floor(ms / 60_000);
	return `${m}m ${Math.round((ms - m * 60_000) / 1000)}s`;
}

function separatorLine(width: number, pad: number): string {
	const n = SEPARATOR_WIDTH > 0 ? Math.min(SEPARATOR_WIDTH, width - pad * 2) : width - pad * 2;
	return " ".repeat(pad) + muted(SEPARATOR_CHAR.repeat(Math.max(1, n)));
}

/** `left` flush left, `right` flush right, inside `pad`, truncated to width. */
function alignedLine(width: number, pad: number, left: string, right: string): string {
	const rightWidth = visibleWidth(right);
	const maxLeft = Math.max(1, width - pad * 2 - (rightWidth ? rightWidth + 1 : 0));
	const leftText = truncateToWidth(left, maxLeft, "…");
	const gap = Math.max(0, width - pad * 2 - visibleWidth(leftText) - rightWidth);
	return " ".repeat(pad) + leftText + " ".repeat(gap) + right;
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
/** Does the run continue *past* this component (so the next sibling is absorbed)? */
const continuesRun = (c: any): boolean => isCompactTool(c) || endsWithThinking(c);

/** True when `component`'s run part is absorbed into a summary drawn by an earlier sibling. */
function absorbedInRun(component: any): boolean {
	if (isExpanded()) return false;
	const s = siblings(component);
	return s !== undefined && s.index > 0 && continuesRun(s.list[s.index - 1]);
}

// ---- run summary ----

interface RunSummary {
	thinking: number; // thinking blocks seen
	thinkingMs: number;
	tools: Map<string, number>; // icon -> count
	errors: number;
	totalMs: number;
	running: boolean;
	/** Current activity while running: "thinking" or a tool title. */
	activity?: string;
}

/** Walk the chat from `start` over the run it begins and total it up. */
function summarizeRun(start: any): RunSummary {
	const sum: RunSummary = { thinking: 0, thinkingMs: 0, tools: new Map(), errors: 0, totalMs: 0, running: false };
	const s = siblings(start);
	const list = s ? s.list : [start];
	let i = s ? s.index : 0;
	for (; i < list.length; i++) {
		const c: any = list[i];
		if (isCompactTool(c)) {
			const icon = toolIcon(String(c.toolName ?? ""));
			sum.tools.set(icon, (sum.tools.get(icon) ?? 0) + 1);
			const finished = c.result !== undefined && !c.isPartial;
			if (finished && c.result?.isError) sum.errors++;
			const t = toolTimings.get(c.toolCallId);
			const ms = finished ? durationOf(t) : elapsedOf(t);
			if (ms !== undefined) sum.totalMs += ms;
			if (!finished) {
				sum.running = true;
				sum.activity ??= `${icon} ${toolTitle(c)}`;
			}
			continue;
		}
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
	if (sum.thinking > 0) {
		const t = sum.thinkingMs > 0 ? ` ${muted(formatDuration(sum.thinkingMs))}` : "";
		groups.push(bold(fg("accent", THINKING_ICON)) + t);
	}
	for (const [icon, n] of sum.tools) groups.push(`${icon} ${bold(String(n))}`);
	if (sum.errors > 0) groups.push(`${ERROR_ICON} ${bold(fg("error", String(sum.errors)))}`);
	if (sum.running && sum.activity) {
		groups.push(`${RUNNING_ICON} ${fg("warning", sum.activity === "thinking" ? "thinking…" : sum.activity)}`);
	}
	const left = groups.join(GROUP_GAP);
	const right = sum.totalMs > 0 ? muted(formatDuration(sum.totalMs)) : "";
	return alignedLine(width, pad, left, right);
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

/** Replaces the Spacer pi puts between thinking and the answer text: a rule when collapsed, blank when expanded. */
class Separator {
	constructor(private readonly pad: number) {}
	render(width: number): string[] {
		return [isExpanded() ? "" : separatorLine(width, this.pad)];
	}
	invalidate(): void {}
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
		// thinking → text inside one message: pi separates them with a Spacer; make it the rule.
		for (let i = 1; i < children.length - 1; i++) {
			if (children[i] instanceof Spacer && children[i - 1] instanceof ThinkingWindow && children[i + 1] instanceof Markdown) {
				children[i] = new Separator(this.outputPad ?? 1);
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
		const absorbed = absorbedInRun(this);
		// Thinking-only message absorbed into an earlier summary: draw nothing at all.
		if (absorbed && first === "thinking" && !blocks.some((b) => b.type === "text")) return [];
		if (!isBlankLine(lines[0]) || lines.length < 2) return lines;
		// lines[0] may carry OSC 133 zone markers (no visible text); keep them on the new first line.
		// thinking(+text) after a run: its thinking is absorbed, drop the blank line above.
		if (absorbed && first === "thinking") return [lines[0] + lines[1], ...lines.slice(2)];
		// text-only message right after a run: the blank line becomes the separator.
		if (absorbed && first === "text") return [lines[0] + separatorLine(width, this.outputPad ?? 1), ...lines.slice(1)];
		return lines;
	};
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
