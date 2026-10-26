//
//  SetupForm.swift
//  Axial Mobile
//

import Foundation

/// The whole wizard's state as one value — the web's root `FormGroup`
/// (`ISellProjectSetupForm`) plus the documents store, since a document
/// change is an edit like any other and autosaves the same way.
struct SetupForm: Equatable {
    var companyBasics: CompanyBasicsForm
    var capitalRaise: CapitalRaiseForm
    var financials: FinancialsForm
    var documents: SetupDocuments
    var nda: NDAForm
    var cim: CIMForm
    var sharingSettings: SharingSettingsForm
    var messaging: MessagingForm

    init(intent: JSONValue, context: SetupContext) {
        companyBasics = CompanyBasicsForm(intent: intent)
        capitalRaise = CapitalRaiseForm(intent: intent)
        financials = FinancialsForm(intent: intent, now: context.now)
        let documents = SetupDocuments(intent: intent)
        self.documents = documents
        nda = NDAForm(intent: intent, documents: documents)
        cim = CIMForm(intent: intent, documents: documents)
        sharingSettings = SharingSettingsForm(intent: intent)
        messaging = MessagingForm(intent: intent)
    }

    /// `READ_ONLY_INTENT_FIELDS` — what never goes back to the API.
    static let readOnlyFields: [String] = [
        "assigned_to_user", "assigned_to_user_rating", "owned_by_account", "history", "created_at", "updated_at",
        "updated_by", "terms_types", "has_custom_teaser", "is_complete", "wave_level", "last_sellside_activity",
        "in_review_date", "inbound_inquiry_date", "in_market_date", "last_draft_date", "under_loi_date",
        "annotated_headline_public_id", "annotated_description_public_id", "member_id", "member_metadata",
        "axial_brief_requested_at", "last_autosave_attempt", "last_autosave_success", "autodraft_editable_fields",
        "industry_categories", "id", "is_deleted", "is_shared", "supply_state", "owned_by_account_public_id",
        "documents", "intent_state", "approval_state", "hide_teaser_affirm", "autoshare_expires_at",
        "snooze_until", "active_status_confirmed_at", "client", "keywords", "intent_source", "seller_timing",
        // Mobile-only: computed by the backend, never edited here.
        "available_actions",
    ]

    /// `createIntentDataFromForm`: the intent minus read-only fields, with
    /// each available step written in. Steps locked by autodraft are skipped,
    /// so their values never go back while the server owns them.
    func payload(over intent: JSONValue, context: SetupContext) -> JSONValue {
        var shell = intent.removingKeys(Self.readOnlyFields)
        for step in context.sequence where !context.isLocked(step) {
            switch step {
            case .companyBasics: companyBasics.write(into: &shell, context: context)
            case .capitalRaise: capitalRaise.write(into: &shell)
            case .financials: financials.write(into: &shell)
            case .customTeaser: break
            case .nda: nda.write(into: &shell)
            case .cimSummaryMaterials: cim.write(into: &shell)
            case .sharingSettings: sharingSettings.write(into: &shell)
            case .vettingQuestions: break
            case .messaging: messaging.write(into: &shell)
            case .advancedSharing: break
            }
        }
        return shell
    }

    func validate(_ step: SetupStep, context: SetupContext, into v: inout StepValidationBuilder) {
        switch step {
        case .companyBasics: companyBasics.validate(context: context, into: &v)
        case .capitalRaise: capitalRaise.validate(into: &v)
        case .financials: financials.validate(now: context.now, into: &v)
        case .customTeaser: break
        case .nda: nda.validate(documents: documents, into: &v)
        case .cimSummaryMaterials: cim.validate(nda: nda, documents: documents, into: &v)
        case .sharingSettings: sharingSettings.validate(into: &v)
        case .vettingQuestions: break
        case .messaging: messaging.validate(memberCount: context.memberCount, into: &v)
        case .advancedSharing: break
        }
    }

    // MARK: Cross-step behaviour

    /// `handleNdaTypeChange`: the side effects of picking an NDA option.
    mutating func setNDAType(_ next: String?) {
        let previous = nda.ndaType
        guard next != previous else { return }
        nda.ndaType = next
        if previous == "custom", let custom = documents.customNDA { documents.remove(custom) }
        switch next {
        case "axial":
            documents.queueStandardNDA()
        case "custom":
            if previous != nil { documents.clearPendingUploads("NDA") }
            if documents.nda?.isStandardNDA == true, let standard = documents.nda { documents.remove(standard) }
        default:
            documents.clearPendingUploads("NDA")
            if let existing = documents.nda { documents.remove(existing) }
        }
        if next != "custom" { nda.linkedNdaUrl = "" }
    }

    /// A custom NDA file replaces any linked URL, and vice versa.
    mutating func attachNDA(filename: String, mimeType: String, data: Data, signatureType: String) {
        documents.add(bucket: "NDA", filename: filename, mimeType: mimeType, data: data, signatureType: signatureType)
        nda.linkedNdaUrl = ""
    }

    mutating func linkNDA(_ url: String) {
        nda.linkedNdaUrl = url
        if !url.isEmpty, let custom = documents.customNDA { documents.remove(custom) }
    }

    /// Uploading summary materials makes the CIM custom and drops a link.
    mutating func attachCIM(filename: String, mimeType: String, data: Data) {
        documents.add(bucket: "OM", filename: filename, mimeType: mimeType, data: data)
        cim.cimType = "custom"
        cim.linkedCimUrl = ""
    }

    /// `confirmLinkedCimUrl` for a valid URL: the link replaces uploads.
    mutating func linkCIM(_ url: String) {
        cim.linkedCimUrl = url
        if !url.isEmpty {
            documents.removeAll(in: "OM")
            cim.cimType = "custom"
        } else if documents.cimDocuments.isEmpty {
            cim.cimType = nil
        }
    }

    /// Removing the last document unsets the CIM and its sharing method.
    mutating func removeCIMDocument(_ document: SetupDocument) {
        documents.remove(document)
        if documents.cimDocuments.isEmpty, cim.cimType == "custom", cim.linkedCimUrl.isEmpty {
            cim.smartshareState = nil
            cim.cimType = nil
        }
    }

    /// Waiving removes every attached CIM document, the link and the method.
    mutating func setCIMWaived(_ waived: Bool) {
        if waived {
            documents.removeAll(in: "OM")
            cim.linkedCimUrl = ""
            cim.smartshareState = nil
            cim.cimType = "waive"
        } else if cim.cimType == "waive" {
            cim.cimType = nil
        }
    }

    mutating func setCIMSmartshare(_ state: String?) {
        cim.smartshareState = state
        if state == "enabled", cim.cimType == "waive" { cim.cimType = nil }
    }
}

extension SetupContext {
    /// `disabledDuringAutoDraft` for the document steps and vetting;
    /// `disabledWhenAutoDraftOwnsAllFields` elsewhere. Mobile doesn't read
    /// `autodraft_editable_fields`, so it takes the fail-closed reading the
    /// web uses when that list is empty: everything with paths is locked.
    func isLocked(_ step: SetupStep) -> Bool {
        guard isAutoDrafting else { return false }
        return step != .advancedSharing
    }
}
