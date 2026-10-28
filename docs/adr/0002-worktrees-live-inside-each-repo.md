# Worktrees live inside each repo, not in a shared root

Worktrees are where every change starts, and their location is chosen by whatever agent, editor, or harness happens to create one. Left unspecified, that produced worktrees in sibling folders, in harness data directories, and in tool-specific trees on the same machine — different paths for the same job, none of them discoverable.

Three layouts were considered. A **sibling worktree** (`<repo>-<slug>` beside the checkout) needs no configuration but collides across projects and reads as a second, unexplained copy of the repo. A **central root** (`D:\vite\zapi\worktrees\<repo>\<slug>`) is easy to inspect and purge, but it only works when every project is keyed into it, and it scatters a single project's work across two drives. A root **inside the repo** (`.worktrees/<branch-dashed>`) keeps a project's worktree with the project: no keying, no cross-project collisions, and the folder moves with the repo.

We chose the in-repo root. The deciding constraint is that this machine holds many projects with unrelated conventions, and the repo is the only unit that can own a rule without imposing it on the others.

## Consequences

- A worktree's folder name mirrors its branch with `/` replaced by `-`, so `fix/docs-sidebar` lives at `.worktrees/fix-docs-sidebar`. One worktree per branch, never reused.
- `.worktrees/` is gitignored and excluded from `tsc` and ESLint. Without those exclusions a nested worktree is type-checked and linted as part of the primary checkout, which breaks `types:check` for as long as the worktree exists.
- Harnesses are deliberately not configured. The rule is the repo's, so a tool that creates a worktree elsewhere is out of policy: remove it and recreate it under `.worktrees/`.
- `git clean -xfd` in the primary checkout now reaches into every worktree and destroys uncommitted work. The safe form is `git clean -xfd -e .worktrees`.
- The empty `.worktrees/` folder always stays; removing it is how the convention gets forgotten.
- Claude Code's CLI cannot be redirected and writes `<repo>\.claude\worktrees\`, so that path is gitignored too and treated as outside the convention.
