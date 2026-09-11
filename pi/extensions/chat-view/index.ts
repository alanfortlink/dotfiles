/**
 * chat-view - make the pi transcript read like a chat.
 *
 * Display-only. Session, LLM context and every other extension are untouched.
 *
 *   You                                  ← right-aligned, filled bubble
 *                     ┌──────────────────┐   (userMessageBg), shrink-to-fit,
 *                     │ fix the tests    │   capped at USER_MAX_SHARE of the
 *                     └──────────────────┘   terminal width
 *
 *   ● pi · glm-5.3-flash                 ← left-aligned, accent bar down the
 *   ▎ Running them now…                    side, capped at ASSISTANT_MAX_SHARE.
 *   ▎ Two failures, both in …              The label appears once per turn
 *                                          (first assistant text after a user
 *                                          message); later chunks of the same
 *                                          turn keep only the bar.
 *
 * pi has no hook for message layout, so UserMessageComponent.render and
 * AssistantMessageComponent.render are patched on their prototypes. The
 * assistant patch post-processes whatever the inner render produced, so it
 * composes with compact-view in either load order. Container.addChild is
 * patched to record a parent pointer, so a message can look at its chat
 * siblings to decide whether it opens a turn.
 */

import { AssistantMessageComponent, type ExtensionAPI, ToolExecutionComponent, UserMessageComponent } from "@earendil-works/pi-coding-agent";
import { Container, Spacer, stripTerminalSequences, Text, visibleWidth } from "@earendil-works/pi-tui";

// ---- look ----

/** Name shown in the user label. */
const USER_NAME = "You";
/** Name shown in the assistant label; the model id follows it, muted. */
const ASSISTANT_NAME = "pi";
/** Bullet before the assistant name. */
const ASSISTANT_DOT = "●";
/** Bar drawn down the left side of assistant text. */
const ASSISTANT_BAR = "▎";
/** Max width of the user bubble / assistant column, as a share of the terminal width. */
const USER_MAX_SHARE = 0.72;
const ASSISTANT_MAX_SHARE = 0.9;
/** Never squeeze a bubble narrower than this (columns). */
const USER_MIN_WIDTH = 20;
/** Theme colors (keys of pi's theme). */
const USER_LABEL_FG = "accent";
const ASSISTANT_LABEL_FG = "accent";
const ASSISTANT_MODEL_FG = "dim";
const ASSISTANT_BAR_FG = "accent";

// ---- state ----

type Ui = { theme: { fg: (c: any, t: string) => string; bg: (c: any, t: string) => string; bold: (t: string) => string } };
let ui: Ui | undefined;
let modelId: string | undefined;

const OSC133_ZONE_START = "\x1b]133;A\x07";
const OSC133_ZONE_END = "\x1b]133;B\x07";
const OSC133_ZONE_FINAL = "\x1b]133;C\x07";

const PARENT = Symbol.for("chat-view.parent");

function patchContainer(): void {
	const proto = Container.prototype as any;
	const originalAddChild = (proto.__chatViewOriginalAddChild ??= proto.addChild);
	proto.addChild = function (this: any, child: any) {
		if (child && typeof child === "object" && Object.isExtensible(child)) child[PARENT] = this;
		return originalAddChild.call(this, child);
	};
}

const isBlank = (l: string | undefined): boolean => l !== undefined && stripTerminalSequences(l).trim() === "";
const hasText = (message: any): boolean => (message?.content ?? []).some((c: any) => c?.type === "text" && c.text?.trim());

/** Is this the first assistant message with text since the last non-assistant chat entry? */
function opensTurn(component: any): boolean {
	const list: any[] | undefined = component?.[PARENT]?.children;
	if (!list) return true;
	for (let i = list.indexOf(component) - 1; i >= 0; i--) {
		const c = list[i];
		if (c instanceof AssistantMessageComponent) {
			if (hasText((c as any).lastMessage)) return false;
			continue;
		}
		if (c instanceof ToolExecutionComponent || c instanceof Spacer || c instanceof Text) continue;
		return true;
	}
	return true;
}

function zone(lines: string[]): string[] {
	if (lines.length === 0) return lines;
	lines[0] = OSC133_ZONE_START + lines[0];
	lines[lines.length - 1] = OSC133_ZONE_END + OSC133_ZONE_FINAL + lines[lines.length - 1];
	return lines;
}

/** Markdown fences are syntax, not content; don't put the chat gutter in code blocks. */
function isCodeFence(line: string): boolean {
	return /^(?:`{3,}|~{3,})[^`~]*$/.test(stripTerminalSequences(line).trim());
}

// ---- user ----

function patchUserMessage(): void {
	const proto = UserMessageComponent.prototype as any;
	const originalRender = (proto.__chatViewOriginalRender ??= proto.render);
	proto.render = function (this: any, width: number): string[] {
		const box = this.children?.[0];
		const md = box?.children?.[0];
		if (!ui || !box || !md || width < USER_MIN_WIDTH + 4) return originalRender.call(this, width);
		const pad: number = box.paddingX ?? this.outputPad ?? 1;
		const maxBubble = Math.max(USER_MIN_WIDTH, Math.min(width, Math.floor(width * USER_MAX_SHARE)));
		// Shrink to fit: measure the text at the cap, then size the bubble to its widest line.
		const measured: string[] = md.render(Math.max(1, maxBubble - pad * 2));
		const natural = measured.reduce((w, l) => Math.max(w, visibleWidth(stripTerminalSequences(l).replace(/\s+$/, ""))), 0) + pad * 2;
		const bubble = Math.max(USER_MIN_WIDTH, Math.min(maxBubble, natural));
		const body: string[] = box.render(bubble);
		const indent = " ".repeat(Math.max(0, width - bubble));
		const label = ui.theme.bold(ui.theme.fg(USER_LABEL_FG, USER_NAME));
		const labelLine = " ".repeat(Math.max(0, width - visibleWidth(label))) + label;
		return zone([labelLine, ...body.map((l) => indent + l)]);
	};
}

// ---- assistant ----

function patchAssistantMessage(): void {
	const proto = AssistantMessageComponent.prototype as any;
	const originalRender = (proto.__chatViewOriginalRender ??= proto.render);
	proto.render = function (this: any, width: number): string[] {
		if (!ui) return originalRender.call(this, width);
		// The bar alone: the message's own outputPad already separates it from the text.
		const gutter = ui.theme.fg(ASSISTANT_BAR_FG, ASSISTANT_BAR);
		const gutterWidth = visibleWidth(ASSISTANT_BAR);
		const inner = Math.max(10, Math.min(width - gutterWidth, Math.floor(width * ASSISTANT_MAX_SHARE)));
		const lines: string[] = originalRender.call(this, inner);
		if (lines.length === 0) return lines;
		// Carry the escape-only content (OSC 133 markers) of leading blank lines into one blank.
		let i = 0;
		let carry = "";
		while (i < lines.length - 1 && isBlank(lines[i])) carry += lines[i++];
		const rest = lines.slice(i);
		// Trailing blank lines stay blank (no bar) so the block ends cleanly.
		let end = rest.length;
		while (end > 1 && isBlank(rest[end - 1])) end--;
		const out: string[] = [carry];
		if (hasText(this.lastMessage) && opensTurn(this)) {
			const name = ui.theme.bold(ui.theme.fg(ASSISTANT_LABEL_FG, ASSISTANT_NAME));
			const model = modelId ? ui.theme.fg(ASSISTANT_MODEL_FG, ` · ${modelId}`) : "";
			out.push(ui.theme.fg(ASSISTANT_LABEL_FG, ASSISTANT_DOT) + " " + name + model);
		}
		let inCodeBlock = false;
		for (let j = 0; j < end; j++) {
			const fence = isCodeFence(rest[j]);
			// A gutter inside a code block becomes part of copied shell commands.
			out.push((inCodeBlock || fence ? "" : gutter) + rest[j]);
			if (fence) inCodeBlock = !inCodeBlock;
		}
		for (let j = end; j < rest.length; j++) out.push(rest[j]);
		return out;
	};
}

// ---- extension ----

export default function chatView(pi: ExtensionAPI) {
	patchContainer();
	patchUserMessage();
	patchAssistantMessage();

	pi.on("session_start", (_event, ctx) => {
		if (!ctx.hasUI) return;
		ui = ctx.ui as unknown as Ui;
		modelId = ctx.model?.id;
	});
	pi.on("model_select", (event) => {
		modelId = event.model?.id;
	});
}
