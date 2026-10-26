//
//  DocumentsForm.swift
//  Axial Mobile
//

import Foundation

/// File bytes held by reference, so comparing forms on every keystroke
/// compares identity rather than tens of megabytes.
final class FileBlob: Equatable {
    let data: Data
    init(_ data: Data) { self.data = data }
    static func == (lhs: FileBlob, rhs: FileBlob) -> Bool { lhs === rhs }
}

/// One document on the intent, saved or picked and not yet uploaded.
/// `Document` (document.model.ts). Buckets: `T` teaser, `NDA`, `OM`
/// (CIM / summary materials).
struct SetupDocument: Equatable, Identifiable {
    /// Local identity — saved documents get theirs from the server id.
    let localID: String
    var serverID: String?
    var bucket: String
    var filename: String
    var signatureType: String
    var isStandardNDA: Bool
    var fileSize: Int?

    var id: String { localID }
    var isSaved: Bool { serverID != nil }

    /// `isSignable`: the standard NDA, or one set up for e-signature.
    var isSignable: Bool { isStandardNDA || signatureType == "basic" || signatureType == "custom" }

    init?(json: JSONValue) {
        guard let id = json["id"]?.string ?? json["id"]?.int.map(String.init),
              let bucket = json["type"]?.string else { return nil }
        localID = id
        serverID = id
        self.bucket = bucket
        filename = json["filename"]?.string ?? "Document"
        signatureType = json["signature_type"]?.string ?? "download_only"
        isStandardNDA = json["is_standard_nda"]?.bool ?? false
        fileSize = json["filesize"]?.int
    }

    init(localID: String = UUID().uuidString, bucket: String, filename: String,
         signatureType: String = "download_only", isStandardNDA: Bool = false, fileSize: Int? = nil) {
        self.localID = localID
        self.bucket = bucket
        self.filename = filename
        self.signatureType = signatureType
        self.isStandardNDA = isStandardNDA
        self.fileSize = fileSize
    }
}

/// A queued upload. `file == nil` asks the backend for the standard NDA.
struct PendingUpload: Equatable {
    let localID: String
    let bucket: String
    let signatureType: String
    let filename: String
    let mimeType: String
    let file: FileBlob?
}

/// `DocumentsStore`, as part of the form value: documents by bucket, plus
/// the uploads and deletions the next save will carry out. Teaser and NDA
/// hold one document (an upload replaces); OM appends.
struct SetupDocuments: Equatable {
    var documents: [String: [SetupDocument]]
    var pendingUploads: [PendingUpload] = []
    var pendingDeletions: [SetupDocument] = []

    static let maxCIMFiles = 10

    init(intent: JSONValue) {
        let all = intent["documents"]?.array?.compactMap(SetupDocument.init(json:)) ?? []
        documents = Dictionary(grouping: all, by: \.bucket)
    }

    var teaser: SetupDocument? { documents["T"]?.first }
    var nda: SetupDocument? { documents["NDA"]?.first }
    var customNDA: SetupDocument? { nda.flatMap { $0.isStandardNDA ? nil : $0 } }
    var cimDocuments: [SetupDocument] { documents["OM"] ?? [] }
    var hasPendingOperations: Bool { !pendingUploads.isEmpty || !pendingDeletions.isEmpty }
    func hasPendingUpload(_ bucket: String) -> Bool { pendingUploads.contains { $0.bucket == bucket } }

    /// `uploadFile`.
    mutating func add(bucket: String, filename: String, mimeType: String, data: Data,
                      signatureType: String = "download_only") {
        let document = SetupDocument(bucket: bucket, filename: filename, signatureType: signatureType,
                                     fileSize: data.count)
        let upload = PendingUpload(localID: document.localID, bucket: bucket, signatureType: signatureType,
                                   filename: filename, mimeType: mimeType, file: FileBlob(data))
        if bucket == "OM" {
            documents["OM", default: []].append(document)
        } else {
            documents[bucket] = [document]
            pendingUploads.removeAll { $0.bucket == bucket }
        }
        pendingUploads.append(upload)
    }

    /// `queueStandardNda`.
    mutating func queueStandardNDA() {
        pendingUploads.removeAll { $0.bucket == "NDA" }
        let document = SetupDocument(bucket: "NDA", filename: "Axial Standard NDA", signatureType: "basic",
                                     isStandardNDA: true)
        documents["NDA"] = [document]
        pendingUploads.append(PendingUpload(localID: document.localID, bucket: "NDA", signatureType: "download_only",
                                            filename: "", mimeType: "", file: nil))
    }

    /// `deleteFile`: an unsaved document just vanishes; a saved one is
    /// queued for deletion.
    mutating func remove(_ document: SetupDocument) {
        documents[document.bucket]?.removeAll { $0.localID == document.localID }
        pendingUploads.removeAll { $0.localID == document.localID }
        if document.isSaved, !pendingDeletions.contains(where: { $0.localID == document.localID }) {
            pendingDeletions.append(document)
        }
    }

    mutating func removeAll(in bucket: String) {
        for document in documents[bucket] ?? [] { remove(document) }
    }

    mutating func clearPendingUploads(_ bucket: String) {
        pendingUploads.removeAll { $0.bucket == bucket }
    }

    /// After a save: drop only the operations that were sent, and record
    /// the ids the server gave the uploads.
    mutating func didSave(uploads: [PendingUpload], uploadedIDs: [String: String], deletions: [SetupDocument]) {
        let sentUploads = Set(uploads.map(\.localID))
        let sentDeletions = Set(deletions.map(\.localID))
        pendingUploads.removeAll { sentUploads.contains($0.localID) }
        pendingDeletions.removeAll { sentDeletions.contains($0.localID) }
        for (bucket, list) in documents {
            documents[bucket] = list.map { document in
                var document = document
                if let id = uploadedIDs[document.localID] { document.serverID = id }
                return document
            }
        }
    }

    /// `processDocumentOperations`: deletions in a single-document bucket
    /// are skipped when that bucket is also uploading — the upload replaces.
    var deletionsToSend: [SetupDocument] {
        pendingDeletions.filter { $0.bucket == "OM" || !hasPendingUpload($0.bucket) }
    }
}

// MARK: - NDA

/// `NdaType`: axial / custom / waive. A linked NDA is Custom with a URL.
struct NDAForm: Equatable {
    var ndaType: String?
    var linkedNdaUrl: String

    init(intent: JSONValue, documents: SetupDocuments) {
        let saved = intent["nda_type"]?.string
        let linked = intent["linked_nda"]?.text
        // `resolvedNdaType`.
        if saved == "linked", linked != nil { ndaType = "custom" }
        else if let nda = documents.nda { ndaType = nda.isStandardNDA ? "axial" : "custom" }
        else if saved == "waive" { ndaType = "waive" }
        else if saved == "custom" { ndaType = "custom" }
        else { ndaType = nil }
        linkedNdaUrl = linked ?? ""
    }

    func hasCustomNDA(_ documents: SetupDocuments) -> Bool {
        documents.customNDA != nil || documents.hasPendingUpload("NDA") || !linkedNdaUrl.isEmpty
    }

    /// `syncNdaSignableState`.
    func isSignable(_ documents: SetupDocuments) -> Bool {
        switch ndaType {
        case "axial": return true
        case "custom":
            if let upload = documents.pendingUploads.last(where: { $0.bucket == "NDA" }) {
                return upload.signatureType != "download_only"
            }
            return documents.nda?.isSignable ?? false
        default: return false
        }
    }

    /// `extractNdaFromForm`.
    func write(into intent: inout JSONValue) {
        intent.set(.string(orNull: linkedNdaUrl.isEmpty ? nil : linkedNdaUrl), at: "linked_nda")
        if ndaType == "custom", !linkedNdaUrl.isEmpty {
            intent.set("linked", at: "nda_type")
        } else if let ndaType {
            intent.set(.string(ndaType), at: "nda_type")
        } else {
            intent = intent.removingKeys(["nda_type"])
        }
    }

    enum Field {
        static let ndaType: SetupFieldKey = "nda.ndaType"
        static let linkedNdaUrl: SetupFieldKey = "nda.linkedNdaUrl"
    }

    func validate(documents: SetupDocuments, into v: inout StepValidationBuilder) {
        let missingCustom = ndaType == "custom" && !hasCustomNDA(documents)
        v.require(Field.ndaType, satisfied: ndaType != nil && !missingCustom, error: "")
        v.check(Field.linkedNdaUrl, error: URLRule.isValid(linkedNdaUrl) ? nil : "Invalid URL")
    }
}

// MARK: - CIM

struct CIMForm: Equatable {
    /// custom / waive. Linked is custom with a URL.
    var cimType: String?
    /// enabled / off.
    var smartshareState: String?
    var linkedCimUrl: String
    var ccMembers: [String]
    var message: String
    var calendarLink: String

    static let defaultMessage = "{recipient[first_name]},\n\nThank you for signing the NDA. The CIM is now available for your review.\n\nPlease share your feedback at your earliest convenience. Feel free to reach out anytime with questions or to discuss next steps."

    init(intent: JSONValue, documents: SetupDocuments) {
        let saved = intent["cim_type"]?.string
        let linked = intent["linked_cim"]?.text
        // `deriveInitialCimType`.
        if saved == "waive" { cimType = "waive" }
        else if saved == "custom" { cimType = "custom" }
        else if saved == "linked", linked != nil { cimType = "custom" }
        else if !documents.cimDocuments.isEmpty { cimType = "custom" }
        else { cimType = nil }

        if cimType == "waive" {
            smartshareState = nil
        } else {
            switch intent["use_cim_smartshare"]?.bool {
            case true?: smartshareState = "enabled"
            case false?: smartshareState = "off"
            default: smartshareState = nil
            }
        }
        linkedCimUrl = linked ?? ""
        let cim = intent["cim"]
        ccMembers = (cim?["cc_members"]?.strings ?? []) + (cim?["cc_emails"]?.strings ?? [])
        message = (cim?["message"]?.text ?? Self.defaultMessage).trimmingCharacters(in: .whitespacesAndNewlines)
        calendarLink = intent["calendar_link"]?.text ?? ""
    }

    func hasMaterials(_ documents: SetupDocuments) -> Bool {
        cimType != "waive" && (!documents.cimDocuments.isEmpty || !linkedCimUrl.isEmpty)
    }

    /// `extractCimFromForm`.
    func write(into intent: inout JSONValue) {
        intent.set(.string(orNull: linkedCimUrl.isEmpty ? nil : linkedCimUrl), at: "linked_cim")
        switch smartshareState {
        case "enabled": intent.set(true, at: "use_cim_smartshare")
        case "off": intent.set(false, at: "use_cim_smartshare")
        // The API 422s on null, so the key goes.
        default: intent = intent.removingKeys(["use_cim_smartshare"])
        }
        if cimType == "custom", !linkedCimUrl.isEmpty {
            intent.set("linked", at: "cim_type")
        } else if let cimType {
            intent.set(.string(cimType), at: "cim_type")
        } else {
            intent = intent.removingKeys(["cim_type"])
        }
        intent.set(.string(orNull: message.isEmpty ? nil : message), at: "cim.message")
        intent.set(.strings(ccMembers.filter(MemberID.isMemberID)), at: "cim.cc_members")
        intent.set(.string(orNull: calendarLink.isEmpty ? nil : calendarLink), at: "calendar_link")
    }

    enum Field {
        static let cimType: SetupFieldKey = "cim.cimType"
        static let smartshareState: SetupFieldKey = "cim.cimSmartshareState"
        static let linkedCimUrl: SetupFieldKey = "cim.linkedCimUrl"
        static let calendarLink: SetupFieldKey = "cim.cimCalendarLink"
        /// The group-level `cimValidator`.
        static let group: SetupFieldKey = "cim.group"
    }

    /// The banner `cimValidator` produces, if any.
    enum GroupIssue: Equatable {
        case requiresSignableNDA
        case requiresSharingMethod
        case other
    }

    /// `cimValidator`, exactly. Reads the NDA step's state, which is why it
    /// re-runs whenever the NDA changes.
    func groupIssue(nda: NDAForm, documents: SetupDocuments) -> GroupIssue? {
        let smartshare = smartshareState
        if smartshare == nil, cimType == nil { return .other }
        if smartshare == nil, cimType == "custom" { return .requiresSharingMethod }
        if smartshare == "enabled", let ndaType = nda.ndaType {
            if ndaType != "custom", ndaType != "axial" { return .requiresSignableNDA }
            if ndaType == "custom", !nda.isSignable(documents) { return .requiresSignableNDA }
        }
        if smartshare != nil, cimType != "custom" { return .other }
        return nil
    }

    func validate(nda: NDAForm, documents: SetupDocuments, into v: inout StepValidationBuilder) {
        v.require(Field.cimType, satisfied: cimType != nil, error: "")
        if cimType == "custom" {
            v.require(Field.smartshareState, satisfied: smartshareState != nil, error: "")
        }
        v.check(Field.linkedCimUrl, error: URLRule.isValid(linkedCimUrl) ? nil : "Invalid URL")
        v.check(Field.calendarLink, error: URLRule.isValid(calendarLink) ? nil : "Invalid URL")
        switch groupIssue(nda: nda, documents: documents) {
        case .requiresSignableNDA?:
            v.groupError(Field.group, "To use Automatic CIM Share, please select an electronically signable NDA.")
        case .requiresSharingMethod?:
            v.groupError(Field.group, "Please select a sharing method to continue.")
        case .other?:
            v.groupError(Field.group, "")
        case nil:
            break
        }
    }
}

/// `UUID_REGEX` — member public ids are 32 hex characters.
enum MemberID {
    static func isMemberID(_ value: String) -> Bool {
        value.range(of: "^[0-9a-f]{32}$", options: .regularExpression) != nil
    }
}

/// File limits and accepted types for each bucket.
enum DocumentRules {
    /// `MAX_CUSTOM_NDA_UPLOAD_SIZE_MEGABYTES`.
    static let ndaMaxMB = 40
    /// `MAX_CIM_FILE_SIZE_MB`, plus the silent 2 MB tolerance.
    static let cimMaxMB = 50
    static let cimToleranceMB = 2
    static let ndaExtensions = ["pdf", "doc", "docx"]
    static let cimExtensions = ["pdf", "docx", "pptx", "xlsx", "csv"]
    /// `DEAL_DOCUMENT_ACCEPTABLE_TYPES`, by extension.
    static let teaserExtensions = ["pdf", "doc", "docx", "docm", "dotx", "html", "htm", "odt", "ppsx", "ppt",
                                   "pptx", "rtf", "txt", "xls", "xlsx", "zip"]

    static func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "doc": "application/msword"
        case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "ppt": "application/vnd.ms-powerpoint"
        case "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "xls": "application/vnd.ms-excel"
        case "csv": "text/csv"
        case "txt": "text/plain"
        case "rtf": "application/rtf"
        case "zip": "application/zip"
        case "html", "htm": "text/html"
        default: "application/octet-stream"
        }
    }

    /// `confirm-delete-documents.ts`.
    static func deleteMessage(plural: Bool, isShared: Bool, signable: Bool, reason: String? = nil) -> String {
        let subject = plural ? "these documents" : "this document"
        let object = plural ? "them" : "it"
        var paragraphs: [String] = []
        if let reason { paragraphs.append(reason) }
        if isShared {
            if signable {
                paragraphs.append("If you delete \(subject) and save, any groups who have not yet signed \(object) will lose access. If you then replace \(object), they'll get access to the latest version. Groups who have already signed \(plural ? "them" : "this NDA") will retain access to the signed version.")
            } else {
                paragraphs.append("If you delete \(subject) and save, anyone who had received \(object) will lose their access. If you then replace \(object), they'll get access to the latest version.")
            }
        }
        paragraphs.append("Are you sure you want to delete?")
        return paragraphs.joined(separator: "\n\n")
    }
}
