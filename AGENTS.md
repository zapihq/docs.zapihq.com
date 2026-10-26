# docs.zapihq.com

Documentation site for ZAPI, built with Next.js, Fumadocs, and Fumadocs MDX.

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

Five canonical triage roles, with label strings equal to their names (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Writing the docs

Every content page follows `WRITING.md` — voice, money, names, terminology —
read it before writing or editing anything in `content/docs/`. Term
definitions live in `GLOSSARY.md`.

### Domain docs

Single-context: one `GLOSSARY.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.

### Branch & PR workflow

Never commit to `main`. All work happens in a worktree on a feature branch, ships as a PR via the `pr` skill, and lands via squash merge; "merge the PR" also syncs the attached issue's task list and purges branches/worktree. See `docs/agents/workflow.md`.
