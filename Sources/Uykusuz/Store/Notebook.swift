import Foundation

/// The notebook (`defter.json`, owner-only like the rest of the app's files):
/// what Uykusuz noticed and said, the user's replies, the one thing it offers
/// to do, and the notes Claude keeps from one look to the next (`MacAdvisor`).
struct Notebook: Codable, Equatable, Sendable {
    struct Entry: Codable, Equatable, Identifiable, Sendable {
        enum Author: String, Codable, Sendable {
            case uykusuz
            case user
        }

        var id = UUID()
        var date: Date
        var author: Author
        var text: String
        var offer: Offer?
    }

    /// Something Uykusuz does only once the user says yes.
    struct Offer: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable, CaseIterable {
            case shutdownSimulator = "shutdown_simulator"
            case quitApp = "quit_app"
            case stopContainer = "stop_container"
        }

        enum State: String, Codable, Sendable {
            case open
            case done
            case declined
            case failed
            /// What it was for went away, or a newer offer took its place.
            case expired
        }

        var kind: Kind
        /// The simulator's UDID, the app's bundle id or the container's id.
        var target: String
        /// What the snapshot called it.
        var label: String
        var state: State = .open

        /// The button that does it.
        var actionTitle: String {
            switch kind {
            case .shutdownSimulator: "\(label) simülatörünü kapat"
            case .quitApp: "\(label) uygulamasından çık"
            case .stopContainer: "\(label) kapsayıcısını durdur"
            }
        }

        /// What it did, for the notebook.
        func outcome(succeeded: Bool) -> String {
            switch (kind, succeeded) {
            case (.shutdownSimulator, true): "\(label) simülatörünü kapattım."
            case (.shutdownSimulator, false): "\(label) simülatörü kapatılamadı."
            case (.quitApp, true): "\(label) uygulamasından çıkılmasını istedim; kaydedilmemiş bir şey varsa uygulama sorar."
            case (.quitApp, false): "\(label) uygulamasından çıkılamadı."
            case (.stopContainer, true): "\(label) kapsayıcısını durdurdum; docker start ile yeniden açılır."
            case (.stopContainer, false): "\(label) kapsayıcısı durdurulamadı."
            }
        }
    }

    var entries: [Entry] = []
    var notes: [String] = []
    var lastLook: Date?
    var lastNotified: Date?
    /// When the user last had the notebook open.
    var lastRead: Date?

    static let maxEntries = 300
    static let maxNotes = 12
    static let maxNoteLength = 200

    /// The offer still waiting for an answer, newest first; at most one is open.
    var openOffer: (entry: Entry, offer: Offer)? {
        for entry in entries.reversed() {
            if let offer = entry.offer, offer.state == .open { return (entry, offer) }
        }
        return nil
    }

    /// What Uykusuz wrote since the user last looked.
    var unread: Int {
        entries.filter { $0.author == .uykusuz && $0.date > (lastRead ?? .distantPast) }.count
    }

    /// Adds an entry, keeping one offer open and the newest `maxEntries`.
    mutating func append(_ entry: Entry) {
        if entry.offer?.state == .open { closeOpenOffer(as: .expired) }
        entries.append(entry)
        if entries.count > Self.maxEntries { entries.removeFirst(entries.count - Self.maxEntries) }
    }

    mutating func closeOpenOffer(as state: Offer.State) {
        guard let open = openOffer, let index = entries.firstIndex(where: { $0.id == open.entry.id }) else { return }
        entries[index].offer?.state = state
    }

    mutating func setOffer(of id: UUID, to state: Offer.State) {
        guard let index = entries.firstIndex(where: { $0.id == id }), entries[index].offer != nil else { return }
        entries[index].offer?.state = state
    }

    /// Claude's notes as kept: trimmed, short and few.
    mutating func replaceNotes(_ notes: [String]) {
        self.notes = notes
            .map { String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNoteLength)) }
            .filter { !$0.isEmpty }
            .prefix(Self.maxNotes)
            .map(\.self)
    }

    /// Declined within `within`: the same thing is not offered again before that.
    func wasDeclined(kind: Offer.Kind, target: String, since: Date) -> Bool {
        entries.contains { entry in
            guard let offer = entry.offer else { return false }
            return offer.kind == kind && offer.target == target && offer.state == .declined && entry.date >= since
        }
    }
}

extension Store {
    func loadNotebook() -> Notebook {
        do {
            return try read(Notebook.self, from: paths.notebookFile) ?? Notebook()
        } catch {
            Log.error("notebook: could not read \(paths.notebookFile.lastPathComponent) (\(error.localizedDescription)); starting an empty one")
            return Notebook()
        }
    }

    func saveNotebook(_ notebook: Notebook) throws {
        try write(notebook, to: paths.notebookFile)
    }
}
