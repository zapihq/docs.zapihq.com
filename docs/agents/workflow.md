# Workflow: worktrees, feature branches, and PRs

How all implementation work is delivered in this repo. These rules are strict; don't improvise around them.

## Never commit to `main`

- No direct commits to `main`, ever — no exceptions, not even "small" fixes or docs tweaks.
- Everything lands on `main` exclusively through **squash-merged PRs**.

## Starting work (any spec, ticket, issue, or feature)

1. **Create a worktree** for the work (or reuse one via the worktree list if it already covers this work).
2. **Create a feature branch inside that worktree.** Name it after the work: `feat/<slug>`, `fix/<slug>`, or `<issue-number>-<slug>`.
3. **Do all work in that worktree, on that branch.** All commits happen there.
4. **Open a PR with the `pr` skill** when the work is ready for review. Link the driving ticket in the PR body.
5. If the attached issue has a task list, the PR body must say `Part of #<n>` — **not** `Closes #<n>` — so GitHub can't auto-close the issue while tasks remain unchecked. Close the issue manually when its last task is done.

## "Merge the PR" flow

When the user says **"merge the PR"** (or equivalent), run the full sequence:

1. **Squash and merge**: `gh pr merge <n> --squash --delete-branch`. Squash only — never rebase or merge-commit. `--delete-branch` purges the remote feature branch and deletes the local one.
2. **Sync the attached issue's tasks**: if the PR is attached to an issue that has a task list, tick every task the PR actually completed (edit the issue body's checkboxes / sub-issue state). **Leave tasks that were not completed unchecked** — don't tick them, don't delete them.
3. **Close the issue only if fully done**: if every task on the attached issue is now checked (or it had no task list and the PR completes it), close it with `gh issue close <n>`. If unchecked tasks remain, leave the issue open.
4. **Purge the feature branch**: confirm both the remote branch and the local branch are gone (`git push origin --delete <branch>` / `git branch -D <branch>` if `--delete-branch` didn't already handle it).
5. **Remove the worktree**: delete the worktree used for this work (force only to discard leftover untracked files).
6. **Return to `main`**: in the primary checkout, `git checkout main` and `git pull` so the squash commit is present locally.

## Branch hygiene

- One feature branch per worktree; the worktree exists only as long as the branch does.
- Never reuse a merged feature branch for new work — start a fresh worktree + branch.
