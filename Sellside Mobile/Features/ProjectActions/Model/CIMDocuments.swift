//
//  CIMDocuments.swift
//  Sellside Mobile
//

import Foundation

/// The Upload CIM action item's edit — the Upload Documentation segment of
/// the web's CIM / Summary Materials step, on its own: files (or a link),
/// and how they're shared.
struct CIMUpload: Equatable {
    /// `cimSmartshareState`: "enabled" (Automatic CIM Share) or "off".
    var sharing: String?
    var linkedURL = ""

    static let maxFiles = 10

    /// `cimValidator`'s NDA check, read off the saved project: Automatic CIM
    /// Share needs an NDA members can sign electronically — the standard NDA,
    /// or a custom one set up for e-signature.
    static func ndaIsSignable(intent: JSONValue) -> Bool {
        let nda = intent["documents"]?.array?.first { $0["type"]?.string == "NDA" }
        if let nda {
            if nda["is_standard_nda"]?.bool == true { return true }
            let signature = nda["signature_type"]?.string
            return signature == "basic" || signature == "custom"
        }
        return intent["nda_type"]?.string == "axial"
    }

    /// `canLinkCim`.
    static func canLink(intent: JSONValue) -> Bool {
        intent["cim_type"]?.string == "linked" || intent["linked_cim"]?.text != nil
            || intent["owned_by_account"]?["can_link_cim"]?.bool == true
    }

    enum Field {
        static let materials: FormFieldKey = "cim.materials"
        static let sharing: FormFieldKey = "cim.sharing"
        static let link: FormFieldKey = "cim.link"
    }

    /// `cimValidator` and the step's required controls, for a project that
    /// is getting its first CIM.
    func errors(fileCount: Int, ndaIsSignable: Bool) -> [FormFieldKey: String] {
        var errors: [FormFieldKey: String] = [:]
        if fileCount == 0, linkedURL.isEmpty { errors[Field.materials] = "" }
        if !URLRule.isValid(linkedURL) { errors[Field.link] = "Invalid URL" }
        if sharing == nil {
            errors[Field.sharing] = "Please select a sharing method to continue."
        } else if sharing == "enabled", !ndaIsSignable {
            errors[Field.sharing] = "To use Automatic CIM Share, please select an electronically signable NDA."
        }
        return errors
    }

    /// `extractCimFromForm`: custom with a link is saved as "linked".
    var patch: JSONValue {
        [
            "cim_type": linkedURL.isEmpty ? "custom" : "linked",
            "linked_cim": .string(orNull: linkedURL.isEmpty ? nil : linkedURL),
            "use_cim_smartshare": .bool(sharing == "enabled"),
        ]
    }
}

/// File limits and accepted types for uploads.
enum DocumentRules {
    /// `MAX_CIM_FILE_SIZE_MB`, plus the silent 2 MB tolerance.
    static let cimMaxMB = 50
    static let cimToleranceMB = 2
    static let cimExtensions = ["pdf", "docx", "pptx", "xlsx", "csv"]

    static func mimeType(for filename: String) -> String {
        switch (filename as NSString).pathExtension.lowercased() {
        case "pdf": "application/pdf"
        case "doc": "application/msword"
        case "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        case "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "csv": "text/csv"
        default: "application/octet-stream"
        }
    }
}
