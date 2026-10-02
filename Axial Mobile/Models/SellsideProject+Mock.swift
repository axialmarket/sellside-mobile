//
//  SellsideProject+Mock.swift
//  Axial Mobile
//

import Foundation

extension SellsideProject {
    /// Mock for previews and tests. Not for production paths.
    static func mock(
        publicId: String = UUID().uuidString,
        name: String = "Project Neptune",
        state: SupplyState = .inMarket,
        recommended: Int = 24,
        unread: Int? = 3,
        contacted: Int = 12,
        interested: Int = 5,
        sectors: [String] = ["Industrials", "Manufacturing"],
        createdDaysAgo: Int? = 21,
        contact: (first: String, last: String)? = ("Jordan", "Reyes")
    ) -> SellsideProject {
        SellsideProject(
            publicId: publicId,
            internalName: name,
            supplyState: state,
            sectors: sectors.map { Sector(name: $0) },
            activeRecommendations: recommended,
            unreadRecommendations: unread,
            activeDeals: contacted,
            interestedMembers: interested,
            assignedToUser: contact.map { AssignedUser(firstName: $0.first, lastName: $0.last) },
            createdAt: createdDaysAgo.flatMap {
                Calendar.current.date(byAdding: .day, value: -$0, to: .now)
            }
        )
    }
}
