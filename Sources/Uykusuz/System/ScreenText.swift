import AppKit
import ScreenCaptureKit
import Vision

/// The permission a picture of the screen needs. macOS asks once; after that
/// only System Settings can give it.
@MainActor
final class ScreenPermission {
    private var asked = false

    var isGranted: Bool { CGPreflightScreenCaptureAccess() }

    func ask() {
        guard asked else {
            asked = true
            _ = CGRequestScreenCaptureAccess()
            return
        }
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum ScreenTextError: LocalizedError {
    case noDisplay

    var errorDescription: String? { "the display under the area was not found" }
}

/// What is written in a part of the screen. The picture comes from
/// ScreenCaptureKit without this app's own windows, Apple's Vision reads it on
/// this Mac, and it stays in memory until then: nothing is written or sent.
enum ScreenText {
    /// `area`, once what covered it is out of the way: the dim has to be gone
    /// and the app that was in front back.
    static func read(_ area: AreaPicker.Area) async throws -> String {
        try await Task.sleep(for: .milliseconds(150))
        return try await read(capture(area))
    }

    private static func capture(_ area: AreaPicker.Area) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        guard let display = content.displays.first(where: { $0.displayID == area.display }) ?? content.displays.first else {
            throw ScreenTextError.noDisplay
        }
        let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let configuration = SCStreamConfiguration()
        configuration.sourceRect = area.rect
        configuration.width = Int(area.rect.width * area.scale)
        configuration.height = Int(area.rect.height * area.scale)
        configuration.showsCursor = false
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }

    /// What the picture says, ready to read: the document request sorts out
    /// columns, lists and table cells, each becoming a line of its own.
    static func read(_ image: CGImage) async throws -> String {
        var request = RecognizeDocumentsRequest()
        request.textRecognitionOptions.useLanguageCorrection = true
        request.textRecognitionOptions.recognitionLanguages = [Locale.Language(identifier: "tr-TR"), Locale.Language(identifier: "en-US")]
        guard let document = try await request.perform(on: image).first?.document else { return "" }
        return speech(document.paragraphs.map { paragraph in
            paragraph.lines.compactMap { line in
                let top = 1 - (line.boundingBox.origin.y + line.boundingBox.height)
                guard !isCut(top: top, bottom: line.boundingBox.origin.y, confidence: line.confidence) else { return nil }
                return line.topCandidates(1).first?.string
            }
        })
    }

    /// A line the area's edge runs through reads as noise: it touches the top
    /// or the bottom of the picture and Vision itself is unsure of it. Either
    /// alone proves nothing, a tightly drawn area touches whole lines.
    static func isCut(top: CGFloat, bottom: CGFloat, confidence: Float) -> Bool {
        min(top, bottom) < 0.01 && confidence < 0.9
    }

    /// Paragraphs given as their lines, as one text to read aloud, a paragraph
    /// to a line: a line ends where the screen ran out, and a word it cut in
    /// two is one word again. From here on it is what `ClaudeReplySpeech`
    /// makes of any text: addresses and paths are not spelled out.
    static func speech(_ paragraphs: [[String]]) -> String {
        let joined = paragraphs.map { lines in
            var text = ""
            for line in lines.map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
                if text.isEmpty {
                    text = line
                } else if text.hasSuffix("-"), line.first?.isLowercase == true {
                    text.removeLast()
                    text += line
                } else {
                    text += " " + line
                }
            }
            return text.first == "•" ? "- " + text.dropFirst().trimmingCharacters(in: .whitespaces) : text
        }
        return ClaudeReplySpeech.plain(joined.joined(separator: "\n\n"))
    }
}
