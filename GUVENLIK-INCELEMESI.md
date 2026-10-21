# Güvenlik incelemesi

Bu rapor Uykusuz'un ne yaptığını ve neye dokunduğunu inceler: yetkileri,
kalıcı bileşenleri, ağ davranışını, tuttuğu verileri ve diğer uygulamalara
etkisini. Amaç, uygulamanın saldırgan bir davranış içerip içermediğini ve
kullanıcı verisini dışarı aktarıp aktarmadığını görmektir.

- **Tarih:** 2026-10-20
- **İncelenen kaynak:** `main` dalında `e242782` (2026-10-19); sonraki
  değişiklikler [Sonraki değişiklikler](#sonraki-değişiklikler) bölümünde
  ayrıca incelendi.
- **İncelenen derlemeler:** aynı commit'ten Release iş akışıyla üretilen
  gecelik derleme (`nightly-20261019-e24278258445`) ve bu depodan kaynak
  koddan alınan derleme.

## Sonuç

**Kötü amaçlı kod, veri sızdırma, gizli ağ trafiği ya da yapay zekâ ajanlarına
yönelik prompt injection bulunmadı.** Uygulama yalnızca anlattığı işi yapıyor:
uykuyu zamanlı olarak engelliyor, kapak kapalıyken seçilen uygulamaları
donduruyor, ekranı karartıp sesi kapatıyor, Wi-Fi düşerse hotspot'a geçiyor ve
Claude Code çalışırken oturumu kendiliğinden açıp kapatıyor.

## Yöntem

1. **Kaynak kod satır satır okundu.** Swift kaynaklarının tamamı (`Sources/`),
   kurulum, kaldırma ve kurtarma betikleri (`scripts/`), CI iş akışları
   (`.github/`), kodlama ajanlarına yönelik talimatlar (`skills/`) ve testler
   dört ayrı incelemede gözden geçirildi.
2. **Derleme REA ile statik olarak analiz edildi.** REA,
   [morluto/rea](https://github.com/morluto/rea) projesinin `rea-agents` 6.7.0
   npm paketidir; paketin kayıt imzaları ve provenance kaydı doğrulandı.
   Kullanılan komutlar: `inspect-artifact`, `inspect-macho`, `inspect-plist`,
   `inspect-signature`, `list-architectures`, `trace-dylib-resolution`.
3. **Derlemenin kaynağı doğrulandı.** Zip'in SHA-256 özeti tuttu. GitHub
   derleme kanıtı (`gh attestation verify`), zip'in bu commit'ten
   `release.yml` iş akışıyla üretildiğini doğruladı.
4. **Kaynak koddan alınan derleme** REA ile gecelik derlemeyle karşılaştırıldı
   (aşağıda).

## Bulgular

### Ağ

- **Kendiliğinden hiçbir ağ isteği yapılmaz.** İncelenen sürümdeki tek dış
  istek, Ayarlar'daki "Güncellemeleri Denetle" düğmesine basıldığında
  `api.github.com` üzerinden sürüm listesini okuyan iki GET isteğiydi; bu düğme
  ve istekler kaldırıldı. 0.3.0 ile eklenen tek istek isteğe bağlı "Sen yokken"
  özetidir ve yalnızca kullanıcı bir Claude API anahtarı kaydettiyse yapılır
  ([Sonraki değişiklikler](#sonraki-değişiklikler)). Kaynakta `URLSession` ve
  `URLRequest` yalnızca `ClaudeSummaryClient.swift` içinde kullanılır; tek
  adres `https://api.anthropic.com/v1/messages`'tır. `NWConnection` kullanımı
  yoktur.
- `NWPathMonitor` yalnızca Wi-Fi bağlantısının durumunu izler, ağ trafiği
  oluşturmaz.
- Betiklerde `curl`, `wget`, `nc`, `ssh` ya da indirilen bir içeriği çalıştırma
  yoktur.

### Yetki (`sudo`)

`/etc/sudoers.d/uykusuz` dosyası tam olarak şu dört komuta izin verir, joker
karakter yoktur:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -b lowpowermode 1
/usr/bin/pmset -b lowpowermode 0
```

Kural `visudo -cf` ile doğrulanır ve root'a ait, salt okunur olarak kurulur.
Root olarak çalışan başka bir şey yoktur.

### Kalıcılık

- **LaunchAgent:** Kullanıcı düzeyinde tek bir LaunchAgent kurulur
  (`com.mustafaghn.uykusuz.backstop`). Girişte ve her 60 saniyede bir çalışır.
  Önce uygulamanın imzasını sabitlenmiş cdhash'e karşı
  `codesign --verify --strict` ile doğrular, ardından paketin içindeki mühürlü
  `backstop.sh` betiğini çalıştırır.
- **Olmayanlar:** LaunchDaemon, cron, kabuk profili değişikliği ya da
  `/Library` altına yazma yoktur.

### Veri

- **Ayarlar ve kayıtlar:** Ayarlar ve geri alma kayıtları
  `~/Library/Application Support/Uykusuz/` altında tutulur. Dosyalar 0600,
  klasörler 0700 izinlidir.
- **Günlükler:** Günlükler `~/Library/Logs/Uykusuz/` altındadır. Wi-Fi adı
  (SSID), uygulama adları ve aygıt adları burada açık metin olarak durur ama
  bilgisayardan çıkmaz.
- **Hotspot parolası:** Giriş Anahtar Zinciri'nde tek bir kayıt olarak
  saklanır (servis `uykusuz-hotspot`). Hiçbir zaman günlüğe yazılmaz ve komut
  satırına geçirilmez. Uygulama başka Anahtar Zinciri kayıtlarını okumaz.
- **Konum izni:** Yalnızca macOS'un Wi-Fi adlarını gösterebilmesi için
  istenir. Konum verisi okunmaz ya da saklanmaz.
- **Okunmayan veriler:** Pano, ekran içeriği, başka uygulamalara yazılanlar,
  tarayıcı geçmişi ya da sekmeleri, SSH anahtarları ve kabuk geçmişi okunmaz.

### Diğer uygulamalar

- **Dondurma:** `SIGSTOP`/`SIGCONT` sinyalleri yalnızca dondurma listesindeki
  uygulamalara (varsayılan olarak WhatsApp, Word, Excel ve ParaView) ve
  "diğer tüm uygulamaları dondur" açıkken diğer Dock uygulamalarına gönderilir.
  Her süreç, başlangıç zamanı ve önyükleme oturumuyla doğrulanır. Apple
  uygulamaları, ajan uygulamaları, parola yöneticileri ve yerleşik olarak
  korunan uygulamalar hiçbir zaman otomatik olarak dondurulmaz.
- **Ajanlar için App Nap:** İsteğe bağlıdır ve varsayılan olarak kapalıdır.
  Açılırsa ajan uygulamalarının `NSAppSleepDisabled` tercihini yazar, oturum
  sonunda eski değeri geri koyar.
- **tmux dürtmesi:** İsteğe bağlıdır ve varsayılan olarak kapalıdır. Yalnızca
  sizin `@uykusuz-nudge on` ile işaretlediğiniz bölmelere sabit `continue`
  kelimesini yazar.
- **Tarayıcıyı yeniden başlatma:** Yalnızca menüden seçip onay verdiğinizde
  çalışır. Tarayıcının yalnızca komut satırı bayraklarını okur; sekmelerine ya
  da geçmişine bakmaz.
- **Özel Apple API'leri:** Ekran ve klavye parlaklığı için DisplayServices ve
  CoreBrightness, sabit sistem yollarından `dlopen` ile yüklenir. Bunların
  dışında dışarıdan kod yüklenmez.

### REA bulguları (gecelik derleme)

- **İmza:** Ad-hoc imzalıdır (Team ID yok). Entitlement ve hardened runtime
  yoktur.
- **Mimari:** Yalnızca arm64. Minimum sistem macOS 26.0, SDK 26.5.
- **Bağımlılıklar:** 39 dinamik kütüphanenin tamamı `/System/Library` ya da
  `/usr/lib` altındaki Apple kütüphaneleridir. Üçüncü taraf framework ya da
  `@rpath` kütüphanesi yoktur.
- **Ağ ile ilgili importlar:** Yalnızca `NSURLSession` (o zamanki güncelleme
  denetimi) ve `NWPathMonitor` vardır. Soket, `NWConnection` ya da
  `posix_spawn` yoktur.
- **Gömülü adresler:** Yalnızca güncelleme denetiminin kullandığı üç GitHub
  adresi vardı; denetimle birlikte kaldırıldılar.
- **Info.plist:** Kaynaktaki dosyayla aynıdır.
- **Paket içeriği:** Program, `Info.plist`, `Resources/AppIcon.icns` ve
  `Resources/backstop.sh`. Yardımcı araç, XPC hizmeti ya da ayrıcalıklı
  yardımcı yoktur.

### REA karşılaştırması (kaynaktan alınan derleme)

Kaynak `scripts/build-app.sh` ile derlendi ve aynı REA komutlarıyla gecelik
derlemeyle karşılaştırıldı.

- **Hassas importlar birebir aynı.** Süreç ve sinyal (`libSystem`), Anahtar
  Zinciri ve imza (`Security`), güç (`IOKit`), `Network`, Wi-Fi (`CoreWLAN`),
  konum, giriş öğesi, bildirim, ses (`CoreAudio`) ve `AppKit` importlarında
  fark yok.
- **Paket yapısı ve imza türü aynı:** Ad-hoc imza, entitlement yok.
- **`Info.plist` farkı yalnızca yerelleştirme:** `CFBundleDevelopmentRegion = tr`
  ve konum izni metni Türkçe.
- **Diğer farklar derleyiciden kaynaklanıyor:** Yerel SDK `NSURLSession`'ı ayrı
  `CFNetwork` kütüphanesi yerine `Foundation` üzerinden bağlıyor ve birkaç
  SwiftUI sembolü farklı. Yeni bir yetenek ya da kütüphane eklenmedi.

Kurulumda derleme makinenizde yeniden alındığı için cdhash her derlemede
farklı olur.

## Sonraki değişiklikler

İncelenen commit'ten sonra eklenen özellikler, aşağıdaki isteğe bağlı "Sen
yokken" özeti ve iPhone'a iMessage dışında yereldir ve ağ isteği yapmaz. Yeni
bir `sudo` komutu ya da kalıcı bileşen eklenmedi; tek yeni izin, iMessage için
macOS'un sorduğu Otomasyon (Mesajlar) iznidir.

- **Otomatik oturum:** Güç kilitlerini IOKit üzerinden yalnızca okur
  (`IOPMCopyAssertionsByProcess`).
- **Claude Code hook'ları:** İsteğe bağlıdır ve kullanıcı Ayarlar'dan kurar.
  `~/.claude/settings.json` dosyasına hiçbir çıktı vermeyen ve hep başarılı
  dönen bir komut ekler; dosyanın eski hâli yedeklenir. Komut, uygulama destek
  klasörüne oturum başına 0600 izinli bir işaret dosyası yazar ya da onu
  siler. Bash komutlarını ve iş yapıp yapmadıklarını algılamak için yalnızca
  kullanıcının kendi süreçlerinin adları, argümanları ve işlemci süreleri
  okunur.
- **Sesli uyarı:** `/usr/bin/say` ile konuşur; metin tek bir argüman olarak,
  `--` ayıracından sonra verilir. Ses, kurulu sesler arasından seçilen en iyi
  Türkçe sestir (0.4.0); ses listesi yalnızca okunur.
- **Kod modu ve boşta siyah ekran:** Parlaklığı mevcut ekran ve klavye
  arayüzleriyle değiştirir. Yalnızca son girdiden geçen süre okunur
  (`CGEventSource.secondsSinceLastEventType`); bunun için tuş vuruşları
  okunmaz, sahte tuş ya da olay gönderilmez.
- **Kurtarma ajanının başlangıcı:** Ajan `/bin/sh` yerine uygulamanın kendi
  programıyla başlar (`--backstop-agent`); böylece Sistem Ayarları öğeyi
  Uykusuz olarak gösterir. Program hemen aynı `/bin/sh` doğrulama komutunu
  çalıştırır. Fark, doğrulamadan önce paketin içindeki kodun çalışmasıdır;
  paketi yeniden imzalayabilen biri ajan dosyasını da değiştirebildiği için
  pratik bir koruma kaybı yoktur.
- **Claude yanıt beklerken (0.3.0):** Hook'lara onay penceresi, soru, plan
  onayı, reddedilen izin, hata veren araç ve API hatasıyla biten tur olayları
  eklendi. Komut yine hiçbir çıktı vermez ve hep başarılı döner; bu yüzden bir
  izne yanıt vermez. İşaret dosyasına yalnızca bekleme zamanı eklenir. Uygulama
  açılışta, kullanıcının daha önce kurduğu hook'lara eksik olayları ekler; hiç
  kurulmamışsa dokunmaz.
- **Sen yokken özeti (0.3.0):** Kapak açılınca `~/.claude/projects` altındaki
  Claude Code kayıtlarını yalnızca okur; oturum başlığı, araç sayıları,
  düzenlenen dosyaların adları, komut açıklamaları ve Claude'un son
  mesajlarının sonu dışında hiçbir şey alınmaz. Anahtar kayıtlı değilse özet
  yerelde yazılır. Anahtar kayıtlıysa bu metin, `URLSession` ile önbelleksiz ve
  çerezsiz tek bir HTTPS isteğiyle `api.anthropic.com`'a gönderilir. Anahtar
  giriş Anahtar Zinciri'nde, okunması istem açmayan bir kayıtta tutulur;
  config.json'a ve günlüğe yazılmaz.
- **Bilinen Wi-Fi ağına geri dönüş (0.6.0):** Oturum sürerken hotspot'tayken
  CoreWLAN ile tarar ve bilinen ağ listesinden yalnızca adları ve parolalı olup
  olmadıklarını okur; Wi-Fi parolalarını okumaz ve hiçbir ağa kendisi katılmaz.
  Yalnızca hotspot bağlantısını keser (`disassociate`); parolasız bir ağa
  düşülürse oradan da ayrılıp hotspot'a döner.
- **iPhone'a iMessage (0.7.0):** İsteğe bağlıdır ve varsayılan olarak kapalıdır.
  Kullanıcı uzaktayken bekleyen ya da biten bir Claude oturumu için Mesajlar'a
  `osascript` ile `send` komutu gönderilir; metin ve alıcı argüman olarak verilir,
  betiğe gömülmez. Erişilebilirlik izni ya da tuş taklidi yoktur; macOS ilk
  gönderimde Otomasyon (Mesajlar) iznini sorar. Info.plist'e bunun için
  `NSAppleEventsUsageDescription` eklendi. Anahtar kayıtlıysa mesajı yazmak
  için "Sen yokken" özetindeki alanlar, yalnızca o oturum için, aynı yolla
  `api.anthropic.com`'a gönderilir.
- **Telefondan yanıt (0.7.0):** İsteğe bağlıdır ve varsayılan olarak kapalıdır.
  Açılınca `~/.claude/settings.json` dosyasının `env` bölümüne Claude Code'un
  `CLAUDE_CLIENT_PRESENCE_FILE` satırı eklenir (dosyanın eski hâli yedeklenir;
  başka bir dosyayı gösteren satıra dokunulmaz) ve kullanıcı Mac'in başındayken
  uygulama destek klasöründe 0600 izinli boş bir dosya tutulur. Kapatınca satır,
  uygulama kapanınca dosya silinir. Ağ isteği yoktur; telefondan gelen yanıtları
  Uykusuz değil Claude'un Remote Control özelliği taşır.
- **İzin isteklerini otomatik onaylama (0.7.2):** İsteğe bağlıdır ve varsayılan
  olarak kapalıdır. Açıkken `PermissionRequest` hook'u, bir soru
  (`AskUserQuestion`) ya da plan onayı (`ExitPlanMode`) olmayan her izin
  isteğine Claude Code'un okuduğu `"behavior": "allow"` kararını yazar. Bu hook
  bunun için çıktısı atılmadan kurulur (`2>/dev/null || true`); diğer olayların
  hook'ları sessiz kalır. Ayar her istekte config.json'dan okunur; dosya
  okunamazsa ya da Uykusuz yoksa çıktı olmaz ve karar kullanıcıya kalır.
  Claude Code'un deny ve ask kuralları onaylanan bir çağrıya yine uygulanır.
  Etkisi bypass moduna yakındır: Claude'u yönlendiren bir içerik zararlı bir
  komutu onaylatabilir.
- **Güncelleme denetimi:** Kaldırıldı; incelenen sürümün tek ağ isteği buydu.

## Kötü amaçlı olmayan zayıf noktalar

- **Şifresiz `pmset` izni:** Dar kapsamlıdır ama hesabınızda çalışan her süreç
  bu dört komutu şifresiz çalıştırabilir.
- **`$USER` değişkeni:** `install.sh`, sudoers kuralını yazarken `$USER`
  ortam değişkenini kullanır. Betiği `USER` değişkenini değiştirerek
  çalıştırmayın.
- **Debug derlemeleri:** Bu derlemelerde kapak simülasyonu tetikleyicisi
  bulunur. Uygulamayı her zaman `scripts/install.sh` ile kurun; bu betik
  release derlemesi alır.
- **Çökme sonrası donmuş uygulama:** Uygulama bir süreci durdurduktan hemen
  sonra çökerse o süreç donmuş kalabilir. Menü bunu bildirir; elle
  `kill -CONT <pid>` ile çözülür.
- **Ad-hoc imza:** Her yeniden derlemede cdhash değişir. Bu yüzden hotspot
  parolasını ve Claude API anahtarını yeniden kurulumdan sonra tekrar girmek
  gerekir.
- **Claude API anahtarı:** Anahtarı ele geçiren biri o hesabın API kredisini
  harcayabilir. Anahtarı harcama sınırı olan ayrı bir çalışma alanında
  oluşturun; Console kuruluşunda ödeme yöntemi yoksa en çok o ayın kredisi
  harcanır.
- **Boşta siyah ekranda kilit:** Ekran karardığında kendiliğinden
  kilitlenmez; Mac'in başından kalkarken Ctrl+Cmd+Q ile kilitleyin.

## Depo ayarları

- **GitHub Actions:** Kapalı. Gecelik Release iş akışı her gün macOS üzerinde
  derleme yapıp Actions dakikası tüketeceği için açılmadı.
- **Dependabot:** `.github/dependabot.yml` kaldırıldı.
