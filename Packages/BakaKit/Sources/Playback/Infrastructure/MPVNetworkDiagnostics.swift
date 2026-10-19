import Foundation

/// Only allowlisted categories and host names leave the IPC decoder.
struct MPVNetworkDiagnostics {
    private(set) var lines: [String] = []

    mutating func receive(_ message: MPVMessage) {
        guard message.event == "log-message", let text = message.text else { return }
        let lower = text.lowercased()
        var note: String?
        if lower.contains("timed out") || lower.contains("timeout") { note = "Network timeout" }
        else if lower.contains("tls"), lower.contains("fail") || lower.contains("error") || lower.contains("terminated") {
            note = "TLS negotiation or read failed"
        } else if lower.contains("http error") { note = "HTTP request rejected" }
        else if lower.contains("subtitle"), lower.contains("support") { note = "HLS subtitle handling warning" }
        else if lower.contains("failed to open segment") { note = "Segment open failed" }
        else if lower.contains("failed to open") { note = "Media open failed" }
        else if lower.contains("opening"), let range = text.range(of: #"https?://[^\s'"\]]+"#, options: .regularExpression),
                let url = URL(string: String(text[range])), let host = url.host {
            let kind = url.path.lowercased().contains("/subtitles/") ? "subtitle"
                : (url.pathExtension.lowercased() == "m3u8" ? "playlist" : "media")
            note = "Opening \(kind) · \(host)"
        } else if lower.contains("connection attempt"), lower.contains("success") { note = "TCP connected" }
        if let note, lines.last != note {
            lines.append(note)
            if lines.count > 24 { lines.removeFirst() }
        }
    }
}
