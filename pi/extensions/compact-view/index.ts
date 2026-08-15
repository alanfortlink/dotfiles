/**
 * compact-view - keep the pi transcript short.
 *
 * Display-only changes, all undone by the normal tool-expansion toggle
 * (`app.tools.expand`, ctrl+o by default), which pi already propagates to
 * every chat component:
 *
 * 1. Thinking, while streaming, renders inside a fixed-height window: only
 *    the last THINKING_LINES visual lines are shown, so the block scrolls in
 *    place instead of pushing the transcript up. Once the message is done it
 *    collapses to one line: `Thought for 5.2s` (or `Thought` when the timing
 *    is unknown, e.g. a restored session).
 *
 * 2. Tool blocks, while running, are capped at TOOL_LINES visual lines (head
 *    kept, hint line for the rest). Once finished they collapse to one line:
 *    the tool's title (`$ cmd`, `edit path`, ...) with ` · 120ms` appended.
 *    Errors keep the capped view so they stay visible.
 *
 * pi has no hook for either, so the two components are patched on their
 * prototypes: AssistantMessageComponent.updateContent (post-process the
 * thinking Markdown children) and ToolExecutionComponent.render (post-process
 * the rendered lines). Both are exported from the pi package. Session, LLM
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
import { Box, Markdown, stripTerminalSequences, truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

/** Visual lines of thinking kept on screen while streaming. */
const THINKING_LINES = 4;
/** Max visual lines (including padding) of a running tool block. */
const TOOL_LINES = 10;
/** Theme color token for the bold finished-thinking summary line. */
const THINKING_DONE_FG = "accent" as const;

let ui: ExtensionUIContext | undefined;

const isExpanded = (): boolean => ui?.getToolsExpanded() ?? false;
const muted = (text: string): string => ui?.theme.fg("muted", text) ?? text;

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
		if (!this.isStreaming()) {
			const ms = durationOf(this.timing());
			const label = ms === undefined ? "Thought" : `Thought for ${formatDuration(ms)}`;
			const styled = ui ? ui.theme.bold(ui.theme.fg(THINKING_DONE_FG, label)) : label;
			return [truncateToWidth(" ".repeat(this.pad) + styled, width, "...")];
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
	};

	// Lets pi's setToolsExpanded() reach us like any other expandable chat component.
	// The window reads the live state at render time, so a re-render is all that's needed.
	proto.setExpanded ??= function (this: any, _expanded: boolean) {
		if (this.lastMessage) this.updateContent(this.lastMessage);
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

		const finished = this.result !== undefined && !this.isPartial;
		if (finished && !this.result?.isError) {
			// One line: the tool title, with the duration appended when known.
			const idx = lines.findIndex((l) => stripTerminalSequences(l).trim() !== "");
			if (idx === -1) return lines;
			const title = lines[idx];
			const ms = durationOf(toolTimings.get(this.toolCallId));
			const dur = ms === undefined ? "" : ` · ${formatDuration(ms)}`;
			const durWidth = visibleWidth(dur);
			const textWidth = visibleWidth(stripTerminalSequences(title).trimEnd());
			const maxTitle = Math.min(textWidth, Math.max(1, width - durWidth));
			const ellipsis = textWidth > maxTitle ? "…" : "";
			let line = truncateToWidth(title, maxTitle, ellipsis);
			if (dur) {
				const seg = muted(dur) + " ".repeat(Math.max(0, width - visibleWidth(line) - durWidth));
				line += bg ? bg(seg) : seg;
			}
			return lines[0] !== undefined && stripTerminalSequences(lines[0]).trim() === "" ? [lines[0], line] : [line];
		}

		if (lines.length <= TOOL_LINES) return lines;
		const head = lines.slice(0, TOOL_LINES - (keepTail ? 2 : 1));
		const dropped = lines.length - head.length - (keepTail ? 1 : 0);
		let hint = truncateToWidth(" ".repeat(pad) + hiddenHint(dropped, "more lines"), width, "...");
		if (bg) hint = bg(hint + " ".repeat(Math.max(0, width - visibleWidth(hint))));
		return keepTail ? [...head, hint, lines[lines.length - 1]] : [...head, hint];
	};
}

export default function (pi: ExtensionAPI): void {
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
