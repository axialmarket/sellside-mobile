//
//  ReviewSummary.swift
//  Axial Mobile
//

import Foundation

/// The confirmation panel's Changes list — `FieldMetadataMap` reduced to
/// what the panel shows: changed paths, named, sorted and de-duplicated.
/// confirmation-panel.constants.ts and project-setup-confirmation-panel-
/// changes.ts.
enum ReviewChanges {
    struct Change: Equatable, Identifiable {
        let name: String
        let step: SetupStep
        var id: String { "\(name)|\(step.rawValue)" }
    }

    static func changes(from baseline: JSONValue, to current: JSONValue, documents: SetupDocuments,
                        canManuallyShare: Bool) -> [Change] {
        var paths = flatten(current.diff(from: baseline), prefix: "")
        if documents.hasPendingUpload("T") { paths.append("uploadDocuments.T") }
        else if documents.pendingDeletions.contains(where: { $0.bucket == "T" }) { paths.append("deleteDocuments.T") }
        if current["nda_type"]?.string == "custom", documents.hasPendingUpload("NDA") { paths.append("uploadDocuments.NDA") }
        if current["cim_type"]?.string == "custom" {
            if documents.hasPendingUpload("OM") { paths.append("uploadDocuments.OM") }
            else if documents.pendingDeletions.contains(where: { $0.bucket == "OM" }) { paths.append("deleteDocuments.OM") }
        }

        let smartshareChanged = paths.contains("use_smartshare")
        let approvalChanged = paths.contains("requires_approval")
        let newSmartshare = current["use_smartshare"]?.bool
        let newApproval = current["requires_approval"]?.bool
        // Inbound Inquiry on, or Manual: one row, not two.
        if canManuallyShare, smartshareChanged, approvalChanged, newSmartshare == newApproval {
            paths.removeAll { $0 == "use_smartshare" }
        }
        let relabelAsSharingMethod = canManuallyShare && approvalChanged
            && baseline["requires_approval"]?.bool == true && newApproval == false && newSmartshare == true

        let sorted = paths.sorted { a, b in
            let ia = sortOrder.firstIndex(of: a), ib = sortOrder.firstIndex(of: b)
            switch (ia, ib) {
            case let (x?, y?): return x < y
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a < b
            }
        }
        var result: [Change] = []
        for path in sorted {
            let name: String
            if path == "requires_approval" {
                name = relabelAsSharingMethod ? "Sharing Method" : (canManuallyShare ? "Inbound Inquiry" : "Requires Approval")
            } else {
                name = displayName(path)
            }
            let change = Change(name: name, step: step(for: path))
            if !result.contains(change) { result.append(change) }
        }
        return result
    }

    /// Leaf paths of a patch; arrays and scalars are leaves.
    static func flatten(_ value: JSONValue, prefix: String) -> [String] {
        guard let object = value.object else { return prefix.isEmpty ? [] : [prefix] }
        if object.isEmpty { return [] }
        return object.flatMap { key, child -> [String] in
            let path = prefix.isEmpty ? key : "\(prefix).\(key)"
            // Always to the leaves; `displayName` climbs back to a named parent.
            if child.object != nil { return flatten(child, prefix: path) }
            return [path]
        }
    }

    static func displayName(_ path: String) -> String {
        if let name = displayNames[path], !name.isEmpty { return name }
        // A nested path under a named parent takes the parent's name.
        var parts = path.split(separator: ".").map(String.init)
        while parts.count > 1 {
            parts.removeLast()
            if let name = displayNames[parts.joined(separator: ".")], !name.isEmpty { return name }
        }
        return path
    }

    /// Which step owns a path, for the row's edit button.
    static func step(for path: String) -> SetupStep {
        let prefixes: [(String, SetupStep)] = [
            ("terms.capital", .capitalRaise), ("company.financials", .financials), ("financial_commentary", .financials),
            ("company.is_audited", .financials), ("company.auditing_firm_name", .financials),
            ("company.fiscal_year_end_month", .financials), ("uploadDocuments.T", .customTeaser),
            ("deleteDocuments.T", .customTeaser), ("nda_type", .nda), ("linked_nda", .nda), ("uploadDocuments.NDA", .nda),
            ("cim_type", .cimSummaryMaterials), ("linked_cim", .cimSummaryMaterials), ("use_cim_smartshare", .cimSummaryMaterials),
            ("uploadDocuments.OM", .cimSummaryMaterials), ("deleteDocuments.OM", .cimSummaryMaterials),
            ("cim", .cimSummaryMaterials), ("calendar_link", .cimSummaryMaterials),
            ("use_smartshare", .sharingSettings), ("requires_approval", .sharingSettings),
            ("supply_blocked_counterparties", .sharingSettings), ("advanced_filters", .sharingSettings),
            ("can_have_referral_links", .sharingSettings), ("assigned_to_user_public_id", .messaging),
            ("extra_contacts", .messaging), ("teaser", .messaging), ("follow_up", .messaging), ("nudge_days", .messaging),
        ]
        return prefixes.first { path == $0.0 || path.hasPrefix($0.0 + ".") }?.1 ?? .companyBasics
    }

    /// `INTENT_FIELD_DISPLAY_NAMES`, verbatim.
    static let displayNames: [String: String] = [
        "assigned_to_user_public_id": "Primary Contact", "description": "Company Description",
        "headline": "External Headline", "internal_name": "Internal Codename", "role_types": "Your Role",
        "customer_types": "End Markets", "geography_disclosure": "Company HQ Display Setting", "nda_type": "NDA",
        "linked_nda": "Linked NDA", "cim_type": "CIM / Summary Materials", "linked_cim": "CIM / Summary Materials",
        "use_cim_smartshare": "Automatic CIM Share", "company_website": "Company Website",
        "extra_contacts": "Additional Contacts", "company": "", "company.financials": "Historical Metrics",
        "company.financials.revenue": "Historical Metrics", "company.financials.ebitda": "Historical Metrics",
        "company.financials.gross_profit": "Historical Metrics", "company.financials.capex": "Historical Metrics",
        "company.financials.kpis": "Current Metrics", "company.financials.valuation": "Valuation Multiple",
        "financial_commentary": "Financial Commentary", "company.industries": "Industries",
        "company.is_audited": "Financial Audit", "company.fiscal_year_end_month": "Fiscal Year End",
        "company.geographies": "Company HQ", "company.company_name": "Company Name (Internal use only)",
        "company.year_established": "Business Established Year", "company.full_time_employee_count": "Full-Time Employees",
        "company.part_time_employee_count": "Part-Time Employees", "company.reason_for_sale": "Reason for Sale",
        "company.business_attributes": "Business Attributes", "company.licenses_required": "Business Licenses",
        "company.license_details": "Business Licenses", "company.real_estate_included": "Real Estate",
        "company.real_estate_details": "Real Estate", "cim": "", "cim.cc_members": "CIM Note CC",
        "cim.message": "CIM Message", "calendar_link": "Calendar Link", "follow_up": "",
        "follow_up.message": "Follow-Up Note", "nudge_days": "Follow-Up Note", "teaser": "",
        "teaser.cc_members": "Outreach Note CC", "teaser.message": "Teaser Message",
        "teaser.cc_emails": "Outreach CC Emails", "teaser.include_with_outreach": "Include with Outreach",
        "teaser.subject": "Outreach Subject", "terms.capital.capital_types": "Capital Type",
        "terms.capital.use_of_funds": "Intended Use of Funds", "terms.capital.debt_types": "Debt Type",
        "terms.capital.financial_range.min_value": "Minimum Check Size",
        "terms.capital.financial_range.max_value": "Total Capital", "advanced_filters": "Matching Preferences",
        "use_smartshare": "Sharing Method", "company.auditing_firm_name": "Auditing Firm Name",
        "terms.ma.ceo_exiting_type": "CEO Exit Type", "terms.capital": "Capital Terms",
        "roles.advisor.exclusive_mandate": "Your Mandate", "roles.advisor.expects_buyer_fee": "Sellside Fees",
        "roles.investor.expects_buyer_fee": "Sellside Fees", "can_have_referral_links": "Referrals",
        "uploadDocuments.T": "Custom Teaser", "deleteDocuments.T": "Custom Teaser", "uploadDocuments.NDA": "NDA",
        "deleteDocuments.NDA": "NDA", "uploadDocuments.OM": "CIM / Summary Materials",
        "deleteDocuments.OM": "CIM / Summary Materials", "requires_approval": "Inbound Inquiry",
        "supply_blocked_counterparties": "Member Suppression",
    ]

    /// `INTENT_FIELD_SORT_ORDER`.
    static let sortOrder: [String] = [
        "internal_name", "headline", "company_website", "description", "geography_disclosure", "company.geographies",
        "customer_types", "company.industries", "role_types", "roles.advisor.exclusive_mandate",
        "roles.advisor.expects_buyer_fee", "roles.investor.expects_buyer_fee", "company.company_name",
        "company.year_established", "company.full_time_employee_count", "company.part_time_employee_count",
        "company.reason_for_sale", "company.licenses_required", "company.license_details",
        "company.real_estate_included", "company.real_estate_details", "company.business_attributes",
        "terms.capital.capital_types", "terms.capital.debt_types", "terms.capital.use_of_funds",
        "terms.capital.financial_range.max_value", "terms.capital.financial_range.min_value",
        "company.fiscal_year_end_month", "company.financials", "company.financials.revenue", "company.financials.ebitda",
        "company.financials.gross_profit", "company.financials.capex", "company.financials.kpis",
        "company.financials.valuation", "financial_commentary", "company.is_audited", "company.auditing_firm_name",
        "terms.ma.ceo_exiting_type", "uploadDocuments.T", "deleteDocuments.T", "nda_type", "uploadDocuments.NDA",
        "deleteDocuments.NDA", "linked_nda", "use_cim_smartshare", "cim_type", "uploadDocuments.OM",
        "deleteDocuments.OM", "linked_cim", "use_smartshare", "requires_approval", "supply_blocked_counterparties",
        "cim.cc_members", "cim.message", "calendar_link", "assigned_to_user_public_id", "extra_contacts",
        "teaser.cc_members", "teaser.message", "follow_up.message", "nudge_days", "can_have_referral_links",
        "advanced_filters",
    ]

    static func plural(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(count) \(count == 1 ? singular : (plural ?? singular + "s"))"
    }
}
