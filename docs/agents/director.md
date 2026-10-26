# Director mode

For multi-part projects (the Windows port is the first), the owner works with the main session as a **director**: a
coordinator who plans, briefs, reviews and reports, while **workers** (subagents) write the code. The director keeps a
running conversation with the owner and stays out of the heavy coding.

## The loop

1. **Read the code first.** Size the job yourself (imports, line counts, what is platform-bound) before decomposing.
   Done when you can name the modules and the risky parts.
2. **Put the owner's calls to the owner.** Stack, scope, milestone, test setup and product behaviour are theirs; ask
   with a recommendation. Done when nothing a worker needs is still an open owner decision.
3. **Prepare the shared ground.** Before parallel workers start, the director sets up whatever two of them would both
   edit (project files, package references, interface contracts) on `main`. Each worker gets folders it owns and the
   exact text of any shared contract file.
4. **Brief each worker.** One role per brief: scope, owned paths, contract, how to verify, commit rules, and a capped
   final report (what works, CI status, gaps, owner test steps). Worker briefs start cold: include every fact they need.
5. **Review every hand-back.** Re-run the tests yourself, read the diff stat and any `[verify]`/`TODO` markers, and
   check the report's claims before opening a PR. A worker's report is a claim, not a result.
6. **Report to the owner** after each hand-back or event: a short status table (role, model, task, state), blockers,
   decisions needed, and step-by-step test instructions when something needs a manual check.
7. **Adapt.** Add, retire or re-scope roles as findings arrive, and say so in the next report.

## Workers

- **Model by difficulty**: Haiku for writing up known material (test plans), Sonnet for well-specified work with a
  spec to check against (ports with tests, scaffolding, shell plumbing), Opus for the riskiest or most subtle work
  (capture and overlays, integration of separately written pieces, geometry).
- **Isolation**: run code-writing workers in a worktree, one branch each, **branched from `main`**. Each worker's PR
  stands alone and merges on its own; ordering is by merge sequence, never by stacking branches.
- **Compile loop** for code that only builds in CI (WinUI): the worker pushes its branch, runs the workflow on it with
  `workflow_dispatch`, reads the job logs and repeats until every job is green.

## Lessons from the Windows port

- Stacked PRs plus squash merges caused add/add conflicts and brought deleted files back. Branch from `main` instead.
- Commit types for Windows-only work are `feat(windows)`, `build(windows)`, `test(windows)`, `docs(windows)`.
  `release-please-config.json` excludes `windows/` from the Mac release; keep new Windows-only paths in that list.
- Owner merges with squash; the PR title becomes the commit, so it carries the Conventional Commit type.
- The Windows App SDK refuses to start below Windows 10 1809 ("entry point not found" in
  `Microsoft.WindowsAppRuntime.dll`), and excluding our own overlays from captures needs 2004. The owner tests on an
  up-to-date Windows 10 PC; a Windows 11 ARM VM in UTM is the fallback.
