/** Smoke test: render a user message and assistant messages through the patched components. */
import assert from "node:assert/strict";
import { AssistantMessageComponent, initTheme, UserMessageComponent } from "@earendil-works/pi-coding-agent";
import { Container } from "@earendil-works/pi-tui";
import chatView from "./index.ts";

initTheme("dark");
const handlers: Record<string, (e: unknown, ctx: unknown) => void> = {};
chatView({ on: (n: string, f: any) => (handlers[n] = f) } as never);
const fakeUi = { theme: { fg: (_c: string, t: string) => t, bg: (_c: string, t: string) => t, bold: (t: string) => t } };
handlers.session_start({}, { hasUI: true, ui: fakeUi, model: { id: "glm-5.3-flash" } });

const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, "").replace(/\x1b\][^\x07]*\x07/g, "");
const show = (lines: string[]) => console.log(lines.map((l) => `|${strip(l)}|`).join("\n"));
const W = 60;
const chat = new Container();
const u = new UserMessageComponent("fix the failing tests please");
chat.addChild(u);
const a1 = new AssistantMessageComponent({ role: "assistant", content: [{ type: "text", text: "Running them now." }, { type: "toolCall", id: "t", name: "bash", arguments: {} }], stopReason: "toolUse" } as any);
chat.addChild(a1);
const a2 = new AssistantMessageComponent({ role: "assistant", content: [{ type: "text", text: "Two failures, both in `parser.ts`:\n\n- one\n- two" }], stopReason: "stop" } as any);
chat.addChild(a2);
const code = new AssistantMessageComponent({ role: "assistant", content: [{ type: "text", text: "```bash\necho hello\nnpm test\n```" }], stopReason: "stop" } as any);
chat.addChild(code);
const codeLines = code.render(W).map(strip);
const fenceStart = codeLines.findIndex((line) => line.trim() === "```bash");
const fenceEnd = codeLines.findIndex((line, index) => index > fenceStart && line.trim() === "```");
assert(fenceStart >= 0 && fenceEnd > fenceStart, "code fences should render");
assert(codeLines.slice(fenceStart, fenceEnd + 1).every((line) => !line.includes("▎")), "assistant gutter must not enter code blocks");
const u2 = new UserMessageComponent("a much longer message that should wrap around inside the bubble because it exceeds the cap of the terminal width by a fair margin");
chat.addChild(u2);
show(u.render(W)); show(a1.render(W)); show(a2.render(W)); show(codeLines); show(u2.render(W));
