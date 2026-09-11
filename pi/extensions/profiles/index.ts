import { existsSync, mkdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import type {
	ExtensionAPI,
	ExtensionCommandContext,
	ExtensionContext,
} from "@earendil-works/pi-coding-agent";
import { getAgentDir } from "@earendil-works/pi-coding-agent";
import type { AutocompleteItem } from "@earendil-works/pi-tui";

const CONFIG_PATH = join(getAgentDir(), "profiles.json");
const STATE_TYPE = "profiles-state";
const THINKING_LEVELS = ["off", "minimal", "low", "medium", "high", "xhigh", "max"] as const;

type ThinkingLevel = (typeof THINKING_LEVELS)[number];
type ProfileMode = "direct" | "supervisor";

export interface Profile {
	description: string;
	mode: ProfileMode;
	model?: string;
	thinkingLevel?: ThinkingLevel;
	tools?: string[];
	instructions?: string;
	defaultDelegate?: string;
}

export interface ProfilesConfig {
	version: 1;
	defaultProfile: string;
	profiles: Record<string, Profile>;
}

interface LoadResult {
	config: ProfilesConfig;
	errors: string[];
}

const EMPTY_CONFIG: ProfilesConfig = { version: 1, defaultProfile: "", profiles: {} };

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isProfileName(value: string): boolean {
	return /^[a-z0-9][a-z0-9_-]*$/.test(value);
}

function parseModelSpec(spec: string): { provider: string; modelId: string } | undefined {
	const slash = spec.indexOf("/");
	if (slash <= 0 || slash === spec.length - 1) return undefined;
	return { provider: spec.slice(0, slash), modelId: spec.slice(slash + 1) };
}

function normalizeStringArray(value: unknown): string[] | undefined {
	if (!Array.isArray(value)) return undefined;
	const result = [...new Set(value.filter((item): item is string => typeof item === "string").map((item) => item.trim()).filter(Boolean))];
	return result.length > 0 ? result : undefined;
}

export function normalizeConfig(value: unknown): LoadResult {
	const errors: string[] = [];
	if (!isRecord(value) || !isRecord(value.profiles)) {
		return { config: { ...EMPTY_CONFIG, profiles: {} }, errors: ["profiles.json must contain a profiles object"] };
	}

	const profiles: Record<string, Profile> = {};
	for (const [name, raw] of Object.entries(value.profiles)) {
		if (!isProfileName(name)) {
			errors.push(`Ignored invalid profile name "${name}" (use lowercase letters, numbers, - or _)`);
			continue;
		}
		if (!isRecord(raw)) {
			errors.push(`Ignored profile "${name}": expected an object`);
			continue;
		}
		if (raw.mode !== "direct" && raw.mode !== "supervisor") {
			errors.push(`Ignored profile "${name}": mode must be direct or supervisor`);
			continue;
		}
		if (typeof raw.description !== "string" || !raw.description.trim()) {
			errors.push(`Ignored profile "${name}": description is required`);
			continue;
		}
		if (raw.model !== undefined && (typeof raw.model !== "string" || !parseModelSpec(raw.model))) {
			errors.push(`Ignored profile "${name}": model must be provider/modelId`);
			continue;
		}
		if (
			raw.thinkingLevel !== undefined &&
			(typeof raw.thinkingLevel !== "string" || !THINKING_LEVELS.includes(raw.thinkingLevel as ThinkingLevel))
		) {
			errors.push(`Ignored profile "${name}": invalid thinkingLevel`);
			continue;
		}
		profiles[name] = {
			description: raw.description.trim(),
			mode: raw.mode,
			...(typeof raw.model === "string" ? { model: raw.model } : {}),
			...(typeof raw.thinkingLevel === "string" ? { thinkingLevel: raw.thinkingLevel as ThinkingLevel } : {}),
			...(normalizeStringArray(raw.tools) ? { tools: normalizeStringArray(raw.tools) } : {}),
			...(typeof raw.instructions === "string" && raw.instructions.trim()
				? { instructions: raw.instructions.trim() }
				: {}),
			...(typeof raw.defaultDelegate === "string" && raw.defaultDelegate.trim()
				? { defaultDelegate: raw.defaultDelegate.trim() }
				: {}),
		};
	}

	let defaultProfile = typeof value.defaultProfile === "string" ? value.defaultProfile : "";
	if (!profiles[defaultProfile]) {
		const first = Object.keys(profiles)[0] ?? "";
		if (defaultProfile) errors.push(`Default profile "${defaultProfile}" does not exist; using "${first}"`);
		defaultProfile = first;
	}

	for (const [name, profile] of Object.entries(profiles)) {
		if (profile.mode !== "supervisor" || !profile.defaultDelegate) continue;
		const worker = profiles[profile.defaultDelegate];
		if (!worker || worker.mode !== "direct") {
			errors.push(`Profile "${name}" has invalid defaultDelegate "${profile.defaultDelegate}"`);
			delete profile.defaultDelegate;
		}
	}

	return { config: { version: 1, defaultProfile, profiles }, errors };
}

function loadConfig(): LoadResult {
	if (!existsSync(CONFIG_PATH)) return { config: { ...EMPTY_CONFIG, profiles: {} }, errors: [] };
	try {
		return normalizeConfig(JSON.parse(readFileSync(CONFIG_PATH, "utf8")));
	} catch (error) {
		return {
			config: { ...EMPTY_CONFIG, profiles: {} },
			errors: [`Could not read ${CONFIG_PATH}: ${error instanceof Error ? error.message : String(error)}`],
		};
	}
}

function saveConfig(config: ProfilesConfig): void {
	// Dotfiles installs profiles.json as a symlink. Rename beside the real file
	// so atomic saves update the repository without replacing that symlink.
	const target = existsSync(CONFIG_PATH) ? realpathSync(CONFIG_PATH) : CONFIG_PATH;
	mkdirSync(dirname(target), { recursive: true });
	const temp = `${target}.${process.pid}.tmp`;
	writeFileSync(temp, `${JSON.stringify(config, null, 2)}\n`, { encoding: "utf8", mode: 0o600 });
	renameSync(temp, target);
}

function profileSummary(name: string, profile: Profile): string {
	const model = profile.model ?? "current model";
	return `${name} — ${profile.mode}, ${model}${profile.thinkingLevel ? `, ${profile.thinkingLevel}` : ""}`;
}

function directProfiles(config: ProfilesConfig): Array<[string, Profile]> {
	return Object.entries(config.profiles).filter((entry) => entry[1].mode === "direct");
}

function buildWorkerPrompt(name: string | undefined, profile: Profile | undefined): string {
	const identity = name && profile
		? `You are running as the delegated worker profile "${name}": ${profile.description}`
		: "You are running as a delegated worker.";
	return `${identity}

Execute the assigned task yourself. Do not delegate it. Work autonomously through implementation and verification. Read the relevant code before changing it, keep changes focused, and run the strongest relevant tests or checks available. Do not stop at a plan unless the task explicitly asks only for a plan.

Your final response is the supervisor's review packet. Keep it self-contained and concise: state what changed, list verification actually run and its outcome, and identify any unresolved risk or blocker.${profile?.instructions ? `\n\nProfile instructions:\n${profile.instructions}` : ""}`;
}

export function buildProfilePrompt(name: string, profile: Profile, config: ProfilesConfig): string {
	const basics = [
		`## Active Pi profile: ${name}`,
		`Description: ${profile.description}`,
		`Mode: ${profile.mode}`,
		`Preferred model: ${profile.model ?? "keep the currently selected model"}`,
		`Thinking level: ${profile.thinkingLevel ?? "keep the current level"}`,
	];

	if (profile.mode === "direct") {
		basics.push(
			"Operate as the primary worker. Handle work directly and carry it through implementation and verification rather than handing it off by default.",
		);
	} else {
		const workers = directProfiles(config).map(([workerName, worker]) =>
			`- ${workerName}: ${worker.description}; model=${worker.model ?? "inherit"}; thinking=${worker.thinkingLevel ?? "inherit"}; tools=${worker.tools?.join(",") ?? "defaults"}`,
		);
		basics.push(
			"Operate as a hands-on supervisor. Optimize total quality, latency, cost, and this main thread's context usage on every task.",
			"Plan and decompose substantial work. Decide whether each part is more efficient to do directly or delegate; you retain full power to work directly when that is better.",
			"Prefer delegation for isolated implementation, broad investigation, tests, validation, and independent review—especially when those would flood this expensive main context. Prefer direct work for small, tightly coupled actions or when delegation overhead exceeds the savings.",
			"Selecting this supervisor profile is standing authorization to delegate when useful. Do not ask permission solely to delegate; ask only when the underlying product or implementation decision genuinely belongs to the user.",
			"For delegated work, provide the goal, relevant paths/context, constraints, and a concrete definition of done. Consume final results with delegate_wait; avoid pulling live transcripts into the main context unless progress is explicitly requested.",
			`Default delegate: ${profile.defaultDelegate ?? "none"}`,
			`Available direct worker profiles:\n${workers.length > 0 ? workers.join("\n") : "- none"}`,
		);
	}
	if (profile.instructions) basics.push(`Profile-specific instructions:\n${profile.instructions}`);
	return basics.join("\n\n");
}

function matchingWorker(config: ProfilesConfig, model: string | undefined): [string, Profile] | undefined {
	if (!model) return undefined;
	return directProfiles(config).find(([, profile]) => profile.model === model);
}

export function applyDelegateDefaults(
	input: Record<string, unknown>,
	supervisor: Profile,
	config: ProfilesConfig,
): void {
	if (!Array.isArray(input.tasks)) return;
	const defaultWorker = supervisor.defaultDelegate ? config.profiles[supervisor.defaultDelegate] : undefined;
	const defaultEntry = supervisor.defaultDelegate && defaultWorker?.mode === "direct"
		? ([supervisor.defaultDelegate, defaultWorker] as [string, Profile])
		: undefined;

	for (const rawTask of input.tasks) {
		if (!isRecord(rawTask)) continue;
		const explicitModel = typeof rawTask.model === "string" ? rawTask.model : undefined;
		const selected = matchingWorker(config, explicitModel) ?? (!explicitModel ? defaultEntry : undefined);
		const [workerName, worker] = selected ?? [undefined, undefined];

		if (worker) {
			if (rawTask.model === undefined && worker.model) rawTask.model = worker.model;
			if (rawTask.thinkingLevel === undefined && worker.thinkingLevel) rawTask.thinkingLevel = worker.thinkingLevel;
			if (rawTask.tools === undefined && worker.tools) rawTask.tools = [...worker.tools];
		}

		const managedPrompt = buildWorkerPrompt(workerName, worker);
		const existing = typeof rawTask.appendSystemPrompt === "string" ? rawTask.appendSystemPrompt.trim() : "";
		rawTask.appendSystemPrompt = existing ? `${existing}\n\n${managedPrompt}` : managedPrompt;
	}
}

async function chooseProfile(ctx: ExtensionContext, config: ProfilesConfig, title: string): Promise<string | undefined> {
	const names = Object.keys(config.profiles).sort();
	if (names.length === 0) {
		ctx.ui.notify(`No profiles exist. Create one with /profile create`, "warning");
		return undefined;
	}
	const rows = names.map((name) => profileSummary(name, config.profiles[name]));
	const selected = await ctx.ui.select(title, rows);
	const index = selected ? rows.indexOf(selected) : -1;
	return index >= 0 ? names[index] : undefined;
}

async function chooseModel(ctx: ExtensionContext, current?: string): Promise<string | undefined | null> {
	const models = ctx.modelRegistry
		.getAvailable()
		.map((model) => `${model.provider}/${model.id}`)
		.sort();
	const keep = "(keep current model)";
	const options = current && models.includes(current)
		? [current, keep, ...models.filter((model) => model !== current)]
		: [keep, ...models];
	const selected = await ctx.ui.select("Preferred model", options);
	if (selected === undefined) return null;
	if (selected === keep) return undefined;
	return selected || current;
}

async function editProfile(
	ctx: ExtensionCommandContext,
	config: ProfilesConfig,
	name?: string,
): Promise<{ name: string; profile: Profile } | undefined> {
	if (ctx.mode !== "tui") {
		ctx.ui.notify("Profile editing requires interactive mode", "error");
		return undefined;
	}
	const existing = name ? config.profiles[name] : undefined;
	let profileName = name;
	if (!profileName) {
		const entered = await ctx.ui.input("Profile name", "lowercase-name");
		if (entered === undefined) return undefined;
		profileName = entered.trim();
		if (!isProfileName(profileName)) {
			ctx.ui.notify("Use lowercase letters, numbers, - or _; start with a letter or number", "error");
			return undefined;
		}
		if (config.profiles[profileName]) {
			ctx.ui.notify(`Profile "${profileName}" already exists`, "error");
			return undefined;
		}
	}

	const description = await ctx.ui.editor("Description", existing?.description ?? "");
	if (description === undefined) return undefined;
	if (!description.trim()) {
		ctx.ui.notify("Description is required", "error");
		return undefined;
	}

	const modeOptions = existing
		? [existing.mode, existing.mode === "direct" ? "supervisor" : "direct"]
		: ["direct", "supervisor"];
	const mode = await ctx.ui.select("Mode", modeOptions);
	if (mode === undefined) return undefined;
	const model = await chooseModel(ctx, existing?.model);
	if (model === null) return undefined;
	const thinkingOptions = existing?.thinkingLevel
		? [existing.thinkingLevel, "(keep current level)", ...THINKING_LEVELS.filter((level) => level !== existing.thinkingLevel)]
		: ["(keep current level)", ...THINKING_LEVELS];
	const thinkingChoice = await ctx.ui.select("Thinking level", thinkingOptions);
	if (thinkingChoice === undefined) return undefined;
	const thinkingLevel = thinkingChoice === "(keep current level)" ? undefined : (thinkingChoice as ThinkingLevel);

	const defaultTools = mode === "supervisor"
		? "read,bash,edit,write,ask,websearch,webfetch,delegate,delegate_wait,delegate_status,delegate_steer"
		: "read,bash,edit,write,ask,websearch,webfetch";
	const toolsText = await ctx.ui.editor(
		"Active tools (comma-separated; blank keeps Pi's current tools)",
		existing?.tools?.join(",") ?? defaultTools,
	);
	if (toolsText === undefined) return undefined;
	const tools = [...new Set(toolsText.split(",").map((tool) => tool.trim()).filter(Boolean))];

	const instructions = await ctx.ui.editor("Important instructions added to the system prompt", existing?.instructions ?? "");
	if (instructions === undefined) return undefined;

	let defaultDelegate: string | undefined;
	if (mode === "supervisor") {
		const candidates = directProfiles(config).filter(([candidate]) => candidate !== profileName);
		if (candidates.length > 0) {
			const names = candidates.map(([candidate]) => candidate);
			const choices = existing?.defaultDelegate && names.includes(existing.defaultDelegate)
				? [existing.defaultDelegate, "(no default)", ...names.filter((candidate) => candidate !== existing.defaultDelegate)]
				: ["(no default)", ...names];
			const selected = await ctx.ui.select("Default delegated worker", choices);
			if (selected === undefined) return undefined;
			defaultDelegate = selected === "(no default)" ? undefined : selected;
		}
	}

	return {
		name: profileName,
		profile: {
			description: description.trim(),
			mode: mode as ProfileMode,
			...(model ? { model } : {}),
			...(thinkingLevel ? { thinkingLevel } : {}),
			...(tools.length > 0 ? { tools } : {}),
			...(instructions.trim() ? { instructions: instructions.trim() } : {}),
			...(defaultDelegate ? { defaultDelegate } : {}),
		},
	};
}

export default function profilesExtension(pi: ExtensionAPI): void {
	let config: ProfilesConfig = { ...EMPTY_CONFIG, profiles: {} };
	let activeProfileName: string | undefined;
	let uiReady = false;

	const refreshConfig = (ctx?: ExtensionContext): ProfilesConfig => {
		const loaded = loadConfig();
		config = loaded.config;
		if (ctx && loaded.errors.length > 0) ctx.ui.notify(loaded.errors.join("\n"), "warning");
		return config;
	};

	const updateStatus = (ctx: ExtensionContext): void => {
		ctx.ui.setStatus(
			"profile",
			activeProfileName ? ctx.ui.theme.fg("accent", `profile:${activeProfileName}`) : undefined,
		);
	};

	const applyProfile = async (
		name: string,
		ctx: ExtensionContext,
		options: { persist: boolean; applyModel: boolean },
	): Promise<boolean> => {
		const profile = config.profiles[name];
		if (!profile) {
			ctx.ui.notify(`Unknown profile "${name}"`, "error");
			return false;
		}

		if (options.applyModel && profile.model) {
			const parsed = parseModelSpec(profile.model);
			const model = parsed ? ctx.modelRegistry.find(parsed.provider, parsed.modelId) : undefined;
			if (!model) {
				ctx.ui.notify(`Profile "${name}": model ${profile.model} is unavailable; keeping current model`, "warning");
			} else if (!(await pi.setModel(model))) {
				ctx.ui.notify(`Profile "${name}": authentication is not configured for ${profile.model}; keeping current model`, "warning");
			}
		}
		if (options.applyModel && profile.thinkingLevel) pi.setThinkingLevel(profile.thinkingLevel);

		if (profile.tools) {
			const available = new Set(pi.getAllTools().map((tool) => tool.name));
			const valid = profile.tools.filter((tool) => available.has(tool));
			const unknown = profile.tools.filter((tool) => !available.has(tool));
			if (unknown.length > 0) ctx.ui.notify(`Profile "${name}": unavailable tools: ${unknown.join(", ")}`, "warning");
			if (valid.length > 0) pi.setActiveTools(valid);
		}

		activeProfileName = name;
		if (options.persist) pi.appendEntry(STATE_TYPE, { name });
		updateStatus(ctx);
		return true;
	};

	const restoreFromBranch = async (ctx: ExtensionContext, persistDefault: boolean): Promise<void> => {
		const state = [...ctx.sessionManager.getBranch()]
			.reverse()
			.find((entry: any) => entry.type === "custom" && entry.customType === STATE_TYPE) as
			| { data?: { name?: string } }
			| undefined;
		const requested = state?.data?.name;
		const name = requested && config.profiles[requested] ? requested : config.defaultProfile;
		if (!name) {
			activeProfileName = undefined;
			updateStatus(ctx);
			return;
		}
		// Session restoration already restores model/thinking changes. Only a
		// profile-free session needs its default model applied.
		await applyProfile(name, ctx, { persist: persistDefault && !state, applyModel: !state });
	};

	pi.registerCommand("profile", {
		description: "Create, list, edit, delete, select, or set the default profile",
		getArgumentCompletions: (prefix: string): AutocompleteItem[] | null => {
			const current = loadConfig().config;
			const verbs = ["use", "list", "create", "edit", "delete", "default", "show"];
			const parts = prefix.trimStart().split(/\s+/);
			if (parts.length <= 1 && !prefix.endsWith(" ")) {
				const matches = verbs.filter((verb) => verb.startsWith(parts[0] ?? ""));
				return matches.length ? matches.map((value) => ({ value, label: value })) : null;
			}
			const verb = parts[0];
			if (!["use", "edit", "delete", "default", "show"].includes(verb)) return null;
			const partial = parts.at(-1) ?? "";
			const names = Object.keys(current.profiles).filter((name) => name.startsWith(partial));
			return names.length ? names.map((name) => ({ value: `${verb} ${name}`, label: name })) : null;
		},
		handler: async (args, ctx) => {
			await ctx.waitForIdle();
			refreshConfig(ctx);
			const [verb = "", nameArg] = args.trim().split(/\s+/, 2);

			if (!verb) {
				const names = Object.keys(config.profiles).sort();
				const profileRows = names.map((name) => `${name === activeProfileName ? "✓ " : "  "}${profileSummary(name, config.profiles[name])}`);
				const actions = ["＋ Create profile", "✎ Edit profile", "− Delete profile", "★ Set default", "≡ List details"];
				const selected = await ctx.ui.select("Profiles", [...profileRows, ...actions]);
				if (!selected) return;
				const index = profileRows.indexOf(selected);
				if (index >= 0) {
					if (await applyProfile(names[index], ctx, { persist: true, applyModel: true }))
						ctx.ui.notify(`Profile "${names[index]}" active`, "info");
					return;
				}
				const action = actions.indexOf(selected);
				if (action === 0) return await runCreate(ctx);
				if (action === 1) return await runEdit(ctx);
				if (action === 2) return await runDelete(ctx);
				if (action === 3) return await runDefault(ctx);
				if (action === 4) return showList(ctx);
				return;
			}

			if (verb === "list") return showList(ctx);
			if (verb === "create") return await runCreate(ctx);
			if (verb === "edit") return await runEdit(ctx, nameArg);
			if (verb === "delete") return await runDelete(ctx, nameArg);
			if (verb === "default") return await runDefault(ctx, nameArg);
			if (verb === "show") {
				const name = nameArg ?? (await chooseProfile(ctx, config, "Show profile"));
				if (!name || !config.profiles[name]) return;
				ctx.ui.notify(buildProfilePrompt(name, config.profiles[name], config), "info");
				return;
			}
			if (verb === "use") {
				const name = nameArg ?? (await chooseProfile(ctx, config, "Use profile"));
				if (!name) return;
				if (await applyProfile(name, ctx, { persist: true, applyModel: true }))
					ctx.ui.notify(`Profile "${name}" active`, "info");
				return;
			}

			// `/profile worker` is a convenient alias for `/profile use worker`.
			if (config.profiles[verb]) {
				if (await applyProfile(verb, ctx, { persist: true, applyModel: true }))
					ctx.ui.notify(`Profile "${verb}" active`, "info");
				return;
			}
			ctx.ui.notify("Usage: /profile [use|list|create|edit|delete|default|show] [name]", "error");
		},
	});

	const showList = (ctx: ExtensionContext): void => {
		const lines = Object.entries(config.profiles).map(([name, profile]) => {
			const marks = `${name === activeProfileName ? "active, " : ""}${name === config.defaultProfile ? "default, " : ""}`.replace(/, $/, "");
			return `${profileSummary(name, profile)}${marks ? ` [${marks}]` : ""}\n  ${profile.description}`;
		});
		ctx.ui.notify(lines.join("\n") || "No profiles configured", "info");
	};

	const runCreate = async (ctx: ExtensionCommandContext): Promise<void> => {
		const result = await editProfile(ctx, config);
		if (!result) return;
		config.profiles[result.name] = result.profile;
		if (!config.defaultProfile) config.defaultProfile = result.name;
		saveConfig(config);
		ctx.ui.notify(`Created profile "${result.name}"`, "info");
	};

	const runEdit = async (ctx: ExtensionCommandContext, requested?: string): Promise<void> => {
		const name = requested ?? (await chooseProfile(ctx, config, "Edit profile"));
		if (!name) return;
		if (!config.profiles[name]) {
			ctx.ui.notify(`Unknown profile "${name}"`, "error");
			return;
		}
		const result = await editProfile(ctx, config, name);
		if (!result) return;
		config.profiles[name] = result.profile;
		if (result.profile.mode !== "direct") {
			for (const profile of Object.values(config.profiles)) {
				if (profile.defaultDelegate === name) delete profile.defaultDelegate;
			}
		}
		saveConfig(config);
		if (activeProfileName === name) await applyProfile(name, ctx, { persist: true, applyModel: true });
		ctx.ui.notify(`Updated profile "${name}"`, "info");
	};

	const runDelete = async (ctx: ExtensionCommandContext, requested?: string): Promise<void> => {
		const name = requested ?? (await chooseProfile(ctx, config, "Delete profile"));
		if (!name) return;
		if (!config.profiles[name]) {
			ctx.ui.notify(`Unknown profile "${name}"`, "error");
			return;
		}
		if (name === activeProfileName) {
			ctx.ui.notify("Switch away from an active profile before deleting it", "error");
			return;
		}
		const confirmed = await ctx.ui.confirm("Delete profile?", `Delete "${name}" permanently?`);
		if (!confirmed) return;
		delete config.profiles[name];
		for (const profile of Object.values(config.profiles)) {
			if (profile.defaultDelegate === name) delete profile.defaultDelegate;
		}
		if (config.defaultProfile === name) config.defaultProfile = Object.keys(config.profiles)[0] ?? "";
		saveConfig(config);
		ctx.ui.notify(`Deleted profile "${name}"`, "info");
	};

	const runDefault = async (ctx: ExtensionCommandContext, requested?: string): Promise<void> => {
		const name = requested ?? (await chooseProfile(ctx, config, "Default profile for new sessions"));
		if (!name) return;
		if (!config.profiles[name]) {
			ctx.ui.notify(`Unknown profile "${name}"`, "error");
			return;
		}
		config.defaultProfile = name;
		saveConfig(config);
		ctx.ui.notify(`Default profile set to "${name}"`, "info");
	};

	pi.on("session_start", async (_event, ctx) => {
		// Delegated/headless sessions load global extensions too. Profiles are a
		// user-selected TUI concern; worker defaults arrive through delegate task
		// options and must never recursively activate the global default profile.
		if (ctx.mode !== "tui") return;
		uiReady = true;
		refreshConfig(ctx);
		await restoreFromBranch(ctx, true);
	});

	pi.on("session_tree", async (_event, ctx) => {
		if (!uiReady || ctx.mode !== "tui") return;
		refreshConfig(ctx);
		await restoreFromBranch(ctx, false);
	});

	pi.on("before_agent_start", async (event) => {
		if (!uiReady || !activeProfileName) return;
		const profile = config.profiles[activeProfileName];
		if (!profile) return;
		return { systemPrompt: `${event.systemPrompt}\n\n${buildProfilePrompt(activeProfileName, profile, config)}` };
	});

	pi.on("tool_call", async (event) => {
		if (!uiReady || event.toolName !== "delegate" || !activeProfileName) return;
		const supervisor = config.profiles[activeProfileName];
		if (!supervisor || supervisor.mode !== "supervisor") return;
		applyDelegateDefaults(event.input as Record<string, unknown>, supervisor, config);
	});

	pi.on("session_shutdown", async () => {
		uiReady = false;
	});
}
