import Anthropic from "@anthropic-ai/sdk";
import { BaseAIProvider } from "./base.js";

export class AnthropicProvider extends BaseAIProvider {
  constructor(config) {
    super(config);
    this.client = new Anthropic({ apiKey: config.api_key });
  }

  async analyze({ systemPrompt, userMessage }) {
    const response = await this.client.messages.create({
      model: this.config.model,
      max_tokens: 4096,
      system: [
        {
          type: "text",
          text: systemPrompt,
          cache_control: { type: "ephemeral" },
        },
      ],
      messages: [
        {
          role: "user",
          content: [
            {
              type: "text",
              text: userMessage,
            },
          ],
        },
      ],
    });

    const rawText = response.content
      .filter((b) => b.type === "text")
      .map((b) => b.text)
      .join("");

    const usage = response.usage;
    if (usage?.cache_read_input_tokens > 0) {
      console.log(`Cache hit: ${usage.cache_read_input_tokens} tokens read from cache.`);
    }

    return this.parseOutputs(rawText);
  }
}
