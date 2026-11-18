//
//  DealDetailStore.swift
//  Axial Mobile
//

import Foundation
import Observation

/// Everything the deal screen holds beyond the list row: the buyer's
/// profile, the conversation and the internal comments.
///
/// App-scoped and keyed by deal id, like `ProjectDashboardStore`, so paging
/// back to a deal you've seen renders from cache.
///
/// The row itself — status, interest, NDA — stays in `ProjectDashboardStore`
/// and is read from there. Status actions on this screen go through that
/// store too, so the card in the list and the screen you're on can't drift.
///
/// The four requests are independent, as they are on the web
/// (`fetchSingleContactedTarget$` plus the notes and interactions effects):
/// a failed conversation doesn't cost the profile, and the screen's header
/// never waits on any of them because it's borrowed from the row.
@Observable
final class DealDetailStore {
    struct Detail: Equatable {
        var profile: DealProfile?
        var sources = DealFeedSources()
        var hasLoadedProfile = false
        var hasLoadedFeed = false
        var hasLoadedNotes = false
        /// `GET /documents/deal/{id}`. Merged with the profile's own
        /// `documents`, so the Files tab doesn't depend on either alone.
        var documents: [JSONValue] = []
        var profileError: String?
        var feedError: String?
        var notesError: String?
    }

    /// One observable box per deal, in a dictionary that isn't itself
    /// observed. A screen reading `detail(for:)` then depends on its own
    /// deal only. With one observed `[String: Detail]`, every update to any
    /// deal redrew every open deal screen, and opening one, with its
    /// neighbours warming behind it, meant fifteen-odd full redraws during
    /// the zoom transition.
    @ObservationIgnored private var entries: [String: Entry] = [:]
    private(set) var currentUser: CurrentUser?

    @Observable
    final class Entry {
        var detail = Detail()
    }

    private let apiClient: any APIRequesting
    private var inFlight: [String: Task<Void, Never>] = [:]

    /// How long to wait between polls for a sent message to show up. Tests
    /// turn it down.
    var pollInterval: Duration = .seconds(2)

    init(apiClient: any APIRequesting) {
        self.apiClient = apiClient
        // Anything a previous run left mid-preview.
        DealFilePreview.purge()
    }

    func detail(for dealId: String) -> Detail {
        entry(for: dealId).detail
    }

    /// Made on first read, without notifying anyone: the dictionary is
    /// bookkeeping, and the entry is what views observe.
    private func entry(for dealId: String) -> Entry {
        if let existing = entries[dealId] { return existing }
        let made = Entry()
        entries[dealId] = made
        return made
    }

    /// The Messages timeline, worded with what we know of both sides.
    func feed(for dealId: String, row: SellsideDeal?) -> [DealFeedItem] {
        let detail = detail(for: dealId)
        return DealFeedItem.feed(from: detail.sources, names: DealFeedNames(profile: detail.profile, deal: row))
    }

    /// The Files tab: the deal's documents, then message attachments.
    func files(for dealId: String) -> [DealFile] {
        let detail = detail(for: dealId)
        return DealFile.files(documents: (detail.profile?.documents ?? []) + detail.documents,
                              signedNda: detail.profile?.signedNda,
                              linkedCim: detail.profile?.linkedCim,
                              messages: detail.sources.messages)
    }

    func loadIfNeeded(dealId: String) async {
        guard !detail(for: dealId).hasLoadedProfile else { return }
        await load(dealId: dealId)
    }

    /// Fetches everything for a deal. Concurrent loads of the same deal
    /// collapse into one.
    func load(dealId: String) async {
        if let existing = inFlight[dealId] { return await existing.value }
        let task = Task {
            async let profile: Void = loadProfile(dealId)
            async let feed: Void = loadFeed(dealId)
            async let notes: Void = loadNotes(dealId)
            async let documents: Void = loadDocuments(dealId)
            async let me: Void = loadCurrentUserIfNeeded()
            _ = await (profile, feed, notes, documents, me)
        }
        inFlight[dealId] = task
        await task.value
        inFlight[dealId] = nil
    }

    // MARK: - Loading

    /// `GET /deals/sellside-sidebar/{id}`.
    private func loadProfile(_ dealId: String) async {
        do {
            let json: JSONValue = try await apiClient.get("deals/sellside-sidebar/\(dealId)")
            update(dealId) {
                $0.profile = DealProfile(json: json)
                $0.hasLoadedProfile = true
                $0.profileError = nil
            }
        } catch {
            update(dealId) {
                $0.hasLoadedProfile = true
                // A failed refresh keeps the profile already on screen.
                if $0.profile == nil { $0.profileError = error.localizedDescription }
            }
        }
    }

    /// Threads and interactions — `GET /messaging/threads?deal_ids=` and
    /// `GET /deals/{id}/interaction` — then the names behind the events'
    /// user ids, `GET /users?ids=` (the web chunks those by 40).
    func loadFeed(_ dealId: String) async {
        do {
            async let threads: JSONValue = apiClient.get(
                "messaging/threads", query: [URLQueryItem(name: "deal_ids", value: dealId)], headers: [:])
            async let interactions: JSONValue = apiClient.get("deals/\(dealId)/interaction")
            let messages = try await DealMessage.messages(fromThreads: threads)
            let parsed = try await (interactions.array ?? []).compactMap(DealInteraction.init(json:))
            let names = await userNames(for: Array(Set(parsed.flatMap(\.userIds))))
            update(dealId) {
                $0.sources.messages = messages
                $0.sources.interactions = parsed
                $0.sources.userNames.merge(names) { _, new in new }
                $0.hasLoadedFeed = true
                $0.feedError = nil
            }
        } catch {
            update(dealId) {
                $0.hasLoadedFeed = true
                if $0.sources.messages.isEmpty, $0.sources.interactions.isEmpty {
                    $0.feedError = error.localizedDescription
                }
            }
        }
    }

    /// `GET /notes/deal/{id}`.
    private func loadNotes(_ dealId: String) async {
        do {
            let json: JSONValue = try await apiClient.get("notes/deal/\(dealId)")
            let notes = (json.array ?? []).compactMap(DealNote.init(json:))
            update(dealId) {
                $0.sources.notes = notes
                $0.hasLoadedNotes = true
                $0.notesError = nil
            }
        } catch {
            update(dealId) {
                $0.hasLoadedNotes = true
                if $0.sources.notes.isEmpty { $0.notesError = error.localizedDescription }
            }
        }
    }

    /// `GET /documents/deal/{id}` — `DealApiService.fetchDealDocuments`. Best
    /// effort: the sidebar payload carries the deal's documents too.
    private func loadDocuments(_ dealId: String) async {
        guard let json: JSONValue = try? await apiClient.get("documents/deal/\(dealId)") else { return }
        update(dealId) { $0.documents = json.array ?? [] }
    }

    private func loadCurrentUserIfNeeded() async {
        guard currentUser == nil else { return }
        if let json: JSONValue = try? await apiClient.get("users/me") {
            currentUser = CurrentUser(json: json)
        }
    }

    private func userNames(for ids: [String]) async -> [String: String] {
        guard !ids.isEmpty else { return [:] }
        var names: [String: String] = [:]
        for start in stride(from: 0, to: ids.count, by: 40) {
            let chunk = ids[start..<min(start + 40, ids.count)]
            let users: JSONValue? = try? await apiClient.get(
                "users", query: [URLQueryItem(name: "ids", value: chunk.joined(separator: ","))], headers: [:])
            for user in users?.array ?? [] {
                if let person = DealProfile.Person(json: user) { names[person.id] = person.fullName }
            }
        }
        return names
    }

    // MARK: - Comments

    /// `POST /notes/deal/{id}` with `{ note }`. The response is the note, so
    /// it's added from that rather than by refetching the list.
    func addNote(_ text: String, dealId: String) async throws {
        let json: JSONValue = try await apiClient.post("notes/deal/\(dealId)", body: ["note": text] as [String: String])
        guard let note = DealNote(json: json) else { throw APIError.unknown }
        update(dealId) { $0.sources.notes.append(note) }
    }

    /// `DELETE /notes/{id}`.
    func deleteNote(_ note: DealNote, dealId: String) async throws {
        try await apiClient.delete("notes/\(note.id)")
        update(dealId) { $0.sources.notes.removeAll { $0.id == note.id } }
    }

    /// Only your own comments can be edited or deleted — the web's
    /// `note.author.id === currentUser.id`.
    func isOwn(_ note: DealNote) -> Bool {
        guard let me = currentUser, let author = note.authorId else { return false }
        return me.id == author
    }

    /// A message the viewer sent — shown as "You" in the conversation.
    func isMine(_ message: DealMessage) -> Bool {
        guard let me = currentUser, let sender = message.from.userId else { return false }
        return me.id == sender
    }

    // MARK: - Messages

    /// Sends a reply. The endpoint answers with nothing, so — as the web
    /// does — the message shows straight away from what was sent, and the
    /// threads are polled until the server's copy replaces it.
    func send(_ draft: MessageDraft, dealId: String) async throws {
        if currentUser == nil { await loadCurrentUserIfNeeded() }
        guard let me = currentUser else { throw APIError.unknown }
        let _: JSONValue = try await apiClient.post("messaging/messages", body: draft.request(dealId: dealId, from: me))

        let known = Set(detail(for: dealId).sources.messages.map(\.id))
        let local = DealMessage(
            id: "local-\(UUID().uuidString)",
            from: .init(userId: me.id, name: me.fullName, email: me.email),
            to: draft.to, cc: [], subject: draft.subject,
            body: draft.body.trimmingCharacters(in: .whitespacesAndNewlines),
            sentAt: .now, isUnread: false, attachments: [], type: "user_message"
        )
        update(dealId) { $0.sources.messages.append(local) }

        Task {
            for _ in 0..<5 {
                try? await Task.sleep(for: pollInterval)
                await loadFeed(dealId)
                if detail(for: dealId).sources.messages.contains(where: { !known.contains($0.id) && !$0.id.hasPrefix("local-") }) {
                    return
                }
                // Not there yet: put the local copy back for the next poll.
                if !detail(for: dealId).sources.messages.contains(where: { $0.id == local.id }) {
                    update(dealId) { $0.sources.messages.append(local) }
                }
            }
        }
    }

    // MARK: - Files

    /// Downloads a file and writes it where QuickLook can open it. The caller
    /// discards it when the preview closes (`DealFilePreview.discard`).
    ///
    /// A deal document is one call (`downloadDealDocument`). An attachment is
    /// two: the API hands back a signed URL (`getAttachmentUrl`), and the
    /// file comes from there.
    func previewURL(for file: DealFile, dealId: String) async throws -> URL {
        let downloaded: DownloadedFile
        switch file.source {
        case .dealDocument(let id):
            downloaded = try await apiClient.download("documents/deal/\(dealId)/\(id)")
        case .attachment(let id):
            let link: JSONValue = try await apiClient.get("messaging/attachments/\(id)")
            guard let url = link["url"]?.text.flatMap(URL.init(string:)) else { throw APIError.unknown }
            downloaded = try await apiClient.download(from: url)
        case .link(let url):
            return url
        }
        return try DealFilePreview.write(downloaded, suggestedName: file.filename)
    }

    // MARK: - Contact

    /// `GET /deals/{id}/phone-number` — fetched on demand, as the web's
    /// Copy Phone Number does, so the number isn't loaded for every deal.
    func phoneNumber(dealId: String) async throws -> String {
        let json: JSONValue = try await apiClient.get("deals/\(dealId)/phone-number")
        guard let number = json["full_number"]?.text ?? json["e164"]?.text ?? json["number"]?.text else {
            throw APIError.unknown
        }
        return number
    }

    private func update(_ dealId: String, _ change: (inout Detail) -> Void) {
        let box = entry(for: dealId)
        var detail = box.detail
        change(&detail)
        // Unchanged (a refresh that brought the same thing back) notifies
        // nobody.
        if detail != box.detail { box.detail = detail }
    }
}
