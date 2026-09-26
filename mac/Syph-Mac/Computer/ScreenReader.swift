import AppKit
import ScreenCaptureKit
import Vision

/// Captures the main display and reads it with on-device OCR. Coordinates are
/// global screen points with a top-left origin — the same space `InputSynth`
/// clicks in, so an employee can read, then click what it read.
enum ScreenReader {
    struct Line {
        let text: String
        let frame: CGRect
        let confidence: Float
    }

    struct Reading {
        let lines: [Line]
        let size: CGSize
        let thumbnailBase64: String?
    }

    enum Failure: LocalizedError {
        case permission, noDisplay
        var errorDescription: String? {
            switch self {
            case .permission: return "Screen Recording permission is off for Syph. Turn it on in System Settings → Privacy & Security."
            case .noDisplay: return "No display is available to read."
            }
        }
    }

    static func capture() async throws -> (CGImage, CGSize) {
        guard CGPreflightScreenCaptureAccess() else { throw Failure.permission }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        let mainID = CGMainDisplayID()
        guard let display = content.displays.first(where: { $0.displayID == mainID }) ?? content.displays.first else {
            throw Failure.noDisplay
        }
        // Leave Syph's own overlay and panels out of what the employee sees.
        let ownBundle = Bundle.main.bundleIdentifier
        let own = content.applications.filter { $0.bundleIdentifier == ownBundle }
        let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
        let config = SCStreamConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        return (image, CGSize(width: display.width, height: display.height))
    }

    static func read(includeThumbnail: Bool = true) async throws -> Reading {
        let (image, size) = try await capture()
        let lines = try await recognize(image, pointSize: size)
        let thumb = includeThumbnail ? thumbnail(image, maxSide: 1280) : nil
        return Reading(lines: lines, size: size, thumbnailBase64: thumb)
    }

    static func recognize(_ image: CGImage, pointSize: CGSize) async throws -> [Line] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let lines: [Line] = observations.compactMap { observation in
                    guard let best = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    let frame = CGRect(
                        x: box.minX * pointSize.width,
                        y: (1 - box.maxY) * pointSize.height,
                        width: box.width * pointSize.width,
                        height: box.height * pointSize.height
                    )
                    return Line(text: best.string, frame: frame, confidence: best.confidence)
                }
                // Reading order: top to bottom, then left to right within a row.
                let sorted = lines.sorted { a, b in
                    abs(a.frame.midY - b.frame.midY) < 6 ? a.frame.minX < b.frame.minX : a.frame.midY < b.frame.midY
                }
                continuation.resume(returning: sorted)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Finds on-screen text matching `query` and returns the best frame to click.
    static func locate(_ query: String, in lines: [Line]) -> Line? {
        let needle = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        if let exact = lines.first(where: { $0.text.lowercased().trimmingCharacters(in: .whitespaces) == needle }) {
            return exact
        }
        let matches = lines.filter { $0.text.lowercased().contains(needle) }
        // Prefer the tightest match: a button label over a paragraph mentioning it.
        return matches.min { $0.text.count < $1.text.count }
    }

    /// Frame of `query` inside a matched line, approximated by character offset.
    static func focus(of query: String, in line: Line) -> CGPoint {
        let lower = line.text.lowercased()
        guard let range = lower.range(of: query.lowercased()), !line.text.isEmpty else {
            return CGPoint(x: line.frame.midX, y: line.frame.midY)
        }
        let start = CGFloat(lower.distance(from: lower.startIndex, to: range.lowerBound))
        let length = CGFloat(query.count)
        let perChar = line.frame.width / CGFloat(line.text.count)
        return CGPoint(x: line.frame.minX + (start + length / 2) * perChar, y: line.frame.midY)
    }

    static func thumbnail(_ image: CGImage, maxSide: CGFloat) -> String? {
        let width = CGFloat(image.width), height = CGFloat(image.height)
        let ratio = min(1, maxSide / max(width, height))
        let target = CGSize(width: Int(width * ratio), height: Int(height * ratio))
        guard let context = CGContext(data: nil, width: Int(target.width), height: Int(target.height),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(origin: .zero, size: target))
        guard let scaled = context.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: scaled)
        guard let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.55]) else { return nil }
        return data.base64EncodedString()
    }
}
