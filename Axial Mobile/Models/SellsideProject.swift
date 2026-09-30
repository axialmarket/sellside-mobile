//
//  SellsideProject.swift
//  Axial Mobile
//

import Foundation

/// One row from `GET /sellside-projects`. Mirrors fe-app's
/// `ISupplyIntentRowData` (supply-intent-row.model.ts), decoding only
/// the fields the app displays. Lenient by design: everything except
/// `public_id` and `internal_name` tolerates absence.
struct SellsideProject: Decodable, Identifiable, Equatable {
    struct Sector: Decodable, Equatable {
        let name: String
    }

    struct AssignedUser: Decodable, Equatable {
        let firstName: String
        let lastName: String

        enum CodingKeys: String, CodingKey {
            case firstName = "first_name"
            case lastName = "last_name"
        }

        var fullName: String { "\(firstName) \(lastName)" }
    }

    let publicId: String
    // Mutable so a full project response can be folded back in — see merging(_:).
    var internalName: String
    var supplyState: SupplyState
    let intentType: String?
    let sectors: [Sector]
    let activeRecommendations: Int
    let unreadRecommendations: Int?
    let activeDeals: Int
    let interestedMembers: Int
    let assignedToUser: AssignedUser?
    let createdAt: Date?

    var id: String { publicId }

    /// Key for `/api/intents/{id}` and for the detail cache — see `IntentID`.
    var intentId: String { IntentID.normalized(publicId) }

    var sectorNames: String { sectors.map(\.name).joined(separator: ", ") }

    /// Overlays the authoritative fields from a whole-project response so the
    /// card can't drift from the dashboard. The counts aren't touched:
    /// `/api/intents/{id}` doesn't carry them, only the list endpoint does.
    func merging(_ detail: ProjectDetail) -> SellsideProject {
        var updated = self
        updated.internalName = detail.internalName
        updated.supplyState = detail.supplyState
        return updated
    }

    enum CodingKeys: String, CodingKey {
        case publicId = "public_id"
        case internalName = "internal_name"
        case supplyState = "supply_state"
        case intentType = "intent_type"
        case sectors
        case activeRecommendations = "active_recommendations"
        case unreadRecommendations = "unread_recommendations"
        case activeDeals = "active_deals"
        case interestedMembers = "interested_members"
        case assignedToUser = "assigned_to_user"
        case createdAt = "created_at"
    }

    init(
        publicId: String,
        internalName: String,
        supplyState: SupplyState,
        intentType: String? = nil,
        sectors: [Sector] = [],
        activeRecommendations: Int = 0,
        unreadRecommendations: Int? = nil,
        activeDeals: Int = 0,
        interestedMembers: Int = 0,
        assignedToUser: AssignedUser? = nil,
        createdAt: Date? = nil
    ) {
        self.publicId = publicId
        self.internalName = internalName
        self.supplyState = supplyState
        self.intentType = intentType
        self.sectors = sectors
        self.activeRecommendations = activeRecommendations
        self.unreadRecommendations = unreadRecommendations
        self.activeDeals = activeDeals
        self.interestedMembers = interestedMembers
        self.assignedToUser = assignedToUser
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        publicId = try c.decode(String.self, forKey: .publicId)
        internalName = try c.decode(String.self, forKey: .internalName)
        supplyState = try c.decodeIfPresent(SupplyState.self, forKey: .supplyState) ?? .unknown
        intentType = try c.decodeIfPresent(String.self, forKey: .intentType)
        sectors = try c.decodeIfPresent([Sector].self, forKey: .sectors) ?? []
        activeRecommendations = try c.decodeIfPresent(Int.self, forKey: .activeRecommendations) ?? 0
        unreadRecommendations = try c.decodeIfPresent(Int.self, forKey: .unreadRecommendations)
        activeDeals = try c.decodeIfPresent(Int.self, forKey: .activeDeals) ?? 0
        interestedMembers = try c.decodeIfPresent(Int.self, forKey: .interestedMembers) ?? 0
        assignedToUser = try c.decodeIfPresent(AssignedUser.self, forKey: .assignedToUser)
        createdAt = Self.flexibleDate(from: c, key: .createdAt)
    }

    /// `created_at` is typed `string` in the TS model but the wire format is
    /// unverified (ISO 8601 with/without fractional seconds vs epoch).
    /// Parse leniently; nil on any mismatch — the UI treats it as optional.
    private static func flexibleDate(
        from c: KeyedDecodingContainer<CodingKeys>, key: CodingKeys
    ) -> Date? {
        if let string = try? c.decode(String.self, forKey: key) {
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let plain = ISO8601DateFormatter()
            return fractional.date(from: string) ?? plain.date(from: string)
        }
        if let epoch = try? c.decode(Double.self, forKey: key) {
            return Date(timeIntervalSince1970: epoch)
        }
        return nil
    }
}
