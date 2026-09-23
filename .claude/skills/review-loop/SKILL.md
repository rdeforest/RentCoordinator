---
name: review-loop
description: Run an adversarial review loop over a change — two or more independent reviewers that only see the diff and are told to assume it is wrong, then a fixer that applies their findings. Use after finishing a bug fix or feature, before committing.
argument-hint: [git-ref | "staged" | "working" (default)]
allowed-tools: |
  Bash(git diff *)
  Bash(git show *)
  Bash(git status *)
  Bash(git log *)
  Bash(npm run test:integration)
  Bash(coffee test/*)
  Read
  Grep
  Glob
---

# Adversarial review loop

Split the roles so no single context both writes the code and judges it. The
author wants the change to land; the reviewer wants to find why it does not
work. Keeping those in separate contexts is the whole point — do not shortcut
it by reviewing the diff yourself.

## Target

`$ARGUMENTS` selects what to review. Default is the working tree.

- (empty) or `working` — `git diff` plus `git diff --cached`, and the contents
  of any untracked file that is part of the change
- `staged` — `git diff --cached`
- anything else — treat as a git ref: `git show <ref>`, or
  `git diff <ref>..HEAD` if the ref names a base

## Current state

!`git status --short`

!`git diff --stat HEAD`

## Steps

### 1. Capture the diff

Produce the full diff text for the target. If it is empty, stop and say so —
there is nothing to review.

Note the bug number or intent of the change for your own orchestration, but
**do not pass it to the reviewers**. They get the diff and nothing else. An
explanation of what the change was trying to do is exactly the bias the split
exists to remove.

### 2. Fan out reviewers

Spawn **at least two** `adversarial-reviewer` agents in a single message so
they run concurrently and cannot see each other's findings. Give each one the
diff verbatim plus one lens:

- **Lens A — mechanism.** Does this code do what its own lines say it does?
  Units, rounding, boundaries, control flow, truthiness, the error path.
- **Lens B — contracts and callers.** Who else reads or writes this? Grep for
  every caller and every consumer of a changed key, signature, or event
  shape. What happens to rows already in the database?
- **Lens C — standards and structure** (add for larger changes). Does it
  violate CLAUDE.md? Duplicated constants, `else if` chains, restating
  comments, swallowed errors, floats for money, defensive checks stacked on
  defensive checks.

Each reviewer prompt should contain: the diff, its lens, and the instruction
to assume the code is wrong. Nothing about who wrote it or why.

### 3. Collate

Merge the findings into one ordered list. De-dupe by file:line + mechanism —
when two reviewers independently found the same thing, say so and raise its
confidence; that agreement is the strongest signal the loop produces.

Rank blocking, then major, then minor.

### 4. Fix

Hand the collated list to one `review-fixer` agent. It applies the specific
fixes and reports what it applied, rejected, or ruled out of scope. It does
not redesign.

### 5. Verify and decide

Run the suites:

```bash
npm run test:integration
```

```bash
coffee test/services/rent.coffee && coffee test/services/period.coffee && coffee test/services/backup.coffee
```

Then:

- Any **blocking** finding that the fixer applied → go back to step 1 with the
  new diff. The fix is itself unreviewed code.
- Any finding marked **rejected** or **out of scope** → surface it to the user
  with the reviewer's reasoning and the fixer's, and let them arbitrate. Do
  not quietly drop it.
- Clean run, nothing blocking → report and stop. Do not commit unless asked.

## Reporting

Give the user, in this order:

1. What the reviewers agreed on (highest-signal findings).
2. What got fixed.
3. What was rejected or deferred, and why — this is the part that matters and
   the part that is easiest to lose.
4. Test results, verbatim on failure.

Do not summarize a failing run as "mostly passing".
