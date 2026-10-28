# Worktrees

Where worktrees live, what they're called, and which command creates them. This is this repo's convention only; other checkouts on the machine run their own.

## Location

Every worktree lives inside the repo, under `.worktrees/`:

```
docs.zapihq.com/
└── .worktrees/
    └── fix-docs-sidebar/     ← branch fix/docs-sidebar
```

The folder name mirrors the branch with `/` replaced by `-`: branch `feat/nav-cleanup` lives in `.worktrees/feat-nav-cleanup`. The mapping is one-to-one, so a path names its branch without guessing, and the same branch never gets a second worktree.

`.worktrees/` is gitignored and excluded from TypeScript and ESLint. Leave the folder itself in place even when it's empty — an absent folder is how this convention gets forgotten.

## Creating a worktree

Use the script, from the primary checkout:

```bat
scripts\worktree.cmd new feat/nav-cleanup
```

It creates `.worktrees/feat-nav-cleanup` on a new branch cut from `origin/main`, refuses if the directory or branch already exists, and prints the path. Work there from then on — every commit for this branch happens in that folder.

If the script is missing or broken, the same thing by hand:

```
git fetch origin
git worktree add .worktrees/<branch-dashed> -b <branch> origin/main
```

## Listing and removing

```bat
scripts\worktree.cmd list
scripts\worktree.cmd rm .worktrees\feat-nav-cleanup
```

`list` wraps `git worktree list`. `rm` refuses a worktree with uncommitted or untracked changes, and refuses any path outside `.worktrees/`; `-Force` discards the changes instead. Removing a worktree leaves its branch behind — delete that separately (see the merge flow in `workflow.md`).

## Rules

- **A worktree outside `.worktrees/` is out of policy.** If a tool — editor, IDE, agent harness — creates one somewhere else, remove it and recreate it here. Nothing in this repo configures individual tools to honour the path; the rule belongs to the repo, not to the tool.
- **One worktree per branch.** Never reuse a merged branch for new work; start a new branch, with a new worktree.
- **`git clean -xfd` in the primary checkout deletes `.worktrees/`** along with every uncommitted change inside it. If you must clean, use `git clean -xfd -e .worktrees`.
- **Never remove the `.worktrees/` folder itself**, only the worktrees inside it.
