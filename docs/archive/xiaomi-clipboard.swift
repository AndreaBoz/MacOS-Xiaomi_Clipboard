
import AppKit
import Foundation

let clipboard = NSPasteboard.general
var lastChange = clipboard.changeCount

print("Sincronizzazione Xiaomi attiva")

while true {
    Thread.sleep(forTimeInterval: 0.4)

    let currentChange = clipboard.changeCount
    guard currentChange != lastChange else { continue }
    lastChange = currentChange

    // Non modificare immagini o file copiati
    let types = clipboard.types ?? []
    if types.contains(.tiff) ||
       types.contains(.png) ||
       types.contains(.fileURL) {
        continue
    }

    guard let text = clipboard.string(forType: .string) else {
        continue
    }

    // Riscrivi il contenuto come testo semplice
    clipboard.clearContents()
    if clipboard.setString(text, forType: .string) {
        lastChange = clipboard.changeCount
    }
}
