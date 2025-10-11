# Git Hooks for RentCoordinator

This directory contains git hooks that help ensure code quality before pushing changes.

## Installation

To install the git hooks, run:

```bash
./hooks/install.sh
```

This will create symlinks from `.git/hooks/` to the hooks in this directory.

## Available Hooks

### pre-push

Runs before `git push` and performs the following checks:

1. **Build** - Compiles CoffeeScript to JavaScript via `deno task build`
2. **Lint** - Runs `deno lint` on compiled JavaScript output (dist/ and scripts/)
3. **Test** - Runs `deno test` if test files exist (skipped if no tests found)

If any check fails, the push is aborted and you'll need to fix the issues before pushing.

## Why These Hooks?

### Local Linting vs CI Linting

We perform linting locally (pre-push) rather than in CI because:

1. **Faster feedback** - Catch issues before waiting for CI
2. **CoffeeScript consideration** - Deno lint only works on JavaScript, so we lint the compiled output
3. **Reduced CI load** - CI focuses on build verification and tests

### CoffeeScript Linting

There's no widely-adopted linter for CoffeeScript that matches your coding standards. Instead:

- We lint the **compiled JavaScript output** (dist/ and scripts/)
- CoffeeScript source (lib/ and static/) is excluded from linting
- This catches JavaScript-level issues while respecting your CoffeeScript style

The `deno.json` configuration excludes source directories:

```json
{
  "lint": {
    "exclude": ["lib/", "static/"]
  }
}
```

## Manual Usage

You can run the same checks manually:

```bash
# Run all checks (same as pre-push hook)
deno task build
deno task lint
deno test -A

# Or just linting
deno task lint
```

## Bypassing Hooks

If you need to bypass the pre-push hook (not recommended):

```bash
git push --no-verify
```

## Uninstalling Hooks

To remove the hooks:

```bash
rm .git/hooks/pre-push
```

Or reinstall to restore them:

```bash
./hooks/install.sh
```

## Troubleshooting

### Hook doesn't run

Make sure the hook is executable and properly symlinked:

```bash
ls -la .git/hooks/pre-push
# Should show: .git/hooks/pre-push -> ../../hooks/pre-push

chmod +x hooks/pre-push
```

### Build or lint fails

Fix the reported issues. The hooks are there to catch problems early.

If you believe the check is incorrect:
1. Review the error message
2. Check if your code actually has an issue
3. Update `deno.json` lint configuration if needed
