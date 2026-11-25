import AppKit
import ClipboardCore
import Darwin
import Foundation
import os

let label = "it.andrea.xiaomi-clipboard"
let logger = Logger(subsystem: label, category: "service")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func lockInstance() -> Int32 {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(label + ".lock").path
    let fd = open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { fail("Cannot open instance lock") }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
        close(fd)
        print("Another instance is active. Stop it before running this command.")
        exit(0)
    }
    // Keep the file in place: unlinking a flock file introduces an inode race.
    return fd
}

let arguments = Array(CommandLine.arguments.dropFirst())
let command = arguments.first ?? (Bundle.main.bundleURL.pathExtension == "app" ? "toggle" : "help")

if command == "toggle" { toggleStudySession() }

if command == "agent-plist" {
    guard arguments.count == 4, arguments[1].hasPrefix("/"),
          let mode = Mode(rawValue: arguments[2]), mode == .preserve || mode == .plain,
          let interval = Double(arguments[3]), interval.isFinite, (0.2...5).contains(interval) else {
        fail("Usage: agent-plist /absolute/executable preserve|plain interval")
    }
    let plist = agentDefinition(executable: arguments[1], mode: mode.rawValue, interval: arguments[3])
    do {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        FileHandle.standardOutput.write(data)
        exit(0)
    } catch { fail("Cannot encode LaunchAgent") }
}

if command == "help" || command == "--help" {
    print("""
    xiaomi-clipboard run [--mode preserve|plain] [--interval 0.4] [--verbose]
    xiaomi-clipboard once [--mode preserve|replay|inplace|plain]
    xiaomi-clipboard inspect

    Double-click Xiaomi Clipboard.app to toggle a background study session.
    preserve: republish original bytes, UTF-8 text first (experimental).
    replay:   republish original representations in their original order.
    inplace:  set the text without clearing (diagnostic only).
    plain:    remove rich text (default, confirmed with Xiaomi).
    inspect prints types and counters only, never clipboard content.
    """)
    exit(0)
}

guard ["run", "once", "inspect"].contains(command) else { fail("Unknown command. Use --help.") }
var mode = Mode.plain
var interval = 0.4
var verbose = false
var kdeOnly = false
var index = 1
while index < arguments.count {
    switch arguments[index] {
    case "--mode":
        index += 1
        guard index < arguments.count, let parsed = Mode(rawValue: arguments[index]) else { fail("Invalid mode") }
        mode = parsed
    case "--interval":
        index += 1
        guard index < arguments.count, let parsed = Double(arguments[index]),
              parsed.isFinite, (0.2...5).contains(parsed) else { fail("Interval must be between 0.2 and 5 seconds") }
        interval = parsed
    case "--verbose": verbose = true
    case "--kde-only": kdeOnly = true
    default: fail("Unknown option")
    }
    index += 1
}
if command == "run" && mode != .preserve && mode != .plain {
    fail("replay and inplace are diagnostic modes: use once")
}

if command == "inspect" {
    let pb = NSPasteboard.general
    let start = pb.changeCount
    let items = (pb.pasteboardItems ?? []).map { item in
        item.types.map { ["type": $0.rawValue, "allowed": Policy.allows($0)] as [String: Any] }
    }
    let globalTypes = (pb.types ?? []).map {
        ["type": $0.rawValue, "allowed": Policy.allows($0)] as [String: Any]
    }
    var result: [String: Any] = ["changeCount": start, "globalTypes": globalTypes,
                               "items": items, "stable": pb.changeCount == start]
    if #available(macOS 15.4, *) { result["accessBehavior"] = pb.accessBehavior.rawValue }
    if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
        FileHandle.standardOutput.write(data)
        print("")
    }
    exit(0)
}

let instanceLock = lockInstance()
let clipboard = SystemClipboard(.general)
if command == "once" {
    do {
        let before = clipboard.changeCount
        let snapshot = try clipboard.snapshot(expected: before)
        let own = try clipboard.write(snapshot, mode: mode)
        print("mode=\(mode.rawValue) before=\(before) owned=\(own) after=\(clipboard.changeCount)")
        exit(0)
    } catch { fail(String(describing: error)) }
}

let monitor = Monitor(clipboard: clipboard, mode: mode)
monitor.report = { message in
    if verbose { print(message); fflush(stdout) }
    if monitor.halted {
        logger.error("Clipboard write failed; service stopped. Restart manually after inspection.")
        exit(0) // KeepAlive SuccessfulExit=false prevents an automatic retry loop.
    }
}
logger.notice("Clipboard service started")
if verbose { print("Active: mode=\(mode.rawValue), interval=\(interval)s"); fflush(stdout) }
let timer = DispatchSource.makeTimerSource(queue: .main)
timer.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
timer.setEventHandler { if !kdeOnly { autoreleasepool { monitor.tick() } } }
timer.resume()

var signalSources: [DispatchSourceSignal] = []
for number in [SIGINT, SIGTERM] {
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler { try? screenshots("off"); close(instanceLock); exit(0) }
    source.resume()
    signalSources.append(source)
}
dispatchMain()
