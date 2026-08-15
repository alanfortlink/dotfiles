/**
 * Smoke test: render thinking + tools through the patched components with a
 * fake UI context, collapsed and expanded.
 *
 * See README "Test" for the jiti one-liner that runs this.
 */
import { AssistantMessageComponent, initTheme, ToolExecutionComponent } from "@earendil-works/pi-coding-agent";
import { Container } from "@earendil-works/pi-tui";
import compactView from "./index.ts";

initTheme("dark");
let expanded = false;
const fakeUi = {
	getToolsExpanded: () => expanded,
	theme: { fg: (_c: string, t: string) => t, bg: (_c: string, t: string) => t, bold: (t: string) => `*${t}*` },
};
const handlers: Record<string, (e: unknown, ctx: unknown) => void> = {};
const entries: any[] = [];
const fakePi = {
	on: (name: string, fn: (e: unknown, ctx: unknown) => void) => (handlers[name] = fn),
	appendEntry: (customType: string, data: unknown) => entries.push({ type: "custom", customType, data }),
};
compactView(fakePi as never);
handlers.session_start({}, { hasUI: true, ui: fakeUi, sessionManager: { getEntries: () => entries } });

const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "").replace(/\x1b\][^\x07]*\x07/g, "");
const show = (title: string, lines: string[]) => console.log(`--- ${title} ---\n` + lines.map((l) => `|${strip(l)}`).join("\n"));
const fakeTui = { requestRender() {} } as never;
const thinking = Array.from({ length: 40 }, (_, i) => `thought line ${i + 1}`).join("\n\n");
const chat = new Container();

// ---- 1. streaming: thinking-only message starts a run ----
const a1 = new AssistantMessageComponent();
chat.addChild(a1);
a1.updateContent({ timestamp: 1, role: "assistant", content: [{ type: "thinking", thinking }] } as never, true);
show("streaming: thinking", chat.render(60));

// tool call arrives (thinking done), tool running
a1.updateContent({ timestamp: 1, role: "assistant", content: [{ type: "thinking", thinking }, { type: "toolCall", id: "t1", name: "bash", arguments: { command: "echo t1" } }] } as never, true);
handlers.tool_execution_start({ toolCallId: "t1" }, {});
const t1 = new ToolExecutionComponent("bash", "t1", { command: "echo t1" }, {}, undefined, fakeTui, "/tmp");
chat.addChild(t1);
show("streaming: tool running", chat.render(60));

// tool done (error), message ends
handlers.tool_execution_end({ toolCallId: "t1" }, {});
t1.updateResult({ content: [{ type: "text", text: "boom" }], isError: true } as never, false);
a1.updateContent(a1["lastMessage"], false);
show("after first message", chat.render(60));

// ---- 2. second message: thinking + more tools, absorbed into the same run ----
const a2 = new AssistantMessageComponent();
chat.addChild(a2);
a2.updateContent({ timestamp: 2, role: "assistant", content: [{ type: "thinking", thinking: "hmm" }, { type: "toolCall", id: "t2", name: "edit" }, { type: "toolCall", id: "t3", name: "bash" }] } as never, false);
for (const [id, name, args] of [["t2", "edit", { path: "/tmp/x", oldText: "a", newText: "b" }], ["t3", "bash", { command: "ls" }]] as const) {
	handlers.tool_execution_start({ toolCallId: id }, {});
	const t = new ToolExecutionComponent(name, id, args as never, {}, undefined, fakeTui, "/tmp");
	chat.addChild(t);
	handlers.tool_execution_end({ toolCallId: id }, {});
	t.updateResult({ content: [{ type: "text", text: "ok" }] } as never, false);
}
show("run with 2 messages, 3 tools", chat.render(60));

// ---- 3. final message: thinking + answer text ----
const a3 = new AssistantMessageComponent();
chat.addChild(a3);
a3.updateContent({ timestamp: 3, role: "assistant", content: [{ type: "thinking", thinking: "ok" }, { type: "text", text: "final answer" }] } as never, false);
show("run + answer", chat.render(60));

// ---- 4. text-only message right after a tool: rule replaces the blank line ----
handlers.tool_execution_start({ toolCallId: "t4" }, {});
const t4 = new ToolExecutionComponent("bash", "t4", { command: "echo t4" }, {}, undefined, fakeTui, "/tmp");
chat.addChild(t4);
handlers.tool_execution_end({ toolCallId: "t4" }, {});
t4.updateResult({ content: [{ type: "text", text: "ok" }] } as never, false);
const a4 = new AssistantMessageComponent();
chat.addChild(a4);
a4.updateContent({ timestamp: 4, role: "assistant", content: [{ type: "text", text: "plain answer" }] } as never, false);
show("second run + text-only answer", chat.render(60).slice(-4));

expanded = true;
console.log(`--- expanded: ${chat.render(60).length} lines ---`);
expanded = false;

handlers.turn_end({}, {});
console.log("--- persisted entries ---");
console.log(JSON.stringify(entries));
