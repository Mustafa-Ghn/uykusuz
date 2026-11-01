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
        openSettings()
    }

    /// Where a grant a new install has lost is given again: macOS asks nothing then.
    func openSettings() {
        // Puts the app on the list if it has never been there.
        _ = CGRequestScreenCaptureAccess()
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else { return }
        NSWorkspace.shared.open(url)
    }
}

enum ScreenTextError: LocalizedError {
    case noDisplay

    var errorDescription: String? { "the display under the area was not found" }
}

/// A word on the screen, folded for matching (`WordAligner.fold`), in global
/// points from the bottom left.
struct ScreenWord: Equatable, Sendable {
    var text: String
    var rect: CGRect
}

/// Looks at the screen as often as a reading needs to know where its words are.
/// Each look is one picture of a display, without this app's windows, and it is
/// gone as soon as its words are known.
actor ScreenLook {
    private struct Source: @unchecked Sendable {
        let filter: SCContentFilter
        let frame: CGRect
        let width: Int
        let height: Int
    }

    private var sources: [Source] = []

    /// The words on the display around `near`, or on every display without it.
    func words(near: CGPoint?) async throws -> [ScreenWord] {
        if sources.isEmpty { sources = try await Self.displays() }
        let chosen = near.flatMap { point in sources.first { $0.frame.contains(point) } }.map { [$0] } ?? sources
        var words: [ScreenWord] = []
        do {
            for source in chosen {
                let configuration = SCStreamConfiguration()
                configuration.width = source.width
                configuration.height = source.height
                configuration.showsCursor = false
                let image = try await SCScreenshotManager.captureImage(contentFilter: source.filter, configuration: configuration)
                words += try ScreenText.words(in: image, frame: source.frame)
            }
        } catch {
            // A display came or went: the next look asks again.
            sources = []
            throw error
        }
        return words
    }

    private static func displays() async throws -> [Source] {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let own = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        let primary = CGDisplayBounds(CGMainDisplayID()).height
        return content.displays.map { display in
            // SCDisplay counts from the top left, AppKit from the bottom left.
            let frame = CGRect(x: display.frame.minX, y: primary - display.frame.maxY, width: display.frame.width, height: display.frame.height)
            return Source(
                filter: SCContentFilter(display: display, excludingApplications: own, exceptingWindows: []),
                frame: frame,
                // Twice the points whatever the display: recognition misses more below that.
                width: display.width * 2,
                height: display.height * 2
            )
        }
    }
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

    /// The words in a picture of `frame`, top to bottom. Fast recognition has
    /// no Turkish, which folding makes up for (`WordAligner.fold`); its French
    /// keeps the ç that its English reads as G. It takes about a tenth of the
    /// work of accurate recognition, and on a real chat window every mark it
    /// placed was on the right word. That makes looking every few seconds cheap
    /// enough for a reading, which accuracy would not.
    static func words(in image: CGImage, frame: CGRect) throws -> [ScreenWord] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["fr-FR"]
        try VNImageRequestHandler(cgImage: image).perform([request])
        let lines = (request.results ?? []).sorted { a, b in
            let sameRow = abs(a.boundingBox.midY - b.boundingBox.midY) < min(a.boundingBox.height, b.boundingBox.height) * 0.5
            return sameRow ? a.boundingBox.minX < b.boundingBox.minX : a.boundingBox.midY > b.boundingBox.midY
        }
        var words: [ScreenWord] = []
        for line in lines {
            guard let candidate = line.topCandidates(1).first else { continue }
            let read = candidate.string
            // One character for one, so a place in `text` is the same place in `read`.
            let text = WordAligner.withLetterForMarks(read)
            text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { word, range, _, _ in
                guard let word else { return }
                let start = String.Index(utf16Offset: range.lowerBound.utf16Offset(in: text), in: read)
                let end = String.Index(utf16Offset: range.upperBound.utf16Offset(in: text), in: read)
                let box = (try? candidate.boundingBox(for: start..<end))?.boundingBox ?? line.boundingBox
                words.append(ScreenWord(text: WordAligner.fold(word), rect: place(box, in: frame)))
            }
        }
        return words
    }

    /// A box in a picture's own 0...1, from the bottom left, as global points.
    static func place(_ box: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + box.minX * frame.width,
            y: frame.minY + box.minY * frame.height,
            width: box.width * frame.width,
            height: box.height * frame.height
        )
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
