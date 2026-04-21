import OpenAI from "openai";
import { BaseAIProvider } from "./base.js";

export class OpenAIProvider extends BaseAIProvider {
  constructor(config) {
    super(config);
    this.client = new OpenAI({ apiKey: config.api_key });
  }

  async analyze({ systemPrompt, userMessage }) {
    const response = await this.client.chat.completions.create({
      model: this.config.model,
      max_tokens: this.config.max_tokens ?? 4096,
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userMessage },
      ],
    });

    const rawText = response.choices[0]?.message?.content ?? "";
    return this.parseOutputs(rawText);
  }
}
