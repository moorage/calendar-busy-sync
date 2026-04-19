import process from "node:process";
import { spawn } from "node:child_process";
import { startScreencastCapture } from "./record_screencast.mjs";

const parseArgs = (argv) => {
  const separatorIndex = argv.indexOf("--");
  if (separatorIndex === -1) {
    throw new Error("Expected `--` followed by the workflow command");
  }

  let output = "artifacts/screencasts/feature.mp4";
  for (let index = 0; index < separatorIndex; index += 1) {
    const value = argv[index];
    if (value === "--output" && argv[index + 1]) {
      output = argv[index + 1];
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${value}`);
  }

  const command = argv[separatorIndex + 1];
  const commandArgs = argv.slice(separatorIndex + 2);
  if (!command) {
    throw new Error("Expected a workflow command after `--`");
  }
  return { command, commandArgs, output };
};

const waitForCommand = (child) =>
  new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => resolve({ code, signal }));
  });

const forwardSignal = (child, signal) => {
  if (!child || child.exitCode !== null || child.signalCode) return;
  try {
    child.kill(signal);
  } catch (error) {
    if (error?.code !== "ESRCH") throw error;
  }
};

const run = async () => {
  const { command, commandArgs, output } = parseArgs(process.argv.slice(2));
  const capture = await startScreencastCapture({ output });
  const workflow = spawn(command, commandArgs, {
    stdio: "inherit",
    env: process.env,
  });

  let interrupted = false;
  const onSignal = (signal) => {
    if (interrupted) return;
    interrupted = true;
    forwardSignal(workflow, signal);
  };

  process.on("SIGINT", () => onSignal("SIGINT"));
  process.on("SIGTERM", () => onSignal("SIGTERM"));
  process.on("SIGHUP", () => onSignal("SIGTERM"));

  let workflowResult;
  try {
    workflowResult = await waitForCommand(workflow);
  } finally {
    await capture.stop({ signal: "SIGINT" });
  }

  if (workflowResult.signal) {
    process.exit(workflowResult.signal === "SIGINT" ? 130 : 143);
  }
  process.exit(workflowResult.code ?? 1);
};

await run();
