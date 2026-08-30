import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { StringEnum } from "@earendil-works/pi-ai";
import { Type } from "typebox";
import TurndownService from "turndown";
import * as htmlparser2 from "htmlparser2";

// ─── Helpers ───────────────────────────────────────────────────────────────────

const MAX_FETCH_BYTES = 5 * 1024 * 1024; // 5 MiB
const MAX_OUTPUT_LINES = 2000;
const MAX_OUTPUT_BYTES = 50 * 1024; // 50 KiB

const CHROME_UA =
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36";

// Exa free tier (no key) is heavily rate-limited. Set EXA_API_KEY to lift the
// limit; without a key we transparently fall back to DuckDuckGo lite.
const EXA_MCP_URL = "https://mcp.exa.ai/mcp";

function exaUrl(): string {
  const key = process.env.EXA_API_KEY?.trim();
  return key ? `${EXA_MCP_URL}?exaApiKey=${encodeURIComponent(key)}` : EXA_MCP_URL;
}

const ACCEPT_HEADERS: Record<string, string> = {
  markdown:
    "text/markdown;q=1.0, text/x-markdown;q=0.9, text/plain;q=0.8, text/html;q=0.7, */*;q=0.1",
  text: "text/plain;q=1.0, text/markdown;q=0.9, text/html;q=0.8, */*;q=0.1",
  html: "text/html;q=1.0, application/xhtml+xml;q=0.9, text/plain;q=0.8, text/markdown;q=0.7, */*;q=0.1",
};

// ─── Turndown (HTML → Markdown) ────────────────────────────────────────────────

const turndown = new TurndownService({
  headingStyle: "atx",
  hr: "---",
  bulletListMarker: "-",
  codeBlockStyle: "fenced",
  emDelimiter: "*",
});

// Remove noisy elements before conversion
turndown.remove(["script", "style", "meta", "link", "noscript", "iframe"]);

// ─── HTML → Plain text extraction ──────────────────────────────────────────────

const BLOCK_TAGS = new Set([
  "p", "div", "section", "article", "li", "tr", "td", "th", "h1", "h2", "h3", "h4", "h5", "h6",
  "blockquote", "pre", "table", "ul", "ol", "header", "footer", "main", "nav", "aside",
]);

function extractText(html: string): string {
  const parts: string[] = [];
  let depth = 0;
  let skip = 0;

  const parser = new htmlparser2.Parser({
    onopentag(name) {
      depth++;
      // Only start a skip when not already inside one, so a nested skip-tag's
      // close (e.g. <noscript><iframe/>leak</noscript>) can't end the outer skip
      if (skip === 0 && ["script", "style", "noscript", "iframe", "object", "embed"].includes(name)) {
        skip = depth;
      }
      if (skip === 0 && (name === "br" || name === "hr")) parts.push("\n");
    },
    ontext(text) {
      if (skip === 0) parts.push(text);
    },
    onclosetag(name) {
      if (skip === depth) skip = 0;
      depth--;
      // Separate block elements so "<div>foo</div><div>bar</div>" isn't "foobar"
      if (skip === 0 && BLOCK_TAGS.has(name)) parts.push("\n");
    },
  });

  parser.write(html);
  parser.end();
  return parts
    .join("")
    .replace(/[ \t]+\n/g, "\n")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

// ─── Truncation ────────────────────────────────────────────────────────────────

function truncateOutput(text: string): string {
  const lines = text.split("\n");
  const overLines = lines.length > MAX_OUTPUT_LINES;
  if (overLines) lines.length = MAX_OUTPUT_LINES;

  let result = lines.join("\n");
  const overBytes = Buffer.byteLength(result, "utf8") > MAX_OUTPUT_BYTES;
  if (overBytes) {
    const bytes = Buffer.from(result, "utf8").subarray(0, MAX_OUTPUT_BYTES);
    // Non-fatal decode turns a trailing cut multi-byte sequence into a single U+FFFD;
    // strip at most one (may rarely eat a legitimate trailing U+FFFD — acceptable).
    result = new TextDecoder("utf-8", { fatal: false }).decode(bytes).replace(/�$/, "");
  }

  if (overLines || overBytes) {
    const reasons = [
      ...(overLines ? [`${MAX_OUTPUT_LINES} lines`] : []),
      ...(overBytes ? [`${MAX_OUTPUT_BYTES} bytes`] : []),
    ];
    result += `\n\n[Output truncated: exceeded ${reasons.join(" and ")} limit]`;
  }

  return result;
}

// ─── Bounded body reading ──────────────────────────────────────────────────────

/** Read at most maxBytes of a response body as UTF-8 text, cancelling the rest. */
async function readTextCapped(response: Response, maxBytes: number): Promise<string> {
  const decoder = new TextDecoder("utf-8", { fatal: false });
  if (!response.body) {
    const buf = new Uint8Array(await response.arrayBuffer());
    return decoder.decode(buf.subarray(0, maxBytes));
  }
  const reader = response.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const room = maxBytes - total;
    if (value.byteLength >= room) {
      chunks.push(value.subarray(0, room));
      total = maxBytes;
      await reader.cancel().catch(() => {});
      break;
    }
    chunks.push(value);
    total += value.byteLength;
  }
  return decoder.decode(Buffer.concat(chunks, total));
}

// ─── SSE / JSON-RPC result parser ──────────────────────────────────────────────

function extractContent(json: unknown): string | undefined {
  const obj = json as {
    error?: { message?: unknown };
    result?: { content?: unknown };
  };
  // Surface JSON-RPC errors instead of masking them as "no results"
  if (obj?.error) {
    const msg =
      typeof obj.error.message === "string" ? obj.error.message : JSON.stringify(obj.error);
    throw new Error(`Search provider error: ${msg}`);
  }
  const contentItems = obj?.result?.content;
  if (Array.isArray(contentItems)) {
    for (const item of contentItems) {
      if (item?.text && typeof item.text === "string" && item.text.trim()) {
        return item.text;
      }
    }
  }
  return undefined;
}

function parseSearchResponse(body: string): string | undefined {
  const trimmed = body.trim();

  // Try direct JSON decode
  if (trimmed.startsWith("{")) {
    let json: unknown;
    try {
      json = JSON.parse(trimmed);
    } catch {
      json = undefined; // Fall through to SSE parsing
    }
    if (json !== undefined) {
      const text = extractContent(json);
      if (text) return text;
    }
  }

  // Try SSE: events are separated by blank lines; multiple data lines per event
  // are joined with \n ("data:" with or without the following space is spec-legal)
  let dataLines: string[] = [];
  const flush = (): string | undefined => {
    if (dataLines.length === 0) return undefined;
    const payload = dataLines.join("\n").trim();
    dataLines = [];
    if (!payload.startsWith("{")) return undefined;
    let frame: unknown;
    try {
      frame = JSON.parse(payload);
    } catch {
      return undefined; // skip unparseable frames
    }
    return extractContent(frame);
  };

  for (const line of body.split(/\r?\n/)) {
    if (line === "") {
      const text = flush();
      if (text) return text;
      continue;
    }
    const match = line.match(/^data:\s?(.*)$/);
    if (match) dataLines.push(match[1]);
  }
  const text = flush();
  if (text) return text;

  return undefined;
}

// ─── DuckDuckGo fallback search ───────────────────────────────────────────────

function unwrapDdgUrl(href: string): string {
  try {
    if (href.startsWith("//")) href = `https:${href}`;
    const uddg = new URL(href).searchParams.get("uddg");
    if (uddg) return decodeURIComponent(uddg);
  } catch {
    // keep original href
  }
  return href;
}

async function searchDuckDuckGo(
  query: string,
  numResults: number,
  signal?: AbortSignal
): Promise<string> {
  const response = await fetch("https://lite.duckduckgo.com/lite/", {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "User-Agent": CHROME_UA,
      Accept: "text/html",
    },
    body: new URLSearchParams({ q: query }).toString(),
    signal,
  });
  if (!response.ok) {
    throw new Error(`DuckDuckGo search failed (HTTP ${response.status})`);
  }
  const html = await readTextCapped(response, MAX_FETCH_BYTES);

  const doc = htmlparser2.parseDocument(html, { decodeEntities: true });
  const results: { title: string; url: string; snippet: string }[] = [];

  const getText = (node: unknown): string => {
    const n = node as { type?: string; data?: string; children?: unknown[] };
    if (n.type === "text") return n.data ?? "";
    if (Array.isArray(n.children)) return n.children.map(getText).join("");
    return "";
  };

  const walk = (node: unknown): void => {
    const n = node as {
      type?: string;
      tagName?: string;
      attribs?: Record<string, string>;
      children?: unknown[];
    };
    // Don't early-return on non-tags (root/document): keep descending.
    if (n.type === "tag") {
      if (n.tagName === "a" && n.attribs?.class === "result-link") {
        results.push({
          title: getText(n).trim(),
          url: unwrapDdgUrl(n.attribs.href ?? ""),
          snippet: "",
        });
      } else if (
        n.tagName === "td" &&
        n.attribs?.class === "result-snippet" &&
        results.length > 0 &&
        !results[results.length - 1].snippet
      ) {
        results[results.length - 1].snippet = getText(n).replace(/\s+/g, " ").trim();
      }
    }

    for (const child of n.children ?? []) walk(child);
  };
  walk(doc);

  const limited = results.filter((r) => r.title && r.url).slice(0, numResults);
  if (limited.length === 0) {
    throw new Error("DuckDuckGo returned no results");
  }

  return limited
    .map((r, i) => `${i + 1}. ${r.title}\n   URL: ${r.url}${r.snippet ? `\n   ${r.snippet}` : ""}`)
    .join("\n\n");
}

// ─── Extension ─────────────────────────────────────────────────────────────────

export default function (pi: ExtensionAPI) {
  // ── websearch ──────────────────────────────────────────────────────────────

  pi.registerTool({
    name: "websearch",
    label: "Web Search",
    promptSnippet:
      "Search the web for current information: websearch({ query, numResults?, livecrawl?, type?, contextMaxCharacters? })",
    promptGuidelines: [
      "Use websearch to find up-to-date information, current events, and recent data beyond your knowledge cutoff.",
      "When searching for recent information, include the current year in your query if relevant.",
      "Use webfetch after websearch when you need to read the full content of a specific URL found in search results.",
    ],
    description: `Search the web using Exa - performs real-time web searches and returns content from the most relevant websites.
- Provides up-to-date information for current events and recent data
- Supports configurable result counts
- Use this tool for accessing information beyond your knowledge cutoff
- Searches are performed within a single API call

Usage notes:
  - livecrawl: 'fallback' (backup if cached unavailable) or 'preferred' (prioritize live crawling)
  - type: 'auto' (balanced), 'fast' (quick results), or 'deep' (comprehensive search)

The current year is ${new Date().getFullYear()}. You MUST use this year when searching for recent information or current events.`,
    parameters: Type.Object({
      query: Type.String({ description: "Search query string" }),
      numResults: Type.Optional(
        Type.Integer({
          minimum: 1,
          maximum: 20,
          description: "Number of results to return (default: 8, max: 20)",
        })
      ),
      livecrawl: Type.Optional(
        StringEnum(["fallback", "preferred"] as const, {
          description: "Crawl mode: 'fallback' (default) or 'preferred'",
        })
      ),
      type: Type.Optional(
        StringEnum(["auto", "fast", "deep"] as const, {
          description: "Search type: 'auto' (default), 'fast', or 'deep'",
        })
      ),
      contextMaxCharacters: Type.Optional(
        Type.Integer({
          minimum: 100,
          maximum: 50_000,
          description: "Max characters of context to return (server default ~10000)",
        })
      ),
    }),
    async execute(_toolCallId, params, signal) {
      const numResults = params.numResults ?? 8;
      const livecrawl = params.livecrawl ?? "fallback";
      const searchType = params.type ?? "auto";

      const arguments_: Record<string, unknown> = {
        query: params.query,
        type: searchType,
        numResults,
        livecrawl,
      };
      if (params.contextMaxCharacters != null) {
        arguments_.contextMaxCharacters = params.contextMaxCharacters;
      }

      const body = JSON.stringify({
        jsonrpc: "2.0",
        id: 1,
        method: "tools/call",
        params: {
          name: "web_search_exa",
          arguments: arguments_,
        },
      });

      const controller = new AbortController();
      const linkedSignal = signal
        ? AbortSignal.any([signal, controller.signal])
        : controller.signal;
      const timer = setTimeout(() => controller.abort(), 25_000);

      const runExa = async (): Promise<string | undefined> => {
        const response = await fetch(exaUrl(), {
          method: "POST",
          headers: {
            Accept: "application/json, text/event-stream",
            "Content-Type": "application/json",
          },
          body,
          signal: linkedSignal,
        });

        if (!response.ok) {
          const text = await readTextCapped(response, 4096).catch(() => "");
          throw new Error(`Search failed (HTTP ${response.status}): ${text.slice(0, 500)}`);
        }

        const responseText = await readTextCapped(response, MAX_FETCH_BYTES);
        const result = parseSearchResponse(responseText);

        return result;
      };

      let text: string;
      try {
        text = (await runExa()) ?? "";
      } catch (exaErr: unknown) {
        // User cancellation is not an Exa failure — don't fall back on it.
        if (signal?.aborted) throw exaErr;

        let msg = exaErr instanceof Error ? exaErr.message : String(exaErr);
        if (/rate limit/i.test(msg)) {
          msg += " (Hint: set the EXA_API_KEY environment variable to avoid free-tier rate limits.)";
        }
        try {
          const ddg = await searchDuckDuckGo(params.query, numResults, linkedSignal);
          text = `[Exa unavailable: ${msg} — showing DuckDuckGo results]\n\n${ddg}`;
        } catch (ddgErr: unknown) {
          const ddgMsg = ddgErr instanceof Error ? ddgErr.message : String(ddgErr);
          throw new Error(`Exa: ${msg} | DuckDuckGo fallback: ${ddgMsg}`);
        }
      }

      try {
        if (!text.trim()) {
          try {
            text = await searchDuckDuckGo(params.query, numResults, linkedSignal);
          } catch {
            return {
              content: [
                {
                  type: "text" as const,
                  text: "No search results found. Please try a different query.",
                },
              ],
              details: {},
            };
          }
        }

        return {
          content: [{ type: "text" as const, text: truncateOutput(text) }],
          details: {},
        };
      } finally {
        clearTimeout(timer);
      }
    },
  });

  // ── webfetch ───────────────────────────────────────────────────────────────

  pi.registerTool({
    name: "webfetch",
    label: "Web Fetch",
    promptSnippet:
      "Fetch and convert web page content: webfetch({ url, format?, timeout? })",
    promptGuidelines: [
      "Use webfetch when you need to retrieve and analyze content from a specific URL.",
      "If websearch is available, use it first to discover URLs, then use webfetch to read the full content.",
      "The URL must be a fully-formed valid URL starting with http:// or https://.",
      "Format options: 'markdown' (default), 'text', or 'html'.",
      "This tool is read-only and does not modify any files.",
    ],
    description: `Fetches content from a specified URL and converts it to the requested format.
- Takes a URL and optional format as input
- Fetches the URL content, converts to requested format (markdown by default)
- Returns the content in the specified format
- Use this tool when you need to retrieve and analyze web content

Usage notes:
  - The URL must be a fully-formed valid URL starting with http:// or https://
  - Format options: "markdown" (default), "text", or "html"
  - Format conversion applies to HTML responses; non-HTML content (JSON, plain text, etc.) is returned as-is regardless of format
  - Images (png/jpeg/gif/webp) are returned as viewable attachments
  - This tool is read-only and does not modify any files`,
    parameters: Type.Object({
      url: Type.String({
        description:
          "The URL to fetch. Must be a fully-formed valid URL starting with http:// or https://",
      }),
      format: Type.Optional(
        StringEnum(["text", "markdown", "html"] as const, {
          description:
            "Output format: 'markdown' (default), 'text' (plain text), or 'html' (raw HTML)",
        })
      ),
      timeout: Type.Optional(
        Type.Integer({
          minimum: 1,
          maximum: 120,
          description: "Request timeout in seconds (default: 30, max: 120)",
        })
      ),
    }),
    async execute(_toolCallId, params, signal) {
      const url = params.url.trim();
      const format = params.format ?? "markdown";
      const timeoutSec = Math.min(Math.max(params.timeout ?? 30, 1), 120);

      // Validate URL prefix
      if (!url.startsWith("http://") && !url.startsWith("https://")) {
        throw new Error(
          `Invalid URL: "${url}". URL must start with http:// or https://`
        );
      }

      // One timeout budget for the whole call (request + body read), so a server
      // that sends headers fast but dribbles the body forever is still bounded.
      const controller = new AbortController();
      const linkedSignal = signal
        ? AbortSignal.any([signal, controller.signal])
        : controller.signal;
      const timer = setTimeout(() => controller.abort(), timeoutSec * 1000);

      const doFetch = (userAgent: string): Promise<Response> =>
        fetch(url, {
          method: "GET",
          headers: {
            "User-Agent": userAgent,
            "Accept-Language": "en-US,en;q=0.9",
            Accept: ACCEPT_HEADERS[format] ?? ACCEPT_HEADERS.markdown,
          },
          signal: linkedSignal,
          redirect: "follow",
        });

      try {

        // First attempt with Chrome UA
        let response = await doFetch(CHROME_UA);

        // Cloudflare retry: on 403 with cf-mitigated header, retry with honest UA
        // (Cloudflare flags the Chrome-UA-on-Node-TLS mismatch; the honest UA passes)
        if (
          response.status === 403 &&
          response.headers.get("cf-mitigated") === "challenge"
        ) {
          // Release the first response's connection before refetching
          await response.body?.cancel().catch(() => {});
          response = await doFetch("pi");
        }

        if (!response.ok) {
          const errText = await readTextCapped(response, 4096).catch(() => "");
          throw new Error(
            `Failed to fetch "${url}" (HTTP ${response.status}): ${errText.slice(0, 500)}`
          );
        }

        const contentType = (response.headers.get("content-type") ?? "").toLowerCase();
        // Sniff MIME: content up to first ;
        const mime = contentType.split(";")[0]?.trim() ?? "";
        const title = `${url} (${contentType || "unknown"})`;

        // Stream the body, keeping at most MAX_FETCH_BYTES. Oversized responses are
        // truncated (and the transfer cancelled), not rejected — the output gets
        // tail-truncated to MAX_OUTPUT_BYTES anyway.
        let bodyBytes: Uint8Array;
        let bodyTruncated = false;
        if (response.body) {
          const reader = response.body.getReader();
          const chunks: Uint8Array[] = [];
          let total = 0;
          while (true) {
            const { done, value } = await reader.read();
            if (done) break;
            if (total + value.byteLength > MAX_FETCH_BYTES) {
              chunks.push(value.subarray(0, MAX_FETCH_BYTES - total));
              total = MAX_FETCH_BYTES;
              bodyTruncated = true;
              await reader.cancel().catch(() => {});
              break;
            }
            chunks.push(value);
            total += value.byteLength;
          }
          bodyBytes = Buffer.concat(chunks, total);
        } else {
          bodyBytes = new Uint8Array(await response.arrayBuffer());
          if (bodyBytes.byteLength > MAX_FETCH_BYTES) {
            bodyBytes = bodyBytes.subarray(0, MAX_FETCH_BYTES);
            bodyTruncated = true;
          }
        }

        // Image branch — only formats vision-capable providers actually accept
        const SUPPORTED_IMAGE_MIMES = new Set([
          "image/png",
          "image/jpeg",
          "image/gif",
          "image/webp",
        ]);
        // (svg is textual — let it fall through to the text/markdown path)
        if (mime.startsWith("image/") && mime !== "image/svg+xml") {
          if (!SUPPORTED_IMAGE_MIMES.has(mime)) {
            throw new Error(
              `Unsupported image type "${mime}" (supported: png, jpeg, gif, webp): ${url}`
            );
          }
          if (bodyTruncated) {
            // A truncated image is corrupt data; unlike text there is no useful prefix.
            throw new Error(
              `Image too large (exceeds ${MAX_FETCH_BYTES} bytes limit): ${url}`
            );
          }
          return {
            content: [
              { type: "text" as const, text: "Image fetched successfully" },
              {
                type: "image" as const,
                data: Buffer.from(bodyBytes).toString("base64"),
                mimeType: mime,
              },
            ],
            details: { title },
          };
        }

        // Decode using the declared charset when present (unknown labels → UTF-8)
        const charset = contentType.match(/charset=["']?([\w.-]+)/)?.[1] ?? "utf-8";
        let decoder: TextDecoder;
        try {
          decoder = new TextDecoder(charset, { fatal: false });
        } catch {
          decoder = new TextDecoder("utf-8", { fatal: false });
        }
        const rawBody = decoder.decode(bodyBytes);

        // Format conversion
        const isHtml =
          contentType.includes("text/html") || contentType.includes("application/xhtml+xml");
        let output: string = rawBody;

        if (isHtml) {
          switch (format) {
            case "markdown":
              try {
                output = turndown.turndown(rawBody);
              } catch {
                // turndown is recursive; deeply-nested hostile HTML can overflow the
                // stack. Fall back to the streaming, non-recursive text extractor.
                output = extractText(rawBody);
              }
              break;
            case "text":
              output = extractText(rawBody);
              break;
            case "html":
              output = rawBody;
              break;
          }
        }
        // Non-HTML: returned verbatim regardless of requested format

        let text = truncateOutput(output);
        if (bodyTruncated) {
          text += `\n\n[Response body exceeded ${MAX_FETCH_BYTES} bytes; only the first ${MAX_FETCH_BYTES} bytes were fetched and converted]`;
        }

        return {
          content: [{ type: "text" as const, text }],
          details: { title },
        };
      } catch (err: unknown) {
        const isAbort = err instanceof Error && err.name === "AbortError";
        if (isAbort && linkedSignal.aborted && !signal?.aborted) {
          throw new Error(
            `Fetch of "${url}" timed out after ${timeoutSec} seconds.`
          );
        }
        throw err;
      } finally {
        clearTimeout(timer);
      }
    },
  });
}
