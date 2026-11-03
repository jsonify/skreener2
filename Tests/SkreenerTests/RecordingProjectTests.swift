import XCTest
@testable import Skreener

final class RecordingProjectTests: XCTestCase {
    private func sampleEvents() -> RecordingEvents {
        var e = RecordingEvents()
        e.cursor = [.init(t: 0, x: 10, y: 20, visible: true), .init(t: 1 / 30, x: 12.5, y: 21, visible: false)]
        e.cursorImages = [.init(file: "0.png", width: 17, height: 23, hotspotX: 4, hotspotY: 4)]
        e.cursorChanges = [.init(t: 0, image: 0)]
        e.clicks = [.init(t: 0.5, x: 30, y: 40, button: .left, down: true),
                    .init(t: 0.6, x: 30, y: 40, button: .left, down: false),
                    .init(t: 0.9, x: 1, y: 2, button: .right, down: true)]
        e.keys = [.init(t: 1, text: "⌘S", append: false), .init(t: 2, text: "a", append: true)]
        e.spotlightAtStart = true
        e.spotlight = [.init(t: 3, on: false)]
        return e
    }

    private func sampleProject() -> RecordingProject {
        RecordingProject(created: Date(timeIntervalSince1970: 1_700_000_000), area: CGRect(x: 100, y: 200, width: 640, height: 360),
                         screenScale: 2, videoWidth: 1280, videoHeight: 720, fps: 60,
                         style: EffectsStyle(clicks: true, keystrokes: true, keystrokesAtTop: true), exported: "/tmp/a.mp4")
    }

    func testEventsRoundTrip() throws {
        let e = sampleEvents()
        let decoded = try RecordingEvents.decode(e.encoded())
        XCTAssertEqual(decoded, e)
        XCTAssertEqual(decoded.version, RecordingEvents.currentVersion)
    }

    func testCursorSamplesUseShortKeys() throws {
        let json = try XCTUnwrap(String(data: sampleEvents().encoded(), encoding: .utf8))
        XCTAssertTrue(json.contains("\"v\":true"), json)
        XCTAssertFalse(json.contains("\"visible\""), json)
    }

    func testProjectRoundTrip() throws {
        let p = sampleProject()
        let decoded = try RecordingProject.decode(p.encoded())
        XCTAssertEqual(decoded, p)
        XCTAssertEqual(decoded.videoSize, CGSize(width: 1280, height: 720))
        XCTAssertEqual(decoded.pixelScale, 2)
    }

    func testNewerVersionsAreRefused() {
        let newer = Data(#"{"version": 99, "cursor": []}"#.utf8)
        XCTAssertThrowsError(try RecordingEvents.decode(newer)) { XCTAssertEqual($0 as? RecordingFileError, .newerVersion(99)) }
        XCTAssertThrowsError(try RecordingProject.decode(newer)) { XCTAssertEqual($0 as? RecordingFileError, .newerVersion(99)) }
    }

    func testFilesWithoutAVersionAreRefused() {
        XCTAssertThrowsError(try RecordingEvents.decode(Data("{}".utf8))) {
            XCTAssertEqual($0 as? RecordingFileError, .notARecordingFile)
        }
    }

    func testOlderOrSameVersionDecodes() throws {
        let minimal = Data(#"{"version": 1, "cursor": [], "cursorImages": [], "cursorChanges": [], "clicks": [], "keys": [], "spotlightAtStart": false, "spotlight": []}"#.utf8)
        XCTAssertEqual(try RecordingEvents.decode(minimal), RecordingEvents())
    }

    func testSortedOrdersEventsAndMergesNearDuplicateSamples() {
        var e = RecordingEvents()
        e.cursor = [.init(t: 0.2, x: 2, y: 0, visible: true), .init(t: 0.1, x: 1, y: 0, visible: true),
                    .init(t: 0.1001, x: 9, y: 0, visible: true)]
        e.clicks = [.init(t: 2, x: 0, y: 0, button: .left, down: true), .init(t: 1, x: 0, y: 0, button: .left, down: true)]
        e.keys = [.init(t: 5, text: "b", append: true), .init(t: 4, text: "a", append: true)]
        let s = e.sorted()
        XCTAssertEqual(s.cursor.map(\.x), [9, 2])
        XCTAssertEqual(s.clicks.map(\.t), [1, 2])
        XCTAssertEqual(s.keys.map(\.text), ["a", "b"])
    }

    func testMakeFolderCreatesAProjectWithACursorsFolder() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent("SkreenerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }
        let dir = try RecordingProject.makeFolder(in: parent)
        XCTAssertEqual(dir.pathExtension, RecordingProject.fileExtension)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(RecordingProject.cursorsFolder).path,
                                                     isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue)
        XCTAssertNotEqual(try RecordingProject.makeFolder(in: parent), dir)
    }
}
