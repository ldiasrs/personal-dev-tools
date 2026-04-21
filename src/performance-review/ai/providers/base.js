export class BaseAIProvider {
  constructor(config) {
    this.config = config;
  }

  // eslint-disable-next-line no-unused-vars
  async analyze({ systemPrompt, userMessage }) {
    throw new Error(`analyze() not implemented in ${this.constructor.name}`);
  }

  parseOutputs(rawText) {
    const marker = "---SIMPLIFIED---";
    const idx = rawText.indexOf(marker);

    if (idx === -1) {
      return { fullReview: rawText.trim(), simplifiedReview: "" };
    }

    return {
      fullReview: rawText.slice(0, idx).trim(),
      simplifiedReview: rawText.slice(idx + marker.length).trim(),
    };
  }
}
