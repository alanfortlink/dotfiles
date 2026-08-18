import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

// LM Studio server endpoint. Override with LMSTUDIO_BASE_URL if needed.
const LMSTUDIO_BASE_URL =
  process.env.LMSTUDIO_BASE_URL?.replace(/\/$/, "") ?? "http://10.0.0.75:1234";

// Shape returned by LM Studio's native /api/v1/models endpoint.
interface LmStudioModelsResponse {
  models: Array<{
    type: "llm" | "embeddings" | string;
    key: string; // id used in /v1/chat/completions
    display_name?: string;
    max_context_length?: number;
    loaded_instances?: Array<{ context_length?: number }>;
    capabilities?: {
      vision?: boolean;
      trained_for_tool_use?: boolean;
      reasoning?: { allowed_options?: string[]; default?: string };
    };
  }>;
}

export default async function (pi: ExtensionAPI) {
  let data: LmStudioModelsResponse;
  try {
    const res = await fetch(`${LMSTUDIO_BASE_URL}/api/v1/models`);
    if (!res.ok) {
      console.error(
        `[lmstudio-provider] /api/v1/models returned ${res.status} ${res.statusText}`
      );
      return;
    }
    data = (await res.json()) as LmStudioModelsResponse;
  } catch (err) {
    console.error(
      "[lmstudio-provider] could not reach LM Studio at",
      LMSTUDIO_BASE_URL,
      err instanceof Error ? err.message : err
    );
    return;
  }

  const models = data.models
    .filter((m) => m.type === "llm")
    .map((m) => {
      const caps = m.capabilities ?? {};
      const reasoningOpts = caps.reasoning?.allowed_options ?? [];
      const reasoning = reasoningOpts.some((o) => o !== "off");
      const vision = caps.vision === true;
      // Prefer the context the model is actually loaded with; fall back to its max.
      const contextWindow =
        m.loaded_instances?.[0]?.context_length ?? m.max_context_length ?? 8192;

      return {
        id: m.key,
        name: m.display_name ?? m.key,
        reasoning,
        input: vision ? (["text", "image"] as const) : (["text"] as const),
        // Local models are free.
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow,
        maxTokens: Math.min(contextWindow, 32768),
      };
    });

  if (models.length === 0) {
    console.error("[lmstudio-provider] no chat models found in LM Studio");
    return;
  }

  pi.registerProvider("lmstudio", {
    name: "LM Studio (Mac)",
    baseUrl: `${LMSTUDIO_BASE_URL}/v1`,
    api: "openai-completions",
    // LM Studio ignores the key, but pi requires *some* auth before models
    // appear in /model. Use a literal placeholder.
    apiKey: "lmstudio",
    // Most local OpenAI-compatible servers reject OpenAI's `developer` role
    // and `reasoning_effort` field, so disable both globally.
    compat: {
      supportsDeveloperRole: false,
      supportsReasoningEffort: false,
    },
    models,
  });
}
