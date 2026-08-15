/**
 * compact-view - keep the pi transcript short.
 *
 * Display-only changes, all undone by the normal tool-expansion toggle
 * (`app.tools.expand`, ctrl+o by default), which pi already propagates to
 * every chat component:
 *
 * 1. Thinking, while streaming, renders inside a fixed-height window: only
 *    the last THINKING_LINES visual lines are shown, so the block scrolls in
 *    place instead of pushing the transcript up. As soon as thinking is over
 *    (a tool call or text follows, or the message ends) it
 *    collapses to one line: `🧠 5.2s` (or `🧠` when the timing is unknown,
 *    e.g. a restored session).
 *
 * 2. Tool blocks, while running, are capped at TOOL_LINES visual lines (head
 *    kept, hint line for the rest). Once finished they collapse to one line:
 *    a tool icon (TOOL_ICONS) + the tool's title (`$ cmd`, `edit path`, ...)
 *    with ` · 120ms` appended.
 *    Errors collapse too (` · error`) on pi's error background.
 *
 * 3. Runs of tool calls / thinking are drawn tight: the blank line pi puts
 *    before each tool block and before a thinking block is dropped when the
 *    previous chat sibling is a collapsed tool or a message that ends in
 *    thinking, so a "thought → tool → tool → thought" sequence reads as one
 *    group. Text keeps its spacing.
 *
 * 4. Collapsed thinking/tool lines are drawn in COLLAPSED_FG (dim) — tools keep
 *    pi's success/error background bar — and a muted rule separates the run
 *    from the answer text that follows — the "done thinking, now answering"
 *    boundary.
 *
 * pi has no hook for either, so the two components are patched on their
 * prototypes: AssistantMessageComponent.updateContent (post-process the
 * thinking Markdown children), AssistantMessageComponent.render and
 * ToolExecutionComponent.render (post-process the rendered lines). Both are
 * exported from the pi package. Sibling lookup needs a parent pointer pi-tui
 * doesn't keep, so Container.addChild is patched to record one. Session, LLM
 * context and the expanded view are untouched. Durations are measured live
 * (thinking: first thinking delta → first non-thinking content; tools:
 * tool_execution_start → tool_execution_end) and persisted per turn as a custom
 * session entry so they survive /reload, restart and resume.
 */

import {
	AssistantMessageComponent,
	type ExtensionAPI,
	type ExtensionUIContext,
	keyHint,
	ToolExecutionComponent,
} from "@earendil-works/pi-coding-agent";
import { Box, Container, Markdown, Spacer, stripTerminalSequences, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

/** Visual lines of thinking kept on screen while streaming. */
const THINKING_LINES = 4;
/** Max visual lines (including padding) of a running tool block. */
const TOOL_LINES = 10;
/** Theme color token for the bold finished-thinking summary line. */
const THINKING_DONE_FG = "accent" as const;
/** Prefix of the finished-thinking summary line (`🧠 5.2s`, or just `🧠` when the timing is unknown). */
const THINKING_DONE_ICON = "🧠";
/** Background token for the collapsed thinking line — same bar as tools so a run reads as one block. */
const THINKING_DONE_BG = "toolSuccessBg" as const;
/**
 * Icon shown before a collapsed tool line, matched against the tool name in
 * order (first hit wins). Extension tools not listed get TOOL_ICON_DEFAULT.
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
/**
 * Collapsed (finished, not expanded) thinking/tool lines are re-styled in this
 * theme color (on top of pi's success/error background bar for tools), so the
 * run reads as quiet metadata under the answer. Set to undefined to keep pi's
 * styling.
 */
const COLLAPSED_FG: "dim" | "muted" | undefined = "dim";
/** Separator drawn between a thinking/tool run and the answer text that follows it. */
const SEPARATOR_CHAR = "─";
/** Separator width in cells; 0 = full width (minus padding). */
const SEPARATOR_WIDTH = 0;

let ui: ExtensionUIContext | undefined;

const isExpanded = (): boolean => ui?.getToolsExpanded() ?? false;
const muted = (text: string): string => ui?.theme.fg("muted", text) ?? text;
/** Re-style a collapsed line: strip pi's colors/background, apply COLLAPSED_FG. */
const dimmed = (text: string): string =>
	COLLAPSED_FG && ui ? ui.theme.fg(COLLAPSED_FG, stripTerminalSequences(text).trimEnd()) : text;

function separatorLine(width: number, pad: number): string {
	const n = SEPARATOR_WIDTH > 0 ? Math.min(SEPARATOR_WIDTH, width - pad * 2) : width - pad * 2;
	return " ".repeat(pad) + muted(SEPARATOR_CHAR.repeat(Math.max(1, n)));
}

/**
 * One collapsed line: `left` (icon + title) flush left, `right` (duration /
 * error) flush right, both inside `pad`, dimmed per COLLAPSED_FG, on `bg`.
 * Every collapsed thinking/tool line goes through here so columns line up.
 */
function collapsedLine(width: number, pad: number, left: string, right: string, bg?: (s: string) => string): string {
	const style = (t: string) => (COLLAPSED_FG ? dimmed(t) : t);
	const rightText = right ? style(right) : "";
	const rightWidth = visibleWidth(rightText);
	const maxLeft = Math.max(1, width - pad * 2 - (rightWidth ? rightWidth + 1 : 0));
	const leftText = truncateToWidth(style(left), maxLeft, "…");
	const gap = Math.max(0, width - pad * 2 - visibleWidth(leftText) - rightWidth);
	const line = " ".repeat(pad) + leftText + " ".repeat(gap) + rightText + " ".repeat(pad);
	return bg ? bg(line) : line;
}

/** Replaces the Spacer pi puts between thinking and the answer text: a rule when collapsed, blank when expanded. */
class Separator {
	constructor(private readonly pad: number) {}
	render(width: number): string[] {
		return [isExpanded() ? "" : separatorLine(width, this.pad)];
	}
	invalidate(): void {}
}

/** "... (N more lines, ctrl+o to expand)" — same shape as pi's own hints. */
function hiddenHint(count: number, word: string): string {
	return `${muted(`... (${count} ${word},`)} ${keyHint("app.tools.expand", "to expand")}${muted(")")}`;
}

function formatDuration(ms: number): string {
	if (ms < 1000) return `${Math.round(ms)}ms`;
	if (ms < 10_000) return `${(ms / 1000).toFixed(1)}s`;
	if (ms < 60_000) return `${Math.round(ms / 1000)}s`;
	const m = Math.floor(ms / 60_000);
	return `${m}m ${Math.round((ms - m * 60_000) / 1000)}s`;
}

interface Timing {
	start?: number;
	end?: number;
}
const durationOf = (t: Timing | undefined): number | undefined =>
	t?.start !== undefined && t.end !== undefined ? t.end - t.start : undefined;

/** Keyed by assistant message timestamp so timings survive chat rebuilds within a session. */
const thinkingTimings = new Map<number, Timing>();
/** Keyed by toolCallId. */
const toolTimings = new Map<string, Timing>();

// ---- persistence ----
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

function flushTimings(): void {
	if (!appendEntry || (!pendingEntry.thinking && !pendingEntry.tools)) return;
	appendEntry(TIMING_ENTRY, pendingEntry);
	pendingEntry = {};
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

// ---- siblings ----
// pi-tui components don't know their parent; record it on addChild so a chat
// component can look at the sibling rendered right above it.

const PARENT = Symbol.for("compact-view.parent");

function patchContainer(): void {
	const proto = Container.prototype as any;
	const originalAddChild = (proto.__compactViewOriginalAddChild ??= proto.addChild);
	proto.addChild = function (this: any, child: any) {
		if (child && typeof child === "object") child[PARENT] = this;
		return originalAddChild.call(this, child);
	};
}

function previousSibling(component: any): any {
	const parent = component?.[PARENT];
	const children: any[] | undefined = parent?.children;
	if (!children) return undefined;
	const idx = children.indexOf(component);
	return idx > 0 ? children[idx - 1] : undefined;
}

const isVisibleBlock = (c: any): boolean =>
	(c?.type === "text" && c.text?.trim()) || (c?.type === "thinking" && c.thinking?.trim());
const visibleBlocks = (message: any): any[] => (message?.content ?? []).filter(isVisibleBlock);

/** A collapsed (non-expanded, image-free) tool block — running or finished. */
function isCompactTool(c: any): boolean {
	return c instanceof ToolExecutionComponent && !(c as any).expanded && ((c as any).imageComponents?.length ?? 0) === 0 && !(c as any).hideComponent;
}

/** An assistant message whose last visible block is thinking (drawn as a 🧠 line / window). */
function endsWithThinking(c: any): boolean {
	if (!(c instanceof AssistantMessageComponent)) return false;
	const blocks = visibleBlocks((c as any).lastMessage);
	return blocks.length > 0 && blocks[blocks.length - 1].type === "thinking";
}

/** Should `component` drop the blank line pi draws above it? */
function tightAbove(component: any): boolean {
	if (isExpanded()) return false;
	const prev = previousSibling(component);
	return isCompactTool(prev) || endsWithThinking(prev);
}

const isBlankLine = (l: string | undefined): boolean => l !== undefined && stripTerminalSequences(l).trim() === "";

// ---- thinking ----
/** Wraps a thinking Markdown component: tail window while streaming, one summary line when done. */
class ThinkingWindow {
	constructor(
		private readonly inner: Markdown,
		private readonly pad: number,
		private readonly isStreaming: () => boolean,
		private readonly timing: () => Timing | undefined,
	) {}

	render(width: number): string[] {
		if (isExpanded()) return this.inner.render(width);
		// Collapse as soon as thinking is over (a tool call or text followed), not
		// only at message end — so the streaming view already has the final shape.
		const ms = durationOf(this.timing());
		if (!this.isStreaming() || ms !== undefined) {
			const icon = COLLAPSED_FG || !ui ? THINKING_DONE_ICON : ui.theme.bold(ui.theme.fg(THINKING_DONE_FG, THINKING_DONE_ICON));
			const bg = ui ? (t: string) => ui!.theme.bg(THINKING_DONE_BG, t) : undefined;
			return [collapsedLine(width, this.pad, icon, ms === undefined ? "" : formatDuration(ms), bg)];
		}
		const lines = this.inner.render(width);
		if (lines.length <= THINKING_LINES + 1) return lines;
		const hidden = lines.length - THINKING_LINES;
		const hint = truncateToWidth(" ".repeat(this.pad) + hiddenHint(hidden, "earlier lines"), width, "...");
		return [hint, ...lines.slice(-THINKING_LINES)];
	}

	invalidate(): void {
		this.inner.invalidate();
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

function patchAssistantMessage(): void {
	const proto = AssistantMessageComponent.prototype as any;
	// Keep the pristine method across /reload so a re-import re-patches with the new code.
	const originalUpdateContent = (proto.__compactViewOriginalUpdateContent ??= proto.updateContent);
	proto.updateContent = function (this: any, message: any, isStreaming: boolean = this.isStreaming) {
		originalUpdateContent.call(this, message, isStreaming);
		trackThinking(message, this.isStreaming);
		const children: any[] = this.contentContainer?.children ?? [];
		for (let i = 0; i < children.length; i++) {
			const child = children[i];
			// Thinking blocks are the only Markdown children rendered with a default italic style.
			if (child instanceof Markdown && (child as any).defaultTextStyle?.italic === true) {
				children[i] = new ThinkingWindow(
					child,
					this.outputPad ?? 1,
					() => this.isStreaming,
					() => thinkingTimings.get(this.lastMessage?.timestamp),
				);
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
	// The window reads the live state at render time, so a re-render is all that's needed.
	proto.setExpanded ??= function (this: any, _expanded: boolean) {
		if (this.lastMessage) this.updateContent(this.lastMessage);
	};

	// After a tool/thinking run: a thinking-first message drops its leading blank
	// line (stays in the run); a text-first message turns it into the separator.
	const originalRender = (proto.__compactViewOriginalRender ??= proto.render);
	proto.render = function (this: any, width: number): string[] {
		const lines: string[] = originalRender.call(this, width);
		if (lines.length < 2 || !isBlankLine(lines[0]) || !tightAbove(this)) return lines;
		const first = visibleBlocks(this.lastMessage)[0];
		// lines[0] may carry OSC 133 zone markers (no visible text); keep them on the new first line.
		if (first?.type === "thinking") return [lines[0] + lines[1], ...lines.slice(2)];
		if (first?.type === "text") return [lines[0] + separatorLine(width, this.outputPad ?? 1), ...lines.slice(1)];
		return lines;
	};
}

// ---- tools ----

function patchToolExecution(): void {
	const proto = ToolExecutionComponent.prototype as any;
	const originalRender = (proto.__compactViewOriginalRender ??= proto.render);
	proto.render = function (this: any, width: number): string[] {
		const lines: string[] = originalRender.call(this, width);
		if (this.expanded || (this.imageComponents?.length ?? 0) > 0) return lines;

		// Which shell rendered the block decides background, padding and whether the
		// last line is box padding worth keeping. Self-rendering tools (edit) usually
		// wrap themselves in a Box too, so borrow its style when there is one.
		const children: unknown[] = this.children ?? [];
		const box: any = children.includes(this.contentBox)
			? this.contentBox
			: children.includes(this.contentText)
				? undefined
				: this.selfRenderContainer?.children?.find((c: unknown) => c instanceof Box);
		const bg: ((s: string) => string) | undefined = box?.bgFn ?? this.contentText?.customBgFn;
		const pad: number = box?.paddingX ?? (children.includes(this.contentText) ? 1 : 0);
		const keepTail = box !== undefined || children.includes(this.contentText);

		// Runs of tools/thinking are drawn without pi's blank separator line.
		const tight = tightAbove(this);
		const lead: string[] = tight || !isBlankLine(lines[0]) ? [] : [lines[0]];
		if (tight && isBlankLine(lines[0])) lines.shift();

		const finished = this.result !== undefined && !this.isPartial;
		if (finished) {
			// One line: the tool title, with error marker / duration appended when known.
			const idx = lines.findIndex((l) => stripTerminalSequences(l).trim() !== "");
			if (idx === -1) return [...lead, ...lines];
			// Left: tool icon + pi's title text; right: "error · 120ms" — on pi's bg bar.
			const icon = toolIcon(String(this.toolName ?? ""));
			const rawTitle = lines[idx];
			const titleText = COLLAPSED_FG ? stripTerminalSequences(rawTitle).trim() : rawTitle.trimStart();
			const ms = durationOf(toolTimings.get(this.toolCallId));
			const right = [this.result?.isError ? "error" : "", ms === undefined ? "" : formatDuration(ms)].filter(Boolean).join(" · ");
			return [...lead, collapsedLine(width, pad, `${icon} ${titleText}`, right, bg)];
		}

		if (lines.length + lead.length <= TOOL_LINES) return [...lead, ...lines];
		const head = lines.slice(0, TOOL_LINES - lead.length - (keepTail ? 2 : 1));
		const dropped = lines.length - head.length - (keepTail ? 1 : 0);
		let hint = truncateToWidth(" ".repeat(pad) + hiddenHint(dropped, "more lines"), width, "...");
		if (bg) hint = bg(hint + " ".repeat(Math.max(0, width - visibleWidth(hint))));
		return keepTail ? [...lead, ...head, hint, lines[lines.length - 1]] : [...lead, ...head, hint];
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
	pi.on("turn_end", () => flushTimings());
	pi.on("agent_end", () => flushTimings());
}
