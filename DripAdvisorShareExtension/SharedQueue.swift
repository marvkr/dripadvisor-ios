import Foundation

/// JSONL-backed queue stored in the App Group container so the Share
/// Extension and the main app can share pending wardrobe inserts. Drained by
/// the main app on launch + on willEnterForeground.
///
/// Both targets must declare the same App Group capability for this to work:
///   group.com.dripadvisor.shared
enum SharedQueue {
    static let appGroupID = "group.com.dripadvisor.shared"
    private static let filename = "pending-wardrobe.jsonl"

    static var queueURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(filename)
    }

    static func enqueue(_ item: PendingWardrobeItem) {
        guard let url = queueURL else { return }
        guard let line = encode(item) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: line)
            }
        } else {
            try? line.write(to: url, options: .atomic)
        }
    }

    /// Drains all pending items + returns them. Called by the main app.
    static func drain() -> [PendingWardrobeItem] {
        guard let url = queueURL,
              let data = try? Data(contentsOf: url) else {
            return []
        }
        let items = parse(data)
        try? FileManager.default.removeItem(at: url)
        return items
    }

    private static func encode(_ item: PendingWardrobeItem) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var blob = try? encoder.encode(item) else { return nil }
        blob.append(0x0A)  // newline
        return blob
    }

    private static func parse(_ blob: Data) -> [PendingWardrobeItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return blob.split(separator: 0x0A).compactMap { line in
            try? decoder.decode(PendingWardrobeItem.self, from: Data(line))
        }
    }
}
