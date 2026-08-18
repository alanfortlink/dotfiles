/**
 * Smoke test: render thinking + tools through the patched components with a
 * fake UI context, collapsed and expanded.
 *
 * See README "Test" for the jiti one-liner that runs this.
 */
import { AssistantMessageComponent, initTheme, ToolExecutionComponent, UserMessageComponent } from "@earendil-works/pi-coding-agent";
import { Container } from "@earendil-works/pi-tui";
import compactView from "./index.ts";

initTheme("dark");
// Deterministic clock: every timing below is measured through Date.now().
let now = 1_700_000_000_000;
Date.now = () => now;
const tick = (ms: number) => (now += ms);
let expanded = false;
const working: (string | undefined)[] = [];
const fakeUi = {
	getToolsExpanded: () => expanded,
	setWorkingMessage: (m?: string) => working.push(m),
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

// ---- 0. user prompt = interaction boundary ----
chat.addChild(new UserMessageComponent("do things", undefined as never, 1, []));

// ---- 1. streaming: thinking-only message ----
const a1 = new AssistantMessageComponent();
chat.addChild(a1);
handlers.message_update({ message: { timestamp: 1, role: "assistant" }, assistantMessageEvent: { type: "thinking_delta" } }, {});
a1.updateContent({ timestamp: 1, role: "assistant", content: [{ type: "thinking", thinking }] } as never, true);
tick(3000);
show("streaming: thinking", chat.render(60));

// tool call arrives (thinking done), tool running
a1.updateContent({ timestamp: 1, role: "assistant", content: [{ type: "thinking", thinking }, { type: "toolCall", id: "t1", name: "bash", arguments: { command: "echo t1" } }] } as never, true);
tick(1000); // 4s of generation, 400 tokens → 100 tok/s
const m1 = { ...a1["lastMessage"], usage: { output: 400 } };
handlers.message_end({ message: m1 }, {});
a1.updateContent(m1 as never, true);
handlers.tool_execution_start({ toolCallId: "t1", toolName: "bash", args: { command: "echo t1" } }, {});
const t1 = new ToolExecutionComponent("bash", "t1", { command: "echo t1" }, {}, undefined, fakeTui, "/tmp");
chat.addChild(t1);
show("streaming: tool running", chat.render(60));

// tool done (error), message ends
tick(500);
handlers.tool_execution_end({ toolCallId: "t1" }, {});
t1.updateResult({ content: [{ type: "text", text: "boom" }], isError: true } as never, false);
a1.updateContent(m1 as never, false);
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
show("2 messages, 3 tools", chat.render(60));

// ---- 3. final message: thinking + answer text ----
const a3 = new AssistantMessageComponent();
chat.addChild(a3);
a3.updateContent({ timestamp: 3, role: "assistant", content: [{ type: "thinking", thinking: "ok" }, { type: "text", text: "final answer" }] } as never, false);
show("thinking + interim answer", chat.render(60));

// ---- 4. text-only message right after a tool: rule replaces the blank line ----
handlers.tool_execution_start({ toolCallId: "t4" }, {});
const t4 = new ToolExecutionComponent("bash", "t4", { command: "echo t4" }, {}, undefined, fakeTui, "/tmp");
chat.addChild(t4);
handlers.tool_execution_end({ toolCallId: "t4" }, {});
t4.updateResult({ content: [{ type: "text", text: "ok" }] } as never, false);
const a4 = new AssistantMessageComponent();
chat.addChild(a4);
handlers.message_update({ message: { timestamp: 4, role: "assistant" }, assistantMessageEvent: { type: "text_delta" } }, {});
a4.updateContent({ timestamp: 4, role: "assistant", content: [{ type: "text", text: "plain answer ".repeat(20) }] } as never, true);
tick(1000); // ~260 chars → ~65 tokens over 1s, on top of 400/4s
show("more tools + final answer streaming (estimated rate)", chat.render(60).slice(-9, -5));
const m4 = { timestamp: 4, role: "assistant", content: [{ type: "text", text: "plain answer" }], usage: { output: 100 } };
handlers.message_end({ message: m4 }, {}); // 500 tokens / 5s = 100 tok/s exact
a4.updateContent(m4 as never, false);
show("final answer done, turn still running", chat.render(60).slice(-5));
handlers.agent_end({}, {});
show("turn ended", chat.render(60).slice(-4));
console.log("--- working messages ---\n" + JSON.stringify(working));

// ---- 5. next interaction: thinking-only reply ----
chat.addChild(new UserMessageComponent("again", undefined as never, 1, []));
const a5 = new AssistantMessageComponent();
chat.addChild(a5);
a5.updateContent({ timestamp: 5, role: "assistant", content: [{ type: "thinking", thinking: "…" }, { type: "text", text: "second answer" }] } as never, false);
show("second interaction", chat.render(60).slice(-5));

// ---- 6. plain answer, no thinking, no tools: time + rate only ----
chat.addChild(new UserMessageComponent("quick one", undefined as never, 1, []));
const a6 = new AssistantMessageComponent();
chat.addChild(a6);
handlers.message_update({ message: { timestamp: 6, role: "assistant" }, assistantMessageEvent: { type: "text_delta" } }, {});
tick(600);
const m6 = { timestamp: 6, role: "assistant", content: [{ type: "text", text: "yes" }], usage: { output: 3 } };
handlers.message_end({ message: m6 }, {});
a6.updateContent(m6 as never, false);
show("plain answer", chat.render(60).slice(-5));

expanded = true;
console.log(`--- expanded: ${chat.render(60).length} lines ---`);
expanded = false;

handlers.turn_end({}, {});
console.log("--- persisted entries ---");
console.log(JSON.stringify(entries));
