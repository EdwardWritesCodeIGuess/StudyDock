import Foundation
import PDFKit
import Vision
import UniformTypeIdentifiers
import StudyDockCore

enum AttachmentImporter {
    static func importFile(_ url: URL, into directory: URL) async throws -> Attachment {
        try await Task.detached(priority: .userInitiated) {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true else { throw StudyError.message("Choose a file rather than a folder.") }
            guard (values.fileSize ?? 0) <= 50 * 1024 * 1024 else { throw StudyError.message("\(url.lastPathComponent) is over 50 MB. Choose a smaller file.") }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let storedName = UUID().uuidString + (url.pathExtension.isEmpty ? "" : ".\(url.pathExtension)")
            let copy = directory.appendingPathComponent(storedName)
            try FileManager.default.copyItem(at: url, to: copy)
            var text = ""
            var note: String?
            let type = UTType(filenameExtension: url.pathExtension)
            if type?.conforms(to: .pdf) == true {
                if let document = PDFDocument(url: copy), !document.isLocked {
                    text = (0..<min(document.pageCount, 50)).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).count < 30 {
                        var recognized: [String] = []
                        for index in 0..<min(document.pageCount, 12) {
                            guard let page = document.page(at: index), let cg = rasterize(page) else { continue }
                            recognized.append(recognize(cg))
                        }
                        text = recognized.joined(separator: "\n")
                        note = "Scanned PDF: text recognized from up to 12 pages. Check the original for accuracy."
                    } else if document.pageCount > 50 { note = "Brief uses the first 50 pages. The complete PDF is attached." }
                } else { note = "This PDF is locked or unreadable. Unlock it or add instructions in your notes." }
            } else if type?.conforms(to: .image) == true {
                if let source = CGImageSourceCreateWithURL(copy as CFURL, nil), let cg = CGImageSourceCreateImageAtIndex(source, 0, nil) { text = recognize(cg) }
                note = "Text recognized on this device. Check the original for accuracy."
            } else if type?.conforms(to: .text) == true || ["md", "txt", "csv"].contains(url.pathExtension.lowercased()) {
                text = (try? String(contentsOf: copy, encoding: .utf8)) ?? ""
            } else { note = "File attached. Add key instructions in your notes to include them in the brief." }
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                note = note ?? "No readable text found. Add the instructions in your notes."
            }
            return Attachment(name: url.lastPathComponent, storedName: storedName, text: String(text.prefix(100_000)), note: note)
        }.value
    }
    private static func recognize(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
    private static func rasterize(_ page: PDFPage) -> CGImage? {
        let rect = page.bounds(for: .mediaBox)
        guard rect.width > 0, rect.height > 0 else { return nil }
        let scale = min(2, 1800 / max(rect.width, rect.height))
        guard let context = CGContext(data: nil, width: Int(rect.width * scale), height: Int(rect.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: context.width, height: context.height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -rect.minX, y: -rect.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }
}
