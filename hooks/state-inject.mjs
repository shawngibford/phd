#!/usr/bin/env node
/**
 * state-inject.mjs — PHD SessionStart hook
 *
 * Claude Code hook I/O contract (SessionStart):
 *   stdin  : JSON object with at minimum { session_id, cwd, hook_event_name, ... }
 *   stdout : JSON object:
 *              { "hookSpecificOutput": { "hookEventName": "SessionStart",
 *                                        "additionalContext": "<string>" } }
 *            OR empty / exit 0 (no-op passthrough)
 *   exit 0 : always (never block session start)
 *
 * This hook reads STATE.md and the last 15 lines of LEDGER.md from the project
 * cwd and injects them as additionalContext so every session starts with
 * up-to-date PHD state visible to Claude.  Gracefully no-ops if files are absent.
 */

import { readFileSync } from 'fs';
import { join } from 'path';

function readTail(filePath, maxLines) {
  try {
    const content = readFileSync(filePath, 'utf8');
    const lines = content.split('\n');
    if (lines.length <= maxLines) return content;
    return lines.slice(-maxLines).join('\n');
  } catch {
    return null;
  }
}

async function main() {
  // Read and parse stdin (JSON from Claude Code)
  let input = {};
  try {
    const raw = readFileSync('/dev/stdin', 'utf8');
    if (raw.trim()) {
      input = JSON.parse(raw);
    }
  } catch {
    // stdin unreadable or empty — still run with empty input
  }

  // Determine project root from cwd field (Claude Code sets this to the project dir)
  const cwd = input.cwd || process.cwd();

  const statePath  = join(cwd, 'STATE.md');
  const ledgerPath = join(cwd, 'LEDGER.md');

  const stateContent  = readTail(statePath, 9999);   // STATE.md is small; take all
  const ledgerTail    = readTail(ledgerPath, 15);     // last 15 lines of ledger

  // If neither file exists, no-op (don't inject empty context)
  if (!stateContent && !ledgerTail) {
    process.exit(0);
  }

  const parts = [];
  if (stateContent) {
    parts.push('## PHD STATE.md\n' + stateContent.trimEnd());
  }
  if (ledgerTail) {
    parts.push('## PHD LEDGER.md (last entries)\n' + ledgerTail.trimEnd());
  }

  const additionalContext = parts.join('\n\n');

  const output = {
    hookSpecificOutput: {
      hookEventName: 'SessionStart',
      additionalContext,
    },
  };

  process.stdout.write(JSON.stringify(output) + '\n');
  process.exit(0);
}

main().catch(() => process.exit(0));
