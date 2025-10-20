#!/usr/bin/env -S deno run --allow-read --allow-write --allow-env --unstable-kv
// scripts/backup.ts

import { parseArgs } from "node:util";

// Parse command line arguments
const { values, positionals } = parseArgs({
  args: Deno.args,
  options: {
    help: {
      type: "boolean",
      short: "h",
    },
    "dry-run": {
      type: "boolean",
      short: "d",
    },
    "no-overwrite": {
      type: "boolean",
    },
    output: {
      type: "string",
      short: "o",
    },
  },
  allowPositionals: true,
});

const command = positionals[0];
const filepath = positionals[1];

// Show help
if (values.help || !command) {
  console.log(`
RentCoordinator Backup Utility

Usage:
  deno task backup              Create a new backup
  deno task restore <file>      Restore from backup file

Options:
  -h, --help                    Show this help message
  -d, --dry-run                 Preview restore without making changes
  --no-overwrite                Skip existing entries during restore
  -o, --output <dir>            Backup directory (default: ./backups)

Examples:
  # Create backup
  deno task backup

  # Create backup to custom directory
  deno task backup -o /path/to/backups

  # Restore from backup
  deno task restore ./backups/backup-2025-10-20T12-30-45.json

  # Preview restore without making changes
  deno task restore ./backups/backup.json --dry-run

  # Restore without overwriting existing data
  deno task restore ./backups/backup.json --no-overwrite
`);
  Deno.exit(0);
}

// Initialize database schema (required before backup operations)
await import("../dist/lib/db/schema.js");

// Import backup service
const backupService = await import("../dist/lib/services/backup.js");

// Execute command
try {
  if (command === "backup" || command === "export") {
    const backupDir = values.output || "./backups";
    console.log(`Creating backup in ${backupDir}...\n`);

    const result = await backupService.createBackup(backupDir);

    console.log(`\n✓ Backup completed successfully`);
    console.log(`  File: ${result.filepath}`);
  } else if (command === "restore" || command === "import") {
    if (!filepath) {
      console.error("Error: Backup file path required");
      console.error("Usage: deno task restore <file>");
      Deno.exit(1);
    }

    console.log(`Restoring from ${filepath}...\n`);

    const options = {
      overwrite: !values["no-overwrite"],
      dryRun: values["dry-run"] || false,
    };

    const result = await backupService.restoreBackup(filepath, options);

    if (options.dryRun) {
      console.log(`\n✓ Dry run completed (no changes made)`);
    } else {
      console.log(`\n✓ Restore completed successfully`);
    }

    console.log(
      `  Created: ${result.stats.created}, Updated: ${result.stats.updated}, Skipped: ${result.stats.skipped}, Errors: ${result.stats.errors}`,
    );
  } else {
    console.error(`Error: Unknown command '${command}'`);
    console.error("Run 'deno task backup --help' for usage information");
    Deno.exit(1);
  }
} catch (err) {
  console.error(`\n✗ Error: ${err.message}`);
  if (err.stack) {
    console.error(err.stack);
  }
  Deno.exit(1);
}
