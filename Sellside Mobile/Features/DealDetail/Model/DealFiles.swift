//
//  DealFiles.swift
//  Sellside Mobile
//

import Foundation

/// One file on a deal's Files tab. Mirrors the rows of the web's
/// `DealFilesComponent` (deal-details-modal/files/deal-files.component.ts) —
/// teaser, NDA, signed NDA, summary materials, then message attachments —
/// seen from the seller's side: what has been shared with this buyer.
struct DealFile: Identifiable, Equatable {
    /// `TLegacyDocumentType` plus the attachment rows. Raw values order the
    /// tab the way the web orders its rows.
    enum Kind: Int, Comparable {
        case teaser, nda, signedNda, cim, attachment, other

        static func < (lhs: Kind, rhs: Kind) -> Bool { lhs.rawValue < rhs.rawValue }

        /// The web's `type` column.
        var label: String {
            switch self {
            case .teaser: "Teaser"
            case .nda: "NDA"
            case .signedNda: "Signed NDA"
            case .cim: "CIM"
            case .attachment: "Attachment"
            case .other: "File"
            }
        }

        var systemImage: String {
            switch self {
            case .teaser: "doc.richtext"
            case .nda: "doc.text"
            case .signedNda: "signature"
            case .cim: "doc.text.magnifyingglass"
            case .attachment: "paperclip"
            case .other: "doc"
            }
        }
    }

    /// Where the bytes come from.
    enum Source: Equatable {
        /// `GET /documents/deal/{dealId}/{documentId}` — `downloadDealDocument`.
        case dealDocument(id: String)
        /// `GET /messaging/attachments/{id}` hands back a signed URL —
        /// `getAttachmentUrl`.
        case attachment(id: String)
        /// A linked CIM (`cim_type: "linked"`), opened in the browser.
        case link(URL)
    }

    let id: String
    let kind: Kind
    let filename: String
    let date: Date?
    let source: Source

    /// "PDF", from the filename — the web's `getFileExtensionName`.
    var format: String? {
        let ext = (filename as NSString).pathExtension
        return ext.isEmpty || ext.count > 5 ? nil : ext.uppercased()
    }
}

extension DealFile {
    /// Every file on the deal, in the web's order: documents by kind, then
    /// attachments newest first (the web reverses the thread's digest).
    ///
    /// - documents: the deal's `documents` (`IDealData.documents`), from the
    ///   sidebar payload and `GET /documents/deal/{id}` — merged by id.
    /// - signedNda: `signed_nda`, which survives the deal moving on even when
    ///   the document list doesn't carry it (`Deal.embeddedSignedNda`).
    /// - linkedCim: the project's CIM link when `cim_type` is `linked`.
    /// - messages: attachments that aren't inline images in a message body.
    static func files(documents: [JSONValue], signedNda: JSONValue?, linkedCim: URL?,
                      messages: [DealMessage]) -> [DealFile] {
        var seen = Set<String>()
        var files: [DealFile] = []

        for document in documents {
            guard let id = document["id"]?.string ?? document["public_id"]?.string,
                  document["is_deleted"]?.bool != true,
                  seen.insert(id).inserted else { continue }
            let kind: Kind = switch document["type"]?.string {
            case "T": .teaser
            case "NDA": .nda
            case "SIGNED": .signedNda
            case "OM": .cim
            default: .other
            }
            files.append(DealFile(
                id: id, kind: kind,
                filename: document["filename"]?.text ?? kind.label,
                date: document["updated_at"]?.date ?? document["created_at"]?.date,
                source: .dealDocument(id: id)
            ))
        }

        if !files.contains(where: { $0.kind == .signedNda }),
           let signed = signedNda, let id = signed["id"]?.string ?? signed["public_id"]?.string,
           seen.insert(id).inserted {
            files.append(DealFile(
                id: id, kind: .signedNda,
                filename: signed["filename"]?.text ?? "Signed NDA",
                date: signed["updated_at"]?.date ?? signed["created_at"]?.date,
                source: .dealDocument(id: id)
            ))
        }

        if let linkedCim, !files.contains(where: { $0.kind == .cim }) {
            files.append(DealFile(id: "linked-cim", kind: .cim,
                                  filename: linkedCim.host() ?? linkedCim.absoluteString,
                                  date: nil, source: .link(linkedCim)))
        }

        files.sort { $0.kind < $1.kind }

        let attachments = messages.sorted { $0.sentAt > $1.sentAt }.flatMap { message in
            message.attachments.filter { !$0.isInline }.map { attachment in
                DealFile(id: "a.\(attachment.id)", kind: .attachment, filename: attachment.filename,
                         date: message.sentAt, source: .attachment(id: attachment.id))
            }
        }
        for attachment in attachments where seen.insert(attachment.id).inserted {
            files.append(attachment)
        }
        return files
    }
}

// MARK: - Previewing

/// A downloaded file, written somewhere QuickLook can open it for as long as
/// it's on screen, then deleted.
///
/// The app otherwise keeps deal data in memory only; this is the one place
/// bytes touch the disk, because the system previewer needs a file. They go
/// to a temporary folder with full file protection, are removed when the
/// preview closes, and anything left behind (a crash mid-preview) is cleared
/// on the next launch.
enum DealFilePreview {
    static var folder: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("DealFiles", isDirectory: true)
    }

    static func write(_ file: DownloadedFile, suggestedName: String) throws -> URL {
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(safeName(file.filename ?? suggestedName))
        try file.data.write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }

    /// Removes one preview's file and its folder.
    static func discard(_ url: URL) {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    /// Clears anything a previous run left behind.
    static func purge() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A filename the file system accepts, keeping the extension QuickLook
    /// needs to pick a viewer.
    static func safeName(_ name: String) -> String {
        let cleaned = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "File" : cleaned
    }
}
