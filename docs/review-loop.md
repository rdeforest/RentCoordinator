# The adversarial review loop

A change is written by one context and judged by two or three others that
never see the reasoning behind it. The split is the whole mechanism: the
context that wrote the code wants it to land, and a reviewer sharing that
context inherits the want. Keeping them apart is what makes a review find
anything.

Adapted from the arrangement Jarred Sumner describes for Bun's Rust port —
one implementer, two or more adversarial reviewers, one fixer.

## The pieces

| File | Role |
|---|---|
| [`.claude/agents/adversarial-reviewer.md`](../.claude/agents/adversarial-reviewer.md) | Read-only. Receives a diff and a lens. Told to assume the code is wrong. |
| [`.claude/agents/review-fixer.md`](../.claude/agents/review-fixer.md) | Applies the specific fix each finding asks for, and nothing else. |
| [`.claude/skills/review-loop/SKILL.md`](../.claude/skills/review-loop/SKILL.md) | `/review-loop` — captures the diff, fans out the reviewers, collates, hands the list to the fixer, re-verifies. |

## Isolation

Every agent runs in its own git worktree (`isolation: worktree` in each
definition). It is what makes the loop safe to run while you are still working:
a reviewer's most valuable move is mutation testing — breaking the code to see
whether a test notices — and in a shared checkout that races your edits.

Two things make it work here, and both are easy to get wrong:

- **`.claude/settings.json` sets `worktree.baseRef` to `"head"`.** Without it a
  subagent worktree branches from the repository's *default* branch, so on a
  feature branch every agent would review `main` and see none of your work.
- **A worktree branches from a commit and carries no uncommitted changes.**
  Commit before delegating, or the agent reviews the previous state and reports
  on code you have already changed.

Verified rather than assumed, on 2026-09-23: the worktree branched from the
feature branch's HEAD; `node_modules` resolved upward from the main checkout so
the suite ran normally; the Write tool and `git -C <main checkout>` were both
refused; and a mutation to `lib/money.coffee` stayed in the worktree while the
main checkout kept its original line.

One gap found in the same check: **a plain shell redirect to an absolute path
is not blocked.** `echo x > /main/checkout/file` succeeds from inside a
worktree. Isolation guards the Edit and Write tools and git redirection, not
arbitrary paths — so the agent definitions tell agents to work from their own
directory and never to treat the main checkout's path as somewhere to write.
The realistic accident (an agent editing `lib/x.coffee` relative to its own
cwd) is fully prevented; the one that remains needs someone to hand over the
absolute path.

**Restarts.** A new `.claude/agents/` directory needs a Claude Code restart
before the names resolve — and so does an *edit* to an agent already registered
in a running session. A probe caught this the hard way: the definition had
`isolation: worktree` on disk, the running session still held the previous
version, and the agent ran in the main checkout and modified it. Until the
restart, pass `isolation: "worktree"` on the Agent call itself; that takes
effect immediately because it does not come from the cached definition.

## Running it

```
/review-loop            # the working tree
/review-loop staged     # what is staged
/review-loop HEAD~3     # a range
```

## What makes it work

**The reviewers get the diff and nothing else.** Not the bug number, not the
intent, not the commit message. An explanation is exactly the bias the split
removes. If a change only makes sense with the explanation attached, that is
itself a finding.

**Two or more, with different lenses, in parallel.** They cannot see each
other's findings. When two independently land on the same file and line, that
agreement is the strongest signal the loop produces — stronger than either
report alone. The lenses used here:

- *mechanism* — does the code do what its own lines say? units, rounding,
  boundaries, truthiness, the error path
- *contracts and callers* — who else reads this? what happens to rows already
  in the database? what documentation is now false?
- *standards and structure* — duplicated constants, `else if` chains over a
  fixed set, restating comments, swallowed errors, floats for money

**The fixer does not redesign.** It applies what the findings ask for. If it
produces a different diff, the review no longer applies to the thing being
shipped. It is also allowed to reject a finding, and says so — reviewers told
to assume the code is wrong are sometimes wrong themselves.

**A blocking finding that gets fixed goes round again.** The fix is unreviewed
code.

## What it actually caught

From the 2026-09-23 sweep, on a diff whose author (reasonably) believed it was
finished and whose tests were green:

- Nothing in any deploy path ran database migrations. The documented in-place
  upgrade is `git pull` + restart; `CREATE TABLE IF NOT EXISTS` never alters an
  existing table, so a new column the code depended on would have taken login
  down until somebody migrated by hand. Both reviewers found it independently.
- The new login throttle was keyed on an attacker-supplied email. Both
  addresses are public, so six anonymous requests could have locked the real
  users out indefinitely — a remote denial of service *introduced* by a
  security fix. Both reviewers found it, and both demonstrated it against a
  running server.
- The PII tokenizer's pattern matched `node_modules/@aws-sdk/client-s3/…`, so
  stack frames were replaced by tokens and filesystem paths were written into
  the PII store as though they were somebody's address.
- Mounting the error handler correctly turned every body-parser 400 into a 500,
  because the handler ignored `err.status`.
- The secret guard read the *defaulted* `NODE_ENV`, so the one case it existed
  to catch — a production box with no `NODE_ENV` set — took the safe-looking
  branch.

Every one of those was found by reading the diff and running it, not by being
told where to look.

A second round over the fixes then found two more blocking bugs, both of them
*in the round-one fixes*, and both invisible to a green test suite:

- The boot-time migration runner — the fix for the first blocking finding —
  killed the server on every existing database. One migration's "already
  applied" shortcut was `process.exit 0`, which was harmless while migrations
  ran as child processes and fatal once they ran in-process. The server ended
  mid-boot with status 0, so nothing downstream could tell it from a clean
  shutdown. Every test starts from a fresh database, where that branch is
  never taken.
- The same runner found zero migrations in the compiled artifact — it matched
  `.coffee` and `dist/` holds `.js` — and reported "already up to date"
  against a completely unmigrated database.

It also found that the atomic-restore fix left the running process on an
orphaned inode (serving stale reads, failing every write, still reporting
healthy), and that the PII-tokenizer fix turned one unauthenticated request
into three thousand database writes.

That is the argument for running the loop again after applying its findings,
and it is why the skill says a blocking finding that gets fixed goes round
again: **a fix is unreviewed code.**
