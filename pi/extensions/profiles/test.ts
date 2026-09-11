import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const piCommand = execFileSync("sh", ["-lc", "command -v pi"], { encoding: "utf8" }).trim();
const piCli = realpathSync(piCommand);
const PI = resolve(dirname(piCli), "../..");
const HERE = dirname(fileURLToPath(import.meta.url));
const { createJiti } = await import(`${PI}/node_modules/jiti/lib/jiti.mjs`);
const jiti = createJiti(import.meta.url, {
	moduleCache: false,
	alias: {
		"@earendil-works/pi-coding-agent": `${PI}/dist/index.js`,
		"@earendil-works/pi-tui": `${PI}/node_modules/@earendil-works/pi-tui/dist/index.js`,
	},
});

const module = (await jiti.import(join(HERE, "index.ts"))) as any;
const extension = module.default as (pi: any) => void;
const { applyDelegateDefaults, buildProfilePrompt, normalizeConfig } = module;

const normalized = normalizeConfig({
	version: 1,
	defaultProfile: "boss",
	profiles: {
		worker: { description: "does work", mode: "direct", model: "p/model/with/slash", tools: ["read", "read"] },
		boss: { description: "manages", mode: "supervisor", defaultDelegate: "worker" },
		"Bad Name": { description: "bad", mode: "direct" },
	},
});
assert.deepEqual(normalized.config.profiles.worker.tools, ["read"]);
assert.equal(normalized.config.defaultProfile, "boss");
assert.equal(normalized.errors.length, 1);
assert.match(buildProfilePrompt("boss", normalized.config.profiles.boss, normalized.config), /standing authorization to delegate/);

const delegated: Record<string, unknown> = { tasks: [{ prompt: "implement" }] };
applyDelegateDefaults(delegated, normalized.config.profiles.boss, normalized.config);
const delegatedTask = (delegated.tasks as Array<Record<string, unknown>>)[0];
assert.equal(delegatedTask.model, "p/model/with/slash");
assert.deepEqual(delegatedTask.tools, ["read"]);
assert.match(String(delegatedTask.appendSystemPrompt), /review packet/);

const explicit: Record<string, unknown> = { tasks: [{ prompt: "review", model: "other/model" }] };
applyDelegateDefaults(explicit, normalized.config.profiles.boss, normalized.config);
assert.equal((explicit.tasks as any[])[0].model, "other/model");
assert.match((explicit.tasks as any[])[0].appendSystemPrompt, /delegated worker/);

const handlers = new Map<string, (...args: any[]) => any>();
let command: any;
let activeTools: string[] = [];
const modelChanges: string[] = [];
const thinkingChanges: string[] = [];
const entries: any[] = [];
const statuses: Array<string | undefined> = [];
const notifications: string[] = [];
const allTools = [
	"read", "bash", "edit", "write", "ask", "websearch", "webfetch",
	"delegate", "delegate_wait", "delegate_status", "delegate_steer",
].map((name) => ({ name }));

const fakePi = {
	on(name: string, handler: (...args: any[]) => any) { handlers.set(name, handler); },
	registerCommand(name: string, definition: any) {
		if (name === "profile") command = definition;
	},
	getAllTools: () => allTools,
	getActiveTools: () => activeTools,
	setActiveTools(tools: string[]) { activeTools = tools; },
	async setModel(model: any) { modelChanges.push(`${model.provider}/${model.id}`); return true; },
	setThinkingLevel(level: string) { thinkingChanges.push(level); },
	appendEntry(customType: string, data: any) { entries.push({ type: "custom", customType, data }); },
};
extension(fakePi);
assert.ok(command, "registered /profile");

const models = [
	{ provider: "opencode-go", id: "glm-5.3-flash" },
	{ provider: "openai-codex", id: "gpt-5.6-luna" },
	{ provider: "openai-codex", id: "gpt-5.6-sol" },
];
const ctx: any = {
	mode: "tui",
	hasUI: true,
	cwd: "/tmp",
	ui: {
		theme: { fg: (_color: string, text: string) => text },
		setStatus: (_key: string, value?: string) => statuses.push(value),
		notify: (message: string) => notifications.push(message),
		select: async () => undefined,
		input: async () => undefined,
		editor: async () => undefined,
		confirm: async () => false,
	},
	modelRegistry: {
		getAvailable: () => models,
		find: (provider: string, id: string) => models.find((model) => model.provider === provider && model.id === id),
	},
	sessionManager: { getBranch: () => entries },
	waitForIdle: async () => {},
};

await handlers.get("session_start")?.({ reason: "startup" }, ctx);
assert.equal(modelChanges.at(-1), "opencode-go/glm-5.3-flash");
assert.equal(thinkingChanges.at(-1), "high");
assert.ok(activeTools.includes("edit"));
assert.ok(!activeTools.includes("delegate"));
assert.deepEqual(entries.at(-1), { type: "custom", customType: "profiles-state", data: { name: "worker" } });
assert.equal(statuses.at(-1), "profile:worker");

await command.handler("use supervisor", ctx);
assert.equal(modelChanges.at(-1), "openai-codex/gpt-5.6-sol");
assert.ok(activeTools.includes("delegate"));
assert.equal(statuses.at(-1), "profile:supervisor");

const promptResult = await handlers.get("before_agent_start")?.({ systemPrompt: "base" }, ctx);
assert.match(promptResult.systemPrompt, /Active Pi profile: supervisor/);
assert.match(promptResult.systemPrompt, /worker: Hands-on/);

const call: any = { toolName: "delegate", input: { tasks: [{ prompt: "implement it" }] } };
await handlers.get("tool_call")?.(call, ctx);
assert.equal(call.input.tasks[0].model, "opencode-go/glm-5.3-flash");
assert.equal(call.input.tasks[0].thinkingLevel, "high");
assert.ok(call.input.tasks[0].tools.includes("write"));
assert.ok(!call.input.tasks[0].tools.includes("delegate"));
assert.match(call.input.tasks[0].appendSystemPrompt, /worker profile "worker"/);

const lunaCall: any = {
	toolName: "delegate",
	input: { tasks: [{ prompt: "hard implementation", model: "openai-codex/gpt-5.6-luna" }] },
};
await handlers.get("tool_call")?.(lunaCall, ctx);
assert.equal(lunaCall.input.tasks[0].model, "openai-codex/gpt-5.6-luna");
assert.match(lunaCall.input.tasks[0].appendSystemPrompt, /worker profile "luna-worker"/);

// A resumed session restores its recorded profile's tools and prompt, while Pi's
// native session model/thinking history remains the source of truth.
const restoredHandlers = new Map<string, (...args: any[]) => any>();
let restoredTools: string[] = [];
let restoredModelChanges = 0;
const restoredStatuses: Array<string | undefined> = [];
const restoredPi = {
	on: (name: string, handler: (...args: any[]) => any) => restoredHandlers.set(name, handler),
	registerCommand: () => {},
	getAllTools: () => allTools,
	setActiveTools: (tools: string[]) => { restoredTools = tools; },
	setModel: async () => { restoredModelChanges++; return true; },
	setThinkingLevel: () => {},
	appendEntry: () => { throw new Error("restored profile should not append a default state"); },
};
extension(restoredPi);
const restoredCtx = {
	...ctx,
	ui: { ...ctx.ui, setStatus: (_key: string, value?: string) => restoredStatuses.push(value) },
	sessionManager: {
		getBranch: () => [{ type: "custom", customType: "profiles-state", data: { name: "supervisor" } }],
	},
};
await restoredHandlers.get("session_start")?.({ reason: "resume" }, restoredCtx);
assert.equal(restoredModelChanges, 0);
assert.ok(restoredTools.includes("delegate"));
assert.equal(restoredStatuses.at(-1), "profile:supervisor");

console.log("profiles: all tests passed");
