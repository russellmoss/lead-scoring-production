#!/usr/bin/env node

/**
 * @savvy/agent-guard CLI
 *
 * Commands:
 *   init          — Interactive setup: generates config, scripts, hooks, and workflows
 *   detect        — Auto-detect baselines and write them to agent-docs.config.json
 *   gen           — Run all inventory generators
 *   check         — Run pre-commit doc check (used by husky hook)
 */

import { parseArgs } from 'node:util';
import { resolve } from 'node:path';
import { existsSync } from 'node:fs';

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    help: { type: 'boolean', short: 'h', default: false },
    verbose: { type: 'boolean', short: 'v', default: false },
    config: { type: 'string', short: 'c', default: 'agent-docs.config.json' },
    'dry-run': { type: 'boolean', default: false },
  },
});

const command = positionals[0];

if (values.help || !command) {
  console.log(`
  @savvy/agent-guard — Self-healing documentation for AI-assisted development

  Usage: agent-guard <command> [options]

  Commands:
    init          Interactive setup wizard
    detect        Auto-detect baselines and update config
    gen           Run all inventory generators
    check         Run pre-commit documentation check

  Options:
    -c, --config  Path to config file (default: agent-docs.config.json)
    -v, --verbose Verbose output
    --dry-run     Show what would be created without writing files
    -h, --help    Show this help message
  `);
  process.exit(0);
}

// Resolve config path
const configPath = resolve(process.cwd(), values.config);

// Commands that DON'T require an existing config
const noConfigCommands = ['init'];

if (!noConfigCommands.includes(command) && !existsSync(configPath)) {
  console.error(`\n  ✗ Config file not found: ${values.config}`);
  console.error(`  Run "agent-guard init" first to create your configuration.\n`);
  process.exit(1);
}

// Dynamic import for the selected command
try {
  const commandModule = await import(`../src/commands/${command}.js`);
  await commandModule.default({ configPath, flags: values });
} catch (err) {
  if (err.code === 'ERR_MODULE_NOT_FOUND') {
    console.error(`\n  ✗ Unknown command: "${command}"`);
    console.error(`  Run "agent-guard --help" for available commands.\n`);
    process.exit(1);
  }
  throw err;
}
