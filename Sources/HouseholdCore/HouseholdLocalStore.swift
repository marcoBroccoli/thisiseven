import Foundation

public struct IgnoredSenderRule: Equatable, Codable, Hashable, Sendable {
    public var value: String

    public init(value: String) {
        self.value = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func matches(sender: String) -> Bool {
        normalized(sender) == normalized(value)
    }

    private func normalized(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

public struct LocalReplyDraft: Equatable, Codable, Sendable {
    public var draftID: UUID
    public var body: String

    public init(draftID: UUID, body: String) {
        self.draftID = draftID
        self.body = body
    }
}

public struct LocalHouseholdState: Equatable, Codable, Sendable {
    public var drafts: [InboxDraft]
    public var replyDrafts: [LocalReplyDraft]
    public var lastCalendarSyncAt: Date?
    public var ignoredSenders: [IgnoredSenderRule]

    public init(
        drafts: [InboxDraft] = [],
        replyDrafts: [LocalReplyDraft] = [],
        lastCalendarSyncAt: Date? = nil,
        ignoredSenders: [IgnoredSenderRule] = []
    ) {
        self.drafts = drafts
        self.replyDrafts = replyDrafts
        self.lastCalendarSyncAt = lastCalendarSyncAt
        self.ignoredSenders = ignoredSenders
    }

    private enum CodingKeys: String, CodingKey {
        case drafts
        case replyDrafts
        case lastCalendarSyncAt
        case ignoredSenders
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        drafts = try container.decodeIfPresent([InboxDraft].self, forKey: .drafts) ?? []
        replyDrafts = try container.decodeIfPresent([LocalReplyDraft].self, forKey: .replyDrafts) ?? []
        lastCalendarSyncAt = try container.decodeIfPresent(Date.self, forKey: .lastCalendarSyncAt)
        ignoredSenders = try container.decodeIfPresent([IgnoredSenderRule].self, forKey: .ignoredSenders) ?? []
    }

    public func replyText(for draftID: UUID) -> String? {
        replyDrafts.first { $0.draftID == draftID }?.body
    }

    public mutating func setReplyText(_ body: String, for draftID: UUID) {
        if let index = replyDrafts.firstIndex(where: { $0.draftID == draftID }) {
            replyDrafts[index].body = body
        } else {
            replyDrafts.append(LocalReplyDraft(draftID: draftID, body: body))
        }
    }

    public func mergingImportedDrafts(_ importedDrafts: [InboxDraft]) -> LocalHouseholdState {
        var merged = self
        let existingMessageIDs = Set(drafts.map(\.source.gmailMessageID))
        let newDrafts = importedDrafts.filter { draft in
            !existingMessageIDs.contains(draft.source.gmailMessageID)
                && !ignoredSenders.contains(where: { rule in rule.matches(sender: draft.source.from) })
        }
        merged.drafts.append(contentsOf: newDrafts)
        return merged
    }

    public mutating func ignoreSender(_ sender: String) {
        let rule = IgnoredSenderRule(value: sender)
        guard !ignoredSenders.contains(where: { $0.matches(sender: sender) }) else { return }
        ignoredSenders.append(rule)
    }
}

public struct HouseholdLocalStore: Sendable {
    public var fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> LocalHouseholdState {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return LocalHouseholdState()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(LocalHouseholdState.self, from: data)
    }

    public func save(_ state: LocalHouseholdState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: [.atomic])
    }
}
