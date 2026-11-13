//
//  DealMessagesTab.swift
//  Axial Mobile
//

import SwiftUI

/// The sidebar's Messages tab — `axl-messages-feed`: thread messages,
/// status history and events, and comment markers on one timeline, oldest
/// first, grouped under a heading per day.
///
/// Read-mostly by design. Mobile replies in plain text to the people the
/// web would address (see `MessageDraft`); attachments, CC and the old
/// message center stay on the web. The Reply button is the screen's, pinned
/// above the footer, so it stays in reach however long the thread runs.
struct DealMessagesTab: View {
    let feed: [DealFeedItem]
    let isLoaded: Bool
    let error: String?
    let hasLegacyMessages: Bool
    /// The viewer's own messages read as "You", on a tinted card.
    let isMine: (DealMessage) -> Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if hasLegacyMessages {
                FormNotice(style: .info, message: "Looking for older messages? They're in the original message center on the web.")
            }
            if !isLoaded, feed.isEmpty {
                DealCardSkeleton(rows: 2)
                    .transition(.opacity)
            } else if let error, feed.isEmpty {
                DealTabError(title: "Couldn't load messages", message: error, onRetry: onRetry)
            } else if feed.isEmpty {
                EmptyStateCard(message: "No messages or activity yet.")
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(DealFeedDay.days(feed)) { day in
                        DayHeading(day: day.day)
                        ForEach(day.items) { item in
                            DealFeedRow(item: item, isMine: isMine)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: isLoaded)
    }
}

/// "Today", "Yesterday", or the date — this year's without the year.
private struct DayHeading: View {
    let day: Date

    private var text: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        let thisYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
        return thisYear
            ? day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            : day.formatted(.dateTime.month(.abbreviated).day().year())
    }

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(AxialColor.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct DealFeedRow: View {
    let item: DealFeedItem
    let isMine: (DealMessage) -> Bool

    var body: some View {
        switch item.kind {
        case .message(let message):
            MessageCard(message: message, isMine: isMine(message))
        case .activity(let text, let detail):
            ActivityRow(systemImage: "clock.arrow.circlepath", text: text, detail: detail, date: item.date)
        case .comment(let author):
            ActivityRow(systemImage: "bubble.left", text: "\(author) added an internal comment.",
                        detail: nil, date: item.date)
        }
    }
}

/// One message. Unread ones open expanded, as the web's feed does; read
/// ones clamp to a few lines and expand on tap. Your own sit on a brand
/// tint, so the two sides of the conversation read apart at a glance.
private struct MessageCard: View {
    let message: DealMessage
    let isMine: Bool

    @State private var isExpanded: Bool

    init(message: DealMessage, isMine: Bool) {
        self.message = message
        self.isMine = isMine
        _isExpanded = State(initialValue: message.isUnread)
    }

    /// `collapsedRecipients`: two names, then a count.
    private var recipients: String {
        let names = message.to.map(\.displayName)
        let shown = names.prefix(2).joined(separator: ", ")
        let more = names.count - 2 + message.cc.count
        return "To \(shown)" + (more > 0 ? " +\(more)" : "")
    }

    private var attachments: [DealMessage.Attachment] {
        message.attachments.filter { !$0.isInline }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                PersonAvatar(name: message.from.displayName, url: nil, size: 28)
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Text(isMine ? "You" : message.from.displayName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AxialColor.textPrimary)
                            .lineLimit(1)
                        if message.isUnread {
                            Circle().fill(AxialColor.brandPrimary).frame(width: 7, height: 7)
                                .accessibilityLabel("Unread")
                        }
                    }
                    if !message.to.isEmpty {
                        Text(recipients)
                            .font(.caption)
                            .foregroundStyle(AxialColor.textSecondary)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Text(message.sentAt, format: .dateTime.hour().minute())
                    .font(.caption)
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
            if let subject = message.subject {
                Text(subject)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AxialColor.textPrimary)
            }
            if !message.body.isEmpty {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(AxialColor.textPrimary)
                    .lineLimit(isExpanded ? nil : 4)
                    .textSelection(.enabled)
            }
            if !attachments.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(attachments) {
                        TagCapsule(text: $0.filename, palette: .plain, systemImage: "paperclip")
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isMine ? AxialColor.brandSubtle : AxialColor.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(message.isUnread ? AxialColor.brandPrimary.opacity(0.4)
                          : isMine ? AxialColor.brandPrimary.opacity(0.12) : AxialColor.border))
        .shadow(color: CardShadow.color, radius: CardShadow.radius, y: CardShadow.y)
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture {
            withAnimation(.snappy) { isExpanded.toggle() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(isExpanded ? "" : "Shows the whole message")
    }
}

/// A status change, event or comment marker: a quiet line between messages,
/// with any note it carried behind a disclosure.
private struct ActivityRow: View {
    let systemImage: String
    let text: String
    let detail: String?
    let date: Date

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(AxialColor.textPlaceholder)
                Text(text)
                    .font(.footnote)
                    .foregroundStyle(AxialColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(date, format: .dateTime.hour().minute())
                    .font(.caption2)
                    .foregroundStyle(AxialColor.textPlaceholder)
            }
            if let detail {
                Button(isExpanded ? "Hide Message" : "Show Message") {
                    withAnimation(.snappy) { isExpanded.toggle() }
                }
                .font(.caption.weight(.semibold))
                .tint(AxialColor.brandPrimary)
                .padding(.leading, 22)
                if isExpanded {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(AxialColor.textPrimary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AxialColor.layer3, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.leading, 22)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }
}
