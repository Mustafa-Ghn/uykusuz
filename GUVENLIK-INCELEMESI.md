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

- **Uykusuz hiçbir ağ isteği yapmaz.** İncelenen sürümdeki tek dış istek,
  Ayarlar'daki "Güncellemeleri Denetle" düğmesine basıldığında `api.github.com`
  üzerinden sürüm listesini okuyan iki GET isteğiydi; bu düğme ve istekler
  kaldırıldı. 2026-10-20 itibarıyla kaynakta `URLSession`, `URLRequest` ya da
  `NWConnection` kullanımı yoktur ve kurulu derlemede gömülü bir http(s)
  adresi bulunmaz.
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

İncelenen commit'ten sonra eklenen her özellik yereldir ve ağ isteği yapmaz.
Yeni bir yetki, `sudo` komutu ya da kalıcı bileşen eklenmedi.

- **Otomatik oturum:** Güç kilitlerini IOKit üzerinden yalnızca okur
  (`IOPMCopyAssertionsByProcess`).
- **Claude Code hook'ları:** İsteğe bağlıdır ve kullanıcı Ayarlar'dan kurar.
  `~/.claude/settings.json` dosyasına hiçbir çıktı vermeyen ve hep başarılı
  dönen bir komut ekler; dosyanın eski hâli yedeklenir. Komut, uygulama destek
  klasörüne oturum başına 0600 izinli bir işaret dosyası yazar ya da onu
  siler. Bash komutlarını algılamak için yalnızca kullanıcının kendi
  süreçlerinin adları ve argümanları okunur.
- **Sesli uyarı:** `/usr/bin/say` ile konuşur; metin tek bir argüman olarak,
  `--` ayıracından sonra verilir.
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
- **Güncelleme denetimi:** Kaldırıldı; uygulamanın tek ağ isteği buydu.

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
  parolasını yeniden kurulumdan sonra tekrar girmek gerekir.
- **Boşta siyah ekranda kilit:** Ekran karardığında kendiliğinden
  kilitlenmez; Mac'in başından kalkarken Ctrl+Cmd+Q ile kilitleyin.

## Depo ayarları

- **GitHub Actions:** Kapalı. Gecelik Release iş akışı her gün macOS üzerinde
  derleme yapıp Actions dakikası tüketeceği için açılmadı.
- **Dependabot:** `.github/dependabot.yml` kaldırıldı.
