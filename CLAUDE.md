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
