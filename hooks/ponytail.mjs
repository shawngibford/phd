#!/usr/bin/env node
/**
 * ponytail.mjs — PHD UserPromptSubmit anti-bloat hook
 *
 * The governor's always-on arm. On every prompt it injects a short minimalism
 * reminder so the daemon writes the smallest correct change, not 400 lines where
 * 12 will do. The full ruleset lives in the `code-minimalism` skill; this hook
 * keeps it top-of-mind without the model having to recall the skill.
 *
 * Modes (env PHD_PONYTAIL):
 *   off    — pure passthrough, no injection
 *   lite   — short reminder (default)
 *   strict — reminder + line/file budgets
 *
 * Claude Code hook I/O contract (UserPromptSubmit):
 *   stdin  : JSON { session_id, cwd, hook_event_name, prompt, ... }
 *   stdout : JSON { hookSpecificOutput: { hookEventName, additionalContext } } or empty
 *   exit 0 : prompt proceeds (additionalContext, if any, is prepended to context)
 *
 * Adapted from ponytail (MIT). Never blocks; fails open.
 */

import { readFileSync } from 'fs';

const LITE = [
  'Code-minimalism governor (lite): write the smallest change that makes the next',
  'experiment run correctly — nothing more. Reuse before adding. No speculative',
  'abstraction, no unrequested features, no premature optimization. Prefer deletion.',
  'One concern per diff. (Framing/research dialogue is exempt — conciseness governs code.)',
].join(' ');

const STRICT = LITE + ' STRICT: flag functions >~40 lines or new files >~150; comment why, not what.';

async function main() {
  let raw = '';
  try { raw = readFileSync('/dev/stdin', 'utf8'); } catch { /* ignore */ }

  const mode = (process.env.PHD_PONYTAIL || 'lite').toLowerCase();
  if (mode === 'off') process.exit(0);

  const additionalContext = mode === 'strict' ? STRICT : LITE;

  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'UserPromptSubmit',
      additionalContext,
    },
  }) + '\n');
  process.exit(0);
}

main().catch(() => process.exit(0));
