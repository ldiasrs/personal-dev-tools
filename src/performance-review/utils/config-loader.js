import { readFileSync } from "fs";
import { resolve } from "path";
import yaml from "js-yaml";

const CONFIG_PATH = resolve("performance-review/config/config.yaml");

const REQUIRED_FIELDS = [
  ["user.name", (c) => c.user?.name],
  ["user.git_identities", (c) => c.user?.git_identities?.length > 0],
  ["repos", (c) => c.repos?.length > 0],
  ["ai.provider", (c) => c.ai?.provider],
  ["ai.model", (c) => c.ai?.model],
  ["ai.api_key", (c) => c.ai?.api_key],
  ["profile.role", (c) => c.profile?.role],
  ["profile.expectations", (c) => c.profile?.expectations],
];

const SUPPORTED_PROVIDERS = ["anthropic", "openai"];

export function loadConfig() {
  let raw;
  try {
    raw = readFileSync(CONFIG_PATH, "utf8");
  } catch {
    throw new Error(
      `Config file not found at ${CONFIG_PATH}\n` +
        `Copy performance-review/config-sample/config.yaml to performance-review/config/config.yaml and fill it in.`
    );
  }

  const config = yaml.load(raw);

  for (const [field, check] of REQUIRED_FIELDS) {
    if (!check(config)) {
      throw new Error(`Missing required config field: ${field}`);
    }
  }

  if (!SUPPORTED_PROVIDERS.includes(config.ai.provider)) {
    throw new Error(
      `Unsupported AI provider "${config.ai.provider}". Supported: ${SUPPORTED_PROVIDERS.join(", ")}`
    );
  }

  return config;
}
