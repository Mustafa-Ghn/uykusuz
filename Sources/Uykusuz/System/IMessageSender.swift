import Foundation

/// Sends one text message to the user's phone.
protocol MessageSending: Sendable {
    func send(_ text: String, to handle: String) async throws
}

struct MessageSendError: LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }
}

/// Through the Messages app on this Mac, as an iMessage (fork addition).
/// Messages' own AppleScript `send`; no keystrokes, no Accessibility
/// permission. The text and the handle are passed as `argv`, never pasted
/// into the script, so nothing in them is read as AppleScript. The first
/// send makes macOS ask once whether Uykusuz may control Messages.
struct IMessageSender: MessageSending {
    static let osascript = "/usr/bin/osascript"
    static let script = [
        "on run argv",
        "tell application \"Messages\"",
        "set theService to 1st account whose service type = iMessage",
        "send (item 1 of argv) to participant (item 2 of argv) of theService",
        "end tell",
        "end run",
    ]

    static func arguments(text: String, handle: String) -> [String] {
        script.flatMap { ["-e", $0] } + [text, handle]
    }

    var timeout: TimeInterval = 30

    func send(_ text: String, to handle: String) async throws {
        let result = try await Shell.run(Self.osascript, Self.arguments(text: text, handle: handle), timeout: timeout)
        guard result.succeeded else {
            throw MessageSendError(message: Self.explain(result.stderr))
        }
    }

    /// What the Settings line says for an osascript failure.
    static func explain(_ stderr: String) -> String {
        let text = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.contains("-1743") {
            return "Uykusuz'un Mesajlar'ı denetleme izni yok: Sistem Ayarları > Gizlilik ve Güvenlik > Otomasyon'da Uykusuz için Mesajlar'ı açın"
        }
        if text.contains("-1728") || text.contains("-1719") {
            return "Mesajlar'da iMessage hesabı ya da bu alıcı bulunamadı"
        }
        return text.isEmpty ? "Mesajlar mesajı gönderemedi" : "Mesajlar mesajı gönderemedi: \(text)"
    }
}
