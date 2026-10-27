import Foundation

/// A shell command the user wrote (#276): run on a capture from the Send To menu, or after every capture. Settings →
/// Send To edits the list; the capture's path and text reach the command as environment variables and as `$1`.
struct CustomAction: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var command: String
    /// Runs on its own after every screenshot, as well as from Send To.
    var runAfterCapture = false
    /// Puts what the command printed on the clipboard (e.g. an upload link).
    var copyOutput = false

    /// Whether the command uses the screenshot's text, so Skreener only reads it (OCR) for actions that do.
    var wantsText: Bool { command.contains("SKREENER_TEXT") }
}

/// The logic of custom actions that needs no screen: storage, what a command is given, and how its result is told.
enum CustomActions {
    static let defaultsKey = "customActions"
    /// A command is stopped after this long.
    static let timeout: TimeInterval = 60
    /// The most text passed in SKREENER_TEXT: the environment has a size limit, and a script rarely needs more.
    static let maxTextLength = 100_000

    static func load(from defaults: UserDefaults = .standard) -> [CustomAction] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [] }
        return (try? JSONDecoder().decode([CustomAction].self, from: data)) ?? []
    }

    static func save(_ actions: [CustomAction], to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(actions) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    /// The actions that run on their own after a capture, in the order Settings lists them.
    static func afterCapture(_ actions: [CustomAction]) -> [CustomAction] { actions.filter(\.runAfterCapture) }

    /// What the command sees besides the login shell's own environment. SKREENER_APP is empty when the app the
    /// capture came from isn't known; SKREENER_TEXT is only there when the screenshot had text.
    static func environment(file: URL, text: String?, app: String?) -> [String: String] {
        var env = ["SKREENER_FILE": file.path, "SKREENER_APP": app ?? ""]
        if let text, !text.isEmpty { env["SKREENER_TEXT"] = String(text.prefix(maxTextLength)) }
        return env
    }

    /// The arguments for `/bin/zsh`: `-l` so the command finds what the user's own Terminal finds (Homebrew…), `-c` for
    /// the command, then `$0` and `$1`, the capture's path.
    static func arguments(command: String, file: URL) -> [String] { ["-lc", command, "skreener", file.path] }

    /// What the user is told once a command has finished.
    struct Report: Equatable {
        var ok: Bool
        var title: String
        var detail: String?
        /// What goes on the clipboard (the command's output, when the action asks for it).
        var clipboard: String?
    }

    static func report(name: String, outcome: ScriptRunner.Outcome, copyOutput: Bool) -> Report {
        let out = outcome.output.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = outcome.errorOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        if let launchError = outcome.launchError {
            return Report(ok: false, title: "Couldn't run \(name)", detail: launchError)
        }
        if outcome.timedOut {
            return Report(ok: false, title: "\(name) took too long", detail: "Stopped after \(Int(timeout)) seconds.")
        }
        if outcome.status != 0 {
            let why = excerpt(err.isEmpty ? out : err, limit: 300)
            return Report(ok: false, title: "\(name) failed",
                          detail: why.isEmpty ? "Exit status \(outcome.status)." : "Exit status \(outcome.status): \(why)")
        }
        if copyOutput, !out.isEmpty {
            return Report(ok: true, title: "\(name): output copied", detail: excerpt(out, limit: 200), clipboard: out)
        }
        return Report(ok: true, title: "\(name) done", detail: out.isEmpty ? nil : excerpt(out, limit: 200))
    }

    /// `text` cut to `limit` characters (an ellipsis marks the cut), for a message.
    static func excerpt(_ text: String, limit: Int) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.count > limit ? String(t.prefix(limit)) + "…" : t
    }
}

/// Runs a custom action's command with `/bin/zsh -lc`, off the main thread.
enum ScriptRunner {
    struct Outcome: Equatable {
        var status: Int32 = 0
        var output = ""
        var errorOutput = ""
        var timedOut = false
        /// Why the shell couldn't be started at all.
        var launchError: String?
    }

    static func run(command: String, file: URL, environment: [String: String],
                    timeout: TimeInterval = CustomActions.timeout) async -> Outcome {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(returning: runBlocking(command: command, file: file, environment: environment,
                                                           timeout: timeout))
            }
        }
    }

    private static func runBlocking(command: String, file: URL, environment: [String: String],
                                    timeout: TimeInterval) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = CustomActions.arguments(command: command, file: file)
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        process.currentDirectoryURL = file.deletingLastPathComponent()
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return Outcome(launchError: error.localizedDescription) }

        // Read both pipes while it runs, so a chatty command can't fill a pipe and stall.
        let outBytes = Box<Data>(Data()), errBytes = Box<Data>(Data())
        let readers = DispatchGroup()
        for (handle, bytes) in [(out.fileHandleForReading, outBytes), (err.fileHandleForReading, errBytes)] {
            readers.enter()
            DispatchQueue.global(qos: .utility).async {
                bytes.value = handle.readDataToEndOfFile()
                readers.leave()
            }
        }
        let timedOut = Box<Bool>(false)
        let stop = DispatchWorkItem {
            timedOut.value = true
            process.terminate()
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: stop)
        finished.wait()
        stop.cancel()
        // A background job the command left running may keep the pipes open: don't wait for it for long.
        _ = readers.wait(timeout: .now() + 5)
        return Outcome(status: process.terminationStatus,
                       output: String(decoding: outBytes.value, as: UTF8.self),
                       errorOutput: String(decoding: errBytes.value, as: UTF8.self),
                       timedOut: timedOut.value)
    }

    /// A value handed from one queue to another.
    private final class Box<T: Sendable>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: T
        init(_ value: T) { stored = value }
        var value: T {
            get { lock.lock(); defer { lock.unlock() }; return stored }
            set { lock.lock(); stored = newValue; lock.unlock() }
        }
    }
}
