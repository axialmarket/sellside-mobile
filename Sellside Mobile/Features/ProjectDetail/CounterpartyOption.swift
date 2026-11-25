//
//  CounterpartyOption.swift
//  Sellside Mobile
//

import Foundation

/// A company that can be named as the counterparty when a project goes under
/// LOI or closes.
struct CounterpartyOption: Identifiable, Hashable {
    let accountId: String
    let name: String

    var id: String { accountId }
}

extension CounterpartyOption {
    /// Mirrors fe-app's `parsePossibleCounterParties` + `filterCompanies`
    /// (update-intent-with-counterparty-modal.component.ts): one entry per
    /// company, deals without an account id dropped (imported contacts), and
    /// sorted by name.
    ///
    /// Web keeps the first deal seen for a duplicated account and doesn't look
    /// at the name when deduping, so two genuinely different companies sharing
    /// a name still produce two entries. Same here, deliberately — matching
    /// the web is worth more than the fix while both exist.
    static func options(from deals: [SellsideDeal]) -> [CounterpartyOption] {
        var seen: Set<String> = []
        var options: [CounterpartyOption] = []

        for deal in deals {
            guard let accountId = deal.demandAccountPublicId, !accountId.isEmpty else { continue }
            guard seen.insert(accountId).inserted else { continue }
            options.append(CounterpartyOption(accountId: accountId, name: deal.demandAccountName ?? ""))
        }

        return options.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

/// Body for `sellside-exclusive-loi` and `sellside-closed`. Mirrors what
/// fe-app's modal submits: a name *or* an account id, never both, plus how the
/// buyside party was sourced.
struct CounterpartyInfo: Encodable, Equatable {
    let name: String?
    let accountPublicId: String?
    let isSourcedViaAxial: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case accountPublicId = "account_public_id"
        case isSourcedViaAxial = "is_sourced_via_axial"
    }
}

/// Which counterparty the user picked, if any. Web leaves the counterparty
/// field optional — only the sourcing question is required — so "unspecified"
/// is a valid submission.
enum CounterpartySelection: Hashable {
    case unspecified
    case member(String) // account public id
    case outsideAxial
}

extension CounterpartyInfo {
    /// Resolves the sheet's state into the request body. Web looks the typed
    /// text back up against its options to decide id-vs-name; picking from a
    /// list makes that explicit, but the resulting payload is the same.
    static func make(
        selection: CounterpartySelection,
        customName: String,
        sourcedViaAxial: Bool
    ) -> CounterpartyInfo {
        switch selection {
        case .member(let accountId):
            return CounterpartyInfo(
                name: nil, accountPublicId: accountId, isSourcedViaAxial: sourcedViaAxial
            )

        case .outsideAxial:
            // Web normalizes an empty entry to null rather than sending "".
            let trimmed = customName.trimmingCharacters(in: .whitespacesAndNewlines)
            return CounterpartyInfo(
                name: trimmed.isEmpty ? nil : trimmed,
                accountPublicId: nil,
                isSourcedViaAxial: sourcedViaAxial
            )

        case .unspecified:
            return CounterpartyInfo(
                name: nil, accountPublicId: nil, isSourcedViaAxial: sourcedViaAxial
            )
        }
    }
}
