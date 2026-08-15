/**
 * Smoke test: render a long thinking block and a long tool block through the
 * patched components with a fake UI context, collapsed and expanded.
 *
 *   PI=~/.local/share/mise/installs/node/25.9.0/lib/node_modules/@earendil-works/pi-coding-agent
 *   node $PI/node_modules/jiti/lib/jiti-cli.mjs test.ts
 */
import { AssistantMessageComponent, initTheme, ToolExecutionComponent } from "@earendil-works/pi-coding-agent";
import compactView from "./index.ts";

initTheme("dark");
let expanded = false;
const fakeUi = { getToolsExpanded: () => expanded, theme: { fg: (_c: string, t: string) => t, bold: (t: string) => `*${t}*` } };
const handlers: Record<string, (e: unknown, ctx: unknown) => void> = {};
const entries: any[] = [];
const fakePi = {
	on: (name: string, fn: (e: unknown, ctx: unknown) => void) => (handlers[name] = fn),
	appendEntry: (customType: string, data: unknown) => entries.push({ type: "custom", customType, data }),
};
compactView(fakePi as never);
handlers.session_start({}, { hasUI: true, ui: fakeUi, sessionManager: { getEntries: () => entries } });

const thinking = Array.from({ length: 40 }, (_, i) => `thought line ${i + 1}`).join("\n\n");
const msg = {
	timestamp: 123,
	role: "assistant",
	content: [
		{ type: "thinking", thinking },
		{ type: "text", text: "done" },
	],
	stopReason: "stop",
} as never;
const am = new AssistantMessageComponent();
am.updateContent({ ...(msg as any), content: [{ type: "thinking", thinking }] } as never, true);
console.log("--- thinking streaming (window) ---");
console.log(am.render(60).map((l) => l.replace(/\x1b\[[0-9;]*m/g, "")).join("\n"));
am.updateContent(msg, true);
console.log("--- thinking streaming, text started ---");
console.log(am.render(60).map((l) => l.replace(/\x1b\[[0-9;]*m/g, "")).join("\n"));
am.updateContent(msg, false);
const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "");
console.log("--- thinking finished ---");
console.log(am.render(60).map(strip).join("\n"));
expanded = true;
console.log(`--- thinking expanded: ${am.render(60).length} lines ---`);
expanded = false;

const fakeTui = { requestRender() {} } as never;
handlers.tool_execution_start({ toolCallId: "id1" }, {});
const te = new ToolExecutionComponent("edit", "id1", { path: "/tmp/x", oldText: "a", newText: "b" }, {}, undefined, fakeTui, "/tmp");
console.log("--- tool running ---");
console.log(te.render(60).map(strip).join("\n"));
handlers.tool_execution_end({ toolCallId: "id1" }, {});
te.updateResult(
	{
		content: [{ type: "text", text: "ok" }],
		details: { diff: Array.from({ length: 30 }, (_, i) => `${i % 2 ? "+" : "-"} line ${i}`).join("\n"), firstChangedLine: 1 },
	} as never,
	false,
);
console.log("--- tool finished ---");
console.log(te.render(60).map(strip).join("\n"));
te.setExpanded(true);
console.log(`--- tool expanded: ${te.render(60).length} lines ---`);

// ---- persistence: flush, then "reload" (fresh module state via a second registration) ----
handlers.turn_end({}, {});
console.log("--- persisted entries ---");
console.log(JSON.stringify(entries));

// ---- grouping: thought → tool → tool(error) → thought+text, in one chat container ----
import { Container } from "@earendil-works/pi-tui";
const chat = new Container();
const think = (ts: number, text?: string) =>
	({ timestamp: ts, role: "assistant", content: [{ type: "thinking", thinking: "hmm" }, ...(text ? [{ type: "text", text }] : [])], stopReason: "stop" }) as never;
const a1 = new AssistantMessageComponent();
chat.addChild(a1);
a1.updateContent(think(1), false);
const mkTool = (id: string, isError: boolean) => {
	handlers.tool_execution_start({ toolCallId: id }, {});
	const t = new ToolExecutionComponent("bash", id, { command: `echo ${id}` }, {}, undefined, fakeTui, "/tmp");
	chat.addChild(t);
	handlers.tool_execution_end({ toolCallId: id }, {});
	t.updateResult({ content: [{ type: "text", text: isError ? "boom\nline2\nline3" : "ok" }], isError } as never, false);
	return t;
};
mkTool("t1", false);
mkTool("t2", true);
const a2 = new AssistantMessageComponent();
chat.addChild(a2);
a2.updateContent(think(2, "final answer"), false);
console.log("--- grouped ---");
console.log(chat.render(60).map((l) => `|${strip(l)}`).join("\n"));
expanded = true;
console.log(`--- grouped expanded: ${chat.render(60).length} lines ---`);
expanded = false;

// text-only message right after a tool: rule replaces the blank line
mkTool("t3", false);
const a3 = new AssistantMessageComponent();
chat.addChild(a3);
a3.updateContent({ timestamp: 3, role: "assistant", content: [{ type: "text", text: "plain answer" }], stopReason: "stop" } as never, false);
console.log("--- text after tool ---");
console.log(chat.render(60).slice(-3).map((l) => `|${strip(l)}`).join("\n"));
