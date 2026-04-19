import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..");

const run = (args) =>
  spawnSync("git", args, {
    cwd: repoRoot,
    encoding: "utf8",
  });

const insideGit = run(["rev-parse", "--is-inside-work-tree"]);
if (insideGit.status !== 0 || insideGit.stdout.trim() !== "true") {
    console.log("Skipping git hook install; repository metadata is unavailable.");
    process.exit(0);
}

const hookPathResult = run(["config", "--local", "core.hooksPath", ".githooks"]);
if (hookPathResult.status !== 0) {
  console.error(hookPathResult.stderr.trim() || "Failed to configure core.hooksPath");
  process.exit(hookPathResult.status ?? 1);
}

console.log("Configured git hooks to use .githooks/");
