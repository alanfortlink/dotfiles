/**
 * The delegate inspector: a live overlay listing every task, with a zoom view
 * into a single agent's activity. This is where you steer or kill an individual
 * agent - those are human actions, not tool calls.
 *
 * List:  j/k or ↑/↓ move · enter open · gg/G first/last · s steer · x kill · c clear finished
 * Zoom:  j/k or ↑/↓ scroll · ctrl+u/d half page · gg top · G tail
 *
 * The transcript follows live output until you scroll up, which pins it to an
 * absolute line so incoming output cannot move what you are reading. Esc (or
 * scrolling back to the bottom) resumes following; esc again leaves the task.
 */

import { Key, Markdown, matchesKey, type Component, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { getMarkdownTheme } from "@earendil-works/pi-coding-agent";
import { type Task, currentActivity, displayName, isSettled, listTasks } from "./tasks.ts";

export interface InspectorHooks {
	/** Prompt for a steering message and deliver it. Returns a status line to flash. */
	steer: (task: Task) => Promise<string | undefined>;
	kill: (task: Task) => void;
	/** Drop this session's settled tasks. Returns how many were removed. */
	clear: () => number;
	close: () => void;
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

export class Inspector implements Component {
	private selected = 0;
	private zoomId: string | null = null;
	/** True while the transcript sticks to the newest output. */
	private follow = true;
	/** Absolute index of the top visible line while pinned. */
	private top = 0;
	private flash = "";
	private busy = false;
	private readonly mdCache = new Map<string, string[]>();
	/** Set by the last zoom render, so the key handler can clamp and jump. */
	private maxTop = 0;
	/** Half of a `gg`. */
	private pendingG = false;

	constructor(
		private readonly tui: { requestRender: () => void; terminal?: { rows: number } },
		private readonly fg: Fg,
		private readonly hooks: InspectorHooks,
	) {}

	invalidate(): void {}

	/** Called by the extension whenever task state changes. */
	refresh(): void {
		const tasks = listTasks();
		if (this.selected >= tasks.length) this.selected = Math.max(0, tasks.length - 1);
		this.tui.requestRender();
	}

	/** Leave room for the frame, the footer, and the editor underneath the overlay. */
	private get bodyHeight(): number {
		const rows = this.tui.terminal?.rows ?? 40;
		return Math.max(6, Math.min(28, rows - 12));
	}

	private zoomed(): Task | undefined {
		return this.zoomId ? listTasks().find((t) => t.id === this.zoomId) : undefined;
	}

	// ---- input ----

	handleInput(data: string): void {
		if (this.busy) return;
		const tasks = listTasks();
		const key = data.toLowerCase();
		const isUp = key === "k" || matchesKey(data, Key.up);
		const isDown = key === "j" || matchesKey(data, Key.down);
		const isEnter = matchesKey(data, Key.enter);
		const isEscape = matchesKey(data, Key.escape) || key === "q";
		const isHalfUp = matchesKey(data, Key.ctrl("u"));
		const isHalfDown = matchesKey(data, Key.ctrl("d"));
		const isPageUp = matchesKey(data, Key.pageUp);
		const isPageDown = matchesKey(data, Key.pageDown);

		if (this.zoomId) {
			const zoom = this.zoomed();
			const half = Math.max(1, Math.floor(this.bodyHeight / 2));
			// Scrolling up pins the view; scrolling back to the bottom releases it.
			// While following, `top` is only synced by a render, so derive the anchor
			// from maxTop instead - keys must not depend on a repaint having happened.
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
				this.follow = true; // back to the live tail
				this.pendingG = false;
			} else if (data === "g") {
				if (this.pendingG) {
					this.follow = false; // gg -> top
					this.top = 0;
					this.pendingG = false;
				} else {
					this.pendingG = true;
				}
			} else {
				this.pendingG = false;
				if (isEscape) {
					// First esc resumes following, so a pinned reader does not lose the
					// task by reflex. Esc again leaves it.
					if (!this.follow) this.follow = true;
					else this.zoomId = null;
				} else if (isUp) older(1);
				else if (isDown) newer(1);
				else if (isHalfUp) older(half);
				else if (isHalfDown) newer(half);
				else if (isPageUp) older(half * 2);
				else if (isPageDown) newer(half * 2);
				else if (key === "s" && zoom) void this.doSteer(zoom);
				else if (key === "x" && zoom) this.doKill(zoom);
			}
			this.tui.requestRender();
			return;
		}

		if (data === "G") this.selected = Math.max(0, tasks.length - 1);
		else if (data === "g") {
			if (this.pendingG) {
				this.selected = 0;
				this.pendingG = false;
			} else {
				this.pendingG = true;
			}
		} else {
			this.pendingG = false;
			if (isEscape) {
				this.hooks.close();
				return;
			}
			if (isUp) this.selected = Math.max(0, this.selected - 1);
			else if (isDown) this.selected = Math.min(tasks.length - 1, this.selected + 1);
			else if (isEnter && tasks[this.selected]) {
				this.zoomId = tasks[this.selected].id;
				this.follow = true;
				this.top = 0;
			} else if (key === "s" && tasks[this.selected]) void this.doSteer(tasks[this.selected]);
			else if (key === "x" && tasks[this.selected]) this.doKill(tasks[this.selected]);
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
		this.flash = msg;
		this.tui.requestRender();
		setTimeout(() => {
			if (this.flash === msg) {
				this.flash = "";
				this.tui.requestRender();
			}
		}, 2500);
	}

	// ---- render ----

	render(width: number): string[] {
		const inner = Math.max(20, width - 4);
		const zoom = this.zoomed();
		const body = zoom ? this.renderZoom(zoom, inner) : this.renderList(inner);
		const title = zoom ? `delegate · ${zoom.id} (${displayName(zoom)})` : "delegate";
		const help = zoom
			? (this.follow ? "live · " : "paused, esc to follow · ") + "j/k ctrl+u/d gg/G · s steer · x kill · esc"
			: "↑/↓ move · enter open · s steer · x kill · c clear finished · esc close";
		// Invariant for the frame: exactly one terminal line per entry. Markdown and
		// streamed model text both arrive with embedded newlines.
		const flat = body.flatMap((l) => (l.includes("\n") ? l.split("\n") : [l]));
		return this.frame(title, flat, this.flash || help, inner);
	}

	private renderList(inner: number): string[] {
		const tasks = listTasks();
		if (tasks.length === 0) return [this.fg("dim", "no tasks yet")];

		// A task emits one or two rows, so the window has to be measured in rows.
		// Sizing it in tasks let the body grow past the terminal and break the frame.
		const rows: string[] = [];
		const firstRowOf: number[] = [];
		for (const t of tasks) {
			const isSel = tasks[this.selected]?.id === t.id;
			const marker = isSel ? this.fg("accent", "❯ ") : "  ";
			const icon = this.fg(COLORS[t.status], ICONS[t.status]);
			const head = `${t.id} ${displayName(t)}`;
			const meta = `${t.provider ?? "?"} · ${usageLine(t)}`;
			firstRowOf.push(rows.length);
			rows.push(
				truncateToWidth(
					`${marker}${icon} ${this.fg(isSel ? "accent" : "text", head)}  ${this.fg("muted", meta)}`,
					inner,
				),
			);
			const last = currentActivity(t);
			if (last) rows.push(truncateToWidth(`     ${this.fg("dim", last)}`, inner));
		}

		const height = this.bodyHeight;
		if (rows.length <= height) return rows;

		// Keep the selection centred, and spend one row saying what was cut.
		const budget = height - 1;
		const selRow = firstRowOf[this.selected] ?? 0;
		const start = Math.max(0, Math.min(selRow - Math.floor(budget / 2), rows.length - budget));
		return [...rows.slice(start, start + budget), this.fg("muted", `  … ${rows.length - budget} more row(s)`)];
	}

	/**
	 * The transcript view: what this subagent has been doing and saying, with its
	 * prose rendered as markdown the way pi renders the main agent's.
	 */
	private renderZoom(task: Task, inner: number): string[] {
		const header: string[] = [
			truncateToWidth(`${this.fg("muted", "prompt ")}${this.fg("text", task.prompt.replace(/\s+/g, " "))}`, inner),
			truncateToWidth(
				`${this.fg("muted", "model ")}${this.fg("text", task.model ?? "session default")}  ${this.fg("muted", usageLine(task))}`,
				inner,
			),
		];
		if (task.errorMessage) header.push(truncateToWidth(this.fg("error", task.errorMessage), inner));
		header.push("");

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
		// Whatever it is writing this instant, un-cached since it changes constantly.
		if (task.stream.trim()) {
			body.push(...this.wrap(this.fg("text", task.stream.trim()), inner));
			body.push(this.fg("dim", "▍"));
		}
		if (task.status === "done" && task.output) {
			body.push("", this.fg("muted", "── final output ──"), ...this.markdown(task.output, inner, `${task.id}:final`));
		}

		const height = Math.max(3, this.bodyHeight - header.length);
		// While following, the window sits at the bottom and moves with new output.
		// While pinned, `top` is an absolute line index, so arriving output extends
		// the transcript below without shifting what is on screen.
		this.maxTop = Math.max(0, body.length - height);
		this.top = this.follow ? this.maxTop : Math.min(this.top, this.maxTop);
		const visible = body.slice(this.top, this.top + height);
		return [...header, ...visible.map((l) => truncateToWidth(l, inner))];
	}

	/** Markdown-render a block, memoized so a redraw per token doesn't re-parse the transcript. */
	private markdown(text: string, width: number, key: string): string[] {
		// Keyed on content: two feed entries can share a task id, a millisecond and
		// a length (a tool call and its result), and would otherwise alias.
		let hash = 5381;
		for (let i = 0; i < text.length; i++) hash = ((hash * 33) ^ text.charCodeAt(i)) >>> 0;
		const cacheKey = `${key}:${width}:${text.length}:${hash}`;
		const hit = this.mdCache.get(cacheKey);
		if (hit) return hit;
		let lines: string[];
		try {
			lines = new Markdown(text.trim(), 0, 0, getMarkdownTheme()).render(width);
		} catch {
			lines = this.wrap(text.trim(), width);
		}
		lines = lines.flatMap((l) => (l.includes("\n") ? this.wrap(l, width) : [l]));
		if (this.mdCache.size > 200) this.mdCache.clear();
		this.mdCache.set(cacheKey, lines);
		return lines;
	}

	/**
	 * Split on real newlines first - a returned "line" containing \n would break
	 * the frame - then wrap with the SDK's escape-aware wrapper. These strings are
	 * already themed, so slicing by raw index would cut through an SGR sequence.
	 */
	private wrap(text: string, width: number): string[] {
		return text.split("\n").flatMap((line) => (visibleWidth(line) <= width ? [line] : wrapTextWithAnsi(line, width)));
	}

	private frame(title: string, body: string[], footer: string, inner: number): string[] {
		const bar = "─".repeat(inner);
		const pad = (s: string) => {
			const w = visibleWidth(s);
			return w >= inner ? truncateToWidth(s, inner) : s + " ".repeat(inner - w);
		};
		return [
			this.fg("toolTitle", `┌─${bar}─┐`),
			`${this.fg("toolTitle", "│ ")}${pad(this.fg("toolTitle", title))}${this.fg("toolTitle", " │")}`,
			this.fg("toolTitle", `├─${bar}─┤`),
			...body.map((l) => `${this.fg("toolTitle", "│ ")}${pad(l)}${this.fg("toolTitle", " │")}`),
			this.fg("toolTitle", `├─${bar}─┤`),
			`${this.fg("toolTitle", "│ ")}${pad(this.fg("dim", footer))}${this.fg("toolTitle", " │")}`,
			this.fg("toolTitle", `└─${bar}─┘`),
		];
	}
}
