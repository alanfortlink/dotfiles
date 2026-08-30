/**
 * file-paste-icon
 *
 * When you paste a file path (drag-and-drop, ctrl+v of a copied file, etc.)
 * the editor shows a compact file icon instead of the full path:
 *
 *     📄 foo.ts
 *
 * The icon is an OSC 8 hyperlink to the absolute path, so clicking it in
 * your terminal opens the file with the default application (xdg-open).
 * On submit, tokens are expanded back to absolute paths, so the LLM always
 * sees the real path.
 *
 * Fallback: /openfile lists recently pasted files and opens the picked one.
 */
import { CustomEditor, type ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { statSync } from "node:fs";
import { homedir } from "node:os";
import { basename, extname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const OSC_OPEN = "\x1b]8;;";
const OSC_ST = "\x1b\\";
const OSC_CLOSE = `${OSC_OPEN}${OSC_ST}`;

/** Matches a file token: OSC8 hyperlink pointing at a file:// URL. */
const FILE_TOKEN_RE = /\x1b\]8;;(file:\/\/[^\x1b]*)\x1b\\[^\x1b]*\x1b\]8;;\x1b\\/g;

const ICONS: Record<string, string> = {
	".md": "📝",
	".txt": "📄",
	".json": "⚙️",
	".yaml": "⚙️",
	".yml": "⚙️",
	".toml": "⚙️",
	".lock": "📦",
	".png": "🖼️",
	".jpg": "🖼️",
	".jpeg": "🖼️",
	".gif": "🖼️",
	".webp": "🖼️",
	".svg": "🖼️",
	".pdf": "📕",
	".ts": "🟦",
	".tsx": "🟦",
	".js": "🟨",
	".jsx": "🟨",
	".py": "🐍",
	".rs": "🦀",
	".go": "🐹",
	".sh": "🐚",
};

/** Files pasted this session (for /openfile). */
const recentFiles: string[] = [];

function iconFor(path: string): string {
	return ICONS[extname(path).toLowerCase()] ?? "📄";
}

/** Turn an absolute path into a display token (icon + basename, hyperlink-wrapped). */
function makeToken(absPath: string): string {
	const label = `${iconFor(absPath)} ${basename(absPath)}`;
	return `${OSC_OPEN}${pathToFileURL(absPath).href}${OSC_ST}${label}${OSC_CLOSE}`;
}

/** If a single whitespace-free token refers to an existing file, return its absolute path. */
function existingFile(raw: string): string | null {
	let p = raw.trim();
	if (!p || /\s/.test(p)) return null;
	// Strip surrounding quotes some terminals add
	p = p.replace(/^["']|["']$/g, "");
	if (!p) return null;
	const expanded = p === "~" ? homedir() : p.startsWith("~/" ) ? homedir() + p.slice(1) : p;
	const abs = resolve(expanded);
	try {
		return statSync(abs).isFile() ? abs : null;
	} catch {
		return null;
	}
}

/**
 * Merge grapheme/word segments so each file token is a single atomic unit
 * for cursor movement, deletion, and word-wrapping (same trick the built-in
 * editor uses for `[paste #N]` markers).
 */
function mergeTokenSegments(text: string, segments: Array<{ segment: string; index: number }>) {
	const spans: Array<[number, number]> = [];
	for (const m of text.matchAll(FILE_TOKEN_RE)) {
		spans.push([m.index, m.index + m[0].length]);
	}
	if (spans.length === 0) return segments;

	const out: Array<{ segment: string; index: number }> = [];
	let i = 0;
	while (i < segments.length) {
		const seg = segments[i];
		const span = spans.find(([s, e]) => seg.index >= s && seg.index < e);
		if (span) {
			const [s, e] = span;
			let merged = "";
			while (i < segments.length && segments[i].index < e) {
				merged += segments[i].segment;
				i++;
			}
			out.push({ segment: merged, index: s });
		} else {
			out.push(seg);
			i++;
		}
	}
	return out;
}

class FilePasteEditor extends CustomEditor {
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	handlePaste(pastedText: string): void {
		// Replace every whitespace-separated token that is an existing file
		// with an icon token; leave everything else untouched.
		const parts = pastedText.split(/(\s+)/);
		let replaced = false;
		const rebuilt = parts
			.map((part) => {
				if (/^\s+$/.test(part) || part === "") return part;
				const abs = existingFile(part);
				if (!abs) return part;
				replaced = true;
				if (!recentFiles.includes(abs)) {
					recentFiles.push(abs);
					if (recentFiles.length > 20) recentFiles.shift();
				}
				return makeToken(abs);
			})
			.join("");

		if (replaced) {
			// insertTextAtCursor handles undo snapshot, autocomplete cancel, etc.
			this.insertTextAtCursor(rebuilt);
			return;
		}
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		(super.handlePaste as any)(pastedText);
	}

	// Make file tokens atomic for cursor ops / wrapping.
	// eslint-disable-next-line @typescript-eslint/no-explicit-any
	segment(text: string, mode: any) {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		const segments = (super.segment as any)(text, mode);
		return mergeTokenSegments(text, segments);
	}

	/** Sent to the LLM on submit: tokens become absolute paths. */
	getExpandedText(): string {
		// eslint-disable-next-line @typescript-eslint/no-explicit-any
		const base = (super.getExpandedText as any)() as string;
		return base.replace(FILE_TOKEN_RE, (match, url: string) => {
			try {
				return fileURLToPath(url);
			} catch {
				return match;
			}
		});
	}
}

export default function (pi: ExtensionAPI) {
	pi.on("session_start", async (_event, ctx) => {
		if (ctx.mode !== "tui") return;
		ctx.ui.setEditorComponent((tui, theme, keybindings) => new FilePasteEditor(tui, theme, keybindings));
	});

	pi.registerCommand("openfile", {
		description: "Open a recently pasted file",
		handler: async (_args, ctx) => {
			if (recentFiles.length === 0) {
				ctx.ui.notify("No files pasted yet", "info");
				return;
			}
			const picked = await ctx.ui.select("Open file:", [...recentFiles].reverse());
			if (picked) {
				await pi.exec("xdg-open", [picked]);
				ctx.ui.notify(`Opened ${picked}`, "info");
			}
		},
	});
}
