import AppKit
import ClipboardCore

final class FakeClipboard: ClipboardAccess {
    var changeCount = 1
    var text = "first"
    var writes = 0
    var failWrite = false
    var changeDuringRead = false
    var failRead = false
    func snapshot(expected: Int) throws -> Snapshot {
        if changeDuringRead { changeCount += 1; throw ClipboardError.changed }
        if failRead { throw ClipboardError.skipped("unavailable representation") }
        return Snapshot(generation: expected, representations: [Representation(.string, Data(text.utf8))], text: text)
    }
    func write(_ snapshot: Snapshot, mode: Mode) throws -> Int {
        if failWrite { throw ClipboardError.writeFailed }
        guard snapshot.generation == changeCount else { throw ClipboardError.changed }
        writes += 1
        changeCount += 1
        return changeCount
    }
    func copy(_ value: String) { text = value; changeCount += 1 }
}

final class MonitorTests: TestCase {
    func testStartupStableDelayAndOwnWriteAreIgnored() {
        let board = FakeClipboard()
        let monitor = Monitor(clipboard: board, mode: .preserve)
        monitor.tick(now: 0)
        expectEqual(board.writes, 0)
        board.copy("new")
        monitor.tick(now: 1)
        monitor.tick(now: 1.05)
        expectEqual(board.writes, 0)
        monitor.tick(now: 1.4)
        expectEqual(board.writes, 1)
        for i in 2...10 { monitor.tick(now: Double(i)) }
        expectEqual(board.writes, 1)
    }

    func testRapidCopiesOnlyRewriteTheLatest() {
        let board = FakeClipboard()
        let monitor = Monitor(clipboard: board, mode: .preserve)
        board.copy("a"); monitor.tick(now: 0)
        board.copy("b"); monitor.tick(now: 0.4)
        expectEqual(board.writes, 0)
        monitor.tick(now: 0.8)
        expectEqual(board.writes, 1)
        expectEqual(board.text, "b")
    }

    func testEchoIsSuppressedButLaterRecopyWorks() {
        let board = FakeClipboard()
        let monitor = Monitor(clipboard: board, mode: .preserve)
        board.copy("a"); monitor.tick(now: 0); monitor.tick(now: 0.4)
        board.copy("a"); monitor.tick(now: 1); monitor.tick(now: 1.4)
        expectEqual(board.writes, 1)
        board.copy("a"); monitor.tick(now: 4); monitor.tick(now: 4.4)
        expectEqual(board.writes, 2)
    }

    func testReadRaceDoesNotWriteAndNextCopyCanProceed() {
        let board = FakeClipboard()
        let monitor = Monitor(clipboard: board, mode: .preserve)
        board.changeDuringRead = true
        board.copy("a"); monitor.tick(now: 0); monitor.tick(now: 0.4)
        expectEqual(board.writes, 0)
        board.changeDuringRead = false
        monitor.tick(now: 0.8); monitor.tick(now: 1.2)
        expectEqual(board.writes, 1)
    }

    func testUnavailableDataIsNotRetriedForever() {
        let board = FakeClipboard()
        let monitor = Monitor(clipboard: board, mode: .preserve)
        board.failRead = true
        board.copy("a"); monitor.tick(now: 0); monitor.tick(now: 0.4)
        board.failRead = false
        monitor.tick(now: 1)
        expectEqual(board.writes, 0)
    }

    func testWriteFailureHaltsMonitor() {
        let board = FakeClipboard()
        let monitor = Monitor(clipboard: board, mode: .preserve)
        board.failWrite = true
        board.copy("a"); monitor.tick(now: 0); monitor.tick(now: 0.4)
        expect(monitor.halted)
        board.failWrite = false
        board.copy("b"); monitor.tick(now: 1); monitor.tick(now: 1.4)
        expectEqual(board.writes, 0)
    }

    func testRateLimitAndRecovery() {
        let board = FakeClipboard()
        let monitor = Monitor(clipboard: board, mode: .preserve)
        for i in 0..<10 {
            board.copy("copy \(i)")
            monitor.tick(now: Double(i) * 0.8)
            monitor.tick(now: Double(i) * 0.8 + 0.4)
        }
        expectEqual(board.writes, 8)
        board.copy("after cooldown"); monitor.tick(now: 40); monitor.tick(now: 40.4)
        expectEqual(board.writes, 9)
    }
}

final class PasteboardTests: TestCase {
    var pb: NSPasteboard!
    override func setUpWithError() throws {
        pb = NSPasteboard.withUniqueName()
        pb.clearContents()
        guard pb.setString("availability probe", forType: .string) else {
            throw TestUnavailable("Pasteboard server unavailable in this sandbox; rerun with GUI-session access")
        }
    }
    override func tearDown() { pb?.releaseGlobally() }

    func seed(_ values: [(NSPasteboard.PasteboardType, Data)]) throws {
        let item = NSPasteboardItem()
        for (type, data) in values { expect(item.setData(data, forType: type)) }
        pb.clearContents()
        expect(pb.writeObjects([item]))
    }
    var richValues: [(NSPasteboard.PasteboardType, Data)] {
        [(.html, Data("<b>Caffè 👋</b>".utf8)),
         (.rtf, Data(#"{\rtf1\ansi\b Caffe}"#.utf8)),
         (.string, Data("Caffè 👋\nSeconda riga".utf8))]
    }

    func testPreserveRetainsEveryByteAndAnnouncesNewOwnership() throws {
        try seed(richValues)
        let board = SystemClipboard(pb)
        let snapshot = try board.snapshot(expected: board.changeCount)
        let own = try board.write(snapshot, mode: .preserve)
        expectGreater(own, snapshot.generation)
        expectEqual(board.changeCount, own)
        expectEqual(pb.pasteboardItems?.count, 1)
        expectEqual(pb.pasteboardItems?.first?.types.first, .string)
        for (type, data) in richValues { expectEqual(pb.data(forType: type), data) }
    }

    func testReplayRetainsOrderAndBytes() throws {
        try seed(richValues)
        let beforeTypes = pb.pasteboardItems![0].types
        let board = SystemClipboard(pb)
        let snapshot = try board.snapshot(expected: board.changeCount)
        _ = try board.write(snapshot, mode: .replay)
        expectEqual(pb.pasteboardItems![0].types, beforeTypes)
        for (type, data) in richValues { expectEqual(pb.data(forType: type), data) }
    }

    func testInplaceKeepsRichTextButDoesNotAdvanceChangeCount() throws {
        try seed(richValues)
        let board = SystemClipboard(pb)
        let before = board.changeCount
        _ = try board.write(board.snapshot(expected: before), mode: .inplace)
        expectEqual(board.changeCount, before)
        for (type, data) in richValues { expectEqual(pb.data(forType: type), data) }
    }

    func testPlainExplicitlyDiscardsFormatting() throws {
        try seed(richValues)
        let board = SystemClipboard(pb)
        _ = try board.write(board.snapshot(expected: board.changeCount), mode: .plain)
        expectEqual(pb.pasteboardItems![0].types, [.string])
        expectEqual(pb.string(forType: .string), "Caffè 👋\nSeconda riga")
    }

    var chromiumValues: [(NSPasteboard.PasteboardType, Data)] {
        [(.html, Data("<b>Test ChatGPT</b>".utf8)),
         (.string, Data("Test ChatGPT".utf8)),
         (.init("org.chromium.internal.source-rfh-token"), Data([0, 1, 2, 3])),
         (.init("org.chromium.source-url"), Data("https://example.com/chat".utf8))]
    }

    func testChromiumSelectionIsNormalizedByMonitor() throws {
        let board = SystemClipboard(pb)
        let monitor = Monitor(clipboard: board, mode: .plain)
        try seed(chromiumValues)
        let before = pb.changeCount
        monitor.tick(now: 0)
        monitor.tick(now: 0.4)
        expectGreater(pb.changeCount, before)
        expectEqual(pb.pasteboardItems![0].types, [.string])
        expectEqual(pb.string(forType: .string), "Test ChatGPT")
        let rewritten = pb.changeCount
        monitor.tick(now: 0.8)
        monitor.tick(now: 1.2)
        expectEqual(pb.changeCount, rewritten)
    }

    func testChromiumMetadataIsRetainedInPreserveMode() throws {
        try seed(chromiumValues)
        let board = SystemClipboard(pb)
        _ = try board.write(board.snapshot(expected: board.changeCount), mode: .preserve)
        for (type, data) in chromiumValues { expectEqual(pb.data(forType: type), data) }
    }

    func testChromiumMetadataDoesNotOverrideProtectedFormats() throws {
        for name in ["public.url", "public.file-url", "public.png",
                     "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
                     "org.chromium.web-custom-data", "org.chromium.image-html",
                     "org.chromium.internal.unknown-object"] {
            try seed(chromiumValues + [(.init(name), Data([1, 2, 3]))])
            let before = pb.changeCount
            expectThrows(try SystemClipboard(pb).snapshot(expected: before), name)
            expectEqual(pb.changeCount, before)
            expectEqual(pb.data(forType: .init(name)), Data([1, 2, 3]))
        }
    }

    func testProtectedContentIsNeverChanged() throws {
        let protected = [
            "public.png", "public.jpeg", "public.tiff", "com.adobe.pdf", "public.file-url", "public.url",
            "com.apple.flat-rtfd", "com.apple.pasteboard.promised-file-url",
            "org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType",
            "org.nspasteboard.AutoGeneratedType", "org.nspasteboard.source",
            "com.apple.is-remote-clipboard", "com.agilebits.onepassword", "com.example.unknown-object"
        ]
        for name in protected {
            try seed([(.string, Data("text fallback".utf8)), (.init(name), Data([1, 2, 3]))])
            let board = SystemClipboard(pb)
            let before = board.changeCount
            expectThrows(try board.snapshot(expected: before), name)
            expectEqual(board.changeCount, before, name)
            expectEqual(pb.data(forType: .init(name)), Data([1, 2, 3]), name)
        }
    }

    func testMultipleItemsAreSkipped() throws {
        let items = ["a", "b"].map { value -> NSPasteboardItem in
            let item = NSPasteboardItem(); item.setString(value, forType: .string); return item
        }
        pb.clearContents(); expect(pb.writeObjects(items))
        let before = pb.changeCount
        expectThrows(try SystemClipboard(pb).snapshot(expected: before))
        expectEqual(pb.changeCount, before)
        expectEqual(pb.pasteboardItems?.count, 2)
    }

    func testLegacyFileListIsProtected() {
        let legacy = NSPasteboard.PasteboardType("NSFilenamesPboardType")
        pb.declareTypes([legacy, .string], owner: nil)
        expect(pb.setPropertyList(["/tmp/clipboard-test-no-file-read"], forType: legacy))
        expect(pb.setString("filename", forType: .string))
        let before = pb.changeCount
        expectThrows(try SystemClipboard(pb).snapshot(expected: before))
        expectEqual(pb.changeCount, before)
    }

    func testSizeLimitLeavesClipboardUntouched() throws {
        try seed(richValues)
        let before = pb.changeCount
        expectThrows(try SystemClipboard(pb, maximumBytes: 2).snapshot(expected: before))
        expectEqual(pb.changeCount, before)
    }

    func testNewOwnerPreventsStaleWrite() throws {
        try seed(richValues)
        let board = SystemClipboard(pb)
        let snapshot = try board.snapshot(expected: board.changeCount)
        try seed([(.string, Data("new copy".utf8))])
        let before = board.changeCount
        expectThrows(try board.write(snapshot, mode: .preserve))
        expectEqual(board.changeCount, before)
        expectEqual(pb.string(forType: .string), "new copy")
    }

    func testPlainURLTextIsAllowedWhileURLObjectsAreProtected() throws {
        try seed([(.string, Data("https://example.com".utf8))])
        let board = SystemClipboard(pb)
        expectNoThrow(try board.snapshot(expected: board.changeCount))
    }

    func testEmptyTextIsSkipped() throws {
        try seed([(.string, Data())])
        expectThrows(try SystemClipboard(pb).snapshot(expected: pb.changeCount))
    }
}
