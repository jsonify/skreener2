import XCTest
@testable import Skreener

/// Custom actions (#276): storage, what a command is given, how its result is told, and a real run of /bin/zsh.
final class CustomActionsTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "SkreenerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testActionsRoundTripThroughDefaultsInOrder() {
        let defaults = freshDefaults()
        XCTAssertEqual(CustomActions.load(from: defaults), [])
        let actions = [
            CustomAction(name: "Upload", command: "rsync \"$SKREENER_FILE\" server:/shots/", runAfterCapture: true),
            CustomAction(name: "Link", command: "curl -F file=@\"$1\" https://example.com", copyOutput: true),
        ]
        CustomActions.save(actions, to: defaults)
        XCTAssertEqual(CustomActions.load(from: defaults), actions)
    }

    func testUnreadableDataLoadsAsNoActions() {
        let defaults = freshDefaults()
        defaults.set(Data("not json".utf8), forKey: CustomActions.defaultsKey)
        XCTAssertEqual(CustomActions.load(from: defaults), [])
    }

    func testOnlyAfterCaptureActionsRunOnTheirOwn() {
        let a = CustomAction(name: "A", command: "true", runAfterCapture: true)
        let b = CustomAction(name: "B", command: "true")
        XCTAssertEqual(CustomActions.afterCapture([b, a]), [a])
    }

    func testTextIsOnlyWantedByCommandsThatMentionIt() {
        XCTAssertTrue(CustomAction(name: "T", command: "echo \"$SKREENER_TEXT\" | pbcopy").wantsText)
        XCTAssertFalse(CustomAction(name: "F", command: "open \"$1\"").wantsText)
    }

    func testEnvironmentCarriesFileAppAndText() {
        let file = URL(fileURLWithPath: "/tmp/Shot 1.png")
        XCTAssertEqual(CustomActions.environment(file: file, text: "Hello", app: "Safari"),
                       ["SKREENER_FILE": "/tmp/Shot 1.png", "SKREENER_APP": "Safari", "SKREENER_TEXT": "Hello"])
        XCTAssertEqual(CustomActions.environment(file: file, text: nil, app: nil),
                       ["SKREENER_FILE": "/tmp/Shot 1.png", "SKREENER_APP": ""])
        XCTAssertNil(CustomActions.environment(file: file, text: "", app: nil)["SKREENER_TEXT"])
    }

    func testLongTextIsCut() {
        let text = String(repeating: "x", count: CustomActions.maxTextLength + 500)
        let env = CustomActions.environment(file: URL(fileURLWithPath: "/tmp/a.png"), text: text, app: nil)
        XCTAssertEqual(env["SKREENER_TEXT"]?.count, CustomActions.maxTextLength)
    }

    func testPathIsTheFirstArgument() {
        XCTAssertEqual(CustomActions.arguments(command: "echo hi", file: URL(fileURLWithPath: "/tmp/a b.png")),
                       ["-lc", "echo hi", "skreener", "/tmp/a b.png"])
    }

    func testReportForSuccessWithOutput() {
        let outcome = ScriptRunner.Outcome(output: "https://example.com/abc\n")
        XCTAssertEqual(CustomActions.report(name: "Link", outcome: outcome, copyOutput: false),
                       CustomActions.Report(ok: true, title: "Link done", detail: "https://example.com/abc"))
        XCTAssertEqual(CustomActions.report(name: "Link", outcome: outcome, copyOutput: true),
                       CustomActions.Report(ok: true, title: "Link: output copied", detail: "https://example.com/abc",
                                            clipboard: "https://example.com/abc"))
    }

    func testReportForSuccessWithoutOutputCopiesNothing() {
        let report = CustomActions.report(name: "Quiet", outcome: ScriptRunner.Outcome(), copyOutput: true)
        XCTAssertEqual(report, CustomActions.Report(ok: true, title: "Quiet done"))
    }

    func testReportForFailureShowsTheErrorOutput() {
        let outcome = ScriptRunner.Outcome(status: 3, output: "ignored", errorOutput: "rsync: no route\n")
        let report = CustomActions.report(name: "Upload", outcome: outcome, copyOutput: true)
        XCTAssertFalse(report.ok)
        XCTAssertEqual(report.title, "Upload failed")
        XCTAssertEqual(report.detail, "Exit status 3: rsync: no route")
        XCTAssertNil(report.clipboard)
        XCTAssertEqual(CustomActions.report(name: "X", outcome: ScriptRunner.Outcome(status: 1), copyOutput: false).detail,
                       "Exit status 1.")
    }

    func testReportForTimeoutAndLaunchFailure() {
        XCTAssertEqual(CustomActions.report(name: "Slow", outcome: ScriptRunner.Outcome(timedOut: true), copyOutput: false).title,
                       "Slow took too long")
        let launch = CustomActions.report(name: "Bad", outcome: ScriptRunner.Outcome(launchError: "no such shell"), copyOutput: false)
        XCTAssertFalse(launch.ok)
        XCTAssertEqual(launch.detail, "no such shell")
    }

    func testExcerptCutsLongText() {
        XCTAssertEqual(CustomActions.excerpt("  short \n", limit: 10), "short")
        XCTAssertEqual(CustomActions.excerpt("abcdefghij", limit: 4), "abcd…")
    }

    // MARK: Running a command (macOS has /bin/zsh)

    private let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Skreener Test.png")

    func testCommandSeesEnvironmentAndFirstArgument() async {
        let env = CustomActions.environment(file: file, text: "some text", app: "Notes")
        let outcome = await ScriptRunner.run(command: "print -r -- \"$SKREENER_FILE|$1|$SKREENER_TEXT|$SKREENER_APP\"",
                                             file: file, environment: env)
        XCTAssertEqual(outcome.status, 0)
        XCTAssertEqual(outcome.output.trimmingCharacters(in: .whitespacesAndNewlines),
                       "\(file.path)|\(file.path)|some text|Notes")
    }

    func testFailingCommandReportsStatusAndStderr() async {
        let outcome = await ScriptRunner.run(command: "echo oops >&2; exit 4", file: file, environment: [:])
        XCTAssertEqual(outcome.status, 4)
        XCTAssertEqual(outcome.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines), "oops")
        XCTAssertFalse(outcome.timedOut)
    }

    func testSlowCommandIsStoppedAtTheTimeout() async {
        let outcome = await ScriptRunner.run(command: "exec sleep 30", file: file, environment: [:], timeout: 0.5)
        XCTAssertTrue(outcome.timedOut)
        XCTAssertNotEqual(outcome.status, 0)
    }
}
