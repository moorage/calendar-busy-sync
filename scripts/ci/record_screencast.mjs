import path from "node:path";
import process from "node:process";
import { mkdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, "..", "..");

const parseArgs = (argv) => {
  let output = "artifacts/screencasts/feature.mp4";
  for (let index = 0; index < argv.length; index += 1) {
    const value = argv[index];
    if (value === "--output" && argv[index + 1]) {
      output = argv[index + 1];
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${value}`);
  }
  return { output: path.resolve(repoRoot, output) };
};

const resolveCaptureConfig = (output) => ({
  output,
  audioFormat: process.env.HARNESS_CAPTURE_AUDIO_FORMAT ?? "pulse",
  audioInput: process.env.HARNESS_CAPTURE_AUDIO_INPUT ?? "auto_null.monitor",
  display: process.env.HARNESS_CAPTURE_DISPLAY ?? ":99.0",
  enabled: process.env.HARNESS_CAPTURE_WITH_FFMPEG ?? "1",
  frameRate: "30",
  videoSize: process.env.HARNESS_CAPTURE_VIDEO_SIZE ?? "1440x900",
});

const killChild = (child, signal) => {
  if (!child || child.exitCode !== null || child.signalCode) return;
  try {
    child.kill(signal);
  } catch (error) {
    if (error?.code !== "ESRCH") throw error;
  }
};

export const startScreencastCapture = async ({ output }) => {
  const config = resolveCaptureConfig(output);
  if (config.enabled === "0") {
    throw new Error("HARNESS_CAPTURE_WITH_FFMPEG=0 disables screencast capture");
  }

  await mkdir(path.dirname(config.output), { recursive: true });

  const ffmpegArgs = [
    "-y",
    "-video_size",
    config.videoSize,
    "-framerate",
    config.frameRate,
    "-f",
    "x11grab",
    "-i",
    config.display,
    "-f",
    config.audioFormat,
    "-i",
    config.audioInput,
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-pix_fmt",
    "yuv420p",
    "-c:a",
    "aac",
    "-movflags",
    "+faststart",
    config.output,
  ];

  const child = spawn("ffmpeg", ffmpegArgs, {
    cwd: repoRoot,
    stdio: ["ignore", "inherit", "inherit"],
  });
  let stopRequested = false;

  const exited = new Promise((resolve, reject) => {
    child.once("error", reject);
    child.once("exit", (code, signal) => {
      if (stopRequested && (signal || code === 255)) {
        resolve({ code, signal });
        return;
      }
      if (signal) {
        resolve({ code: null, signal });
        return;
      }
      if (code === 0) {
        resolve({ code, signal: null });
        return;
      }
      reject(new Error(`ffmpeg exited with code ${code ?? 1}`));
    });
  });

  const stop = async ({ signal = "SIGINT", timeoutMs = 5000 } = {}) => {
    if (child.exitCode !== null || child.signalCode) {
      return exited;
    }
    stopRequested = true;
    killChild(child, signal);
    const forceTimer = setTimeout(() => {
      killChild(child, "SIGTERM");
    }, timeoutMs);
    try {
      return await exited;
    } finally {
      clearTimeout(forceTimer);
    }
  };

  return { child, exited, output: config.output, stop };
};

const runCli = async () => {
  const { output } = parseArgs(process.argv.slice(2));
  const capture = await startScreencastCapture({ output });
  let stopping = null;

  const stopForSignal = (signal) => {
    if (stopping) return;
    stopping = capture
      .stop({ signal })
      .then(() => {
        process.exit(signal === "SIGINT" ? 130 : 143);
      })
      .catch((error) => {
        console.error(error instanceof Error ? error.message : String(error));
        process.exit(1);
      });
  };

  process.on("SIGINT", () => stopForSignal("SIGINT"));
  process.on("SIGTERM", () => stopForSignal("SIGTERM"));
  process.on("SIGHUP", () => stopForSignal("SIGTERM"));

  await capture.exited;
};

if (import.meta.url === `file://${process.argv[1]}`) {
  await runCli();
}
