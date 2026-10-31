import AppKit
import SwiftUI

/// The settings window (spec 10). Every change is written straight through
/// `manager.config` to config.json.
struct SettingsView: View {
    let manager: SessionManager
    let secrets: any HotspotSecretStore
    let locationPermission: LocationPermission
    /// Launch at login as macOS reports it, not as config.json remembers it.
    let loginItem: LoginItem
    /// "While you were away" (fork addition); nil leaves its section out.
    var awaySummary: AwaySummary? = nil
    /// Claude's reply read aloud (fork addition); nil leaves its section out.
    var replyReader: ClaudeReplyReader? = nil
    /// iMessage when Claude waits (fork addition); nil leaves it out.
    var waitingAlerts: WaitingAlerts? = nil
    /// Replies from the phone (fork addition); nil leaves them out.
    var pushGate: ClaudePushGate? = nil

    @State private var newPreset = ""
    @State private var presetError: String?
    @State private var newFreezeBundle = ""
    @State private var newAgentBundle = ""
    @State private var newTmuxTarget = ""
    /// The password field, saving, what was saved, and the notice under
    /// the field.
    @State private var hotspot = HotspotPasswordField()
    /// Names of the apps the automatic lid-close scope would freeze right
    /// now (the freeze list excluded); refreshed on appear and toggle.
    @State private var wouldFreeze: [String] = []
    /// Whether ~/.claude/settings.json runs this app's hook, and the last
    /// install or removal error.
    /// macOS's "Ask to join hotspots", which the failover wants on Otomatik.
    @State private var hotspotJoinMode: HotspotJoinMode?
    /// The Turkish voice alerts and summaries are spoken in.
    @State private var voiceChoice: TurkishVoice.Choice?
    @State private var apiKeyDraft = ""
    @State private var apiKeyStatus = "\u{2026}"
    @State private var apiKeySaved = false
    @State private var apiKeyBusy = false
    @State private var claudeHooksInstalled = ClaudeHooks.isInstalled()
    @State private var claudeHooksError: String?
    @State private var phoneRepliesError: String?

    var body: some View {
        Form {
            sessionSection
            lidSection
            agentSection
            powerSection
            agentModeSection
            if awaySummary != nil {
                awaySummarySection
            }
            if replyReader != nil {
                replyReadingSection
            }
            if pushGate != nil {
                phoneRepliesSection
            }
            if waitingAlerts != nil {
                waitingAlertsSection
            }
            networkSection
            appSection
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .frame(minHeight: 560, idealHeight: 720)
        .onAppear {
            loadPassword()
            refreshWouldFreeze()
            // The user may have approved or removed the item in System
            // Settings since the launch-time check (LoginItem also re-reads
            // whenever the app becomes active, for a window left open).
            loginItem.refresh()
        }
        // The failover may find the saved password unreadable while the
        // window is open, and an SSID edit makes the notice about another
        // hotspot's item: the notice follows both.
        .onChange(of: manager.services?.status.hotspotPasswordReport) { recheckPassword() }
        .onChange(of: HotspotSSID.normalized(manager.config.hotspotSSID)) { recheckPassword() }
        // The preview depends on the toggle, both lists and what is running:
        // recompute on any config change and whenever an app launches or quits.
        .onChange(of: manager.config) { refreshWouldFreeze() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in refreshWouldFreeze() }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in refreshWouldFreeze() }
    }

    // MARK: Bindings

    private func bind<T: Equatable>(_ keyPath: WritableKeyPath<Config, T>) -> Binding<T> {
        Binding(
            get: { manager.config[keyPath: keyPath] },
            set: { value in
                guard manager.config[keyPath: keyPath] != value else { return }
                manager.config[keyPath: keyPath] = value
                save()
            }
        )
    }

    private func save() {
        do {
            try manager.store.saveConfig(manager.config)
        } catch {
            Log.error("could not save config: \(error.localizedDescription)")
        }
    }

    private func update(_ change: (inout Config) -> Void) {
        var c = manager.config
        change(&c)
        guard c != manager.config else { return }
        manager.config = c
        save()
    }

    /// The floor steppers go through the Config setters, which move the
    /// other floor when the two would cross.
    private var lowPowerFloor: Binding<Int> {
        Binding(get: { manager.config.lowPowerFloor }, set: { v in update { $0.setLowPowerFloor(v) } })
    }

    private var endFloor: Binding<Int> {
        Binding(get: { manager.config.endFloor }, set: { v in update { $0.setEndFloor(v) } })
    }

    // MARK: Sections

    private var sessionSection: some View {
        Section("Oturum") {
            ForEach(manager.config.presets, id: \.self) { p in
                HStack {
                    Text(chipLabel(for: p))
                        .monospacedDigit()
                    Spacer()
                    if p == manager.config.defaultPreset {
                        Text("varsayılan").font(.caption).foregroundStyle(.secondary)
                    }
                    removeButton {
                        update { $0.presets.removeAll { $0 == p } }
                    }
                }
            }
            HStack {
                TextField("Hazır süre ekle (30dk, 2sa, 1sa30dk, 3g)", text: $newPreset)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addPreset)
                Button("Ekle", action: addPreset)
                    .disabled(DurationParser.seconds(from: newPreset) == nil)
            }
            if let presetError {
                Text(presetError).font(.caption).foregroundStyle(.red)
            }
            Picker("Varsayılan hazır süre", selection: bind(\.defaultPreset)) {
                ForEach(manager.config.presets, id: \.self) { p in
                    Text(chipLabel(for: p)).tag(p)
                }
                if !manager.config.presets.contains(manager.config.defaultPreset) {
                    Text(chipLabel(for: manager.config.defaultPreset)).tag(manager.config.defaultPreset)
                }
            }
            Picker("Varsayılan alan", selection: bind(\.defaultFocusField)) {
                ForEach(DurationInput.Field.allCases, id: \.self) { field in
                    Text(field.placeholder).tag(field)
                }
            }
            .help("Süre alanları açıldığında odaklanan alan")
            LabeledContent("En uzun oturum") {
                Text(chipLabel(for: manager.config.maxDuration)).foregroundStyle(.secondary)
            }
        }
    }

    private func addPreset() {
        guard let s = DurationParser.seconds(from: newPreset) else { return }
        guard s <= manager.config.maxDuration else {
            presetError = "Hazır süre en fazla \(chipLabel(for: manager.config.maxDuration)) olabilir."
            return
        }
        presetError = nil
        update {
            if !$0.presets.contains(s) {
                $0.presets.append(s)
                $0.presets.sort()
            }
        }
        newPreset = ""
    }

    /// Under the mute toggle and in the README. Apple Platform Security,
    /// "Hardware microphone disconnect".
    static let microphoneNote = "Apple çipli ya da T2 çipli Mac dizüstü bilgisayarlarda kapağı kapatmak, yerleşik mikrofonun bağlantısını donanım düzeyinde keser. Kapak kapalıyken bir toplantıyı kaydetmek için AirPods ya da harici bir mikrofon gerekir."

    private var lidSection: some View {
        Section {
            // The one-time lid-close update, for a user who has
            // notifications turned off. Stays until dismissed.
            if let notice = manager.config.lidCloseDefaultsNotice {
                HStack(alignment: .firstTextBaseline) {
                    Text(notice.settingsLine)
                        .font(.callout)
                    Spacer()
                    Button("Kapat") { manager.dismissLidCloseNotice() }
                }
            }
            Toggle("Ekranı ve klavye arka ışığını kapat", isOn: bind(\.darkenDisplayOnLidClose))
            ForEach(manager.darkenRefusals, id: \.self) { reason in
                Text(reason)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            bundleList(
                title: "Kapak kapalıyken dondurulacaklar",
                items: manager.config.freezeList,
                newValue: $newFreezeBundle,
                add: { id in update { if !$0.freezeList.contains(id) { $0.freezeList.append(id) } } },
                remove: { id in update { $0.freezeList.removeAll { $0 == id } } }
            )
            Toggle("Kapak kapalıyken diğer tüm uygulamaları dondur", isOn: bind(\.freezeAllApps))
            Text(wouldFreezeText)
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Çalışan kapsayıcı yokken Docker Desktop'ı duraklat", isOn: bind(\.dockerRule))
            Text("Varsayılan olarak kapalıdır. Açıkken Docker Desktop, yalnızca duraklatmadan hemen önce yapılan ikinci bir denetim de çalışan kapsayıcı bulamazsa duraklatılır; tam o son anda başlayan bir kapsayıcı da onunla birlikte duraklatılır.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Kapak kapanınca sesi kapat", isOn: bind(\.muteOnLidClose))
            Text(Self.microphoneNote)
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Kapak kapalıyken Düşük Güç Modu", isOn: bind(\.lowPowerOnLidClose))
                // A floor input: apply it now if the lid is already closed.
                .onChange(of: manager.config.lowPowerOnLidClose) { manager.services?.reevaluateFloors() }
            Toggle("Kapak kapalıyken sesli uyar (pil, ısı, oturum sonu)", isOn: bind(\.voiceAlerts))
            Text("Kapak kapalıyken bildirimler görünmez. Uykusuz sesi bir an açar, uyarıyı Türkçe söyler ve eski ses ayarını geri koyar.")
                .font(.callout)
                .foregroundStyle(.secondary)
            LabeledContent("Ses") {
                HStack {
                    Text(voiceChoice?.label ?? "\u{2026}")
                        .foregroundStyle(.secondary)
                    Button("Dinle") {
                        Task { await SaySpeech().speak(Self.voiceSample) }
                    }
                }
            }
            .task { voiceChoice = await TurkishVoice.current(fresh: true) }
            if voiceChoice?.quality == .basic {
                Text("Daha doğal bir ses için Sistem Ayarları > Erişilebilirlik > Seslendirilen İçerik > Sistem sesi bölümünden Türkçe \"Yelda (Gelişmiş)\" sesini indirin. Uykusuz kurulu en iyi Türkçe sesi kendiliğinden kullanır.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Kapak kapanınca yapılacaklar")
        } footer: {
            Text("Yukarıdaki listede bulunan uygulamalar kapak kapalıyken SIGSTOP ile dondurulur ve kapak açılınca çözülür. \"Diğer tüm uygulamaları dondur\" açıkken (varsayılan olarak açık) Dock'taki diğer tüm uygulamalar da dondurulur; ajan uygulamaları, Apple uygulamaları, Docker Desktop ve yerleşik olarak korunan uygulamalar (düzenleyiciler, terminaller, tarayıcılar, yapay zekâ uygulamaları, parola yöneticileri, yerel veritabanları, Tailscale, ProtonVPN, AnyDesk, yerel model sunucuları ve Zoom, Teams, Webex, Wispr Flow, Granola, Otter, OBS ve Loom gibi toplantı, kayıt ve dikte uygulamaları) bunun dışındadır. Ajan uygulamaları hiçbir zaman dondurulmaz. Ekran parlaklığı ve klavye arka ışığı kaydedilir, sıfıra indirilir ve kapak açılınca geri yüklenir. Kapağı açtığınızda Uykusuz çalışmıyorsa parlaklık artırma tuşuna basın.")
        }
    }

    private var agentSection: some View {
        Section {
            bundleList(
                title: "Asla kısıtlanmayacak veya dondurulmayacaklar",
                items: manager.config.agentList,
                newValue: $newAgentBundle,
                add: { id in update { if !$0.agentList.contains(id) { $0.agentList.append(id) } } },
                remove: { id in update { $0.agentList.removeAll { $0 == id } } }
            )
            Toggle("Oturum sırasında bu uygulamalarda App Nap'i kapat", isOn: bind(\.disableAppNapForAgents))
            Text("Oturum başlarken listedeki her uygulamanın tercihlerine NSAppSleepDisabled = YES yazar, oturum bitince önceki değeri geri koyar.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } header: {
            Text("Ajan uygulamaları")
        } footer: {
            Text("Ajan uygulamaları hiçbir zaman dondurulmaz veya kısıtlanmaz. Düzenleyiciler, yapay zekâ uygulamaları, terminaller, tarayıcılar, parola yöneticileri, yerel veritabanları, Tailscale, yerel model sunucuları ve toplantı, kayıt ve dikte uygulamaları burada listelenmeseler bile otomatik kapak kapanma kapsamından korunur; bunlardan birini yukarıdaki dondurulacaklar listesine eklemek bu korumayı geçersiz kılar.")
        }
    }

    private var wouldFreezeText: String {
        guard manager.config.freezeAllApps else { return "Şu anda dondurulacaklar: yalnızca yukarıdaki liste" }
        return wouldFreeze.isEmpty ? "Şu anda dondurulacaklar: başka bir şey yok" : "Şu anda dondurulacaklar: \(wouldFreeze.joined(separator: ", "))"
    }

    /// Same planner as the lid-close action, over the apps running now.
    private func refreshWouldFreeze() {
        let selfId = Bundle.main.bundleIdentifier ?? Paths.bundleIdentifier
        wouldFreeze = FreezePlanner.automaticCandidates(config: manager.config, apps: Freezer.runningApps(), selfBundleId: selfId).map(\.name)
    }

    private var powerSection: some View {
        Section("Pil ve ısı") {
            Stepper(value: lowPowerFloor, in: 0...100, step: Config.floorStep) {
                LabeledContent("Düşük Güç Modu için pil alt sınırı", value: "%\(manager.config.lowPowerFloor)")
            }
            Stepper(value: endFloor, in: 0...Config.maxEndFloor, step: Config.floorStep) {
                LabeledContent("Oturumu bitirmek için pil alt sınırı", value: "%\(manager.config.endFloor)")
            }
            Text("0, pil nedeniyle oturumu bitirmeyi kapatır. Bitirme alt sınırı, Düşük Güç Modu alt sınırının altında kalır. Birini diğerinin üstüne getirmek onu da beraberinde kaydırır.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle("Isı kuralları (ısınınca Düşük Güç Modu, kritik düzeyde oturumu bitir)", isOn: bind(\.thermalRules))
        }
    }

    /// Fork additions: the automatic session for Claude and code mode.
    private var agentModeSection: some View {
        Section("Claude, kod modu ve ekran") {
            LabeledContent("Claude Code hook'ları") {
                HStack {
                    Text(claudeHooksInstalled ? "Kurulu" : "Kurulu değil")
                        .foregroundStyle(claudeHooksInstalled ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                    Button(claudeHooksInstalled ? "Kaldır" : "Kur") { toggleClaudeHooks() }
                }
            }
            Text(claudeHooksInstalled
                 ? "Claude yalnızca bir görev yürütürken çalışıyor sayılır: bir istek başlayıp Claude yanıtını bitirene kadar ya da Claude'un başlattığı bir komut (arka planda bile) iş yaptığı sürece. Açık bırakılıp boşta bekleyen bir komut, örneğin bir veritabanı bağlantı aracı ya da geliştirme sunucusu, son 5 dakikada işlemci kullanmadıysa sayılmaz."
                 : "Hook'lar kurulu değilken Claude uygulaması açık olduğu sürece çalışıyor sayılır. Kurulum ~/.claude/settings.json dosyasına hook ekler; dosyanın eski hâli settings.json.uykusuz-yedek olarak saklanır.")
                .font(.callout)
                .foregroundStyle(.secondary)
            if let claudeHooksError {
                Text(claudeHooksError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Toggle("Claude'un izin isteklerini otomatik onayla", isOn: bind(\.autoApprovePermissions))
                .disabled(!claudeHooksInstalled)
            Text("Açıkken Uykusuz, Claude'un komut çalıştırma, dosya düzenleme ve araç kullanma izinlerini sizin yerinize hemen onaylar; plan modunda da sizi bekletmez. Claude'un soruları ve plan onayları size kalır; Claude ayarlarınızdaki deny kuralları yine geçerlidir. Bu, bypass moduna yakın bir güvenlik düzeyidir: Claude'un okuduğu bir içerik onu zararlı bir komuta yönlendirirse o komut da onaylanır. Hook'ların kurulu olması gerekir; yeni açılan oturumlarda geçerli olur.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Claude çalışırken otomatik oturum", isOn: bind(\.autoSession))
            Text("Claude bir görev yürüttüğü sürece oturum kendiliğinden başlar ve uzar; Claude \(Int(manager.config.autoIdleGrace / 60)) dakika çalışmayınca biter. Bu oturumda menü çubuğunda geri sayım yerine \"Claude\" yazar. Kapak kapansa da Mac uyanık kalır, bu yüzden Mac'i kapalı bir çantaya koymayın. \"Claude\" yazısına tıklayıp bir süre girerseniz oturum sizin olur ve o andan itibaren girdiğiniz süre kadar sürer. Oturumu basılı tutarak bitirirseniz otomatik oturumu duraklatmak için süre seçebilirsiniz; duraklatma sağ tık menüsünden de açılıp kapatılır.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Claude yanıt beklerken oturumu bitir", isOn: bind(\.endWhileWaiting))
            Stepper(value: bind(\.approvalWaitGrace), in: 60...3600, step: 60) {
                LabeledContent("Bekleme süresi", value: "\(Int(manager.config.approvalWaitGrace / 60)) dk")
            }
            .disabled(!manager.config.endWhileWaiting)
            Text(manager.config.phoneReplies && manager.config.phoneReplyWindow > manager.config.approvalWaitGrace
                 ? "Telefondan yanıt açık olduğu için bekleme \(Int(manager.config.autoWaitGrace / 60)) dakika sürer (Telefondan yanıt bölümündeki süre). Bu süre içinde yanıt gelmezse otomatik oturum biter ve Mac uyur; yanıt verince yeniden başlar. Kapak kapalıyken Uykusuz bunu sesle söyler."
                 : "Claude bir komut için onay, bir soru için yanıt ya da bir plan için onay beklerken bu süre içinde yanıt gelmezse otomatik oturum biter ve Mac uyur; yanıt verince yeniden başlar. Kapak kapalıyken Uykusuz bunu sesle söyler. Onayı telefondan vermek istiyorsanız Telefondan yanıt'ı açın ya da süreyi uzatın.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Toggle("Kod modu: Claude çalışırken Düşük Güç Modu (kapak açıkken)", isOn: bind(\.codeMode))
                .onChange(of: manager.config.codeMode) { manager.services?.reevaluateFloors() }
            Toggle("Boşta siyah ekran (ekran koruyucu yerine)", isOn: bind(\.idleBlackout))
                .onChange(of: manager.config.idleBlackout) { manager.services?.reevaluateFloors() }
            Stepper(value: bind(\.idleBlackoutAfter), in: 15...600, step: 15) {
                LabeledContent("Ekranı karartma süresi", value: "\(Int(manager.config.idleBlackoutAfter)) sn")
            }
            Stepper(value: bind(\.keyboardOffAfter), in: 10...600, step: 10) {
                LabeledContent("Klavye ışığını kapatma süresi", value: "\(Int(manager.config.keyboardOffAfter)) sn")
            }
            Stepper(value: bind(\.lockAfterBlackout), in: 0...7200, step: 5 * 60) {
                LabeledContent("Karardıktan sonra kilitle", value: manager.config.lockAfterBlackout > 0 ? "\(Int(manager.config.lockAfterBlackout / 60)) dk" : "Kilitleme")
            }
            Text("Oturum sürerken kapak açıkken ekran koruyucu ve ekran uykusu çalışmaz. Bu süre boyunca girdi olmazsa ekran parlaklığı 0'a iner ve ekran hiç ışık vermez; klavye ışığı da söner. Bir tuşa ya da fareye dokununca ikisi de geri gelir. Ekran karardıktan sonra yukarıdaki süre boyunca dönmezseniz oturum kilitlenir; ekran koruyucu açılmaz ve ekran karanlık kalır, döndüğünüzde kilit ekranı gelir. Claude ve oturum çalışmayı sürdürür. Bir video oynarken ekran kararmaz ve kilitlenmez; süreler video bitince yeniden başlar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var phoneRepliesSection: some View {
        Section("Telefondan yanıt") {
            Toggle("Claude'un telefon bildirimleri yalnızca ben uzaktayken gelsin", isOn: Binding(
                get: { manager.config.phoneReplies },
                set: { setPhoneReplies($0) }
            ))
            if manager.config.phoneReplies {
                Stepper(value: bind(\.phoneReplyWindow), in: 5 * 60...3 * 3600, step: 5 * 60) {
                    LabeledContent("Yanıt için Mac uyanık kalsın", value: "\(Int(manager.config.phoneReplyWindow / 60)) dk")
                }
            }
            if let phoneRepliesError {
                Text(phoneRepliesError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            Text("Claude uygulamasında Ayarlar > Claude Code > \"Connect new sessions to Remote Control\" açıkken oturumlar iPhone'daki Claude uygulamasında, Code sekmesinde kendi adlarıyla görünür; yanıtı, onayı ya da yeni isteği oradan ilgili oturuma verirsiniz. Claude, onay ya da yanıt beklerken ve bir iş bitince telefona kendisi bildirim gönderir. Bu seçenek açıkken siz Mac'in başındayken bu bildirimler susar; kapak kapalıyken, ekran kilitliyken ya da 2 dakikadır Mac'e dokunulmadıysa gelir. Otomatik oturum da Claude durduktan ya da beklemeye başladıktan sonra yukarıdaki süre kadar sürer, böylece telefondan yanıt verdiğinizde Mac uyanık olur. Açınca ~/.claude/settings.json dosyasına bir satır eklenir; yalnızca bundan sonra açılan oturumlarda geçerlidir.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Puts the presence variable in Claude Code's settings or takes it out,
    /// then the setting. On stays off when the settings could not take it;
    /// off goes off either way, so the file is not kept for nothing.
    private func setPhoneReplies(_ on: Bool) {
        guard let pushGate, manager.config.phoneReplies != on else { return }
        do {
            if on {
                try ClaudeHooks.installPresence(file: pushGate.file)
            } else {
                try ClaudeHooks.removePresence(file: pushGate.file)
            }
            phoneRepliesError = nil
        } catch {
            phoneRepliesError = "Claude Code ayarları değiştirilemedi: \(error.localizedDescription)"
            if on { return }
        }
        manager.config.phoneReplies = on
        save()
        pushGate.tick()
    }

    private var waitingAlertsSection: some View {
        Section("Claude sizi beklerken iPhone'a haber ver") {
            Toggle("iMessage gönder", isOn: bind(\.imessageAlerts))
            TextField("Alıcı: telefon numarası ya da Apple ID e-postası", text: bind(\.imessageHandle))
            if let waitingAlerts {
                HStack {
                    Button("Deneme mesajı gönder") { Task { await waitingAlerts.sendTest() } }
                        .disabled(manager.config.imessageHandle.trimmingCharacters(in: .whitespaces).isEmpty || waitingAlerts.isSendingTest)
                    if let result = waitingAlerts.lastResult {
                        Text(result)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Toggle("Docker kullanılırken de haber ver", isOn: bind(\.dockerAlerts))
            Text("Docker Desktop'ta bir iş sürerken (yeni açılan ya da yoğun çalışan bir kapsayıcı, docker build, pull ya da push) Mac'in başında değilseniz bir mesaj, iş bitince bir mesaj daha gönderilir. Boşta açık duran kapsayıcılar için mesaj gitmez.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Kapak kapalıyken, ekran kilitliyken ya da 2 dakikadır Mac'e dokunulmadıysa, bir Claude Code oturumu onay ya da yanıt beklemeye başlayınca ya da işini bitirip yeni isteğinizi bekleyince Uykusuz bu alıcıya Mesajlar üzerinden iMessage gönderir. API anahtarı kayıtlıysa mesajı Claude yazar, değilse oturumun adı ve Claude'un son mesajının sonu gider. Her oturum için en çok 10 dakikada bir mesaj gönderilir. İlk gönderimde macOS, Uykusuz'un Mesajlar'ı denetlemesine izin vermenizi ister. Kendi numaranıza gönderirseniz mesaj kendinizle olan sohbete düşer; deneme mesajıyla telefonunuzda bildirim gelip gelmediğine bakın. Telefondan yanıt açıksa Claude'un kendi bildirimi de gelir; ikisini birden istemiyorsanız bunu kapatın.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// What "Dinle" says, at the output's current volume.
    static let voiceSample = "Merhaba, ben Uykusuz. Kapak kapalıyken uyarıları bu sesle söylerim."

    private var awaySummarySection: some View {
        Section("Sen yokken özeti") {
            Toggle("Kapak ya da kilit açılınca Claude'un yaptıklarını özetle", isOn: bind(\.awaySummary))
            LabeledContent("Claude API anahtarı") {
                HStack {
                    Text(apiKeyStatus)
                        .foregroundStyle(.secondary)
                    if apiKeySaved {
                        Button("Sil") { changeAPIKey(saving: nil) }
                            .disabled(apiKeyBusy)
                    }
                }
            }
            HStack {
                SecureField("sk-ant-\u{2026}", text: $apiKeyDraft)
                Button("Kaydet") { changeAPIKey(saving: apiKeyDraft) }
                    .disabled(apiKeyBusy || apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Picker("Özeti yazan model", selection: bind(\.summaryModel)) {
                ForEach(AnthropicSummaryClient.models, id: \.id) { model in
                    Text(model.name).tag(model.id)
                }
            }
            if let awaySummary {
                Button("Son 2 saati şimdi özetle") {
                    let now = Date()
                    Task { await awaySummary.summarize(from: now.addingTimeInterval(-2 * 3600), to: now, away: false, sayIfNothing: true) }
                }
                .disabled(awaySummary.isSummarizing)
                if let result = awaySummary.lastResult {
                    Text("Son özet \(result)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Kapak en az 3 dakika kapalı ya da ekran o kadar kilitli kaldıysa, döndüğünüzde ekranın sağ üstünde küçük bir pencerede Claude Code oturumlarında olanlar bir iki cümleyle anlatılır. Siz ▶\u{FE0E} düğmesine basmadan ses çıkmaz; okunan kelime vurgulanır, çubuk ve ileri geri düğmeleriyle istediğiniz yerden dinlersiniz. Son özet göze sağ tıklayınca açılan menüden yeniden açılır. Anahtar kayıtlı değilse özet bu Mac'te sayılarla yazılır ve hiçbir yere gönderilmez. Anahtar kayıtlıysa özeti Claude yazar. İstek yalnızca api.anthropic.com'a gider ve yalnızca oturum başlıklarını, düzenlenen dosyaların adlarını, Claude'un komutlarına yazdığı açıklamaları ve son mesajlarının sonunu içerir; dosya içerikleri, komut satırları ve komut çıktıları gönderilmez. Anahtar giriş Anahtar Zinciri'nde saklanır, config.json'a ve günlüğe yazılmaz. Max ve Team planlarının aylık API kredisini Claude Console'a bağlayın ve anahtarı harcama sınırı olan ayrı bir çalışma alanında oluşturun.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await refreshAPIKeyStatus() }
    }

    private var replyReadingSection: some View {
        Section("Claude'un yanıtını dinle") {
            Toggle("Claude işini bitirince son yanıtını sesli oku", isOn: bind(\.readClaudeReplies))
                .disabled(!claudeHooksInstalled)
                .onChange(of: manager.config.readClaudeReplies) { replyReader?.settingChanged() }
            Text("Claude bir işi bitirince yalnızca size yazdığı son mesaj, ekranın sağ üstündeki küçük pencerede okunur; önceki adımlar okunmaz. Kod blokları atlanır, bağlantı adresleri okunmaz, dosya yollarının yalnızca dosya adı söylenir. Okunan kelime vurgulanır; ❚❚ durdurur, çubuk ve ileri geri düğmeleriyle istediğiniz yere gidersiniz. O oturuma yeni bir istek gönderince okuma durur. Birkaç oturum art arda biterse yanıtlar sırayla okunur; pencereyi kapatınca okuma ve sıradakiler biter. Kapak kapalıyken ya da ekran kilitliyken okunmaz. Bu ayar ve son yanıtı yeniden dinlemek göze sağ tıklayınca açılan menüde de bulunur; toplantıya girmeden önce oradan kapatabilirsiniz. Claude Code hook'larının kurulu olması gerekir. Yanıt bu Mac'te okunur, hiçbir yere gönderilmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func refreshAPIKeyStatus() async {
        guard let awaySummary else { return }
        switch await awaySummary.keyStore.read() {
        case let .key(key):
            apiKeyStatus = "Kayıtlı (\(KeychainAnthropicKeyStore.masked(key)))"
            apiKeySaved = true
        case .none:
            apiKeyStatus = "Kayıtlı değil"
            apiKeySaved = false
        case .unreadable:
            apiKeyStatus = "Bu sürüm okuyamıyor; yeniden kaydedin"
            apiKeySaved = true
        case let .error(message):
            apiKeyStatus = "Okunamadı: \(message)"
            apiKeySaved = false
        }
    }

    /// Saves `saving`, or deletes the key for nil.
    private func changeAPIKey(saving key: String?) {
        guard let awaySummary, !apiKeyBusy else { return }
        apiKeyBusy = true
        Task {
            defer { apiKeyBusy = false }
            do {
                if let key {
                    try await awaySummary.keyStore.save(key)
                    apiKeyDraft = ""
                } else {
                    try await awaySummary.keyStore.delete()
                }
                await refreshAPIKeyStatus()
            } catch {
                apiKeyStatus = (key == nil ? "Silinemedi: " : "Kaydedilemedi: ") + error.localizedDescription
            }
        }
    }

    private func toggleClaudeHooks() {
        do {
            if claudeHooksInstalled {
                try ClaudeHooks.remove()
            } else {
                try ClaudeHooks.install()
            }
            claudeHooksError = nil
        } catch {
            claudeHooksError = "Claude Code ayarları değiştirilemedi: \(error.localizedDescription)"
        }
        claudeHooksInstalled = ClaudeHooks.isInstalled()
    }

    private var networkSection: some View {
        Section {
            TextField("Hotspot ağ adı (SSID)", text: bind(\.hotspotSSID))
            HStack {
                SecureField("Hotspot parolası", text: Binding(get: { hotspot.password }, set: { hotspot.edit($0) }))
                    .onSubmit(savePassword)
                Button(hotspot.buttonTitle(ssid: manager.config.hotspotSSID), action: savePassword)
                    .disabled(hotspot.password.isEmpty || hotspot.saving)
            }
            if let notice = hotspot.notice {
                Text(notice).font(.caption).foregroundStyle(.orange)
            }
            if !HotspotSSID.normalized(manager.config.hotspotSSID).isEmpty {
                hotspotJoinModeRow
            }
            Toggle("Bilinen Wi-Fi ağına geri dön", isOn: bind(\.returnToKnownWiFi))
            Text("Oturum sürerken hotspot'tayken Uykusuz 2 dakikada bir çevreyi tarar. Daha önce bağlandığınız ve parolası olan bir ağ yeterince güçlüyse hotspot'tan ayrılır; macOS o ağa kendi kayıtlı parolasıyla bağlanır. Çevrede bilinen parolasız bir ağ varsa ayrılmaz. macOS yine de parolasız bir ağa bağlanırsa Uykusuz oradan ayrılıp hotspot'a döner. Uykusuz ağ seçmez ve Wi-Fi parolalarını görmez.")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Konum: \(locationPermission.statusDescription)")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if locationPermission.isDenied {
                        Button("Konum Servisleri'ni aç") {
                            locationPermission.openLocationServicesSettings()
                        }
                    }
                }
                // macOS has no when-in-use grant for Mac apps: the grant is
                // recorded as Location Services access for Uykusuz.
                Text("macOS bu izni Uykusuz için Konum Servisleri erişimi olarak kaydeder. Uykusuz bu izni yalnızca Wi-Fi ağ adlarını okumak için kullanır ve konumunuzu hiçbir zaman istemez.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Stepper(value: nudgeSeconds, in: 10...900, step: 10) {
                LabeledContent("tmux dürtmesi", value: "\(Int(manager.config.nudgeThreshold)) sn çevrimdışı kalınca")
            }
            Text("Bu süre boyunca çevrimdışı kalındığında Uykusuz aşağıda listelenen her bölmeye \"continue\" yazar. Yalnızca bu tmux komutuyla işaretlediğiniz bölmeler dürtülür. İçine yazı yazdığınız bir bölmeyi değil, bu iş için ayrılmış bir bölmeyi işaretleyin.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(TmuxNudge.markCommand())
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Toggle("continue yazdıktan sonra Enter'a bas", isOn: bind(\.tmuxNudgePressesEnter))
            Text("Enter, o bölmede önceden yazılmış ne varsa, hiç bitirilmemiş bir satır da dahil, gönderir. Kapalıyken \"continue\" yazılır ve hiçbir şey onu göndermez.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(manager.config.tmuxTargets, id: \.self) { t in
                HStack {
                    Text(t).font(.system(.body, design: .monospaced))
                    Spacer()
                    removeButton {
                        update { $0.tmuxTargets.removeAll { $0 == t } }
                    }
                }
            }
            HStack {
                TextField("tmux hedefi (oturum:pencere.bölme)", text: $newTmuxTarget)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTmuxTarget)
                Button("Ekle", action: addTmuxTarget)
                    .disabled(newTmuxTarget.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            Text("Ağ yedekleme")
        } footer: {
            Text("Parola giriş anahtar zincirinde saklanır ve sormadan yalnızca onu kaydeden Uykusuz derlemesi tarafından okunabilir; yeniden kurulumdan sonra parolayı tekrar girin. Konum izni, macOS'in Wi-Fi ağ adlarını göstermesini ve ayarlanan kişisel erişim noktasını (hotspot) bulmasını sağlar.")
        }
    }

    private var nudgeSeconds: Binding<Int> {
        Binding(
            get: { Int(manager.config.nudgeThreshold) },
            set: { seconds in update { $0.nudgeThreshold = TimeInterval(seconds) } }
        )
    }

    /// Fills the field when the window appears (`loadForField`).
    private func loadPassword() {
        let request = hotspot.startLoad(ssid: manager.config.hotspotSSID)
        Task {
            await Self.loadForField(request, secrets: secrets) {
                hotspot.finishRead($0, ssid: manager.config.hotspotSSID, password: $1.password, notice: $1.notice)
            }
        }
    }

    /// Reads the notice again for the hotspot configured now, without a
    /// prompt and without touching the field.
    private func recheckPassword() {
        recheckPassword(hotspot.startRead(ssid: manager.config.hotspotSSID))
    }

    private func recheckPassword(_ request: HotspotPasswordField.Read) {
        Task {
            await Self.readForField(
                request,
                first: { await recheckedNotice() },
                again: { await recheckedNotice() },
                finish: { hotspot.finishRead($0, ssid: manager.config.hotspotSSID, password: $1.password, notice: $1.notice) }
            )
        }
    }

    private func recheckedNotice() async -> (password: String, notice: String?) {
        let notice = await Self.hotspotNotice(
            reported: manager.services?.status.hotspotPasswordReport,
            ssid: manager.config.hotspotSSID,
            reread: secrets.peek
        )
        return ("", notice)
    }

    /// Loads the saved password into the field, without a keychain prompt.
    /// An item this build may not read leaves the field empty and says
    /// why, so the user re-enters it; saving then replaces the item (see
    /// `KeychainStore`). The read can wait behind a save, so a field
    /// edited meanwhile is kept, even one typed in and emptied again, and
    /// a password read for an SSID edited away meanwhile is not shown: the
    /// SSID configured now is read instead. That read is a peek: the
    /// account a later save moves the password from stays the one the
    /// window loaded, as it does for any SSID edit, so the old SSID's item
    /// is still removed.
    static func loadForField(
        _ request: HotspotPasswordField.Read,
        secrets: any HotspotSecretStore,
        finish: @MainActor (HotspotPasswordField.Read, (password: String, notice: String?)) -> HotspotPasswordField.ReadAnswer
    ) async {
        await readForField(
            request,
            first: { await loadedPassword(secrets.load) },
            again: { await loadedPassword(secrets.peek) },
            finish: finish
        )
    }

    /// Runs a load or recheck for the field: `first` reads, and `finish`
    /// takes the answer. While the SSID was edited during the read,
    /// `finish` drops the answer, and `again` reads the SSID configured
    /// now, until an answer is used or dropped.
    static func readForField(
        _ request: HotspotPasswordField.Read,
        first: @MainActor () async -> (password: String, notice: String?),
        again: @MainActor () async -> (password: String, notice: String?),
        finish: @MainActor (HotspotPasswordField.Read, (password: String, notice: String?)) -> HotspotPasswordField.ReadAnswer
    ) async {
        var answer = await first()
        var request = request
        while case let .readAgain(next) = finish(request, answer) {
            request = next
            answer = await again()
        }
    }

    /// A prompt-free load: the password for the field, or an empty field
    /// and a notice saying why it cannot be shown.
    static func loadedPassword(_ load: () async throws -> String?) async -> (password: String, notice: String?) {
        do {
            return (try await load() ?? "", nil)
        } catch let error as KeychainError {
            return ("", error.problem.settingsNotice)
        } catch {
            return ("", HotspotPasswordProblem.error(error.localizedDescription).settingsNotice)
        }
    }

    /// The notice under the password field for the hotspot `ssid`
    /// configured now. A problem the failover reports about that hotspot
    /// shows as it is. A report about another SSID, one edited away since,
    /// does not apply, and a cleared report is not taken as "readable": it
    /// also clears when the session ends. Then the keychain is read again,
    /// without a prompt, and the notice says what that read finds. The
    /// field is left as the user has it, and the reread is a peek: a load
    /// would make an SSID typed since then the account a save moves the
    /// password from, and the old SSID's item would stay behind.
    static func hotspotNotice(reported: HotspotPasswordReport?, ssid: String, reread: () async throws -> String?) async -> String? {
        if let problem = reported?.problem(for: ssid) { return problem.settingsNotice }
        return await loadedPassword(reread).notice
    }

    /// Saves, or clears for an empty field. The button shows "Saving..."
    /// until the keychain answers; one save at a time.
    /// Whether macOS joins hotspots on its own; read when the section
    /// shows, when Uykusuz becomes active (back from System Settings) and
    /// after a hotspot save.
    @ViewBuilder
    private var hotspotJoinModeRow: some View {
        Group {
            switch hotspotJoinMode {
            case .automatic?:
                Label("Sistem Ayarları > Wi-Fi > \"Erişim noktalarına katılmak için sor\": Otomatik", systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .notAutomatic?:
                VStack(alignment: .leading, spacing: 4) {
                    Label("Sistem Ayarları > Wi-Fi > \"Erişim noktalarına katılmak için sor\" Otomatik değil. Bu ayar Otomatik olmadan Uykusuz Wi-Fi koptuğunda iPhone'a geçemeyebilir.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Button("Wi-Fi ayarlarını aç") { NSWorkspace.shared.open(HotspotJoinMode.wifiSettingsURL) }
                }
            case .unknown?, nil:
                EmptyView()
            }
        }
        .task(id: manager.config.hotspotSSID) { await recheckHotspotJoinMode() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await recheckHotspotJoinMode() }
        }
    }

    private func recheckHotspotJoinMode() async {
        hotspotJoinMode = await Task.detached(priority: .utility) { HotspotJoinMode.read() }.value
    }

    private func savePassword() {
        guard hotspot.startSave() else { return }
        if !HotspotSSID.normalized(manager.config.hotspotSSID).isEmpty {
            locationPermission.requestWhenInUse()
        }
        let password = hotspot.password
        Task {
            let outcome = await Self.storePassword(password, in: secrets)
            let recheck = hotspot.finishSave(outcome, ssid: manager.config.hotspotSSID)
            // The failover's report first, so the recheck reads it as the
            // save left it.
            Self.passwordStored(outcome, configuredSSID: manager.config.hotspotSSID, services: manager.services)
            if let recheck { recheckPassword(recheck) }
            await recheckHotspotJoinMode()
        }
    }

    /// A save or clear answered. The failover's report goes, and the next
    /// outage notifies afresh, unless the report is about the hotspot
    /// configured now and the save neither stored for it nor removed its
    /// item (`HotspotPasswordReport.stands`).
    static func passwordStored(_ outcome: HotspotStoreOutcome, configuredSSID: String, services: AppServices?) {
        guard case let .stored(stored) = outcome else { return }
        services?.hotspotPasswordChanged(stored.change, configuredSSID: configuredSSID)
    }

    /// Saves `password`, or clears the saved one when it is empty, and
    /// returns what was stored under which SSID and which loaded account
    /// it removed, or the notice for a failure. The store does the keychain work on `KeychainQueue`, so a
    /// save waiting on a keychain dialog waits there while the main actor
    /// (the battery floor, the deadline timer, End) carries on.
    static func storePassword(_ password: String, in secrets: any HotspotSecretStore) async -> HotspotStoreOutcome {
        do {
            let change = if password.isEmpty {
                try await secrets.delete()
            } else {
                try await secrets.save(password)
            }
            return .stored(.init(ssid: change.ssid, password: password, removed: change.removed))
        } catch {
            Log.error("could not save hotspot password: \(error.localizedDescription)")
            return .failed(notice: "Hotspot parolası kaydedilemedi: \(error.localizedDescription)")
        }
    }

    private func addTmuxTarget() {
        let t = newTmuxTarget.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return }
        update { if !$0.tmuxTargets.contains(t) { $0.tmuxTargets.append(t) } }
        newTmuxTarget = ""
    }

    private var appSection: some View {
        Section("Uygulama") {
            Toggle("Girişte aç", isOn: launchAtLogin)
            loginItemNote
            LabeledContent("Yapılandırma") {
                Text(manager.paths.configFile.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            LabeledContent("Sürüm") {
                Text(AppBuild.current.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if LidSimulationBuild.isCompiledIn {
                Text(LidSimulationBuild.marker)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    /// The switch shows what macOS has on file (`LoginItem.isRegistered`:
    /// enabled or waiting for approval), so a registration that an upgrade
    /// dropped reads as off even while config.json still says on, and a
    /// pending one can be withdrawn by turning the switch off; the note
    /// below explains the state.
    private var launchAtLogin: Binding<Bool> {
        Binding(
            get: { loginItem.isRegistered },
            set: { on in
                // Persist only what macOS accepted; a refused change leaves
                // the flag as it was and its error on screen.
                update { config in _ = loginItem.set(on, config: &config) }
            }
        )
    }

    /// One line under the switch: the last error, a pending approval with
    /// the button that opens Login Items, or a flag macOS no longer honours.
    @ViewBuilder
    private var loginItemNote: some View {
        if let error = loginItem.error {
            Text("Giriş öğesi: \(error)").font(.caption).foregroundStyle(.red)
        } else if loginItem.needsApproval {
            HStack {
                Text("Sistem Ayarları > Genel > Giriş Öğeleri bölümünde onay bekleniyor. Geri çekmek için anahtarı kapatın.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Giriş Öğeleri'ni aç") { loginItem.openLoginItems() }
            }
        } else if manager.config.launchAtLogin, !loginItem.isRegistered {
            Text("Giriş öğesi için macOS'in bildirdiği durum: \(loginItem.status.description). Yeniden kaydetmek için anahtarı açın.")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }

    // MARK: Bundle id lists

    private func bundleList(
        title: String,
        items: [String],
        newValue: Binding<String>,
        add: @escaping (String) -> Void,
        remove: @escaping (String) -> Void
    ) -> some View {
        Group {
            Text(title).font(.headline)
            ForEach(items, id: \.self) { id in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(RunningApps.displayName(for: id))
                        Text(id).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    removeButton { remove(id) }
                }
            }
            HStack {
                TextField("Paket kimliği", text: newValue)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        let v = newValue.wrappedValue.trimmingCharacters(in: .whitespaces)
                        guard !v.isEmpty else { return }
                        add(v)
                        newValue.wrappedValue = ""
                    }
                Button("Ekle") {
                    let v = newValue.wrappedValue.trimmingCharacters(in: .whitespaces)
                    guard !v.isEmpty else { return }
                    add(v)
                    newValue.wrappedValue = ""
                }
                .disabled(newValue.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                Menu("Çalışan uygulama ekle…") {
                    let apps = RunningApps.candidates(excluding: items)
                    if apps.isEmpty {
                        Text("Çalışan başka uygulama yok")
                    }
                    ForEach(apps, id: \.bundleID) { app in
                        Button(app.name) { add(app.bundleID) }
                    }
                }
                .fixedSize()
            }
        }
    }

    private func removeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Kaldır")
    }
}

/// Running apps offered by "Çalışan uygulama ekle…": everything with a
/// bundle id that is not Apple's own.
@MainActor
enum RunningApps {
    struct Entry: Hashable {
        let bundleID: String
        let name: String
    }

    static func candidates(excluding: [String]) -> [Entry] {
        let me = Bundle.main.bundleIdentifier
        var seen = Set<String>()
        var out: [Entry] = []
        for app in NSWorkspace.shared.runningApplications {
            guard let id = app.bundleIdentifier, !id.hasPrefix("com.apple."), id != me,
                  app.activationPolicy != .prohibited,
                  !excluding.contains(id), !seen.contains(id) else { continue }
            seen.insert(id)
            out.append(Entry(bundleID: id, name: app.localizedName ?? id))
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Name of a running app for a bundle id, or the last path component.
    static func displayName(for bundleID: String) -> String {
        if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }),
           let name = app.localizedName {
            return name
        }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.deletingPathExtension().lastPathComponent
        }
        return bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
