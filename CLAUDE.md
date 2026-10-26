# Skreener

macOS menu-bar screenshot app (Swift/AppKit, SwiftPM). See README.md for features and TODO.md for the roadmap.

- Build: `Scripts/build_app.sh` (macOS only). CI builds with `SKREENER_STRICT=1`, which passes
  `-warnings-as-errors`, on the newest Xcode on the runner.
- Tests: `swift test` (macOS only; `Tests/SkreenerTests`, `@testable import Skreener`). CI runs them with warnings
  as errors before the build. They cover logic that runs without a screen or permissions; the rest needs a manual
  check on a Mac.
- Builds must be warning-free. The owner builds locally with a newer Xcode than CI's default, so also
  avoid patterns newer compilers warn about, e.g. a `[weak self]` closure nested inside a closure that
  captures `self` strongly (put `[weak self]` on the outer closure instead).
- Cloud sessions run on Linux without AppKit: the macOS CI build is the compile check. Read its log for
  warnings, not just the result.
- Whenever a change needs the owner to test it (manual checks on a Mac, anything the tests don't cover), give
  step-by-step test instructions: how to build and launch, exactly what to click or press, and the expected
  result for each step, so the owner isn't guessing what or how to test.
- Commit subjects use Conventional Commits (`fix(editor): …`, `feat(capture): …`, `docs: …`, `ci: …`): release-please
  picks the next version from them (fix → patch, feat → minor, `!` → major) and CI rejects PRs whose commits don't
  match. Keep the issue reference, e.g. `fix(capture): keep window corners transparent (#138)`.

## Agent skills

### Issue tracker

Issues and specs live in this repo's GitHub Issues, managed with the `gh` CLI (REST fallback for cloud sessions). See `docs/agents/issue-tracker.md`.

### Director mode

When the owner asks you to direct a project (plan, brief worker subagents, review and report rather than code it
yourself), or resumes the Windows port, read `docs/agents/director.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root, created as terms and decisions get settled. See `docs/agents/domain.md`.
