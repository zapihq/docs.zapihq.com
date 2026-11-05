#!/usr/bin/env node
// Tick tasks on a GitHub issue without round-tripping the body through a shell.
//
// The workflow used to fetch the body into a PowerShell variable, replace
// checkboxes, and write it back. PowerShell decoded the UTF-8 body with the
// legacy codepage (em dashes became `ΓÇö`) and its array handling collapsed
// Markdown newlines. This script keeps the body as one UTF-8 string:
//
//   gh api ... --jq .body   ->  edit selected checkbox lines  ->  gh issue edit --body-file
//
// Usage:
//   node scripts/issue-tasks.mjs <issue> --list
//   node scripts/issue-tasks.mjs <issue> --task <n> [--task <n>...] [--dry-run]
//   node scripts/issue-tasks.mjs --body-file <path> --task <n> --dry-run
//
// `--dry-run` prints the updated body to stdout and leaves the issue alone.
// `--body-file` reads a local body for preview and tests; it is read-only.
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const TASK_RE = /^(\s*(?:[-*+]|\d+[.)])\s+)\[( |x|X)\]\s+(.*)$/;

const HELP = `Usage:
  node scripts/issue-tasks.mjs <issue> --list
  node scripts/issue-tasks.mjs <issue> --task <n> [--task <n>...] [--dry-run]
  node scripts/issue-tasks.mjs --body-file <path> --task <n> --dry-run

Ticks only the tasks you name. Reads and writes the body as UTF-8 through
\`gh api\` and \`gh issue edit --body-file\`, so em dashes and Markdown
newlines survive.

Options:
  --list          print the issue's tasks with their 1-based numbers
  --task <n>      tick task n (repeatable; comma-separated values also work)
  --dry-run       print the updated body to stdout instead of editing the issue
  --body-file     read the body from a local file (read-only; for previews and tests)
`;

function fail(message) {
  console.error(`issue-tasks: ${message}`);
  process.exit(1);
}

function gh(args) {
  try {
    return execFileSync("gh", args, {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    });
  } catch (error) {
    const stderr = error.stderr ? error.stderr.toString() : "";
    throw new Error(stderr.trim() || error.message);
  }
}

function parseArgs(argv) {
  const options = {
    issue: "",
    tasks: [],
    dryRun: false,
    list: false,
    bodyFile: "",
  };
  const rest = [...argv];

  while (rest.length > 0) {
    const arg = rest.shift();
    if (arg === "--help" || arg === "-h") {
      console.log(HELP);
      process.exit(0);
    }
    if (arg === "--list") {
      options.list = true;
      continue;
    }
    if (arg === "--dry-run") {
      options.dryRun = true;
      continue;
    }
    if (arg === "--body-file" || arg.startsWith("--body-file=")) {
      const value =
        arg === "--body-file" ? rest.shift() : arg.slice("--body-file=".length);
      if (!value) fail("--body-file needs a path");
      options.bodyFile = value;
      continue;
    }
    if (arg === "--task" || arg.startsWith("--task=")) {
      const value =
        arg === "--task" ? rest.shift() : arg.slice("--task=".length);
      if (!value) fail("--task needs a number");
      for (const part of value.split(",")) {
        const task = Number(part);
        if (!Number.isInteger(task) || task < 1) {
          fail(`--task must be a positive integer: ${part}`);
        }
        options.tasks.push(task);
      }
      continue;
    }
    if (arg.startsWith("-")) fail(`unknown option: ${arg}`);
    if (options.issue) fail(`unexpected argument: ${arg}`);
    options.issue = arg;
  }

  if (!options.issue && !options.bodyFile) fail("missing issue number");
  if (options.issue && !/^\d+$/.test(options.issue))
    fail(`issue must be a number: ${options.issue}`);
  if (options.bodyFile && !options.list && !options.dryRun) {
    fail("--body-file is read-only; add --dry-run");
  }
  if (!options.list && options.tasks.length === 0) {
    fail("nothing to do: pass --list or --task <n>");
  }
  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const label = options.issue ? `#${options.issue}` : options.bodyFile;

  let body;
  if (options.bodyFile) {
    body = fs.readFileSync(options.bodyFile, "utf8");
  } else {
    const raw = gh([
      "api",
      `repos/{owner}/{repo}/issues/${options.issue}`,
      "--jq",
      ".body",
    ]);
    // The jq output ends with one newline that is not part of the body.
    body = raw.endsWith("\n") ? raw.slice(0, -1) : raw;
  }
  const lines = body.split("\n");
  const tasks = [];

  for (let i = 0; i < lines.length; i += 1) {
    const match = TASK_RE.exec(lines[i]);
    if (!match) continue;
    tasks.push({
      number: tasks.length + 1,
      line: i,
      checked: match[2].toLowerCase() === "x",
      text: match[3],
    });
  }

  if (tasks.length === 0) {
    fail(`no checkbox tasks found in ${label}`);
  }

  if (options.list) {
    for (const task of tasks) {
      console.log(`${task.number}. [${task.checked ? "x" : " "}] ${task.text}`);
    }
    return;
  }

  const selected = new Set(options.tasks);
  for (const number of selected) {
    if (number > tasks.length) {
      fail(`task ${number} is out of range (1-${tasks.length})`);
    }
  }

  let changed = 0;
  for (const task of tasks) {
    if (!selected.has(task.number) || task.checked) continue;
    const match = TASK_RE.exec(lines[task.line]);
    lines[task.line] = `${match[1]}[x] ${match[3]}`;
    changed += 1;
  }

  const updated = lines.join("\n");

  if (options.dryRun) {
    process.stdout.write(updated.endsWith("\n") ? updated : `${updated}\n`);
    console.error(`Would tick ${changed} task(s) on ${label}.`);
    return;
  }

  if (changed === 0) {
    console.log(`No change: selected task(s) already checked on ${label}.`);
    return;
  }

  const tempBody = path.join(
    os.tmpdir(),
    `zapi-issue-${options.issue}-${process.pid}.md`
  );
  try {
    fs.writeFileSync(tempBody, updated, "utf8");
    gh(["issue", "edit", options.issue, "--body-file", tempBody]);
  } finally {
    fs.rmSync(tempBody, { force: true });
  }

  console.log(`Ticked ${changed} task(s) on ${label}.`);
}

try {
  main();
} catch (error) {
  fail(error.message);
}
