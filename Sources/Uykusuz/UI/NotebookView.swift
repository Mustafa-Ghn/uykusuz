import AppKit
import SwiftUI

/// The notebook's window (`MacAdvisor`): the entries, oldest first, with the
/// open offer's button, Claude's notes, and a field to write back.
struct NotebookView: View {
    static let emptyText = "Henüz bir şey yazılmadı. Uykusuz, Claude API anahtarı kayıtlıyken siz Mac'in başındayken iki saatte bir bakar ve söylenecek bir şey olursa buraya yazar."
    static let offText = "Defter kapalı: Ayarlar > Defter bölümünden açabilirsiniz."
    static let notesTitle = "Uykusuz'un notları"

    let advisor: MacAdvisor
    let isOn: () -> Bool
    @State private var draft = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            entries
            if !advisor.notebook.notes.isEmpty {
                Divider()
                DisclosureGroup(Self.notesTitle) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(advisor.notebook.notes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
                }
                .padding(12)
            }
            Divider()
            composer
        }
        .frame(minWidth: 420, idealWidth: 460, minHeight: 420, idealHeight: 540)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(lastLookText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if let line = advisor.statusLine {
                    Text(line)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if advisor.isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            Button("Şimdi bak") { Task { await advisor.lookNow() } }
                .disabled(advisor.isBusy)
        }
        .padding(12)
    }

    private var lastLookText: String {
        guard let last = advisor.notebook.lastLook else { return isOn() ? "Henüz bakılmadı." : Self.offText }
        return "Son bakış: \(MacAdvisor.dayText(last))" + (isOn() ? "" : ". \(Self.offText)")
    }

    private var entries: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if advisor.notebook.entries.isEmpty {
                        Text(Self.emptyText)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ForEach(advisor.notebook.entries) { entry in
                        row(entry).id(entry.id)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .onAppear { proxy.scrollTo(advisor.notebook.entries.last?.id, anchor: .bottom) }
            .onChange(of: advisor.notebook.entries.count) {
                withAnimation { proxy.scrollTo(advisor.notebook.entries.last?.id, anchor: .bottom) }
            }
        }
    }

    private func row(_ entry: Notebook.Entry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(entry.author == .user ? "Siz" : "Uykusuz")
                    .fontWeight(.semibold)
                Text(MacAdvisor.dayText(entry.date))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(entry.text)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if let offer = entry.offer {
                if offer.state == .open {
                    HStack {
                        Button(offer.actionTitle) { Task { await advisor.accept(entry.id) } }
                            .buttonStyle(.borderedProminent)
                        Button("Gerek yok") { advisor.decline(entry.id) }
                    }
                    .disabled(advisor.isBusy)
                    .padding(.top, 2)
                } else {
                    Text("\(offer.actionTitle): \(MacAdvisor.stateName(offer.state))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom) {
            TextField("Yanıtınız", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Gönder", action: send)
                .disabled(advisor.isBusy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(12)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !advisor.isBusy else { return }
        draft = ""
        Task { await advisor.reply(text) }
    }
}

/// The notebook's window, made the first time and kept, like Settings.
@MainActor
final class NotebookWindow {
    static let title = "Uykusuz Defteri"

    private var window: NSWindow?
    private let advisor: MacAdvisor
    private let isOn: () -> Bool

    init(advisor: MacAdvisor, isOn: @escaping () -> Bool) {
        self.advisor = advisor
        self.isOn = isOn
    }

    var isVisible: Bool { window?.isVisible ?? false }

    /// An accessory app activates itself first, or the window opens behind
    /// whatever is in front.
    func show() {
        let window = window ?? make()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        advisor.markRead()
    }

    private func make() -> NSWindow {
        let host = NSHostingController(rootView: NotebookView(advisor: advisor, isOn: isOn))
        let window = NSWindow(contentViewController: host)
        window.title = Self.title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 460, height: 540))
        window.isRestorable = false
        return window
    }
}
