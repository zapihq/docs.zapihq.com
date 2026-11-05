# Workflow: worktrees, feature branches, and PRs

How all implementation work is delivered in this repo. These rules are strict; don't improvise around them.

## Never commit to `main`

- No direct commits to `main`, ever — no exceptions, not even "small" fixes or docs tweaks.
- Everything lands on `main` exclusively through **squash-merged PRs**.

## Starting work (any spec, ticket, issue, or feature)

1. **Create the worktree and its branch together**: `scripts\worktree.cmd new <branch>`. Name the branch after the work: `feat/<slug>`, `fix/<slug>`, or `<issue-number>-<slug>`. It lands at `.worktrees/<branch-dashed>`; details in `worktrees.md`. Never reuse an existing worktree, and never reuse a merged branch.
2. **Do all work in that worktree, on that branch.** All commits happen there.
3. **Run the checks** before opening the PR: `pnpm check` and `bash scripts/test-deploy.sh` (see `README.md`). CI runs the same commands, plus `actionlint` and `shellcheck`.
4. **Open a PR with the `pr` skill** when the work is ready for review. Link the driving ticket in the PR body.
5. If the attached issue has a task list, the PR body must say `Part of #<n>` — **not** `Closes #<n>` — so GitHub can't auto-close the issue while tasks remain unchecked. Close the issue manually when its last task is done.

## "Merge the PR" flow

When the user says **"merge the PR"** (or equivalent), run the full sequence:

1. **Squash and merge**: `gh pr merge <n> --squash`. Squash only — never rebase or merge-commit. Leave `--delete-branch` off: the worktree still has the branch checked out, and letting `gh` delete it can leave a half-removed directory behind.
2. **Remove the worktree**: `scripts\worktree.cmd rm .worktrees\<branch-dashed>`. Force only to discard leftover untracked files. If the registration is already gone, the script deletes the leftover directory.
3. **Delete the branches**: from the primary checkout, `git branch -D <branch>`, then `git worktree prune`, then `git push origin --delete <branch>`.
4. **Sync the attached issue's tasks**: if the PR is attached to an issue that has a task list, tick every task the PR actually completed. Use `node scripts/issue-tasks.mjs <n> --list` and then `--task <i>`; see `issue-tracker.md`. **Leave tasks that were not completed unchecked** — don't tick them, don't delete them.
5. **Close the issue only if fully done**: if every task on the attached issue is now checked (or it had no task list and the PR completes it), close it with `gh issue close <n>`. If unchecked tasks remain, leave the issue open.
6. **Return to `main`**: in the primary checkout, `git checkout main` and `git pull` so the squash commit is present locally.

Leave the empty `.worktrees/` folder in place.

## Branch hygiene

- One feature branch per worktree; the worktree exists only as long as the branch does, and both live in `.worktrees/` (see `worktrees.md`).
- Never reuse a merged feature branch for new work — start a fresh worktree + branch.
