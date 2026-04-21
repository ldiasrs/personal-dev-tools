import { AnthropicProvider } from "./providers/anthropic.js";
import { OpenAIProvider } from "./providers/openai.js";

const PROVIDERS = {
  anthropic: AnthropicProvider,
  openai: OpenAIProvider,
};

export function createProvider(aiConfig) {
  const Provider = PROVIDERS[aiConfig.provider];
  if (!Provider) {
    throw new Error(
      `Unknown AI provider "${aiConfig.provider}". Supported: ${Object.keys(PROVIDERS).join(", ")}`
    );
  }
  return new Provider(aiConfig);
}
