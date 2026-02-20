#!/usr/bin/env node
/**
 * Runs a prompt via the Claude Agent SDK.
 * Used by 02-run.sh to execute QA steps without spawning a nested Claude Code session.
 *
 * Usage: node claude-runner.mjs <prompt> <cwd> [maxTurns] [allowedTools]
 * Output: The final text result from Claude, printed to stdout.
 */

import { query } from "@anthropic-ai/claude-agent-sdk";

const prompt = process.argv[2];
const cwd = process.argv[3] || process.cwd();
const maxTurns = parseInt(process.argv[4] || "15", 10);
const allowedTools = process.argv[5] ? process.argv[5].split(",").map((t) => t.trim()) : undefined;

if (!prompt) {
  console.error("Usage: node claude-runner.mjs <prompt> <cwd> [maxTurns] [allowedTools]");
  process.exit(1);
}

try {
  let result = "";
  let lastAssistantMessage = "";

  const instance = query({
    prompt,
    options: {
      maxTurns,
      permissionMode: "bypassPermissions",
      allowDangerouslySkipPermissions: true,
      allowedTools,
      cwd,
      systemPrompt: {
        type: "preset",
        preset: "claude_code",
      },
      env: { ...process.env, CLAUDECODE: undefined },
    },
  });

  for await (const message of instance) {
    if (message.type === "assistant") {
      // Capture assistant text messages as fallback
      const textContent = message.message?.content?.filter((c) => c.type === "text") ?? [];
      if (textContent.length > 0) {
        lastAssistantMessage = textContent.map((c) => c.text).join("\n");
      }
    } else if (message.type === "result") {
      result = message.result ?? "";
    }
  }

  // Use result if available, otherwise fall back to last assistant message
  const output = result || lastAssistantMessage;
  if (!output) {
    console.error("Warning: No output received from Claude session");
  }
  process.stdout.write(output);
} catch (err) {
  console.error("Claude runner error:", err.message || err);
  if (err.stack) {
    console.error(err.stack);
  }
  process.exit(1);
}
