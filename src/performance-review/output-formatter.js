import { writeReviews, appendProcessedCommits } from "./utils/file-manager.js";

const DATA_DIR = "performance-review/data";

export function saveAnalysisOutputs(fullReview, simplifiedReview, newCommits, windowLabel) {
  writeReviews(fullReview, simplifiedReview);
  appendProcessedCommits(newCommits, windowLabel);

  console.log("\nOutputs written:");
  console.log(`  Full review     → ${DATA_DIR}/full-review.md`);
  console.log(`  Simplified      → ${DATA_DIR}/simplified-review.md`);
  console.log(`  Processed log   → ${DATA_DIR}/processed-commits.md`);
}

export function saveRefineOutputs(fullReview, simplifiedReview) {
  writeReviews(fullReview, simplifiedReview);

  console.log("\nOutputs written:");
  console.log(`  Full review     → ${DATA_DIR}/full-review.md`);
  console.log(`  Simplified      → ${DATA_DIR}/simplified-review.md`);
}
