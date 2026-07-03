import XCTest
@testable import RadarCore

final class RadarCoreTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // Use a unique temp board per test class run for isolation.
        let tempDir = NSTemporaryDirectory()
        let unique = "doodle-test-\(UUID().uuidString)"
        let boardPath = (tempDir as NSString).appendingPathComponent("\(unique)/board.json")
        setenv("DOODLE_BOARD_PATH", boardPath, 1)
        // Clean any prior
        try? FileManager.default.removeItem(atPath: boardPath)
        try? FileManager.default.removeItem(atPath: boardPath + ".lock")
    }

    override func tearDown() {
        // Best effort cleanup of the test board
        if let path = ProcessInfo.processInfo.environment["DOODLE_BOARD_PATH"] {
            try? FileManager.default.removeItem(atPath: path)
            try? FileManager.default.removeItem(atPath: path + ".lock")
            // also any .corrupt we may have created in test
            let dir = (path as NSString).deletingLastPathComponent
            if let contents = try? FileManager.default.contentsOfDirectory(atPath: dir) {
                for name in contents where name.contains("board.json.corrupt-") {
                    try? FileManager.default.removeItem(atPath: (dir as NSString).appendingPathComponent(name))
                }
            }
        }
        super.tearDown()
    }

    func testNameNormalization() {
        XCTAssertEqual(NameNormalizer.normalize("  Auth Middleware  "), "auth middleware")
        XCTAssertEqual(NameNormalizer.normalize("Auth-Middleware"), "auth-middleware")
        XCTAssertEqual(NameNormalizer.normalize("auth middleware"), "auth middleware")
    }

    func testDoneExclusion() throws {
        // Seed via set (uses withLock)
        _ = try BoardStore.set(displayName: "Task A", status: "active", summary: "doing")
        _ = try BoardStore.set(displayName: "Task B", status: "done", summary: "finished")
        _ = try BoardStore.set(displayName: "Task C", status: "waiting_on_user", summary: "ask")

        let withoutDone = try BoardStore.loadFiltered(includeDone: false)
        XCTAssertEqual(withoutDone.count, 2)
        XCTAssertFalse(withoutDone.contains { $0.status == "done" })

        let withDone = try BoardStore.loadFiltered(includeDone: true)
        XCTAssertEqual(withDone.count, 3)
        XCTAssertTrue(withDone.contains { $0.status == "done" })
    }

    func testCorruptFileBackupBehavior() throws {
        guard let boardPath = ProcessInfo.processInfo.environment["DOODLE_BOARD_PATH"] else {
            XCTFail("DOODLE_BOARD_PATH not set")
            return
        }
        let url = URL(fileURLWithPath: boardPath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        // Write garbage JSON
        try "this is not valid json {".write(to: url, atomically: true, encoding: .utf8)

        // Trigger a write (set) which goes through withLock -> should backup + fresh
        let item = try BoardStore.set(displayName: "Recovery task", status: "active", summary: "after corrupt")

        // The set should have succeeded with fresh board containing only the new item
        XCTAssertEqual(item.name, "recovery task")
        let items = try BoardStore.loadFiltered()
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.name, "recovery task")

        // A .corrupt- backup should exist next to board.json
        let dir = url.deletingLastPathComponent()
        let contents = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let corruptFiles = contents.filter { $0.hasPrefix("board.json.corrupt-") }
        XCTAssertFalse(corruptFiles.isEmpty, "Expected a corrupt backup file to be created")
        // The original board.json should now be valid (the new one)
        let newData = try Data(contentsOf: url)
        XCTAssertFalse(newData.isEmpty)
    }

    func testAttributedStringWithLinks_nonASCII() {
        // Emoji/glyphs (non-ASCII) before URLs must not throw off UTF-16 vs character offsets.
        let input = "❓ check github.com/foo/bar 🔨 https://example.com"
        let attr = RadarCore.attributedStringWithLinks(from: input)

        let links = attr.runs.compactMap { run -> String? in
            if run.link != nil {
                return String(attr[run.range].characters)
            }
            return nil
        }
        XCTAssertEqual(links, ["github.com/foo/bar", "https://example.com"])
    }

    func testAttributedStringWithLinks_doesNotClobberFullURL() {
        // http:// full URL must remain unchanged; bare domain gets https
        let input = "http://example.com and plain example.org"
        let attr = RadarCore.attributedStringWithLinks(from: input)

        let links = attr.runs.compactMap { run -> (String, String?)? in
            if let link = run.link {
                return (String(attr[run.range].characters), link.absoluteString)
            }
            return nil
        }

        XCTAssertEqual(links.count, 2)

        // http one should be present with http link
        let httpLink = links.first(where: { $0.0.hasPrefix("http://example.com") })
        XCTAssertNotNil(httpLink)
        XCTAssertTrue(httpLink?.1?.hasPrefix("http://") ?? false)

        // bare one as https
        let httpsLink = links.first(where: { $0.0 == "example.org" })
        XCTAssertNotNil(httpsLink)
        XCTAssertTrue(httpsLink?.1?.hasPrefix("https://example.org") ?? false)
    }
}