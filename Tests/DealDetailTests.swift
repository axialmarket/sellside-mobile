//
//  DealDetailTests.swift
//  Tests
//

import Foundation
import Testing
@testable import Axial_Mobile

/// The deal screen's rules, held against fe-app's sell sidebar:
/// sell-sidebar.service.ts (`createMenuOptions`), sell-sidebar-header,
/// sell-sidebar-overview, sell-sidebar-sourcing-criteria, the messages feed
/// (messages-feed-content / -history / -event) and the composer
/// (messages-feed-sending.component.ts).
@MainActor
struct DealDetailTests {

    private static func json(_ text: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private static let sidebarJSON = """
    {"public_id": "d1", "has_target_pursued": true, "is_anonymous": false,
     "referral": {"referral_source": "deal"},
     "message_counts": {"sent": 0, "read": 2},
     "request_access_event": {"extra_data": {"message": "We'd love to learn more."}},
     "demand_intent": {
        "intent_type": "buy_business", "headline": "Bluewater add-on",
        "client": {"client_name": "Meridian", "intent_subtype": "add_on", "buyside_type": "strategic"},
        "description": "<p>Industrial <b>services</b> platform.</p>",
        "assigned_to_user": {"id": "u1", "first_name": "Jordan", "last_name": "Reyes", "title": "MD",
                             "email": "jordan@bluewater.com", "linkedin_url": "linkedin.com/in/jreyes",
                             "passport_metrics": [{"name": "buyside_responsiveness", "value": 52, "uom": "pct"},
                                                  {"name": "buyside_submitted_bids", "value": 5, "uom": "qty"}]},
        "assigned_to_user_rating": {"average": 4.25},
        "owned_by_account": {"public_id": "a1", "name": "Bluewater Capital", "description": "A fund &amp; more.",
                             "website": "bluewater.com", "capital_source": "committed",
                             "has_active_portcos": true,
                             "primary_office": {"city": "London", "region": "LDN", "country": "GB"}}
     },
     "supply_intent": {"headline": "Project Neptune",
                       "assigned_to_user": {"id": "s1", "first_name": "Sam", "last_name": "Seller"},
                       "owned_by_account": {"name": "Neptune Advisors"}},
     "demand_account_industries": [{"name": "Industrials"}, {"name": "Industrials"}, {"name": "Healthcare"}],
     "demand_account_members": [
        {"id": "u3", "first_name": "Casey", "last_name": "Lee", "order_sequence": 2, "is_active": true},
        {"id": "u1", "first_name": "Jordan", "last_name": "Reyes", "order_sequence": 0, "is_active": true},
        {"id": "u2", "first_name": "Alex", "last_name": "Kim", "order_sequence": 1, "is_active": true},
        {"id": "u4", "first_name": "Gone", "last_name": "Away", "order_sequence": 3, "is_active": false}],
     "demand_account_offices": [
        {"public_id": "o1", "type_code": "SAT", "city": "Boston", "region": "MA", "street_address": ["1 Main St"]},
        {"public_id": "o2", "type_code": "HQ", "city": "New York", "region": "NY", "postal_code": "10016",
         "street_address": ["334 Park Ave S", ""]}],
     "demand_account_tombstones": [{"public_id": "t1", "sellside_company_name": "Acme"},
                                   {"public_id": "t2", "sellside_company_name": "Globex"}],
     "reasons": {
        "financial": {"buyer": {"financials": {"revenue": {"range": {"min_value": 5000000, "max_value": 50000000}},
                                               "ebitda": {"range": {"min_value": 1000000}}}}},
        "industry": {"matches": [
            {"is_implied_match": false, "buyer": {"industry": {"name": "Machinery"}}, "seller": {"industry": {"name": "Tools"}}},
            {"is_implied_match": true, "buyer": {"industry": {"name": "Other"}}, "seller": {"industry": {"name": "Pumps"}}}]}
     }}
    """

    private var profile: DealProfile { DealProfile(json: Self.json(Self.sidebarJSON)) }

    // MARK: - Profile

    @Test func headerTitleIsTheMemberAtTheirAccount() {
        // sell-sidebar-header: `${assignedToUser.full_name} at ${ownedByAccount.name}`
        #expect(profile.headerTitle == "Jordan Reyes at Bluewater Capital")
    }

    /// Mobile's own: the header settles on the first frame, so paging doesn't
    /// reflow it when a profile lands.
    @Test func theHeaderDoesNotChangeWhenTheProfileLands() {
        let deal = SellsideDeal(publicId: "d1", demandAccountName: "Bluewater Capital", demandUserName: "Jordan Reyes",
                                demandAccountCode: "PE", city: "Austin", stateProvince: "TX", country: "US")
        #expect(DealHeader.title(deal: deal, profile: profile) == DealHeader.title(deal: deal, profile: nil))
        #expect(DealHeader.location(deal: deal, profile: profile) == DealHeader.location(deal: deal, profile: nil))
        #expect(DealHeader.location(deal: deal, profile: nil) == "Austin, TX")
    }

    @Test func headerTitleIsBorrowedFromTheRowBeforeTheProfileLands() {
        let deal = SellsideDeal(publicId: "d1", demandAccountName: "Bluewater Capital", demandUserName: "Jordan Reyes")
        #expect(DealHeader.title(deal: deal, profile: nil) == "Jordan Reyes at Bluewater Capital")
        #expect(DealHeader.title(deal: SellsideDeal(publicId: "d2", demandAccountName: "Solo"), profile: nil) == "Solo")
    }

    @Test func accountAgeComparesCalendarYears() {
        // Account.age: getFullYear() - getFullYear(date_joined)
        let calendar = Calendar(identifier: .gregorian)
        let now = Date.now
        func joined(yearsAgo: Int) -> DealProfile {
            let date = calendar.date(byAdding: .year, value: -yearsAgo, to: now)!
            let ms = Int(date.timeIntervalSince1970 * 1000)
            return DealProfile(json: Self.json(#"{"demand_intent": {"owned_by_account": {"date_joined": \#(ms)}}}"#))
        }
        #expect(joined(yearsAgo: 0).accountAge(now: now, calendar: calendar) == "<1 Year on Axial")
        #expect(joined(yearsAgo: 1).accountAge(now: now, calendar: calendar) == "1 Year on Axial")
        #expect(joined(yearsAgo: 4).accountAge(now: now, calendar: calendar) == "4 Years on Axial")
    }

    @Test func primaryOfficeNamesTheCountryOutsideNorthAmerica() {
        #expect(profile.primaryOfficeLocation == "London, GB")
        #expect(DealProfile.location(of: Self.json(#"{"city": "Austin", "region": "TX", "country": "US"}"#)) == "Austin, TX")
    }

    @Test func overviewLinesFollowTheWebsCopy() {
        // investingOnBehalfOf (add_on), sellPanelCapSourceLabels, tombstones
        #expect(profile.investingOnBehalfOf == "Making strategic acquisitions on behalf of Meridian")
        #expect(profile.capitalSourceLine == "Has committed capital")
        #expect(profile.closedDealsLine == "2 closed deals")
        #expect(profile.hasActivePortcos)
        #expect(profile.hasOverview)
    }

    @Test func investingOnBehalfOfFallsBackWhenTheClientIsUnnamed() {
        func line(_ subtype: String, _ type: String) -> String? {
            DealProfile(json: Self.json("""
            {"demand_intent": {"intent_type": "buy_business",
                               "client": {"intent_subtype": "\(subtype)", "buyside_type": "\(type)"}}}
            """)).investingOnBehalfOf
        }
        #expect(line("add_on", "financial") == "Making strategic acquisitions on behalf of a portfolio company")
        #expect(line("buyside", "strategic") == "Making strategic acquisitions on behalf of a client")
        #expect(line("buyside", "financial") == "Making acquisitions on behalf of a financial sponsor")
        #expect(line("direct", "financial") == nil)
    }

    @Test func anAddOnsAboutLeadsWithItsOwnDescription() {
        #expect(profile.about == "Industrial services platform.\n\nA fund & more.")
    }

    @Test func teamLeavesOutThePrimaryContactAndInactiveMembersInOrder() {
        #expect(profile.team.map(\.fullName) == ["Alex Kim", "Casey Lee"])
    }

    @Test func headquartersComesFirst() {
        // sortedDemandOffices
        #expect(profile.offices.map(\.id) == ["o2", "o1"])
        #expect(profile.offices.first?.street == ["334 Park Ave S"])
        #expect(profile.offices.first?.locality == "New York, NY 10016")
    }

    @Test func industriesAreDeduped() {
        #expect(profile.industries == ["Industrials", "Healthcare"])
    }

    @Test func sourcingNamesTheSellersIndustryForAnImpliedMatch() {
        #expect(profile.sourcingIndustries == ["Machinery", "Pumps"])
    }

    @Test func rangesAreInMillionsToOneDecimal() {
        // MillionsFormatterPipe(value / MILLION_FACTOR)
        #expect(profile.revenueRange?.formatted == "$5.0M – $50.0M")
        #expect(profile.ebitdaRange?.formatted == "$1.0M+")
        #expect(DealProfile.millions(0) == "$0")
        #expect(DealProfile.millions(12_500_000) == "$12.5M")
    }

    @Test func passportMetricsAndRatingAreRead() {
        #expect(profile.responsiveness == 52)
        #expect(profile.submittedBids == 5)
        #expect(profile.rating == 4.25)
        #expect(profile.contact?.linkedInURL?.absoluteString == "https://linkedin.com/in/jreyes")
    }

    @Test func aMissingBranchCostsOnlyItsOwnLines() {
        let empty = DealProfile(json: Self.json(#"{"public_id": "d9"}"#))
        #expect(empty.id == "d9")
        #expect(empty.contact == nil)
        #expect(empty.headerTitle == nil)
        #expect(!empty.hasOverview)
        #expect(!empty.showsSourcingCriteria)
    }

    @Test func referralDealsHideSourcingCriteria() {
        let referral = DealProfile(json: Self.json("""
        {"demand_intent": {"intent_source": "deal_referral"},
         "reasons": {"financial": {"buyer": {"financials": {"revenue": {"range": {"min_value": 1}}}}}}}
        """))
        #expect(!referral.showsSourcingCriteria)
    }

    // MARK: - Plain text

    @Test func htmlIsFlattenedOnce() {
        #expect(PlainText.from(html: "<p>Hi&nbsp;there</p><p>Line<br/>two</p>") == "Hi there\nLine\ntwo")
        #expect(PlainText.from(html: "No markup") == "No markup")
        #expect(PlainText.html(from: "a < b\n\nc") == "<p>a &lt; b</p><p><br/></p><p>c</p>")
    }

    // MARK: - Actions

    private func deal(_ status: DealStatus, interested: Bool = false, anonymous: Bool = false,
                      redline: Bool = false) -> SellsideDeal {
        SellsideDeal(publicId: "d1", supplyStatus: status, isInterested: interested, isAnonymous: anonymous,
                     hasPendingNdaRedline: redline)
    }

    // sell-sidebar.service.ts `createMenuOptions`, branch by branch. There's
    // no per-deal follow-up anywhere on the web; it's a project setting.
    @Test func aTeaserOffersEndDiscussionsAndNoFollowUp() {
        for status in [DealStatus.sentTeaser, .targetExpired] {
            let actions = DealDetailActions(deal: deal(status))
            #expect(actions.footer == [.endDiscussions])
            #expect(actions.menu == [.addComment, .updateStatus])
        }
    }

    @Test func aRecommendationOffersPassOnly() {
        // The web's primary, Draft Outreach Note, stays on the web.
        let actions = DealDetailActions(deal: deal(.notShared))
        #expect(actions.footer == [.pass])
        #expect(actions.menu.isEmpty)
    }

    @Test func anAccessRequestOffersPassAndAccept() {
        let actions = DealDetailActions(deal: deal(.targetRequestedAccess))
        #expect(actions.footer == [.pass, .accept])
        #expect(actions.menu == [.addComment])
    }

    @Test func sendCimIsPrimaryOnceTheNdaHasBeenViewed() {
        // canSendCim: target_viewed_nda, target_signed_nda, marked_nda_signed
        for status in [DealStatus.targetViewedNda, .targetSignedNda, .markedNdaSigned] {
            #expect(DealDetailActions(deal: deal(status)).footer == [.endDiscussions, .sendCim])
        }
        for status in [DealStatus.targetPursued, .sentNda, .markedSentNda] {
            #expect(DealDetailActions(deal: deal(status)).footer == [.endDiscussions, .updateStatus])
        }
    }

    @Test func preCimMenuAddsMessageForInterestedAndContactForNamedMembers() {
        let named = DealDetailActions(deal: deal(.targetSignedNda, interested: true))
        #expect(named.menu == [.sendCim, .sendMessage, .addComment, .updateStatus, .copyEmail, .copyPhone])
        let anonymous = DealDetailActions(deal: deal(.targetSignedNda, anonymous: true))
        #expect(anonymous.menu == [.sendCim, .addComment, .updateStatus])
    }

    @Test func postCimHasNoCim() {
        for status in [DealStatus.sentCim, .targetViewedCim, .markedReceivedLoi, .markedClosed] {
            let actions = DealDetailActions(deal: deal(status))
            #expect(actions.footer == [.endDiscussions, .updateStatus])
            #expect(!actions.menu.contains(.sendCim))
        }
    }

    @Test func endedDiscussionsCanBeRestartedOrMovedOn() {
        let actions = DealDetailActions(deal: deal(.endedDiscussions))
        #expect(actions.footer == [.updateStatus, .restartDiscussions])
        #expect(actions.menu.isEmpty)
        // Only `ended_discussions`: a member who ended it falls through.
        #expect(DealDetailActions(deal: deal(.targetEndedDiscussions)) == DealDetailActions(footer: [], menu: []))
    }

    @Test func aPendingRedlineReplacesEndDiscussionsWithUpdateStatus() {
        let actions = DealDetailActions(deal: deal(.targetViewedNda, interested: true, redline: true))
        #expect(actions.footer == [.updateStatus, .reviewRedlines])
        #expect(actions.menu == [.sendMessage, .reviewRedlines, .addComment, .updateStatus, .copyEmail, .copyPhone])
        // Ahead of ended discussions too.
        #expect(DealDetailActions(deal: deal(.endedDiscussions, redline: true)).footer == [.updateStatus, .reviewRedlines])
        // A hand-marked status hides the redline.
        #expect(DealDetailActions(deal: deal(.markedNdaSigned, redline: true)).footer == [.endDiscussions, .sendCim])
    }

    @Test func updateStatusIsNeverThePrimaryButton() {
        #expect(!DealDetailActions.Button.updateStatus.isPrimary)
        #expect(DealDetailActions.Button.restartDiscussions.isPrimary)
    }

    @Test func recommendedAndDeclinedOfferNothing() {
        for status in [DealStatus.recommended, .targetDeclined, .rejectedAccess] {
            #expect(DealDetailActions(deal: deal(status)) == DealDetailActions(footer: [], menu: []))
        }
    }

    @Test func messagesAreHiddenForRecommendationsAndAccessRequests() {
        // messagesTabAvailable
        #expect(!DealDetailActions.showsMessages(for: deal(.recommended)))
        #expect(!DealDetailActions.showsMessages(for: deal(.targetRequestedAccess)))
        #expect(DealDetailActions.showsMessages(for: deal(.sentTeaser)))
        // showMessageBox = isInterested
        #expect(!DealDetailActions.canMessage(deal(.targetSignedNda)))
        #expect(DealDetailActions.canMessage(deal(.targetSignedNda, interested: true)))
    }

    // MARK: - Pager

    @Test func pagingSkipsDealsThatLeftTheList() {
        // prevRow / nextRow skip ids missing from tableRowsLookup
        let pager = DealPager(ids: ["a", "b", "c", "d"])
        let present: Set = ["a", "c", "d"]
        #expect(pager.next(from: "a", among: present) == "c")
        #expect(pager.previous(from: "d", among: present) == "c")
        #expect(pager.previous(from: "a", among: present) == nil)
        #expect(pager.next(from: "d", among: present) == nil)
        #expect(pager.position(of: "b") == "2 of 4")
    }

    // MARK: - Feed

    private let names = DealFeedNames(supplyMember: "Sam Seller", supplyAccount: "Neptune Advisors",
                                      demandPerson: "Jordan Reyes", demandCompany: "Bluewater Capital")

    private func wording(_ json: String, users: [String: String] = [:]) -> String? {
        DealInteraction(json: Self.json(json)).flatMap {
            DealFeedItem.wording(for: $0, names: names, users: users)?.0
        }
    }

    @Test func statusHistoryIsWordedAsTheWebWordsIt() {
        #expect(wording(#"{"source": "supply", "supply_status": "sent_teaser", "created_at": 1}"#)
                == "Sam Seller shared the teaser.")
        #expect(wording(#"{"source": "supply", "supply_status": "sent_nda", "created_at": 1}"#)
                == "Neptune Advisors sent the NDA.")
        #expect(wording(#"{"source": "supply", "supply_status": "target_expired", "created_at": 1}"#)
                == "Bluewater Capital did not pursue or decline within 90 days.")
        #expect(wording(#"{"source": "supply", "supply_status": "target_signed_nda", "actor": {"first_name": "Pat", "last_name": "Q"}, "created_at": 1}"#)
                == "Pat Q signed the NDA.")
        // `_default`: any labelled status.
        #expect(wording(#"{"source": "supply", "supply_status": "marked_received_loi", "created_at": 1}"#)
                == "Sam Seller updated the status to LOI Received.")
    }

    @Test func historyTheWebDoesntShowIsDropped() {
        #expect(wording(#"{"source": "supply", "supply_status": "target_viewed_cim", "created_at": 1}"#) == nil)
        #expect(wording(#"{"source": "supply", "supply_status": "brand_new_status", "created_at": 1}"#) == nil)
        // Demand side only says something when the teaser is first opened.
        #expect(wording(#"{"source": "demand", "demand_is_read": true, "old_demand_is_read": true, "created_at": 1}"#) == nil)
        #expect(wording(#"{"source": "demand", "demand_is_read": true, "old_demand_is_read": false, "created_at": 1}"#)
                == "Bluewater Capital opened the teaser.")
    }

    @Test func eventsNameTheirUsersFromTheLookup() {
        #expect(wording(#"{"id": "e1", "event_type": "download_document", "source_user_id": "u1", "extra_data": {"file_name": "CIM.pdf"}, "created_at": 1}"#,
                        users: ["u1": "Jordan Reyes"]) == "Jordan Reyes viewed a file (CIM.pdf).")
        #expect(wording(#"{"id": "e2", "event_type": "nudge", "created_at": 1}"#) == "Axial Member sent a follow-up.")
        #expect(wording(#"{"id": "e3", "event_type": "cim_link_access", "source_user_id": "u1", "extra_data": {"cim_link": "https://docs.example.com/x"}, "created_at": 1}"#,
                        users: ["u1": "Jordan Reyes"]) == "Jordan Reyes viewed a link (docs.example.com).")
        #expect(wording(#"{"id": "e4", "event_type": "confirm_status", "created_at": 1}"#) == nil)
    }

    @Test func feedMergesMessagesHistoryAndCommentsOldestFirst() {
        let threads = Self.json("""
        [{"digest": [{"id": "m1", "from_user": {"email": "j@b.com", "name": "Jordan"}, "body": "<p>Hello</p>",
                      "created_at": 3000, "read_at": "2026-01-01T00:00:00Z"}]},
         {"digest": [{"id": "m1", "from_user": {"email": "j@b.com", "name": "Jordan"}, "body": "<p>Hello</p>",
                      "created_at": 3000}]}]
        """)
        var sources = DealFeedSources()
        sources.messages = DealMessage.messages(fromThreads: threads)
        sources.interactions = [DealInteraction(json: Self.json(#"{"source": "supply", "supply_status": "sent_teaser", "created_at": 1000}"#))!]
        sources.notes = [DealNote(id: "n1", text: "Call them", createdAt: Date(timeIntervalSince1970: 4), authorName: "Sam")]

        let feed = DealFeedItem.feed(from: sources, names: names)
        #expect(sources.messages.count == 1, "the inbox and sent copies are one message")
        #expect(feed.map(\.id).first == "i.0.1.0")
        #expect(feed.count == 3)
        guard case .message(let message) = feed[1].kind else { Issue.record("expected a message"); return }
        #expect(message.body == "Hello")
        #expect(!message.isUnread)
        #expect(feed[2].kind == .comment(author: "Sam"))
    }

    // MARK: - Composer

    private let me = CurrentUser(id: "s1", email: "sam@neptune.com", fullName: "Sam Seller")
    private let contact = DealProfile.Person(id: "u1", fullName: "Jordan Reyes", firstName: "Jordan", title: nil,
                                             email: "jordan@bluewater.com", linkedInURL: nil, headshotURL: nil)

    private func message(from: String, to: [String], subject: String? = "Intro") -> DealMessage {
        DealMessage(id: "m", from: .init(userId: nil, name: nil, email: from),
                    to: to.map { .init(userId: nil, name: nil, email: $0) }, cc: [], subject: subject,
                    body: "", sentAt: .now, isUnread: false, attachments: [], type: nil)
    }

    @Test func aReplyGoesToTheSenderOfTheLatestMessage() {
        // determineTo, Reply: one recipient unless you sent it
        let draft = MessageDraft.reply(latest: message(from: "jordan@bluewater.com", to: ["sam@neptune.com", "alex@bluewater.com"]),
                                       me: me, contact: contact, headline: "Neptune")
        #expect(draft.to.map(\.email) == ["jordan@bluewater.com"])
        #expect(draft.subject == "Re: Intro")
    }

    @Test func aFollowUpToYourOwnMessageKeepsEveryRecipient() {
        let draft = MessageDraft.reply(latest: message(from: "SAM@neptune.com", to: ["a@b.com", "c@d.com"], subject: "Re: Intro"),
                                       me: me, contact: contact, headline: nil)
        #expect(draft.to.map(\.email) == ["a@b.com", "c@d.com"])
        #expect(draft.subject == "Re: Intro", "Re: isn't stacked")
    }

    @Test func withNoThreadYouWriteToThePrimaryContactUnderTheHeadline() {
        let draft = MessageDraft.reply(latest: nil, me: me, contact: contact, headline: "Bluewater add-on")
        #expect(draft.to.map(\.email) == ["jordan@bluewater.com"])
        #expect(draft.subject == "Bluewater add-on")
        // A thread you're not on (an anonymous teaser) falls back the same way.
        let notOnIt = MessageDraft.reply(latest: message(from: "x@y.com", to: ["z@y.com"]), me: me,
                                         contact: contact, headline: nil)
        #expect(notOnIt.to.map(\.email) == ["jordan@bluewater.com"])
    }

    @Test func theRequestBlanksTheThreadIdAndSendsHTML() throws {
        var draft = MessageDraft.reply(latest: nil, me: me, contact: contact, headline: "Hi")
        draft.body = "Hello\nthere"
        let data = try JSONEncoder().encode(draft.request(dealId: "d1", from: me))
        let sent = try JSONDecoder().decode(JSONValue.self, from: data)["messages"]?.array?.first
        #expect(sent?["thread_id"]?.string == "")
        #expect(sent?["deal_id"]?.string == "d1")
        #expect(sent?["body"]?.string == "<p>Hello</p><p>there</p>")
        #expect(sent?["message_type"]?.string == "user_message")
        #expect(sent?[path: "from.user_id"]?.string == "s1")
        #expect(sent?[path: "recipients.to"]?.array?.first?["email"]?.string == "jordan@bluewater.com")
    }
}

// MARK: - Files

/// Held against `DealFilesComponent.fileRows` (deal-details-modal/files/
/// deal-files.component.ts) and `Deal.signedNda` (deal.model.ts).
/// Mobile's own: the Messages tab heads each day once.
struct DealFeedDayTests {
    @Test func itemsSplitWhereTheDateChangesAndKeepTheirOrder() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let morning = calendar.date(from: DateComponents(year: 2026, month: 3, day: 2, hour: 9))!
        let evening = calendar.date(byAdding: .hour, value: 10, to: morning)!
        let nextDay = calendar.date(byAdding: .day, value: 1, to: morning)!
        let items = [morning, evening, nextDay].enumerated().map { index, date in
            DealFeedItem(id: "\(index)", date: date, kind: .comment(author: "A"))
        }
        let days = DealFeedDay.days(items, calendar: calendar)
        #expect(days.map { $0.items.map(\.id) } == [["0", "1"], ["2"]])
        #expect(days.first?.day == calendar.startOfDay(for: morning))
    }
}

struct DealFilesTests {
    private static func json(_ text: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    private let documents = DealFilesTests.json("""
    [{"id": "om1", "type": "OM", "filename": "Neptune CIM.pdf", "updated_at": 3000},
     {"id": "t1", "type": "T", "filename": "Teaser.pdf"},
     {"id": "n1", "type": "NDA", "filename": "NDA.docx"},
     {"id": "gone", "type": "OM", "filename": "Old.pdf", "is_deleted": true}]
    """).array!

    private func message(_ id: String, at seconds: TimeInterval, _ attachments: [DealMessage.Attachment]) -> DealMessage {
        DealMessage(id: id, from: .init(userId: nil, name: nil, email: "j@b.com"), to: [], cc: [], subject: nil,
                    body: "", sentAt: Date(timeIntervalSince1970: seconds), isUnread: false,
                    attachments: attachments, type: nil)
    }

    @Test func documentsReadInTheWebsRowOrderThenAttachmentsNewestFirst() {
        // fileRows: teaser, NDA rows, summary files, attachments (digest reversed)
        let messages = [
            message("m1", at: 10, [.init(id: "a1", filename: "Q1.xlsx", isInline: false)]),
            message("m2", at: 20, [.init(id: "a2", filename: "Q2.xlsx", isInline: false),
                                   .init(id: "img", filename: "logo.png", isInline: true)]),
        ]
        let files = DealFile.files(documents: documents, signedNda: nil, linkedCim: nil, messages: messages)
        #expect(files.map(\.id) == ["t1", "n1", "om1", "a.a2", "a.a1"])
        #expect(files.map(\.kind) == [.teaser, .nda, .cim, .attachment, .attachment])
    }

    @Test func deletedDocumentsAndInlineImagesAreLeftOff() {
        let files = DealFile.files(documents: documents, signedNda: nil, linkedCim: nil,
                                   messages: [message("m", at: 1, [.init(id: "img", filename: "x.png", isInline: true)])])
        #expect(!files.contains { $0.id == "gone" || $0.id == "a.img" })
    }

    @Test func theEmbeddedSignedNdaFillsInWhenTheListLacksOne() {
        // signedNda: documents.find(type === "SIGNED") || embeddedSignedNda
        let signed = Self.json(#"{"id": "s1", "filename": "Signed NDA.pdf"}"#)
        let files = DealFile.files(documents: documents, signedNda: signed, linkedCim: nil, messages: [])
        #expect(files.map(\.id) == ["t1", "n1", "s1", "om1"])

        let listed = documents + [Self.json(#"{"id": "s2", "type": "SIGNED", "filename": "Signed.pdf"}"#)]
        let both = DealFile.files(documents: listed, signedNda: signed, linkedCim: nil, messages: [])
        #expect(both.filter { $0.kind == .signedNda }.map(\.id) == ["s2"])
    }

    @Test func aLinkedCimStandsInWhenThereIsNoCimFile() {
        let link = URL(string: "https://docs.example.com/cim")!
        let withoutFile = DealFile.files(documents: [], signedNda: nil, linkedCim: link, messages: [])
        #expect(withoutFile.first?.source == .link(link))
        let withFile = DealFile.files(documents: documents, signedNda: nil, linkedCim: link, messages: [])
        #expect(!withFile.contains { $0.source == .link(link) })
    }

    @Test func theSameDocumentFromTwoSourcesIsListedOnce() {
        let files = DealFile.files(documents: documents + documents, signedNda: nil, linkedCim: nil, messages: [])
        #expect(files.count == 3)
    }

    @Test func theFormatComesFromTheExtension() {
        let file = DealFile(id: "x", kind: .cim, filename: "Neptune CIM.pdf", date: nil, source: .dealDocument(id: "x"))
        #expect(file.format == "PDF")
        #expect(DealFile(id: "y", kind: .other, filename: "README", date: nil, source: .dealDocument(id: "y")).format == nil)
    }

    @Test func contentDispositionNamesTheFile() {
        // httpGetAndDownloadOrOpen reads `filename="…"` from the same header.
        #expect(DownloadedFile.filename(fromContentDisposition: #"attachment; filename="NDA - Signed.pdf""#) == "NDA - Signed.pdf")
        #expect(DownloadedFile.filename(fromContentDisposition: "attachment; filename=CIM.pdf") == "CIM.pdf")
        #expect(DownloadedFile.filename(fromContentDisposition: "attachment; filename*=UTF-8''Q%31%20plan.xlsx") == "Q1 plan.xlsx")
        #expect(DownloadedFile.filename(fromContentDisposition: "inline") == nil)
        #expect(DownloadedFile.filename(fromContentDisposition: nil) == nil)
    }
}

// MARK: - Store

@MainActor
struct DealDetailStoreTests {
    private static let threadsJSON = """
    [{"digest": [{"id": "m1", "from_user": {"email": "j@b.com", "name": "Jordan"}, "body": "Hi", "created_at": 1000}]}]
    """

    private func makeStore(_ extra: [String: StubAPI.Response] = [:]) -> (DealDetailStore, StubAPI) {
        var responses: [String: StubAPI.Response] = [
            "deals/sellside-sidebar/d1": .json(#"{"public_id": "d1", "demand_intent": {"owned_by_account": {"name": "Bluewater"}}}"#),
            "messaging/threads": .json(Self.threadsJSON),
            "deals/d1/interaction": .json(#"[{"id": "e1", "event_type": "nudge", "source_user_id": "u9", "created_at": 500}]"#),
            "users": .json(#"[{"id": "u9", "first_name": "Sam", "last_name": "Seller"}]"#),
            "notes/deal/d1": .json(#"[{"id": "n1", "note": "First", "author": {"id": "s1", "first_name": "Sam"}, "created_at": 2000}]"#),
            "users/me": .json(#"{"id": "s1", "email": "sam@neptune.com", "first_name": "Sam", "last_name": "Seller"}"#),
        ]
        responses.merge(extra) { _, new in new }
        let api = StubAPI(responses: responses)
        let store = DealDetailStore(apiClient: api)
        store.pollInterval = .milliseconds(1)
        return (store, api)
    }

    @Test func loadsProfileFeedAndCommentsTogether() async {
        let (store, _) = makeStore()
        await store.load(dealId: "d1")
        let detail = store.detail(for: "d1")
        #expect(detail.profile?.accountName == "Bluewater")
        #expect(detail.sources.messages.map(\.id) == ["m1"])
        #expect(detail.sources.userNames["u9"] == "Sam Seller")
        #expect(detail.sources.notes.map(\.id) == ["n1"])
        #expect(store.currentUser?.id == "s1")
        #expect(store.isOwn(detail.sources.notes[0]))
    }

    @Test func aFailedConversationDoesntCostTheProfile() async {
        let (store, _) = makeStore(["messaging/threads": .failure(APIError.unknown)])
        await store.load(dealId: "d1")
        let detail = store.detail(for: "d1")
        #expect(detail.profile != nil)
        #expect(detail.feedError != nil)
        #expect(detail.hasLoadedFeed)
    }

    @Test func aNewCommentIsAddedFromItsOwnResponse() async throws {
        let (store, api) = makeStore(["notes/deal/d1": .json(#"{"id": "n2", "note": "Second", "created_at": 3000}"#)])
        try await store.addNote("Second", dealId: "d1")
        #expect(store.detail(for: "d1").sources.notes.map(\.id) == ["n2"])
        let body = try JSONDecoder().decode([String: String].self, from: api.postedBodies["notes/deal/d1"]!)
        #expect(body == ["note": "Second"])
    }

    @Test func aSentMessageShowsAtOnce() async throws {
        let (store, api) = makeStore(["messaging/messages": .json("null")])
        await store.load(dealId: "d1")
        let draft = MessageDraft(to: [.init(userId: "u1", name: "Jordan", email: "j@b.com")], subject: "Re: Hi", body: "Thanks!")
        try await store.send(draft, dealId: "d1")
        #expect(store.detail(for: "d1").sources.messages.contains { $0.body == "Thanks!" })
        #expect(api.postedBodies["messaging/messages"] != nil)
    }
    @Test func aDocumentPreviewIsWrittenThenDiscarded() async throws {
        let (store, api) = makeStore()
        api.downloads["documents/deal/d1/om1"] = DownloadedFile(data: Data("pdf".utf8), filename: "CIM.pdf")
        let file = DealFile(id: "om1", kind: .cim, filename: "Fallback.pdf", date: nil, source: .dealDocument(id: "om1"))
        let url = try await store.previewURL(for: file, dealId: "d1")
        #expect(url.lastPathComponent == "CIM.pdf", "the server's name wins")
        #expect(FileManager.default.fileExists(atPath: url.path()))
        DealFilePreview.discard(url)
        #expect(!FileManager.default.fileExists(atPath: url.path()))
    }

    @Test func anAttachmentIsFetchedThroughItsSignedURL() async throws {
        // getAttachmentUrl → { url, user_filename }, then the file itself.
        let (store, api) = makeStore(["messaging/attachments/a1": .json(#"{"url": "https://files.example.com/a1", "user_filename": "Q1.xlsx"}"#)])
        api.downloads["https://files.example.com/a1"] = DownloadedFile(data: Data("x".utf8))
        let file = DealFile(id: "a.a1", kind: .attachment, filename: "Q1.xlsx", date: nil, source: .attachment(id: "a1"))
        let url = try await store.previewURL(for: file, dealId: "d1")
        #expect(url.lastPathComponent == "Q1.xlsx")
        DealFilePreview.discard(url)
    }

    @Test func filesMergeTheSidebarAndTheDocumentsEndpoint() async {
        let (store, _) = makeStore([
            "deals/sellside-sidebar/d1": .json(#"{"public_id": "d1", "documents": [{"id": "t1", "type": "T", "filename": "Teaser.pdf"}]}"#),
            "documents/deal/d1": .json(#"[{"id": "t1", "type": "T", "filename": "Teaser.pdf"}, {"id": "n1", "type": "NDA", "filename": "NDA.pdf"}]"#),
        ])
        await store.load(dealId: "d1")
        #expect(Array(store.files(for: "d1").map(\.id).prefix(2)) == ["t1", "n1"])
    }
}
