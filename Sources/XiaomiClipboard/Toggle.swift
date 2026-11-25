import AppKit
import Foundation

private let serviceLabel = "it.andrea.xiaomi-clipboard"

func agentDefinition(executable: String, mode: String, interval: String) -> [String: Any] {
    [
        "Label": serviceLabel,
        "ProgramArguments": [executable, "run", "--mode", mode, "--interval", interval, "--kde-only"],
        "RunAtLoad": true,
        "KeepAlive": ["SuccessfulExit": false],
        "ThrottleInterval": 10,
        "LimitLoadToSessionType": "Aqua",
        "ProcessType": "Background"
    ]
}

private func launchctl(_ arguments: [String]) throws -> (status: Int32, output: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return (process.terminationStatus, String(decoding: data, as: UTF8.self))
}

private struct ToggleError: LocalizedError {
    let errorDescription: String?
    init(_ description: String) { errorDescription = description }
}

private func requireLaunchctl(_ arguments: [String]) throws {
    let result = try launchctl(arguments)
    guard result.status == 0 else { throw ToggleError(result.output) }
}

func screenshots(_ mode: String) throws {
    guard let resources = Bundle.main.resourceURL else { throw ToggleError("Risorse dell’app mancanti.") }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
    process.arguments = [resources.appendingPathComponent("setup-native-screenshots.py").path, mode]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe
    try process.run()
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw ToggleError("Configurazione screenshot non riuscita: " + String(decoding: data, as: UTF8.self))
    }
}

private func showStatus(_ title: String, _ message: String, error: Bool = false) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.alertStyle = error ? .warning : .informational
    alert.addButton(withTitle: "OK")
    NSApp.activate(ignoringOtherApps: true)
    alert.runModal()
}

/// The clickable app creates only a session job, not a login LaunchAgent file.
/// launchd owns the worker, so it survives the controller closing.
func toggleStudySession() -> Never {
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.accessory)
    let domain = "gui/\(getuid())"
    let service = "\(domain)/\(serviceLabel)"
    do {
        let loaded = try launchctl(["print", service]).status == 0
        if loaded {
            try screenshots("off")
            try requireLaunchctl(["bootout", service])
            showStatus("Sincronizzazione disattivata", "Appunti e invio screenshot disattivati. I nuovi screenshot vengono salvati sulla Scrivania.\n\nRiapri Xiaomi Clipboard quando inizi a studiare.")
        } else {
            guard let executable = Bundle.main.executableURL else {
                throw ToggleError("Eseguibile dell’app non trovato.")
            }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: directory) }
            let plistURL = directory.appendingPathComponent(serviceLabel + ".plist")
            let data = try PropertyListSerialization.data(
                fromPropertyList: agentDefinition(executable: executable.path, mode: "plain", interval: "0.4"),
                format: .xml, options: 0)
            try data.write(to: plistURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL.path)
            try requireLaunchctl(["enable", service])
            try requireLaunchctl(["bootstrap", domain, plistURL.path])
            var running = false
            for _ in 0..<20 {
                let status = try launchctl(["print", service])
                if status.status == 0 && status.output.contains("state = running") { running = true; break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            guard running else {
                _ = try? launchctl(["bootout", service])
                throw ToggleError("Il servizio non è partito. Chiudi il vecchio script Swift o eventuali istanze avviate dal Terminale, poi riprova.")
            }
            do { try screenshots("on") } catch {
                try? screenshots("off")
                _ = try? launchctl(["bootout", service])
                throw error
            }
            showStatus("Sincronizzazione attivata", "Appunti e screenshot attivi. Usa ⌘⇧4 per inviare uno screenshot alla Galleria del tablet. KDE Connect viene aperto sul Mac; lascialo attivo sul tablet. Puoi chiudere questa finestra.\n\nRiapri Xiaomi Clipboard per disattivarlo. KDE Connect gestisce gli appunti direttamente, senza rimuovere la formattazione sul Mac.\n\nNon si riattiva automaticamente al prossimo accesso al Mac.")
        }
        exit(0)
    } catch {
        showStatus("Impossibile cambiare lo stato", error.localizedDescription, error: true)
        exit(1)
    }
}
