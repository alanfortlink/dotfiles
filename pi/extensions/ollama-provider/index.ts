import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// Ollama server endpoint. Override with the OLLAMA_BASE_URL env var if needed
// (e.g. a remote host). Defaults to the local server.
const OLLAMA_BASE_URL =
  process.env.OLLAMA_BASE_URL?.replace(/\/$/, "") ?? "http://localhost:11434";

// Raw shape returned by Ollama's /api/tags endpoint.
interface OllamaTagsResponse {
  models: Array<{
    name: string; // e.g. "qwen3.5:35b" — also the id used in /v1/chat/completions
    details?: {
      context_length?: number;
    };
    capabilities?: string[]; // "completion" | "tools" | "thinking" | "vision"
  }>;
}

export default async function (pi: ExtensionAPI) {
  let tags: OllamaTagsResponse;
  try {
    const res = await fetch(`${OLLAMA_BASE_URL}/api/tags`);
    if (!res.ok) {
      console.error(
        `[ollama-provider] /api/tags returned ${res.status} ${res.statusText}`
      );
      return;
    }
    tags = (await res.json()) as OllamaTagsResponse;
  } catch (err) {
    console.error(
      "[ollama-provider] could not reach Ollama at",
      OLLAMA_BASE_URL,
      err instanceof Error ? err.message : err
    );
    return;
  }

  const models = tags.models
    // Skip embedding-only models; they have no "completion" capability.
    .filter((m) => m.capabilities?.includes("completion") ?? true)
    .map((m) => {
      const caps = m.capabilities ?? [];
      const reasoning = caps.includes("thinking");
      const vision = caps.includes("vision");
      const contextWindow = m.details?.context_length ?? 8192;

      return {
        id: m.name,
        name: m.name,
        reasoning,
        input: vision ? (["text", "image"] as const) : (["text"] as const),
        // Local models are free.
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow,
        maxTokens: Math.min(contextWindow, 32768),
      };
    });

  if (models.length === 0) {
    console.error("[ollama-provider] no chat models found in Ollama");
    return;
  }

  pi.registerProvider("ollama", {
    name: "Ollama (local)",
    baseUrl: `${OLLAMA_BASE_URL}/v1`,
    api: "openai-completions",
    // Ollama ignores the key, but pi requires *some* auth before models
    // appear in /model. Use a literal placeholder.
    apiKey: "ollama",
    // Most local OpenAI-compatible servers reject OpenAI's `developer` role
    // and `reasoning_effort` field, so disable both globally.
    compat: {
      supportsDeveloperRole: false,
      supportsReasoningEffort: false,
    },
    models,
  });
}