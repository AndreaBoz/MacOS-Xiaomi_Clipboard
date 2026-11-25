// A small test runner so Command Line Tools suffice; XCTest requires full Xcode
// on some installations. Assertions report actual failures and return exit 1.
import Foundation

var failures = 0
var passed = 0
var skipped = 0

class TestCase {
    func setUpWithError() throws {}
    func tearDown() {}
}
struct TestUnavailable: Error {
    let message: String
    init(_ message: String) { self.message = message }
}
func expect(_ value: @autoclosure () -> Bool, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    if !value() { failures += 1; print("FAIL \(file):\(line) \(message)") }
}
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    expect(actual == expected, "\(message) actual=\(actual) expected=\(expected)", file: file, line: line)
}
func expectGreater<T: Comparable>(_ actual: T, _ expected: T, file: StaticString = #filePath, line: UInt = #line) {
    expect(actual > expected, "Expected \(actual) > \(expected)", file: file, line: line)
}
func expectThrows<T>(_ expression: @autoclosure () throws -> T, _ message: String = "", file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression(); expect(false, "Expected error: \(message)", file: file, line: line) }
    catch {}
}
func expectNoThrow<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #filePath, line: UInt = #line) {
    do { _ = try expression() }
    catch { expect(false, "Unexpected error: \(error)", file: file, line: line) }
}
func run(_ name: String, _ test: TestCase, _ body: () throws -> Void) {
    let before = failures
    defer { test.tearDown() }
    do {
        try test.setUpWithError()
        try body()
        if failures == before { passed += 1; print("PASS \(name)") }
    } catch let unavailable as TestUnavailable {
        skipped += 1; print("UNAVAILABLE \(name): \(unavailable.message)")
    } catch {
        failures += 1; print("FAIL \(name): \(error)")
    }
}

let monitor = MonitorTests()
run("startup, stability, self-write", monitor, monitor.testStartupStableDelayAndOwnWriteAreIgnored)
run("rapid copies", monitor, monitor.testRapidCopiesOnlyRewriteTheLatest)
run("echo suppression and recopy", monitor, monitor.testEchoIsSuppressedButLaterRecopyWorks)
run("read race", monitor, monitor.testReadRaceDoesNotWriteAndNextCopyCanProceed)
run("unavailable data", monitor, monitor.testUnavailableDataIsNotRetriedForever)
run("write failure stops monitoring", monitor, monitor.testWriteFailureHaltsMonitor)
run("rate limit and recovery", monitor, monitor.testRateLimitAndRecovery)

let native = PasteboardTests()
run("native preserve bytes and ownership", native, native.testPreserveRetainsEveryByteAndAnnouncesNewOwnership)
run("native replay order and bytes", native, native.testReplayRetainsOrderAndBytes)
run("native inplace changeCount", native, native.testInplaceKeepsRichTextButDoesNotAdvanceChangeCount)
run("native plain fallback", native, native.testPlainExplicitlyDiscardsFormatting)
run("native Chromium selection monitor", native, native.testChromiumSelectionIsNormalizedByMonitor)
run("native Chromium preserve metadata", native, native.testChromiumMetadataIsRetainedInPreserveMode)
run("native Chromium protected formats", native, native.testChromiumMetadataDoesNotOverrideProtectedFormats)
run("native protected content", native, native.testProtectedContentIsNeverChanged)
run("native multiple items", native, native.testMultipleItemsAreSkipped)
run("native legacy file list", native, native.testLegacyFileListIsProtected)
run("native size limit", native, native.testSizeLimitLeavesClipboardUntouched)
run("native stale write", native, native.testNewOwnerPreventsStaleWrite)
run("native text URL", native, native.testPlainURLTextIsAllowedWhileURLObjectsAreProtected)
run("native empty text", native, native.testEmptyTextIsSkipped)
print("\(passed) passed; \(failures) failures; \(skipped) unavailable")
exit(failures == 0 && skipped == 0 ? 0 : 1)
