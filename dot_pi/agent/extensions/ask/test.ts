/**
 * Headless test harness for the `ask` extension.
 *
 * pi loads extensions with jiti, so the same loader drives index.ts here without
 * a model, a terminal, or a running pi. The extension is handed a stub
 * ExtensionAPI to capture the tool, and a stub ctx whose ui.custom() hands back
 * the live component; from there the tests feed raw key sequences into
 * handleInput() and assert on render(width).
 *
 * Run: node test.ts
 */

import { execFileSync } from "node:child_process";
import { existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Locate the globally installed pi-coding-agent package, wherever it lives
 * (homebrew on macOS, mise/volta/nvm on Linux, npm root -g anywhere).
 */
function resolvePI(): string {
	const candidates = [
		process.env.PI_PACKAGE,
		"/opt/homebrew/lib/node_modules/@earendil-works/pi-coding-agent",
		"/usr/local/lib/node_modules/@earendil-works/pi-coding-agent",
		...(() => {
			try {
				const root = execFileSync("npm", ["root", "-g"], { encoding: "utf8" }).trim();
				return [join(root, "@earendil-works", "pi-coding-agent")];
			} catch {
				return [];
			}
		})(),
	].filter((c): c is string => !!c && existsSync(c));
	if (candidates.length === 0) {
		throw new Error(
			"Cannot locate the pi-coding-agent package. Set PI_PACKAGE to its path, or run `npm i -g @earendil-works/pi-coding-agent`.",
		);
	}
	return candidates[0];
}

const PI = resolvePI();
const HERE = dirname(fileURLToPath(import.meta.url));

const { createJiti } = await import(`${PI}/node_modules/jiti/lib/jiti.mjs`);
const jiti = createJiti(import.meta.url, {
	moduleCache: false,
	alias: {
		"@earendil-works/pi-coding-agent": `${PI}/dist/index.js`,
		"@earendil-works/pi-ai": `${PI}/node_modules/@earendil-works/pi-ai/dist/compat.js`,
		"@earendil-works/pi-tui": `${PI}/node_modules/@earendil-works/pi-tui/dist/index.js`,
		typebox: `${PI}/node_modules/typebox/build/index.mjs`,
	},
});

// ---- stubs ----

const KEY = {
	up: "\x1b[A",
	down: "\x1b[B",
	left: "\x1b[D",
	right: "\x1b[C",
	enter: "\r",
	escape: "\x1b",
	tab: "\t",
	shiftTab: "\x1b[Z",
	space: " ",
};

const theme = {
	fg: (_color: string, text: string) => `\x1b[38;5;39m${text}\x1b[39m`,
	bg: (_color: string, text: string) => `\x1b[48;5;236m${text}\x1b[49m`,
	bold: (text: string) => `\x1b[1m${text}\x1b[22m`,
};

const tui = {
	requestRender: () => {},
	terminal: { rows: 40, columns: 100 },
};

interface Harness {
	component: any;
	result: Promise<any>;
	feed: (...keys: string[]) => void;
	type: (text: string) => void;
	lines: (width?: number) => string[];
	plain: (width?: number) => string;
}

const extension = (await jiti.import(join(HERE, "index.ts"), { default: true })) as (api: any) => void;

let registered: any;
extension({
	registerTool: (definition: any) => {
		registered = definition;
	},
});

function open(params: any, signal?: AbortSignal): Harness {
	let component: any;
	const ctx = {
		mode: "tui",
		hasUI: true,
		ui: {
			custom: (factory: any) =>
				new Promise((resolve) => {
					component = factory(tui, theme, {}, resolve);
				}),
		},
	};
	const result = registered.execute("call-1", params, signal, undefined, ctx);
	if (!component) throw new Error("ui.custom was never called");
	return {
		component,
		result,
		feed: (...keys: string[]) => {
			for (const key of keys) component.handleInput(key);
		},
		type: (text: string) => {
			for (const ch of text) component.handleInput(ch);
		},
		lines: (width = 72) => component.render(width),
		plain: (width = 72) => stripAnsi(component.render(width).join("\n")),
	};
}

function stripAnsi(text: string): string {
	// biome-ignore lint/suspicious/noControlCharactersInRegex: stripping SGR for assertions
	return text.replace(/\x1b\[[0-9;]*[A-Za-z]/g, "");
}

// visibleWidth from the real TUI package, so wide/zero-width chars count as the TUI counts them.
const { visibleWidth } = (await jiti.import(`${PI}/node_modules/@earendil-works/pi-tui/dist/index.js`)) as {
	visibleWidth: (s: string) => number;
};

// ---- assertions ----

let failures = 0;
let checks = 0;

function check(label: string, ok: boolean, detail?: string) {
	checks++;
	if (ok) {
		console.log(`  ✓ ${label}`);
	} else {
		failures++;
		console.log(`  ✗ ${label}${detail ? `\n      ${detail}` : ""}`);
	}
}

function eq(label: string, actual: unknown, expected: unknown) {
	const a = JSON.stringify(actual);
	const b = JSON.stringify(expected);
	check(label, a === b, `expected ${b}\n      actual   ${a}`);
}

/** The Component contract: one terminal line per array entry, never wider than `width`. */
function checkLayout(label: string, h: Harness) {
	for (const width of [20, 34, 60, 72, 120]) {
		const lines = h.lines(width);
		const tooWide = lines.find((l: string) => visibleWidth(l) > width);
		const multiline = lines.find((l: string) => l.includes("\n"));
		check(
			`${label}: layout at width ${width}`,
			!tooWide && !multiline,
			tooWide
				? `line of visible width ${visibleWidth(tooWide)}: ${JSON.stringify(stripAnsi(tooWide))}`
				: multiline
					? `line contains a newline: ${JSON.stringify(stripAnsi(multiline))}`
					: undefined,
		);
	}
}

// ---- fixtures ----

const singleQuestion = {
	questions: [
		{
			question: "Which authentication method should the service use?",
			header: "Auth method",
			multiSelect: false,
			options: [
				{ label: "OAuth 2.0", description: "Delegate to an external identity provider." },
				{ label: "Session cookies", description: "Server-side sessions, cookie carries the id." },
				{ label: "Signed JWTs", description: "Stateless, but revocation gets awkward." },
			],
		},
	],
};

const multiQuestion = {
	questions: [
		{
			question: "Which observability features should be enabled at launch?",
			header: "Telemetry",
			multiSelect: true,
			options: [
				{ label: "Structured logs", description: "JSON lines to stdout." },
				{ label: "Metrics", description: "Prometheus endpoint on :9090." },
				{ label: "Traces", description: "OTLP export to the collector." },
			],
		},
	],
};

const twoQuestions = {
	questions: [
		singleQuestion.questions[0],
		{
			question: "Where should the rollout land first?",
			header: "Rollout target that is far too long",
			multiSelect: true,
			options: [
				{ label: "Staging only" },
				{ label: "Internal users", description: "Employees, behind a flag." },
				{ label: "10% of production" },
			],
		},
	],
};

// ---- tests ----

console.log("\nsingle-select: pick an option");
{
	const h = open(singleQuestion);
	checkLayout("single-select", h);
	check("cursor starts on the first option", h.plain().includes("❯ ( ) 1. OAuth"), h.plain());
	h.feed(KEY.down, KEY.enter);
	const result = await h.result;
	eq("one answer recorded", result.details.answers.length, 1);
	eq("the second option was chosen", result.details.answers[0].choices, [
		{ label: "Session cookies", index: 2, custom: false },
	]);
	eq("not cancelled", result.details.cancelled, false);
	check("result text names the choice", result.content[0].text.includes("chose: 2. Session cookies"), result.content[0].text);
	check("result text repeats the question", result.content[0].text.includes("[Auth method]"), result.content[0].text);
}

console.log("\nsingle-select: j/k and digit shortcuts");
{
	const h = open(singleQuestion);
	h.feed("j", "j", "k");
	check("j/k moved the cursor to option 2", h.plain().includes("❯ ( ) 2. Session cookies"), h.plain());
	h.feed("3");
	const result = await h.result;
	eq("digit 3 selected the third option", result.details.answers[0].choices, [
		{ label: "Signed JWTs", index: 3, custom: false },
	]);
}

console.log("\nsingle-select: space selects without leaving the question");
{
	const h = open(singleQuestion);
	h.feed(KEY.down, KEY.space);
	let settled = false;
	h.result.then(() => {
		settled = true;
	});
	await new Promise((r) => setImmediate(r));
	check("space did not submit", !settled);
	check("option 2 is marked selected", h.plain().includes("❯ (•) 2. Session cookies"), h.plain());
	h.feed(KEY.down, KEY.space);
	const after = h.plain();
	check("selection moved to option 3", after.includes("(•) 3. Signed JWTs"), after);
	check("option 2 is no longer selected", after.includes("( ) 2. Session cookies"), after);
	check("help line advertises both keys", after.includes("Space select • Enter confirm & continue"), after);
	h.feed(KEY.enter);
	const result = await h.result;
	eq("enter submits the row under the cursor", result.details.answers[0].choices, [
		{ label: "Signed JWTs", index: 3, custom: false },
	]);
}

console.log("\nsingle-select: space opens Other, typing does not submit");
{
	const h = open(singleQuestion);
	h.feed(KEY.up, KEY.space);
	check("the Other row became a text field", h.plain().includes("❯ ( ) 4. > "), h.plain());
	h.type("mTLS between services");
	check("typed text is visible inline", h.plain().includes("4. > mTLS between services"), h.plain());
	let settled = false;
	h.result.then(() => {
		settled = true;
	});
	await new Promise((r) => setImmediate(r));
	check("typing did not submit the question", !settled);
	h.feed(KEY.enter);
	const result = await h.result;
	eq("enter in the field submits the free text", result.details.answers[0].choices, [
		{ label: "mTLS between services", index: null, custom: true },
	]);
}

console.log("\ninline field: focus and cursor marker");
{
	const h = open(singleQuestion);
	h.feed(KEY.up, KEY.space);
	h.type("a b c"); // spaces go into the field, they do not toggle anything
	check("spaces are typed, not swallowed", h.plain().includes("4. > a b c"), h.plain());
	h.component.focused = true;
	const focused = h.lines().find((l: string) => stripAnsi(l).includes("4. >")) ?? "";
	check("focused field emits the hardware cursor marker", focused.includes("\x1b_pi:c\x07"), JSON.stringify(focused));
	checkLayout("focused-field", h);
	h.feed(KEY.escape);
	check("esc left the field", h.plain().includes("4. Other (write your own)"), h.plain());
	check("the draft was discarded", !h.plain().includes("a b c"), h.plain());
	h.feed(KEY.escape);
	await h.result;
}

console.log("\nsingle-select: enter on an empty Other gives guidance, never opens the editor");
{
	const h = open(singleQuestion);
	h.feed(KEY.up, KEY.enter);
	check("enter did not open a text field", !h.plain().includes("4. > "), h.plain());
	check("enter shows the space hint", h.plain().includes("press Space to write your own"), h.plain());
	let settled = false;
	h.result.then(() => {
		settled = true;
	});
	await new Promise((r) => setImmediate(r));
	check("did not submit", !settled);
	h.feed(KEY.escape);
	await h.result;
}

console.log("\nsingle-select: wrap-around navigation");
{
	const h = open(singleQuestion);
	h.feed(KEY.up); // wraps to the last row, which is Other
	check("up from the first row wraps to Other", h.plain().includes("❯ ( ) 4. Other"), h.plain());
	h.feed(KEY.down);
	check("down wraps back to the first option", h.plain().includes("❯ ( ) 1. OAuth"), h.plain());
	h.feed(KEY.escape);
	await h.result;
}

console.log("\nmulti-select: toggle several options");
{
	const h = open(multiQuestion);
	checkLayout("multi-select", h);
	check("renders checkboxes", h.plain().includes("❯ [ ] 1. Structured logs"), h.plain());
	h.feed(KEY.space, KEY.down, KEY.down, KEY.space);
	const mid = h.plain();
	check("first option checked", mid.includes("[x] 1. Structured logs"), mid);
	check("second option unchecked", mid.includes("[ ] 2. Metrics"), mid);
	check("third option checked", mid.includes("❯ [x] 3. Traces"), mid);
	h.feed(KEY.enter);
	const result = await h.result;
	eq("both toggled options recorded in order", result.details.answers[0].choices, [
		{ label: "Structured logs", index: 1, custom: false },
		{ label: "Traces", index: 3, custom: false },
	]);
	check("result text joins them", result.content[0].text.includes("1. Structured logs | 3. Traces"), result.content[0].text);
}

console.log("\nmulti-select: space toggles off again");
{
	const h = open(multiQuestion);
	h.feed(KEY.space, KEY.space, KEY.down, KEY.space, KEY.enter);
	const result = await h.result;
	eq("only the still-checked option is reported", result.details.answers[0].choices, [
		{ label: "Metrics", index: 2, custom: false },
	]);
}

console.log("\nmulti-select: enter with nothing selected refuses to confirm");
{
	const h = open(multiQuestion);
	h.feed(KEY.enter);
	check("shows the warning", h.plain().includes("Pick at least one option"), h.plain());
	let settled = false;
	h.result.then(() => {
		settled = true;
	});
	await new Promise((r) => setImmediate(r));
	check("did not submit", !settled);
	h.feed(KEY.space, KEY.enter);
	const result = await h.result;
	eq("confirms once something is checked", result.details.answers[0].choices.length, 1);
}

console.log('\nsingle-select: "Other" free text');
{
	const h = open(singleQuestion);
	h.feed("4");
	check("digit on an empty Other shows guidance, not the editor", !h.plain().includes("4. > "), h.plain());
	h.feed(KEY.space);
	check("the Other row became a text field", h.plain().includes("❯ ( ) 4. > "), h.plain());
	checkLayout("other-editor", h);
	h.type("mTLS between services");
	check("typed text is visible inline", h.plain().includes("4. > mTLS between services"), h.plain());
	h.feed(KEY.enter);
	const result = await h.result;
	eq("free text is the answer, marked custom", result.details.answers[0].choices, [
		{ label: "mTLS between services", index: null, custom: true },
	]);
	check(
		"result text marks it as free text",
		result.content[0].text.includes('free text: "mTLS between services"'),
		result.content[0].text,
	);
}

console.log('\nsingle-select: esc inside the editor returns to the options');
{
	const h = open(singleQuestion);
	h.feed(KEY.up, KEY.space);
	h.type("half an answer");
	h.feed(KEY.escape);
	check("the field closed", h.plain().includes("❯ ( ) 4. Other (write your own)"), h.plain());
	check("options still shown", h.plain().includes("1. OAuth 2.0"), h.plain());
	h.feed(KEY.space); // cursor is still on Other, so this reopens the editor
	check("space reopens the field", h.plain().includes("❯ ( ) 4. > "), h.plain());
	check("the abandoned draft was dropped", !h.plain().includes("half an answer"), h.plain());
	h.feed(KEY.escape, KEY.escape);
	const result = await h.result;
	eq("esc in the option list cancels", result.details.cancelled, true);
}

console.log('\nmulti-select: "Other" is added alongside the checked options');
{
	const h = open(multiQuestion);
	h.feed(KEY.space, KEY.down, KEY.down, KEY.down, KEY.space);
	const opened = h.plain();
	check("space on the Other row opens the field", opened.includes("❯ [ ] 4. > "), opened);
	check("earlier checkbox survived", opened.includes("[x] 1. Structured logs"), opened);
	checkLayout("multi-select-with-other", h);
	h.type("profiling endpoint");
	h.feed(KEY.enter);
	const result = await h.result;
	eq("both the option and the free text are reported", result.details.answers[0].choices, [
		{ label: "Structured logs", index: 1, custom: false },
		{ label: "profiling endpoint", index: null, custom: true },
	]);
}

console.log('\nmulti-select: enter on an empty Other row shows the warning, not an editor');
{
	const h = open(multiQuestion);
	h.feed(KEY.down, KEY.down, KEY.down, KEY.enter);
	check("enter did not open the field", !h.plain().includes("4. > "), h.plain());
	check("shows the pick-at-least-one warning", h.plain().includes("Pick at least one option"), h.plain());
	let settled = false;
	h.result.then(() => {
		settled = true;
	});
	await new Promise((r) => setImmediate(r));
	check("did not submit", !settled);
	h.feed(KEY.space); // cursor is still on Other; space opens the field
	check("space opens the field", h.plain().includes("❯ [ ] 4. > "), h.plain());
	h.type("audit trail");
	h.feed(KEY.enter);
	const result = await h.result;
	eq("free text alone answers a multi-select", result.details.answers[0].choices, [
		{ label: "audit trail", index: null, custom: true },
	]);
}

console.log("\nesc cancels");
{
	const h = open(singleQuestion);
	h.feed(KEY.escape);
	const result = await h.result;
	eq("cancelled", result.details.cancelled, true);
	eq("no answers", result.details.answers, []);
	check("tells the model to proceed", result.content[0].text.includes("Do not ask again"), result.content[0].text);
}

console.log("\ntwo questions: tab bar navigation and submit");
{
	const h = open(twoQuestions);
	checkLayout("two-questions", h);
	const start = h.plain();
	check("tab bar shows both headers", start.includes("Auth method") && start.includes("Rollout t..."), start);
	check("long header is truncated to 12 columns", !start.includes("Rollout target that"), start);
	check("submit chip is present", start.includes("✓ Submit"), start);

	h.feed(KEY.tab);
	check("tab moved to the second question", h.plain().includes("Where should the rollout land first?"), h.plain());
	h.feed(KEY.shiftTab);
	check("shift+tab moved back", h.plain().includes("Which authentication method"), h.plain());

	h.feed(KEY.enter); // answer Q1 -> auto-advances to the next unanswered question
	check("answering Q1 advanced to Q2", h.plain().includes("Where should the rollout land first?"), h.plain());
	check("Q1 chip is marked answered", h.plain().includes("■ Auth method"), h.plain());

	h.feed(KEY.tab);
	check("tab from the last question lands on Submit", h.plain().includes("Review and submit"), h.plain());
	check("unanswered question is called out", h.plain().includes("unanswered"), h.plain());
	h.feed(KEY.enter);
	check("submit refuses while a question is open", h.plain().includes("Still to answer: Rollout t..."), h.plain());

	h.feed(KEY.shiftTab, KEY.space, KEY.enter); // back to Q2, check option 1, confirm
	check("confirming the last question lands on Submit", h.plain().includes("Review and submit"), h.plain());
	checkLayout("submit-tab", h);
	h.feed(KEY.enter);
	const result = await h.result;
	eq("both questions answered", result.details.answers.length, 2);
	eq("Q1", result.details.answers[0].choices, [{ label: "OAuth 2.0", index: 1, custom: false }]);
	eq("Q2", result.details.answers[1].choices, [{ label: "Staging only", index: 1, custom: false }]);
	check("Q2 is flagged multi-select in the report", result.content[0].text.includes("(multi-select)"), result.content[0].text);
}

console.log("\nabort signal closes the dialog");
{
	const controller = new AbortController();
	const h = open(singleQuestion, controller.signal);
	controller.abort();
	const result = await h.result;
	eq("aborting reads as cancelled", result.details.cancelled, true);
}

console.log("\nnon-interactive modes fail loudly");
for (const mode of ["print", "json"]) {
	const ctx = { mode, hasUI: false, ui: {} };
	let message = "";
	try {
		await registered.execute("call-1", singleQuestion, undefined, undefined, ctx);
	} catch (error) {
		message = (error as Error).message;
	}
	check(`${mode}: throws`, message.includes("needs an interactive terminal"), message || "(no error thrown)");
}
{
	const ctx = { mode: "rpc", hasUI: true, ui: {} };
	let message = "";
	try {
		await registered.execute("call-1", singleQuestion, undefined, undefined, ctx);
	} catch (error) {
		message = (error as Error).message;
	}
	check("rpc: throws (custom() is a no-op there)", message.includes("needs an interactive terminal"), message);
}

console.log("\nnewlines in model-supplied text cannot break the frame");
{
	const h = open({
		questions: [
			{
				question: "Line one\nline two\twith a tab",
				header: "Weird\nheader",
				multiSelect: false,
				options: [
					{ label: "a\nb", description: "c\nd" },
					{ label: "x".repeat(120), description: "y".repeat(200) },
				],
			},
		],
	});
	checkLayout("hostile-input", h);
	h.feed(KEY.escape);
	await h.result;
}

// ---- rendered samples ----

function sample(title: string, h: Harness, width = 72) {
	console.log(`\n${title} (width ${width})`);
	console.log(`${"┄".repeat(width)}`);
	console.log(h.plain(width));
	console.log(`${"┄".repeat(width)}`);
}

const single = open(singleQuestion);
single.feed(KEY.down);
sample("SAMPLE — single-select", single);
single.feed(KEY.escape);
await single.result;

const multi = open(multiQuestion);
multi.feed(KEY.space, KEY.down, KEY.down, KEY.space);
sample("SAMPLE — multi-select", multi);
multi.feed(KEY.escape);
await multi.result;

const pair = open(twoQuestions);
pair.feed(KEY.enter);
sample("SAMPLE — two questions, second one active", pair);
pair.feed(KEY.escape);
await pair.result;

const other = open(singleQuestion);
other.feed("4", KEY.space);
other.type("mTLS between services");
sample("SAMPLE — Other, inline text field", other);
other.feed(KEY.escape, KEY.escape);
await other.result;

console.log(`\n${failures === 0 ? "✓ all" : `✗ ${failures} of`} ${checks} checks ${failures === 0 ? "passed" : "failed"}`);
process.exit(failures === 0 ? 0 : 1);
