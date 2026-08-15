/**
 * claude-footer - Claude Code-style single-line footer for pi, with color.
 *
 * Replaces pi's default two-line status bar (pwd/model line + stats line)
 * with one Claude Code-style line, using theme tokens so it adapts to the
 * active (dark/light) theme:
 *
 *     ~/repos/dotfiles (main) · deepseek-v4-flash · high        $0.03 · ↑1.2k ↓3.4k · 12.3%/200k
 *
 * - LEFT: ~-relative cwd (dim), git branch (accent highlight), then the
 *   model id in bold accent (the session identity), with a muted
 *   `(provider) ` prefix when more than one provider is available. When the
 *   model supports reasoning, the thinking level follows, colored by its
 *   theme token (thinkingMinimal..thinkingMax), mirroring the editor border.
 * - RIGHT (right-aligned): cost (muted), token arrows (accent glyphs, dim
 *   numbers), and the context gauge — accent while healthy, warning > 70%,
 *   error > 90% — with the window size in dim.
 * - Extension statuses (from ctx.ui.setStatus) get their own dim line below,
 *   sorted by key, only when at least one is set.
 *
 * formatTokens and formatCwdForFooter are not exported from the pi package,
 * so they are re-implemented here mirroring the default footer.
 */

import { isAbsolute, relative, resolve, sep } from "node:path";
import type { Model, Usage } from "@earendil-works/pi-ai";
import type { ExtensionAPI, ThemeColor } from "@earendil-works/pi-coding-agent";
import type { TUI } from "@earendil-works/pi-tui";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";

// ---- helpers (semantics copied from the default footer) ----

/** Format token counts for compact footer display. */
function formatTokens(count: number): string {
	if (count < 1000) return count.toString();
	if (count < 10000) return `${(count / 1000).toFixed(1)}k`;
	if (count < 1000000) return `${Math.round(count / 1000)}k`;
	if (count < 10000000) return `${(count / 1000000).toFixed(1)}M`;
	return `${Math.round(count / 1000000)}M`;
}

/** Replace the home directory with `~`. Mirrors the default footer exactly. */
function formatCwdForFooter(cwd: string, home: string | undefined): string {
	if (!home) return cwd;
	const resolvedCwd = resolve(cwd);
	const resolvedHome = resolve(home);
	const relativeToHome = relative(resolvedHome, resolvedCwd);
	const isInsideHome =
		relativeToHome === "" ||
		(relativeToHome !== ".." && !relativeToHome.startsWith(`..${sep}`) && !isAbsolute(relativeToHome));
	if (!isInsideHome) return cwd;
	return relativeToHome === "" ? "~" : `~${sep}${relativeToHome}`;
}

/**
 * Sanitize status text for a single line: strip newlines/tabs/CR, then
 * collapse repeated spaces. ANSI codes from setStatus callers are kept.
 */
function sanitizeStatusText(text: string): string {
	return text.replace(/[\r\n\t]/g, " ").replace(/ +/g, " ").trim();
}

/**
 * $ formatting: >= $0.01 uses 2 decimals; >= $0.0005 uses 3; anything
 * smaller (but still positive) uses up to 6 decimals with trailing zeros
 * stripped. If that still renders as "" or "0" (costs < 0.0000005 are not
 * representable at 6 decimals), escalate to more decimals, up to 15, so a
 * positive cost never displays as zero. (The $ segment is only shown when
 * cost > 0.)
 */
function formatCost(cost: number): string {
	if (cost >= 0.01) return cost.toFixed(2);
	if (cost >= 0.0005) return cost.toFixed(3);
	let s = (cost + Number.EPSILON).toFixed(6).replace(/0+$/, "").replace(/\.$/, "");
	for (let d = 7; d <= 15 && (s === "" || s === "0"); d++) {
		s = (cost + Number.EPSILON).toFixed(d).replace(/0+$/, "").replace(/\.$/, "");
	}
	return s;
}

/** Theme token per thinking level, mirroring the editor border colors. */
const thinkingColors: Record<string, ThemeColor> = {
	off: "dim",
	minimal: "thinkingMinimal",
	low: "thinkingLow",
	medium: "thinkingMedium",
	high: "thinkingHigh",
	xhigh: "thinkingXhigh",
	max: "thinkingMax",
};

export default function (pi: ExtensionAPI): void {
	// Current model and thinking level, kept in sync with ctx and their select
	// events so the footer shows the freshly cycled values immediately.
	let currentModel: Model<any> | undefined;
	let currentThinkingLevel: string | undefined;
	// Captured from the footer factory; used to request re-renders.
	let tuiRef: TUI | undefined;

	pi.on("model_select", (event) => {
		currentModel = event.model;
		tuiRef?.requestRender();
	});

	pi.on("thinking_level_select", (event) => {
		currentThinkingLevel = event.level;
		tuiRef?.requestRender();
	});

	// Install (or re-install) the footer on every session start. Re-setting is
	// safe: setExtensionFooter disposes the previous custom footer first, and
	// the fresh ctx carries the new session manager / model.
	pi.on("session_start", (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		currentModel = ctx.model;
		currentThinkingLevel = ctx.thinkingLevel;

		ctx.ui.setFooter((tui, theme, footerData) => {
			tuiRef = tui;
			const unsubBranch = footerData.onBranchChange(() => tui.requestRender());

			return {
				dispose() {
					unsubBranch();
				},
				invalidate() {
					// Everything is recomputed fresh on each render; nothing to do.
				},
				render(width: number): string[] {
					// Cumulative usage across all session entries, mirroring the
					// default footer (assistant, toolResult, branch_summary, compaction).
					let input = 0;
					let output = 0;
					let cost = 0;
					for (const entry of ctx.sessionManager.getEntries()) {
						let usage: Usage | undefined;
						if (entry.type === "message") {
							if (entry.message.role === "assistant") usage = entry.message.usage;
							else if (entry.message.role === "toolResult") usage = entry.message.usage;
						} else if (entry.type === "branch_summary" || entry.type === "compaction") {
							usage = entry.usage;
						}
						if (usage) {
							input += usage.input;
							output += usage.output;
							cost += usage.cost?.total ?? 0;
						}
					}

					// LEFT: ~-relative cwd (dim) · git branch (accent highlight) ·
					// provider (muted) · model (bold accent) · thinking level
					// (colored by its theme token, like the editor border).
					const cwd = formatCwdForFooter(
						ctx.sessionManager.getCwd(),
						process.env.HOME || process.env.USERPROFILE,
					);
					const branch = footerData.getGitBranch();
					const providerPrefix =
						footerData.getAvailableProviderCount() > 1 && currentModel ? `(${currentModel.provider})` : "";

					const leftParts: string[] = [theme.fg("dim", cwd)];
					if (branch) leftParts.push(theme.fg("accent", ` (${branch})`));
					if (providerPrefix) leftParts.push(theme.fg("muted", ` (${providerPrefix})`));
					leftParts.push(` ${theme.bold(theme.fg("accent", currentModel?.id ?? "no-model"))}`);
					if (currentModel?.reasoning) {
						const level = currentThinkingLevel ?? "off";
						leftParts.push(` ${theme.fg("dim", "·")} ${theme.fg(thinkingColors[level] ?? "dim", level)}`);
					}
					const left = leftParts.join("");

					// RIGHT: cost · ↑in ↓out · context%. Each segment gets its own
					// theme.fg() call: colors end with a reset, which would kill an
					// outer dim wrapper, so segments are dimmed independently.
					const contextUsage = ctx.getContextUsage();
					const contextWindow = contextUsage?.contextWindow ?? currentModel?.contextWindow ?? 0;
					const percent = contextUsage?.percent ?? null;
					const windowStr = formatTokens(contextWindow);

					const stats: string[] = [];
					// Cost: muted (one step brighter than the dim tokens) so the
					// amount spent reads as info, not noise.
					if (cost > 0) stats.push(theme.fg("muted", `$${formatCost(cost)}`));
					// Token arrows: accent glyphs with dim numbers. Each arrow is
					// pushed only when that counter is > 0, but the pair stays one
					// segment (joined by a single space) so the ` · ` layout between
					// cost/arrows/context is unchanged.
					const tokenParts: string[] = [];
					if (input > 0)
						tokenParts.push(`${theme.fg("accent", "↑")}${theme.fg("dim", formatTokens(input))}`);
					if (output > 0)
						tokenParts.push(`${theme.fg("accent", "↓")}${theme.fg("dim", formatTokens(output))}`);
					if (tokenParts.length > 0) stats.push(tokenParts.join(" "));
					// Context gauge: accent while healthy, warning > 70%, error > 90%,
					// with the window size dimmed.
					if (percent === null) {
						stats.push(theme.fg("dim", `?/${windowStr}`));
					} else {
						const levelColor: ThemeColor = percent > 90 ? "error" : percent > 70 ? "warning" : "accent";
						stats.push(
							theme.fg(levelColor, `${percent.toFixed(1)}%`) + theme.fg("dim", `/${windowStr}`),
						);
					}
					const right = stats.join(theme.fg("dim", " · "));

					// Pad between left and right (at least one space). When they
					// don't fit, truncate the LEFT side first (keeping the stats
					// intact), then the RIGHT side only if the left is gone or the
					// result still overflows. Every returned line stays <= width.
					const leftWidth = visibleWidth(left);
					const rightWidth = visibleWidth(right);
					let leftLine = left;
					let rightLine = right;
					let leftLineWidth = leftWidth;
					let rightLineWidth = rightWidth;
					if (leftWidth + rightWidth + 1 > width) {
						const availLeft = Math.max(0, width - rightWidth - 1);
						leftLine = truncateToWidth(left, availLeft, theme.fg("dim", "…"));
						leftLineWidth = visibleWidth(leftLine);
						if (leftLine === "" || leftLineWidth + rightLineWidth + 1 > width) {
							const remaining = Math.max(0, width - leftLineWidth - 1);
							rightLine = truncateToWidth(right, remaining, theme.fg("dim", "…"));
							rightLineWidth = visibleWidth(rightLine);
						}
					}
					const pad = " ".repeat(Math.max(1, width - leftLineWidth - rightLineWidth));
					const lines = [leftLine + pad + rightLine];

					// Extension statuses on their own dim line, sorted by key,
					// only when at least one status is set.
					const statuses = footerData.getExtensionStatuses();
					if (statuses.size > 0) {
						const sorted = Array.from(statuses.entries())
							.sort(([a], [b]) => a.localeCompare(b))
							.map(([, text]) => sanitizeStatusText(text));
						lines.push(truncateToWidth(theme.fg("dim", sorted.join(" ")), width, theme.fg("dim", "...")));
					}

					return lines;
				},
			};
		});
	});
}
