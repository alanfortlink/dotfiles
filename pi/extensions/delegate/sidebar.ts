/**
 * The delegate sidebar: a persistent right-docked panel listing the main
 * session plus every delegate task, with a live transcript pane for the
 * selected one. Replaces the old modal inspector popup.
 *
 * The panel is a non-capturing overlay: it stays visible and live while the
 * editor keeps keyboard focus, and focus moves into it only when the user asks
 * (alt+g or /delegate). It deliberately stops above the editor rows so the
 * prompt is never covered.
 *
 * Focused keys:
 *   j/k or ↑/↓ switch session · enter/esc back to main · q hide panel
 *   ctrl+u/d pageUp/Down scroll transcript · gg top · G follow tail
 *   s steer · x kill · c clear finished
 */

import {
	Key,
	Markdown,
	matchesKey,
	truncateToWidth,
	visibleWidth,
	wrapTextWithAnsi,
	type Component,
	type Focusable,
} from "@earendil-works/pi-tui";
import { getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import { type Task, displayName, isSettled, listTasks } from "./tasks.ts";

export interface SidebarHooks {
	/** Prompt for a steering message and deliver it. Returns a status line to flash. */
	steer: (task: Task) => Promise<string | undefined>;
	kill: (task: Task) => void;
	/** Drop this session's settled tasks. Returns how many were removed. */
	clear: () => number;
	/** Give keyboard focus back to the editor; the panel stays visible. */
	focusEditor: () => void;
	/** Hide the panel entirely (and return focus to the editor). */
	hide: () => void;
}

type Fg = (color: string, text: string) => string;

const ICONS: Record<Task["status"], string> = {
	queued: "·",
	running: "▶",
	done: "✓",
	failed: "✗",
	killed: "⊘",
};

const COLORS: Record<Task["status"], string> = {
	queued: "dim",
	running: "warning",
	done: "success",
	failed: "error",
	killed: "muted",
};

/** Rows kept free at the bottom so the editor, widget and footer stay visible. */
const EDITOR_RESERVE = 10;
/** The list pane never grows past this many rows; the transcript gets the rest. */
const MAX_LIST_ROWS = 8;
/** Rows the frame spends on borders, title, dividers and footer. */
const FRAME_OVERHEAD = 7;
/** The transcript pane never shrinks below this many rows. */
const MIN_TRANSCRIPT = 2;
/** Narrowest terminal the panel renders on; the overlay's visible() gate matches. */
export const MIN_SIDEBAR_COLS = 80;
/** Sentinel id for the main-session row. */
const MAIN = "main";

/** List order for the panel: newest task first, so fresh runs need no scrolling. */
function tasksNewestFirst(): Task[] {
	return listTasks().slice().reverse();
}

function age(from: number, to: number | undefined): string {
	const ms = (to ?? Date.now()) - from;
	if (ms < 1000) return `${ms}ms`;
	const s = Math.round(ms / 1000);
	if (s < 60) return `${s}s`;
	return `${Math.floor(s / 60)}m${String(s % 60).padStart(2, "0")}s`;
}

function usageLine(t: Task): string {
	const parts: string[] = [];
	if (t.turns) parts.push(`${t.turns} turn${t.turns === 1 ? "" : "s"}`);
	if (t.usage.input) parts.push(`↑${t.usage.input}`);
	if (t.usage.output) parts.push(`↓${t.usage.output}`);
	if (t.usage.cost) parts.push(`$${t.usage.cost.toFixed(4)}`);
	parts.push(age(t.startedAt ?? t.createdAt, t.finishedAt));
	return parts.join(" ");
}

export class Sidebar implements Component, Focusable {
	/** Set by the TUI when keyboard focus moves in or out of the panel. */
	focused = false;

	/** Which session the transcript pane shows: MAIN or a task id. */
	private selectedId: string = MAIN;
	/** True while the transcript sticks to the newest output. */
	private follow = true;
	/** Absolute index of the top visible transcript line while pinned. */
	private top = 0;
	/** Set by the last render, so the key handler can clamp and jump. */
	private maxTop = 0;
	private flash = "";
	private busy = false;
	/** Half of a `gg`. */
	private pendingG = false;
	private readonly mdCache = new Map<string, string[]>();

	constructor(
		private readonly tui: { requestRender: () => void; terminal?: { rows: number; columns: number } },
		private readonly fg: Fg,
		private readonly hooks: SidebarHooks,
	) {}

	invalidate(): void {}

	/**
	 * Whether the overlay's visible() gate lets the panel render right now.
	 * Callers must treat a non-renderable panel as hidden (fall back to the
	 * widget, give feedback on alt+g) - the overlay handle alone cannot tell.
	 */
	canRender(): boolean {
		return (this.tui.terminal?.columns ?? MIN_SIDEBAR_COLS) >= MIN_SIDEBAR_COLS;
	}

	/** Called by the extension whenever task state changes. */
	refresh(): void {
		// Selection is tracked by id, not index, so a settling or pruned task
		// cannot silently shift it onto a different row.
		if (this.selectedId !== MAIN && !listTasks().some((t) => t.id === this.selectedId)) {
			this.selectedId = MAIN;
			this.follow = true;
		}
		this.tui.requestRender();
	}

	/** Select the most recent active task (used when the panel auto-opens on spawn). */
	selectFirstActive(): void {
		const active = tasksNewestFirst().find((t) => !isSettled(t));
		if (this.selectedId === MAIN && active) this.selectedId = active.id;
	}

	private selectedTask(): Task | undefined {
		return this.selectedId === MAIN ? undefined : listTasks().find((t) => t.id === this.selectedId);
	}

	/** Ordered row ids: main first, then tasks newest-first. */
	private rowIds(): string[] {
		return [MAIN, ...tasksNewestFirst().map((t) => t.id)];
	}

	// ---- input (only ever delivered while focused) ----

	handleInput(data: string): void {
		if (this.busy) return;
		const key = data.toLowerCase();
		const isUp = data === "k" || matchesKey(data, Key.up);
		const isDown = data === "j" || matchesKey(data, Key.down);
		const isEnter = matchesKey(data, Key.enter);
		const isEscape = matchesKey(data, Key.escape);
		const half = Math.max(1, Math.floor(this.transcriptHeight() / 2));
		const task = this.selectedTask();

		// Scrolling: `top` is only synced by a render while following, so anchor
		// on maxTop - keys must not depend on a repaint having happened.
		const from = () => (this.follow ? this.maxTop : this.top);
		const older = (n: number) => {
			this.top = Math.max(0, from() - n);
			this.follow = false;
		};
		const newer = (n: number) => {
			this.top = Math.min(this.maxTop, from() + n);
			if (this.top >= this.maxTop) this.follow = true;
		};

		if (data === "G") {
			this.follow = true;
			this.pendingG = false;
		} else if (data === "g") {
			if (this.pendingG) {
				this.follow = false;
				this.top = 0;
				this.pendingG = false;
			} else {
				this.pendingG = true;
			}
		} else {
			this.pendingG = false;
			if (isEscape) {
				// First esc releases a pinned transcript; esc again leaves the panel.
				if (!this.follow) this.follow = true;
				else this.hooks.focusEditor();
			} else if (isEnter) {
				this.hooks.focusEditor();
			} else if (data === "q" || matchesKey(data, "alt+g")) {
				this.hooks.hide();
			} else if (isUp || isDown) {
				const ids = this.rowIds();
				const i = Math.max(0, ids.indexOf(this.selectedId));
				const next = ids[Math.min(ids.length - 1, Math.max(0, i + (isDown ? 1 : -1)))];
				if (next !== this.selectedId) {
					this.selectedId = next;
					this.follow = true;
					this.top = 0;
				}
			} else if (matchesKey(data, Key.ctrl("u"))) {
				if (task) older(half);
			} else if (matchesKey(data, Key.ctrl("d"))) {
				if (task) newer(half);
			} else if (matchesKey(data, Key.pageUp)) {
				if (task) older(half * 2);
			} else if (matchesKey(data, Key.pageDown)) {
				if (task) newer(half * 2);
			} else if (key === "s" && task) void this.doSteer(task);
			else if (key === "x" && task) this.doKill(task);
			else if (key === "c") this.doClear();
		}
		this.tui.requestRender();
	}

	private async doSteer(task: Task): Promise<void> {
		if (isSettled(task)) {
			this.setFlash(`${task.id} already settled`);
			return;
		}
		this.busy = true;
		try {
			const result = await this.hooks.steer(task);
			if (result) this.setFlash(result);
		} catch (err) {
			this.setFlash(`steer failed: ${(err as Error).message}`);
		} finally {
			this.busy = false;
			this.tui.requestRender();
		}
	}

	private doKill(task: Task): void {
		if (isSettled(task)) {
			this.setFlash(`${task.id} already settled`);
			return;
		}
		this.hooks.kill(task);
		this.setFlash(`killed ${task.id}`);
	}

	private doClear(): void {
		const n = this.hooks.clear();
		this.setFlash(n > 0 ? `cleared ${n} finished task(s)` : "nothing to clear");
	}

	private setFlash(msg: string): void {
		// The flash renders into a single footer row; never let a newline through.
		const clean = msg.replace(/\s+/g, " ").trim();
		this.flash = clean;
		this.tui.requestRender();
		setTimeout(() => {
			if (this.flash === clean) {
				this.flash = "";
				this.tui.requestRender();
			}
		}, 2500);
	}

	// ---- layout ----

	/** Total panel height: the terminal minus the rows reserved for the editor. */
	private panelHeight(): number {
		const rows = this.tui.terminal?.rows ?? 40;
		return Math.max(10, rows - EDITOR_RESERVE);
	}

	private listHeight(): number {
		// The list shrinks before the frame may exceed panelHeight: on a short
		// terminal a full list would otherwise push the frame into the editor rows.
		const budget = Math.max(1, this.panelHeight() - FRAME_OVERHEAD - MIN_TRANSCRIPT);
		return Math.max(1, Math.min(this.rowIds().length, MAX_LIST_ROWS, budget));
	}

	private transcriptHeight(): number {
		return Math.max(MIN_TRANSCRIPT, this.panelHeight() - this.listHeight() - FRAME_OVERHEAD);
	}

	// ---- render ----

	render(width: number): string[] {
		const inner = Math.max(20, width - 4);
		const tasks = listTasks();

		const running = tasks.filter((t) => t.status === "running").length;
		const queued = tasks.filter((t) => t.status === "queued").length;
		const done = tasks.filter(isSettled).length;
		const tally: string[] = [];
		if (running) tally.push(this.fg("accent", `${running} running`));
		if (queued) tally.push(this.fg("muted", `${queued} queued`));
		if (done) tally.push(this.fg("dim", `${done} finished`));
		const title =
			this.fg("toolTitle", "delegate ") + (tally.length ? tally.join(this.fg("dim", " · ")) : this.fg("dim", "idle"));

		const list = this.renderList(inner);
		const transcript = this.renderTranscript(inner);

		const footer = this.flash
			? this.fg("accent", this.flash)
			: this.focused
				? this.fg("dim", this.follow ? "j/k switch · s steer · x kill · esc main · q hide" : "paused · esc to follow")
				: this.fg("dim", "alt+g to focus");

		return this.frame(title, list, transcript, footer, inner);
	}

	/** One row per session: main first, then every task. */
	private renderList(inner: number): string[] {
		const rowsAll: string[] = [];
		const ids = this.rowIds();
		const tasks = tasksNewestFirst();

		const mainSel = this.selectedId === MAIN;
		rowsAll.push(
			truncateToWidth(
				`${mainSel ? this.fg("accent", "❯ ") : "  "}${this.fg("text", "⌂ ")}${this.fg(mainSel ? "accent" : "text", "main session")}`,
				inner,
			),
		);
		for (const t of tasks) {
			const sel = this.selectedId === t.id;
			const marker = sel ? this.fg("accent", "❯ ") : "  ";
			const icon = this.fg(COLORS[t.status], ICONS[t.status]);
			const meta = t.status === "running" || t.status === "queued" ? age(t.startedAt ?? t.createdAt, undefined) : t.status;
			rowsAll.push(
				truncateToWidth(
					`${marker}${icon} ${this.fg(sel ? "accent" : "text", `${t.id} ${displayName(t)}`)}  ${this.fg("muted", meta)}`,
					inner,
				),
			);
		}

		// Keep the selected row inside the visible window when there are many tasks.
		const height = this.listHeight();
		if (rowsAll.length <= height) return rowsAll;
		const selRow = Math.max(0, ids.indexOf(this.selectedId));
		let start = Math.max(0, Math.min(selRow - Math.floor(height / 2), rowsAll.length - height));
		// The "… N more" marker replaces the window's last row; make sure that
		// row is never the selection (and skip the marker entirely at height 1).
		let needMore = height >= 2 && start + height < rowsAll.length;
		if (needMore && selRow >= start + height - 1) {
			start = Math.min(selRow - height + 2, rowsAll.length - height);
			needMore = start + height < rowsAll.length;
		}
		const win = rowsAll.slice(start, start + height);
		if (needMore) {
			win[win.length - 1] = this.fg("muted", `  … ${rowsAll.length - (start + height - 1)} more`);
		}
		return win;
	}

	/** The transcript pane for the selected session. */
	private renderTranscript(inner: number): string[] {
		const height = this.transcriptHeight();
		const task = this.selectedTask();
		if (!task) return this.renderOverview(inner, height);

		const header: string[] = [
			truncateToWidth(
				`${this.fg("muted", "» ")}${this.fg("text", `${task.id} ${displayName(task)}`)} ${this.fg(COLORS[task.status], task.status)}`,
				inner,
			),
			truncateToWidth(this.fg("muted", `${task.model ?? "session model"} · ${usageLine(task)}`), inner),
		];
		// Collapse whitespace: an errorMessage can be the subagent's entire
		// multi-line output, and a newline here would burst the frame row.
		if (task.errorMessage) {
			header.push(truncateToWidth(this.fg("error", task.errorMessage.replace(/\s+/g, " ").trim()), inner));
		}

		const body: string[] = [];
		for (const entry of task.feed) {
			switch (entry.kind) {
				case "tool":
					body.push(...this.wrap(`${this.fg("accent", "→ ")}${this.fg("text", entry.text)}`, inner));
					break;
				case "toolResult":
					body.push(...this.wrap(this.fg("error", `! ${entry.text}`), inner));
					break;
				case "text":
					body.push(...this.markdown(entry.text, inner, `${task.id}:${entry.at}`));
					break;
				default:
					body.push(...this.wrap(this.fg("dim", `· ${entry.text}`), inner));
			}
		}
		if (task.stream.trim()) {
			body.push(...this.wrap(this.fg("text", task.stream.trim()), inner));
			body.push(this.fg("dim", "▍"));
		}
		if (task.status === "done" && task.output) {
			body.push("", this.fg("muted", "── final output ──"), ...this.markdown(task.output, inner, `${task.id}:final`));
		}

		const view = Math.max(1, height - header.length);
		// While following, the window sits at the bottom and moves with new output.
		// While pinned, `top` is an absolute line index, so arriving output extends
		// the transcript below without shifting what is on screen.
		this.maxTop = Math.max(0, body.length - view);
		this.top = this.follow ? this.maxTop : Math.min(this.top, this.maxTop);
		const visible = body.slice(this.top, this.top + view);
		const lines = [...header, ...visible.map((l) => truncateToWidth(l, inner))];
		while (lines.length < height) lines.push("");
		return lines.slice(0, height);
	}

	/** What the pane shows when `main` is selected: a session-level summary. */
	private renderOverview(inner: number, height: number): string[] {
		// The overview does not scroll; clear any pin state left by a task view.
		this.maxTop = 0;
		this.follow = true;
		const tasks = listTasks();
		const lines: string[] = [];
		if (tasks.length === 0) {
			lines.push(this.fg("dim", "no delegate tasks yet"));
		} else {
			const cost = tasks.reduce((s, t) => s + t.usage.cost, 0);
			const input = tasks.reduce((s, t) => s + t.usage.input, 0);
			const output = tasks.reduce((s, t) => s + t.usage.output, 0);
			lines.push(this.fg("muted", `${tasks.length} task(s) this session`));
			if (input || output) lines.push(this.fg("muted", `↑${input} ↓${output}${cost ? ` · $${cost.toFixed(4)}` : ""}`));
			lines.push("");
			for (const t of tasks.filter(isSettled).slice(-Math.max(1, height - lines.length - 1))) {
				const first = (t.output || t.errorMessage || "").replace(/\s+/g, " ").trim();
				lines.push(
					truncateToWidth(
						`${this.fg(COLORS[t.status], ICONS[t.status])} ${this.fg("text", t.id)} ${this.fg("dim", first)}`,
						inner,
					),
				);
			}
		}
		while (lines.length < height) lines.push("");
		return lines.slice(0, height);
	}

	/** Markdown-render a block, memoized so a redraw per token doesn't re-parse the transcript. */
	private markdown(text: string, width: number, key: string): string[] {
		// Keyed on content: two feed entries can share a task id, a millisecond and
		// a length (a tool call and its result), and would otherwise alias.
		let hash = 5381;
		for (let i = 0; i < text.length; i++) hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0;
		const cacheKey = `${key}:${width}:${text.length}:${hash}`;
		const hit = this.mdCache.get(cacheKey);
		if (hit) {
			// LRU touch: every visible entry is re-requested each frame, so a plain
			// FIFO would evict exactly what the next frame needs first once the
			// transcript outgrows the cap, re-parsing everything per render.
			this.mdCache.delete(cacheKey);
			this.mdCache.set(cacheKey, hit);
			return hit;
		}
		let lines: string[];
		try {
			lines = new Markdown(text.trim(), 0, 0, getMarkdownTheme()).render(width);
		} catch {
			lines = this.wrap(text.trim(), width);
		}
		lines = lines.flatMap((l) => (l.includes("\n") ? this.wrap(l, width) : [l]));
		// Cap above FEED_LIMIT (300) plus finals, so one transcript's working set
		// always fits and eviction only trims other tasks' stale entries.
		while (this.mdCache.size >= 400) {
			const oldest = this.mdCache.keys().next().value;
			if (oldest === undefined) break;
			this.mdCache.delete(oldest);
		}
		this.mdCache.set(cacheKey, lines);
		return lines;
	}

	/**
	 * Split on real newlines first - a returned "line" containing \n would break
	 * the frame - then wrap with the SDK's escape-aware wrapper. These strings are
	 * already themed, so slicing by raw index would cut through an SGR sequence.
	 * Tabs and carriage returns are neutralized first: visibleWidth counts a tab
	 * as one cell while the terminal jumps to the next tab stop, and a stray \r
	 * would drag the cursor over the frame's left border.
	 */
	private wrap(text: string, width: number): string[] {
		const clean = text.replace(/\r\n?/g, "\n").replace(/\t/g, "  ");
		return clean.split("\n").flatMap((line) => (visibleWidth(line) <= width ? [line] : wrapTextWithAnsi(line, width)));
	}

	private frame(title: string, list: string[], transcript: string[], footer: string, inner: number): string[] {
		const bar = "─".repeat(inner);
		const edge = this.focused ? "accent" : "toolTitle";
		const pad = (s: string) => {
			// Truncating a wide char can land one column short; re-pad so the right
			// border never drifts.
			const t = visibleWidth(s) > inner ? truncateToWidth(s, inner) : s;
			const w = visibleWidth(t);
			return w >= inner ? t : t + " ".repeat(inner - w);
		};
		const row = (s: string) => `${this.fg(edge, "│ ")}${pad(s)}${this.fg(edge, " │")}`;
		// Invariant: exactly one terminal line per entry. Markdown and streamed
		// model text both arrive with embedded newlines.
		const flat = (ls: string[]) => ls.flatMap((l) => (l.includes("\n") ? l.split("\n") : [l])).map(row);
		return [
			this.fg(edge, `┌─${bar}─┐`),
			row(title),
			this.fg(edge, `├─${bar}─┤`),
			...flat(list),
			this.fg(edge, `├─${bar}─┤`),
			...flat(transcript),
			this.fg(edge, `├─${bar}─┤`),
			row(footer),
			this.fg(edge, `└─${bar}─┘`),
		];
	}
}
