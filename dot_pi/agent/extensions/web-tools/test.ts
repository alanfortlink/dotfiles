import TurndownService from "turndown";
import * as htmlparser2 from "htmlparser2";

const MAX_OUTPUT_LINES = 2000;
const MAX_OUTPUT_BYTES = 50 * 1024;

// ─── Test 1: Turndown (HTML → Markdown) ──────────────────────────────────────

const turndown = new TurndownService({
  headingStyle: "atx",
  hr: "---",
  bulletListMarker: "-",
  codeBlockStyle: "fenced",
  emDelimiter: "*",
});
turndown.remove(["script", "style", "meta", "link"]);

function test1() {
  const html = `<html><head><title>Test</title><style>body { color: red; }</style></head>
<body><h1>Hello World</h1><p>This is a <strong>test</strong> page.</p><ul><li>Item 1</li><li>Item 2</li></ul></body></html>`;

  const markdown = turndown.turndown(html);
  console.log("=== Test 1: Turndown HTML→Markdown ===");
  console.log(markdown);
  console.log(markdown.includes("# Hello World") ? "✓ PASS" : "✗ FAIL - missing heading");
  console.log(markdown.includes("**test**") ? "✓ PASS" : "✗ FAIL - missing bold");
  console.log(markdown.includes("Item 1") ? "✓ PASS" : "✗ FAIL - missing list item");
  console.log(markdown.includes("style") ? "✗ FAIL - style not removed" : "✓ PASS");
}

// ─── Test 2: HTML → Plain text extraction ────────────────────────────────────

function extractText(html: string): string {
  const parts: string[] = [];
  let depth = 0;
  let skip = 0;

  const parser = new htmlparser2.Parser({
    onopentag(name: string) {
      depth++;
      if (["script", "style", "noscript", "iframe", "object", "embed"].includes(name)) {
        skip = depth;
      }
    },
    ontext(text: string) {
      if (skip === 0) parts.push(text);
    },
    onclosetag() {
      if (skip === depth) skip = 0;
      depth--;
    },
  });

  parser.write(html);
  parser.end();
  return parts.join("").trim();
}

function test2() {
  console.log("\n=== Test 2: HTML→Text extraction ===");
  const html = `<html><head><title>Test</title><style>body { color: red; }</style></head>
<body><h1>Hello World</h1><p>This is a <strong>test</strong> page.</p><ul><li>Item 1</li><li>Item 2</li></ul></body></html>`;
  const extracted = extractText(html);
  console.log("Output:", JSON.stringify(extracted));
  console.log(extracted.includes("Hello World") && extracted.includes("test") && extracted.includes("Item 1") ? "✓ PASS" : "✗ FAIL - got: " + JSON.stringify(extracted));

  const withScript = "<html><script>alert('xss')</script><p>Visible</p><style>body{}</style></html>";
  const stripped = extractText(withScript);
  console.log("Script/style stripped:", JSON.stringify(stripped));
  console.log(stripped === "Visible" ? "✓ PASS" : "✗ FAIL - got: " + JSON.stringify(stripped));
}

// ─── Test 3: Truncation ──────────────────────────────────────────────────────

function truncateOutput(text: string): string {
  const lines = text.split("\n");
  let truncated = false;

  if (lines.length > MAX_OUTPUT_LINES) {
    lines.length = MAX_OUTPUT_LINES;
    truncated = true;
  }

  let result = lines.join("\n");
  if (result.length > MAX_OUTPUT_BYTES) {
    result = result.slice(0, MAX_OUTPUT_BYTES);
    truncated = true;
  }

  if (truncated) {
    result +=
      "\n\n[Output truncated: exceeded " +
      MAX_OUTPUT_LINES +
      " lines / " +
      MAX_OUTPUT_BYTES +
      " bytes limit]";
  }

  return result;
}

function test3() {
  console.log("\n=== Test 3: Truncation ===");
  const short = "short text";
  console.log("Short text unchanged:", truncateOutput(short) === short ? "✓ PASS" : "✗ FAIL");

  const manyLines = Array.from({ length: 2500 }, (_, i) => `Line ${i}`).join("\n");
  const truncatedLines = truncateOutput(manyLines);
  console.log("Lines truncated to ~2000:", truncatedLines.split("\n").length <= 2002 ? "✓ PASS" : "✗ FAIL (" + truncatedLines.split("\n").length + " lines)");
  console.log("Has truncation notice:", truncatedLines.includes("[Output truncated") ? "✓ PASS" : "✗ FAIL");

  const bigText = "x".repeat(MAX_OUTPUT_BYTES + 500);
  const truncatedBytes = truncateOutput(bigText);
  console.log("Bytes truncated:", truncatedBytes.length <= MAX_OUTPUT_BYTES + 150 ? "✓ PASS" : "✗ FAIL");
}

// ─── Test 4: SSE / JSON-RPC parser ───────────────────────────────────────────

function parseSearchResponse(body: string): string | undefined {
  const trimmed = body.trim();

  if (trimmed.startsWith("{")) {
    try {
      const json = JSON.parse(trimmed);
      const contentItems = json?.result?.content;
      if (Array.isArray(contentItems)) {
        for (const item of contentItems) {
          if (item?.text && typeof item.text === "string" && item.text.trim()) {
            return item.text;
          }
        }
      }
    } catch {
      // Fall through
    }
  }

  for (const line of trimmed.split("\n")) {
    if (!line.startsWith("data: ")) continue;
    const payload = line.slice(6).trim();
    if (!payload.startsWith("{")) continue;
    try {
      const frame = JSON.parse(payload);
      const contentItems = frame?.result?.content;
      if (Array.isArray(contentItems)) {
        for (const item of contentItems) {
          if (item?.text && typeof item.text === "string" && item.text.trim()) {
            return item.text;
          }
        }
      }
    } catch {
      // skip
    }
  }

  return undefined;
}

function test4() {
  console.log("\n=== Test 4: SSE/JSON-RPC parser ===");

  const jsonResp = JSON.stringify({
    result: { content: [{ type: "text", text: "Search result text here" }] },
  });
  const jsonParsed = parseSearchResponse(jsonResp);
  console.log("JSON parsed:", jsonParsed === "Search result text here" ? "✓ PASS" : "✗ FAIL");

  const jsonMulti = JSON.stringify({
    result: {
      content: [
        { type: "text", text: "" },
        { type: "text", text: "Second item" },
      ],
    },
  });
  const jsonMultiParsed = parseSearchResponse(jsonMulti);
  console.log("Multi-item first non-empty:", jsonMultiParsed === "Second item" ? "✓ PASS" : "✗ FAIL - got: " + jsonMultiParsed);

  const sseResp = `data: {"result":{"content":[{"type":"text","text":"SSE result"}]}}\n\ndata: [DONE]`;
  const sseParsed = parseSearchResponse(sseResp);
  console.log("SSE parsed:", sseParsed === "SSE result" ? "✓ PASS" : "✗ FAIL - got: " + sseParsed);

  console.log("Invalid returns undefined:", parseSearchResponse("garbage") === undefined ? "✓ PASS" : "✗ FAIL");
  console.log("Empty returns undefined:", parseSearchResponse("") === undefined ? "✓ PASS" : "✗ FAIL");

  const jsonError = JSON.stringify({ error: { code: -1, message: "bad" } });
  console.log("JSON-RPC error returns undefined:", parseSearchResponse(jsonError) === undefined ? "✓ PASS" : "✗ FAIL");
}

// ─── Main ────────────────────────────────────────────────────────────────────

async function main() {
  test1();
  test2();
  test3();
  test4();

  // ─── Test 5: Live websearch endpoint ───────────────────────────────────────

  console.log("\n=== Test 5: Live Exa API call ===");

  const searchBody = JSON.stringify({
    jsonrpc: "2.0",
    id: 1,
    method: "tools/call",
    params: {
      name: "web_search_exa",
      arguments: { query: "pi coding agent terminal", type: "auto", numResults: 3, livecrawl: "fallback" },
    },
  });

  try {
    const resp = await fetch("https://mcp.exa.ai/mcp", {
      method: "POST",
      headers: {
        Accept: "application/json, text/event-stream",
        "Content-Type": "application/json",
      },
      body: searchBody,
      signal: AbortSignal.timeout(15_000),
    });
    console.log("HTTP status:", resp.status);
    const text = await resp.text();
    console.log("Response length:", text.length, "bytes");
    console.log("First 500 chars:", text.slice(0, 500));

    const parsed = parseSearchResponse(text);
    if (parsed) {
      console.log("✓ PASS - Parsed result (" + parsed.length + " chars)");
      console.log("Preview:", parsed.slice(0, 300) + "...");
    } else {
      console.log("✗ FAIL - Could not parse result");
      console.log("Raw body type:", text.startsWith("{") ? "JSON" : text.startsWith("data:") ? "SSE" : "unknown");
    }
  } catch (err: any) {
    console.log("✗ FAIL - Error:", err.message);
  }

  // ─── Test 6: Live webfetch ─────────────────────────────────────────────────

  console.log("\n=== Test 6: Live webfetch ===");

  try {
    const resp = await fetch("https://example.com", {
      method: "GET",
      headers: {
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
        Accept: "text/markdown;q=1.0, text/x-markdown;q=0.9, text/plain;q=0.8, text/html;q=0.7, */*;q=0.1",
      },
      signal: AbortSignal.timeout(15_000),
    });

    console.log("HTTP status:", resp.status);
    const contentType = resp.headers.get("content-type") ?? "";
    console.log("Content-Type:", contentType);

    const buf = await resp.arrayBuffer();
    console.log("Size:", buf.byteLength, "bytes");

    const rawBody = new TextDecoder("utf-8", { fatal: false }).decode(buf);
    const isHtml = contentType.includes("text/html");

    if (isHtml) {
      const md = turndown.turndown(rawBody);
      console.log("Markdown conversion (" + md.length + " chars):");
      console.log(md.slice(0, 400));
    } else {
      console.log("Raw text:", rawBody.slice(0, 400));
    }

    console.log("✓ PASS");
  } catch (err: any) {
    console.log("✗ FAIL - Error:", err.message);
  }

  console.log("\n=== All tests complete ===");
}

main().catch((err: unknown) => {
  console.error("Fatal:", err);
  process.exit(1);
});
