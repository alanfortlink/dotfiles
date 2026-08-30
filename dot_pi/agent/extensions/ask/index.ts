/**
 * `ask` - let the model put structured questions to the user and block on the answer.
 *
 * Modelled on Claude Code's AskUserQuestion: 1-4 questions, each with 2-4
 * options, each question either single-select or multi-select. Every question
 * additionally offers "Other", which turns that row into a text field. The model
 * cannot suppress it - if it asks, the human can always answer in their own words.
 *
 * Unopinionated: there are no question templates and no canned option sets. The
 * model writes the questions and the options; this extension renders them,
 * collects the choices, and reports back exactly what was picked.
 *
 * Blocking is the point. The model asked something it cannot answer itself, so
 * the turn is held until the user answers or cancels. Cancelling returns a
 * result that says so plainly, so the model proceeds on its own rather than
 * hanging or silently guessing.
 */

import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Input, Key, matchesKey, Text, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import { type Static, Type } from "typebox";

/** Chip labels are rendered in a single tab bar row; longer ones get cut. */
const MAX_HEADER_WIDTH = 12;
/** Digit shortcuts are 1-9, and a question can never have more rows than that. */
const DIGITS = ["1", "2", "3", "4", "5", "6", "7", "8", "9"] as const;
const OTHER_LABEL = "Other (write your own)";

// ---- schemas ----

const OptionSchema = Type.Object({
	label: Type.String({ description: "Short display label for this choice." }),
	description: Type.Optional(
		Type.String({ description: "One line explaining what picking this means. Shown under the label." }),
	),
});

const QuestionSchema = Type.Object({
	question: Type.String({ description: "The full question text shown to the user." }),
	header: Type.String({
		description: `Short chip label naming the decision, e.g. "Auth method". Max ${MAX_HEADER_WIDTH} characters.`,
	}),
	multiSelect: Type.Optional(
		Type.Boolean({
			description: "false (default): the user picks exactly one option. true: the user picks any number of options.",
		}),
	),
	options: Type.Array(OptionSchema, {
		minItems: 2,
		maxItems: 4,
		description: "The 2-4 choices you are offering. An 'Other' free-text choice is always added for you.",
	}),
});

const AskParams = Type.Object({
	questions: Type.Array(QuestionSchema, {
		minItems: 1,
		maxItems: 4,
		description: "1-4 questions, asked in order.",
	}),
});

// ---- types ----

interface NormOption {
	label: string;
	description?: string;
}

interface NormQuestion {
	question: string;
	header: string;
	multiSelect: boolean;
	options: NormOption[];
}

interface Choice {
	label: string;
	/** 1-based position in the rendered list, or null for free text. */
	index: number | null;
	custom: boolean;
}

interface AnswerDetail {
	header: string;
	question: string;
	multiSelect: boolean;
	choices: Choice[];
}

interface AskDetails {
	answers: AnswerDetail[];
	cancelled: boolean;
}

// ---- normalization ----

/**
 * Collapse whitespace in every model-supplied string. A newline inside a label
 * would otherwise split one rendered line into two, breaking the Component
 * contract from the inside.
 */
function clean(text: string): string {
	return text.replace(/\s+/g, " ").trim();
}

function normalize(questions: Static<typeof QuestionSchema>[]): NormQuestion[] {
	return questions.map((q, i) => ({
		question: clean(q.question),
		header: truncateToWidth(clean(q.header) || `Q${i + 1}`, MAX_HEADER_WIDTH),
		multiSelect: q.multiSelect === true,
		options: q.options.map((o) => ({
			label: clean(o.label),
			description: o.description ? clean(o.description) : undefined,
		})),
	}));
}

export default function ask(pi: ExtensionAPI) {
	pi.registerTool({
		name: "ask",
		label: "Ask",
		description: [
			"Put 1-4 structured multiple-choice questions to the user and wait for the answers.",
			"Each question is either single-select (the user picks one option) or multiSelect (the user picks any number).",
			"An 'Other' free-text choice is appended to every question automatically - do not add one yourself.",
			"BLOCKING: the turn is held until the user answers or cancels. If they cancel you get told so, and you continue on your own judgement.",
		].join(" "),
		promptSnippet: "Ask the user structured multiple-choice questions and wait for the answers",
		promptGuidelines: [
			"Use ask when a decision is genuinely the user's to make and different answers would lead to materially different work; do not use ask for things you can determine from the code, the request, or a sensible default.",
			"Each ask question needs 2-4 concrete, mutually exclusive options with a short description of what picking it means; if the choices are not exclusive, set multiSelect.",
			"Batch related decisions into one ask call (up to 4 questions) rather than asking one at a time.",
			"ask always offers the user a free-text 'Other' choice, so never spend an option slot on 'other', 'something else', or 'let me type'.",
			"If ask reports that the user cancelled, do not call ask again for the same decision - pick the most reasonable option, say which assumption you made, and carry on.",
		],
		parameters: AskParams,
		executionMode: "sequential",

		async execute(_toolCallId, params, signal, _onUpdate, ctx) {
			if (ctx.mode !== "tui" || !ctx.hasUI) {
				throw new Error(
					`ask needs an interactive terminal, but this session is running in "${ctx.mode}" mode with no UI. ` +
						"There is nobody to answer. Decide yourself, state the assumption you are making, and continue.",
				);
			}
			if (params.questions.length === 0) {
				throw new Error("ask requires at least one question.");
			}

			const questions = normalize(params.questions);

			const details = await ctx.ui.custom<AskDetails>((tui, theme, _kb, done) => {
				// Per-question state. `checked` holds indices into question.options;
				// `custom` holds the free text from the Other row when present.
				const state = questions.map(() => ({
					cursor: 0,
					checked: new Set<number>(),
					custom: null as string | null,
					confirmed: false,
				}));

				const multiQuestion = questions.length > 1;
				const submitTab = questions.length; // only reachable when multiQuestion
				let tab = 0;
				/** Index of the question whose Other row is being typed into, or null. */
				let editing: number | null = null;
				let notice: string | null = null;
				/** Keyed by width and focus: the TUI re-renders on either without invalidating. */
				let cache: { width: number; focused: boolean; lines: string[] } | undefined;

				// One input per question, rendered in place of that question's Other row.
				// Keeping them separate means each keeps its own cursor position.
				const inputs = questions.map(() => new Input());

				function refresh() {
					cache = undefined;
					tui.requestRender();
				}

				function rowCount(qi: number): number {
					return questions[qi].options.length + 1; // + Other
				}

				function isOtherRow(qi: number, row: number): boolean {
					return row === questions[qi].options.length;
				}

				function hasSelection(qi: number): boolean {
					return state[qi].checked.size > 0 || state[qi].custom !== null;
				}

				function answersOf(qi: number): Choice[] {
					const q = questions[qi];
					const s = state[qi];
					const choices: Choice[] = [];
					for (let i = 0; i < q.options.length; i++) {
						if (s.checked.has(i)) choices.push({ label: q.options[i].label, index: i + 1, custom: false });
					}
					if (s.custom !== null) choices.push({ label: s.custom, index: null, custom: true });
					return choices;
				}

				function finish(cancelled: boolean) {
					done({
						cancelled,
						answers: cancelled
							? []
							: questions.map((q, qi) => ({
									header: q.header,
									question: q.question,
									multiSelect: q.multiSelect,
									choices: answersOf(qi),
								})),
					});
				}

				/** Confirm the current question and move on, submitting when it was the only one. */
				function confirm(qi: number) {
					state[qi].confirmed = true;
					notice = null;
					if (!multiQuestion) {
						finish(false);
						return;
					}
					const next = state.findIndex((s, i) => i !== qi && !s.confirmed);
					tab = next === -1 ? submitTab : next;
					refresh();
				}

				/** Turn the Other row of question `qi` into a text field. */
				function openInput(qi: number) {
					editing = qi;
					inputs[qi].setValue(state[qi].custom ?? "");
					state[qi].cursor = questions[qi].options.length;
					notice = null;
					refresh();
				}

				/**
				 * Act on a row: toggle (multi), select (single), or open the Other row's
				 * text field. `advance` is what separates Enter from Space in single-select:
				 * Enter commits the question and moves on, Space just sets the choice and
				 * leaves you on the question.
				 *
				 * The Other row is the one exception: only Space opens its text field.
				 * Enter never opens it - it confirms the stored free text and moves on,
				 * or points at Space when nothing was written yet.
				 */
				function activate(qi: number, row: number, advance: boolean) {
					const q = questions[qi];
					const s = state[qi];
					if (isOtherRow(qi, row)) {
						if (advance) {
							if (s.custom !== null) {
								confirm(qi);
							} else {
								notice = "Nothing written yet - press Space to write your own answer.";
								refresh();
							}
							return;
						}
						openInput(qi);
						return;
					}
					if (q.multiSelect) {
						if (s.checked.has(row)) s.checked.delete(row);
						else s.checked.add(row);
						notice = null;
						refresh();
						return;
					}
					s.checked.clear();
					s.checked.add(row);
					s.custom = null;
					if (advance) {
						confirm(qi);
						return;
					}
					notice = null;
					refresh();
				}

				for (let qi = 0; qi < inputs.length; qi++) {
					// The input keeps its text: it is the Other row's value, not a scratch buffer.
					inputs[qi].onSubmit = (value) => {
						const text = clean(value);
						const q = questions[qi];
						const s = state[qi];
						editing = null;
						s.custom = text || null;
						inputs[qi].setValue(s.custom ?? "");
						if (!text) {
							// Enter with an empty field records nothing; back on the options.
							refresh();
							return;
						}
						// Enter in the field always confirms the question and moves on,
						// exactly like Enter anywhere else in the dialog.
						if (!q.multiSelect) s.checked.clear();
						confirm(qi);
					};
					// Esc drops the draft and puts back whatever was already stored.
					inputs[qi].onEscape = () => {
						editing = null;
						inputs[qi].setValue(state[qi].custom ?? "");
						refresh();
					};
				}

				function handleInput(data: string) {
					if (editing !== null) {
						// Input handles its own Enter and Esc, via onSubmit/onEscape above.
						inputs[editing].handleInput(data);
						refresh();
						return;
					}

					if (matchesKey(data, Key.escape)) {
						finish(true);
						return;
					}

					if (multiQuestion) {
						if (matchesKey(data, Key.tab) || matchesKey(data, Key.right)) {
							tab = (tab + 1) % (submitTab + 1);
							notice = null;
							refresh();
							return;
						}
						if (matchesKey(data, Key.shift("tab")) || matchesKey(data, Key.left)) {
							tab = (tab - 1 + submitTab + 1) % (submitTab + 1);
							notice = null;
							refresh();
							return;
						}
					}

					if (tab === submitTab && multiQuestion) {
						if (matchesKey(data, Key.enter)) {
							const missing = questions.filter((_q, i) => !state[i].confirmed);
							if (missing.length === 0) {
								finish(false);
								return;
							}
							notice = `Still to answer: ${missing.map((q) => q.header).join(", ")}`;
							refresh();
						}
						return;
					}

					const qi = tab;
					const q = questions[qi];
					const s = state[qi];
					const rows = rowCount(qi);

					if (matchesKey(data, Key.up) || matchesKey(data, "k")) {
						s.cursor = (s.cursor - 1 + rows) % rows;
						refresh();
						return;
					}
					if (matchesKey(data, Key.down) || matchesKey(data, "j")) {
						s.cursor = (s.cursor + 1) % rows;
						refresh();
						return;
					}

					for (let i = 0; i < rows && i < DIGITS.length; i++) {
						if (matchesKey(data, DIGITS[i])) {
							s.cursor = i;
							activate(qi, i, !q.multiSelect);
							return;
						}
					}

					// Space never leaves the question: it toggles (multi) or sets the
					// choice (single) and lets you keep looking at the options.
					if (matchesKey(data, Key.space)) {
						if (isOtherRow(qi, s.cursor) && s.custom !== null) {
							s.custom = null; // second press on a filled Other row clears it
							notice = null;
							refresh();
							return;
						}
						activate(qi, s.cursor, false);
						return;
					}

					if (matchesKey(data, Key.enter)) {
						if (!q.multiSelect) {
							activate(qi, s.cursor, true);
							return;
						}
						// Enter never opens the Other field in multi-select either: with
						// nothing picked it falls through to the warning below.
						if (!hasSelection(qi)) {
							notice = "Pick at least one option, or choose Other and write your own answer.";
							refresh();
							return;
						}
						confirm(qi);
					}
				}

				function render(width: number): string[] {
					const W = Math.max(1, width);
					if (cache && cache.width === W && cache.focused === self.focused) return cache.lines;

					const lines: string[] = [];

					function push(text: string) {
						lines.push(...wrapTextWithAnsi(text, W));
					}

					/** Wrap `text` into the space left by `prefix`, indenting continuations to match. */
					function pushWith(prefix: string, text: string) {
						const prefixWidth = visibleWidth(prefix);
						if (prefixWidth >= W) {
							push(prefix + text);
							return;
						}
						const wrapped = wrapTextWithAnsi(text, W - prefixWidth);
						const indent = " ".repeat(prefixWidth);
						for (let i = 0; i < wrapped.length; i++) {
							lines.push(`${i === 0 ? prefix : indent}${wrapped[i]}`);
						}
					}

					push(theme.fg("accent", "─".repeat(W)));

					if (multiQuestion) {
						const chips: string[] = [];
						for (let i = 0; i < questions.length; i++) {
							const box = state[i].confirmed ? "■" : "□";
							const text = ` ${box} ${questions[i].header} `;
							chips.push(
								i === tab ? theme.bg("selectedBg", theme.fg("text", text)) : theme.fg(state[i].confirmed ? "success" : "muted", text),
							);
						}
						const ready = state.every((s) => s.confirmed);
						const submitText = " ✓ Submit ";
						chips.push(
							tab === submitTab
								? theme.bg("selectedBg", theme.fg("text", submitText))
								: theme.fg(ready ? "success" : "dim", submitText),
						);
						pushWith(" ", chips.join(" "));
						lines.push("");
					}

					if (tab === submitTab && multiQuestion) {
						pushWith(" ", theme.bold(theme.fg("accent", "Review and submit")));
						lines.push("");
						for (let i = 0; i < questions.length; i++) {
							const choices = answersOf(i);
							const summary = state[i].confirmed
								? choices.map((c) => (c.custom ? `"${c.label}"` : c.label)).join(", ")
								: theme.fg("warning", "unanswered");
							pushWith(" ", `${theme.fg("muted", `${questions[i].header}: `)}${theme.fg("text", summary)}`);
						}
					} else {
						const q = questions[tab];
						const s = state[tab];
						pushWith(" ", theme.fg("text", q.question));
						lines.push("");

						for (let row = 0; row < rowCount(tab); row++) {
							const other = isOtherRow(tab, row);
							const checked = other ? s.custom !== null : s.checked.has(row);
							const onCursor = row === s.cursor;
							const mark = q.multiSelect ? (checked ? "[x] " : "[ ] ") : checked ? "(•) " : "( ) ";
							const bullet = onCursor ? "❯ " : "  ";
							const plainPrefix = `${bullet}${mark}${row + 1}. `;
							const prefix =
								theme.fg(onCursor ? "accent" : "dim", bullet) +
								theme.fg(checked ? "success" : "dim", mark) +
								theme.fg(onCursor || checked ? "accent" : "text", `${row + 1}. `);

							// The Other row turns into a text field in place while it is being typed into.
							if (other && editing === tab) {
								const input = inputs[tab];
								input.focused = self.focused;
								const field = input.render(Math.max(1, W - visibleWidth(plainPrefix)))[0];
								lines.push(prefix + field);
								continue;
							}

							const label = other ? (s.custom !== null ? `${OTHER_LABEL}: ${s.custom}` : OTHER_LABEL) : q.options[row].label;
							pushWith(prefix, theme.fg(onCursor || checked ? "accent" : "text", label));
							const description = other ? undefined : q.options[row].description;
							if (description) {
								pushWith(" ".repeat(visibleWidth(plainPrefix)), theme.fg("muted", description));
							}
						}
					}

					lines.push("");
					if (notice) {
						pushWith(" ", theme.fg("warning", notice));
					}
					pushWith(" ", theme.fg("dim", helpText()));
					push(theme.fg("accent", "─".repeat(W)));

					cache = { width: W, focused: self.focused, lines };
					return lines;
				}

				function helpText(): string {
					if (editing !== null) return "Type your answer • Enter submit • Esc back to the options";
					if (tab === submitTab && multiQuestion) return "Enter submit • Tab/←→ back to a question • Esc cancel";
					const q = questions[tab];
					const nav = multiQuestion ? "↑↓/jk move • Tab/←→ question" : "↑↓/jk move";
					const pick = q.multiSelect ? "Space toggle • Enter confirm" : "Space select • Enter confirm & continue";
					return `${nav} • ${pick} • 1-${rowCount(tab)} jump • Esc cancel`;
				}

				// The agent can be aborted while the dialog is open (ctrl+c, /abort). That
				// tears the turn down, so treat it exactly like the user cancelling.
				const onAbort = () => finish(true);
				signal?.addEventListener("abort", onAbort, { once: true });

				// `focused` makes this a Focusable, so the TUI keeps it up to date and can
				// place the hardware cursor on the embedded Input for IME input.
				const self = {
					focused: false,
					render,
					invalidate: () => {
						cache = undefined;
						for (const input of inputs) input.invalidate();
					},
					handleInput,
					dispose: () => signal?.removeEventListener("abort", onAbort),
				};
				return self;
			});

			if (details.cancelled) {
				return {
					content: [
						{
							type: "text" as const,
							text:
								"User cancelled - no questions were answered. " +
								"Do not ask again about this. Choose the most reasonable option yourself, say which assumption you made, and continue.",
						},
					],
					details,
				};
			}

			const blocks = details.answers.map((a, i) => {
				const head = `${i + 1}. [${a.header}] ${a.question}${a.multiSelect ? " (multi-select)" : ""}`;
				const picked = a.choices.map((c) => (c.custom ? `free text: "${c.label}"` : `${c.index}. ${c.label}`));
				return `${head}\n   chose: ${picked.join(" | ")}`;
			});

			return {
				content: [{ type: "text" as const, text: `User answered:\n\n${blocks.join("\n\n")}` }],
				details,
			};
		},

		renderCall(args, theme) {
			const questions = args.questions ?? [];
			const headers = questions.map((q) => clean(q.header)).join(", ");
			let text =
				theme.fg("toolTitle", theme.bold("ask ")) +
				theme.fg("accent", `${questions.length} question${questions.length === 1 ? "" : "s"}`);
			if (headers) text += theme.fg("dim", ` (${headers})`);
			return new Text(text, 0, 0);
		},

		renderResult(result, _options, theme) {
			const details = result.details as AskDetails | undefined;
			if (!details) {
				const first = result.content[0];
				return new Text(first?.type === "text" ? first.text : "", 0, 0);
			}
			if (details.cancelled) {
				return new Text(theme.fg("warning", "✗ Cancelled by user"), 0, 0);
			}
			const lines = details.answers.map((a) => {
				const picked = a.choices
					.map((c) => (c.custom ? `${theme.fg("muted", "(wrote) ")}${c.label}` : `${c.index}. ${c.label}`))
					.join(theme.fg("dim", " + "));
				return `${theme.fg("success", "✓ ")}${theme.fg("accent", a.header)}${theme.fg("muted", ": ")}${picked}`;
			});
			return new Text(lines.join("\n"), 0, 0);
		},
	});
}
