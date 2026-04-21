import inquirer from "inquirer";
import { loadConfig } from "./utils/config-loader.js";
import { promptTimeWindow } from "./time-window.js";
import { collectNewCommits } from "./git-collector.js";
import { readExistingReview } from "./utils/file-manager.js";
import { buildSystemPrompt, buildAnalyzeMessage, buildRefineMessage } from "./ai/prompts.js";
import { createProvider } from "./ai/ai-factory.js";
import { saveAnalysisOutputs, saveRefineOutputs } from "./output-formatter.js";

async function promptMode() {
  const { mode } = await inquirer.prompt([
    {
      type: "list",
      name: "mode",
      message: "What do you want to do?",
      choices: [
        { name: "Analyze new commits", value: "analyze" },
        { name: "Refine existing review", value: "refine" },
      ],
    },
  ]);
  return mode;
}

async function runAnalyze(config, provider) {
  const window = await promptTimeWindow();

  console.log(`\nCollecting commits for: ${window.label}`);
  const newCommits = await collectNewCommits(
    config.repos,
    config.user.git_identities,
    window.start,
    window.end
  );

  if (newCommits.length === 0) {
    console.log("No new commits found for this window. Nothing to process.");
    process.exit(0);
  }

  console.log(`Found ${newCommits.length} new commit(s) across ${config.repos.length} repo(s).`);

  const existingReview = readExistingReview();

  console.log("\nAnalyzing with AI...");
  const systemPrompt = buildSystemPrompt(config.profile.expectations);
  const userMessage = buildAnalyzeMessage(existingReview, newCommits);

  const { fullReview, simplifiedReview } = await provider.analyze({ systemPrompt, userMessage });

  saveAnalysisOutputs(fullReview, simplifiedReview, newCommits, window.label);

  console.log(`\nDone. ${newCommits.length} commit(s) processed.`);
}

async function runRefine(config, provider) {
  const existingReview = readExistingReview();

  if (!existingReview) {
    console.log("No existing review found. Run 'Analyze new commits' first.");
    process.exit(0);
  }

  console.log("\nRefining existing review...");
  const systemPrompt = buildSystemPrompt(config.profile.expectations);
  const userMessage = buildRefineMessage(existingReview);

  const { fullReview, simplifiedReview } = await provider.analyze({ systemPrompt, userMessage });

  saveRefineOutputs(fullReview, simplifiedReview);

  console.log("\nDone. Review refined.");
}

async function main() {
  console.log("Performance Review Generator\n");

  const config = loadConfig();
  const mode = await promptMode();
  const provider = createProvider(config.ai);

  if (mode === "analyze") {
    await runAnalyze(config, provider);
  } else {
    await runRefine(config, provider);
  }
}

main().catch((err) => {
  console.error(`\nError: ${err.message}`);
  process.exit(1);
});
