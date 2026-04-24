import { spawn } from "child_process";
import { BaseAIProvider } from "./base.js";

export class ClaudeCodeProvider extends BaseAIProvider {
  async analyze({ systemPrompt, userMessage }) {
    const args = ["-p", "--system-prompt", systemPrompt];
    if (this.config.model) args.push("--model", this.config.model);

    return new Promise((resolve, reject) => {
      const proc = spawn("claude", args);

      let stdout = "";
      let stderr = "";

      proc.stdout.on("data", (d) => { stdout += d; });
      proc.stderr.on("data", (d) => { stderr += d; });

      proc.on("error", (err) => {
        if (err.code === "ENOENT") {
          reject(new Error("claude CLI not found in PATH. Install Claude Code: https://claude.ai/code"));
        } else {
          reject(err);
        }
      });

      proc.on("close", (code) => {
        if (code !== 0) {
          reject(new Error(`claude exited with code ${code}:\n${stderr.trim()}`));
        } else {
          resolve(this.parseOutputs(stdout));
        }
      });

      proc.stdin.write(userMessage);
      proc.stdin.end();
    });
  }
}
