import process from "node:process";
import { spawnSync } from "node:child_process";

const run = (command, args, options = {}) => {
  const result = spawnSync(command, args, {
    stdio: "inherit",
    ...options,
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
};

const getOutput = (command, args) => {
  const result = spawnSync(command, args, {
    encoding: "utf8",
  });
  if (result.status !== 0) {
    process.exit(result.status ?? 1);
  }
  return result.stdout.trim();
};

const hasStagedChanges = () => getOutput("git", ["diff", "--cached", "--name-only"]).length > 0;

if (!hasStagedChanges()) {
  process.exit(0);
}

run("python3", ["scripts/knowledge/generate_repo_map.py"]);

const repoMapPath = "docs/generated/repo-map.json";
const repoMapChanged = spawnSync("git", ["diff", "--quiet", "--", repoMapPath]);
if (repoMapChanged.status === 1) {
  run("git", ["add", repoMapPath]);
  console.log(`pre-commit: refreshed and staged ${repoMapPath}`);
}
