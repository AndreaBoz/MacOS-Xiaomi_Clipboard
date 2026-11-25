import AppKit
import CryptoKit
import Foundation
import UniformTypeIdentifiers

public enum Mode: String, CaseIterable {
    case preserve, replay, inplace, plain
}

public struct Representation {
    public let type: NSPasteboard.PasteboardType
    public let data: Data
    public init(_ type: NSPasteboard.PasteboardType, _ data: Data) {
        self.type = type
        self.data = data
    }
}

public struct Snapshot {
    public let generation: Int
    public let representations: [Representation]
    public let text: String
    public init(generation: Int, representations: [Representation], text: String) {
        self.generation = generation
        self.representations = representations
        self.text = text
    }
}

public enum ClipboardError: Error, CustomStringConvertible {
    case skipped(String), changed, writeFailed
    public var description: String {
        switch self {
        case .skipped(let reason): return "skipped: \(reason)"
        case .changed: return "skipped: clipboard changed during operation"
        case .writeFailed: return "write failed; monitoring stopped"
        }
    }
}

public enum Policy {
    // Unknown formats are deliberately excluded, even when a text flavor is present.
    // A text selection with embedded attachments must not become a text-only object.
    private static let legacyText: Set<String> = [
        "NSStringPboardType", "NSHTMLPboardType", "NSRTFPboardType",
        "Apple HTML pasteboard type", "NeXT Rich Text Format v1.0 pasteboard type",
        "NeXT tabular text pasteboard type",
        "CorePasteboardFlavorType 0x75743136",
        "NSTabularTextPboardType", "public.utf8-plain-text",
        "public.utf16-plain-text", "public.utf16-external-plain-text",
        "public.html", "public.rtf"
    ]
    private static let textMetadata: Set<String> = [
        "org.mozilla.source-url", "org.mozilla.context", "org.mozilla.info",
        // Chromium writes these provenance fields alongside ordinary selections.
        // source-url describes the source page; it is not a copied public.url object.
        // Only these exact metadata types are accepted, never the whole namespace.
        "org.chromium.source-url", "org.chromium.internal.source-rfh-token",
        "com.apple.NSStringEncoding"
    ]

    public static func allows(_ type: NSPasteboard.PasteboardType) -> Bool {
        let name = type.rawValue
        if legacyText.contains(name) || textMetadata.contains(name) { return true }
        guard let uti = UTType(name), !uti.isDynamic else { return false }
        // RTFD may include files; URLs are objects even if they have a text flavor.
        if uti.conforms(to: .url) || uti.conforms(to: .image) ||
            uti.conforms(to: .audiovisualContent) || uti.conforms(to: .fileURL) ||
            uti.conforms(to: .rtfd) || uti.conforms(to: .pdf) { return false }
        return uti.conforms(to: .text)
    }
}

public protocol ClipboardAccess: AnyObject {
    var changeCount: Int { get }
    func snapshot(expected: Int) throws -> Snapshot
    func write(_ snapshot: Snapshot, mode: Mode) throws -> Int
}

public final class SystemClipboard: ClipboardAccess {
    public let pasteboard: NSPasteboard
    public let maximumBytes: Int
    public var changeCount: Int { pasteboard.changeCount }

    public init(_ pasteboard: NSPasteboard, maximumBytes: Int = 8 * 1024 * 1024) {
        self.pasteboard = pasteboard
        self.maximumBytes = maximumBytes
    }

    public func snapshot(expected: Int) throws -> Snapshot {
        guard changeCount == expected else { throw ClipboardError.changed }
        // Check global types first, including privacy/remote/custom markers.
        let globalTypes = pasteboard.types ?? []
        guard !globalTypes.isEmpty, globalTypes.allSatisfy(Policy.allows) else {
            throw ClipboardError.skipped("protected or unknown format")
        }
        guard let items = pasteboard.pasteboardItems, items.count == 1 else {
            throw ClipboardError.skipped("empty or multiple items")
        }
        let item = items[0]
        guard item.types.allSatisfy(Policy.allows), item.types.contains(.string) else {
            throw ClipboardError.skipped("protected format or missing UTF-8 text")
        }
        var representations: [Representation] = []
        var total = 0
        for type in item.types {
            // Materialize lazy data before clearing: if even one flavor is missing,
            // abandon the operation without modifying the clipboard.
            guard let data = item.data(forType: type) else {
                throw ClipboardError.skipped("unavailable representation")
            }
            guard data.count <= maximumBytes - total else {
                throw ClipboardError.skipped("content exceeds size limit")
            }
            total += data.count
            representations.append(Representation(type, data))
            guard changeCount == expected else { throw ClipboardError.changed }
        }
        guard let text = item.string(forType: .string), !text.isEmpty else {
            throw ClipboardError.skipped("empty or unreadable text")
        }
        guard changeCount == expected else { throw ClipboardError.changed }
        return Snapshot(generation: expected, representations: representations, text: text)
    }

    private func makeItem(_ snapshot: Snapshot, mode: Mode) throws -> NSPasteboardItem {
        let item = NSPasteboardItem()
        if mode == .plain {
            guard item.setString(snapshot.text, forType: .string) else { throw ClipboardError.writeFailed }
        } else {
            let original = snapshot.representations
            let ordered = mode == .preserve
                ? original.filter { $0.type == .string } + original.filter { $0.type != .string }
                : original
            for representation in ordered {
                guard item.setData(representation.data, forType: representation.type) else {
                    throw ClipboardError.writeFailed
                }
            }
        }
        return item
    }

    public func write(_ snapshot: Snapshot, mode: Mode) throws -> Int {
        // Prepare both output and recovery before touching the shared pasteboard.
        let output = try makeItem(snapshot, mode: mode)
        let recovery = try makeItem(snapshot, mode: .replay)
        guard changeCount == snapshot.generation else { throw ClipboardError.changed }
        if mode == .inplace {
            guard pasteboard.setString(snapshot.text, forType: .string) else {
                throw ClipboardError.writeFailed
            }
            // This operation does not acquire ownership. Never absorb a newer count.
            return snapshot.generation
        }
        let ownedGeneration = pasteboard.clearContents()
        guard changeCount == ownedGeneration else { throw ClipboardError.changed }
        guard pasteboard.writeObjects([output]) else {
            // Best effort only: never restore over a newer owner's clipboard.
            if changeCount == ownedGeneration {
                _ = pasteboard.clearContents()
                _ = pasteboard.writeObjects([recovery])
            }
            throw ClipboardError.writeFailed
        }
        // writeObjects adds items without changing ownership; return our known
        // generation, not a potentially newer count belonging to another app.
        return ownedGeneration
    }
}

public final class Monitor {
    private let clipboard: ClipboardAccess
    private let mode: Mode
    private var observed: Int
    private var pending: Int?
    private var pendingSince: TimeInterval = 0
    private var recent: [(digest: Data, time: TimeInterval)] = []
    private var writes: [TimeInterval] = []
    private var pauseUntil: TimeInterval = 0
    public private(set) var halted = false
    public var report: (String) -> Void = { _ in }

    public init(clipboard: ClipboardAccess, mode: Mode) {
        self.clipboard = clipboard
        self.mode = mode
        self.observed = clipboard.changeCount // Do not rewrite pre-existing data at startup.
    }

    public func tick(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        guard !halted else { return }
        let current = clipboard.changeCount
        if current != observed {
            observed = current
            pending = current
            pendingSince = now
            return
        }
        // Require one stable polling interval; intermediate copies are discarded.
        guard let expected = pending, now - pendingSince >= 0.1 else { return }
        pending = nil
        guard now >= pauseUntil else { report("skipped: feedback cooldown"); return }
        do {
            let snapshot = try clipboard.snapshot(expected: expected)
            recent.removeAll { now - $0.time >= 3 }
            let digest = Data(SHA256.hash(data: Data(snapshot.text.utf8)))
            guard !recent.contains(where: { $0.digest == digest }) else {
                report("skipped: recent text echo")
                return
            }
            writes.removeAll { now - $0 >= 10 }
            guard writes.count < 8 else {
                pauseUntil = now + 30
                report("skipped: feedback rate limit; paused for 30 seconds")
                return
            }
            observed = try clipboard.write(snapshot, mode: mode)
            recent.append((digest, now))
            writes.append(now)
            report("rewritten: \(mode.rawValue)")
        } catch ClipboardError.writeFailed {
            halted = true // A service restart must not repeatedly damage the same copy.
            report(ClipboardError.writeFailed.description)
        } catch {
            report(String(describing: error))
        }
    }
}
