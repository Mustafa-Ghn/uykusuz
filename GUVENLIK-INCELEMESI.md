# Güvenlik incelemesi

Bu fork'a alınmadan önce [krishhgg/Insomnia](https://github.com/krishhgg/Insomnia)
kaynak kodu ve yayınlanan derlemesi incelendi. Amaç, uygulamanın saldırgan bir
davranış içerip içermediğini ve kullanıcı verisini dışarı aktarıp aktarmadığını
görmekti.

- **Tarih:** 2026-10-20
- **İncelenen kaynak:** `main` dalında `e242782584451a4fa4479bbd8f5a5e149d2f254c` (2026-10-19)
- **İncelenen derleme:** `nightly-20261019-e24278258445` sürümü, `Insomnia-0.1.0-nightly-20261019-e24278258445-macos.zip`

## Sonuç

**Kötü amaçlı kod, veri sızdırma, gizli ağ trafiği ya da yapay zekâ ajanlarına
yönelik prompt injection bulunmadı.** Uygulama yalnızca anlattığı işi yapıyor:
kapak kapalıyken uykuyu zamanlı olarak engelliyor, seçilen uygulamaları
donduruyor, ekranı karartıp sesi kapatıyor ve Wi-Fi düşerse hotspot'a geçiyor.

## Yöntem

1. **Kaynak kod satır satır okundu.** Swift kaynaklarının tamamı (`Sources/`),
   kurulum, kaldırma ve kurtarma betikleri (`scripts/`), CI iş akışları
   (`.github/`), yapay zekâ ajanlarına yönelik talimatlar (`skills/`) ve
   testler dört ayrı incelemede gözden geçirildi.
2. **Yayınlanan derleme REA ile statik olarak analiz edildi.** REA,
   [morluto/rea](https://github.com/morluto/rea) projesinin `rea-agents` 6.7.0
   npm paketidir; paketin kayıt imzaları ve provenance kaydı doğrulandı.
   Kullanılan komutlar: `inspect-artifact`, `inspect-macho`, `inspect-plist`,
   `inspect-signature`, `list-architectures`, `trace-dylib-resolution`.
3. **Derlemenin kaynağı doğrulandı.** Zip'in SHA-256 özeti tuttu. GitHub
   derleme kanıtı (`gh attestation verify`), zip'in bu commit'ten upstream'in
   `release.yml` iş akışıyla üretildiğini doğruladı.
4. **Kaynak koddan bu fork'un derlemesi alındı** ve REA ile yayınlanan
   derlemeyle karşılaştırıldı (aşağıda).

## Bulgular

### Ağ
- **Tek dış istek, Ayarlar'daki "Güncellemeleri Denetle" düğmesine
  basıldığında yapılır.** Bu istek `api.github.com` üzerinden upstream'in sürüm
  listesini GET ile okur. Gönderilen tek bilgi, User-Agent başlığındaki uygulama
  sürümüdür. Yönlendirmeler reddedilir. Uygulama hiçbir şeyi indirmez, kurmaz ya
  da çalıştırmaz.
- `NWPathMonitor` yalnızca Wi-Fi bağlantısının durumunu izler, ağ trafiği
  oluşturmaz.
- Betiklerde `curl`, `wget`, `nc`, `ssh` ya da indirilen bir içeriği çalıştırma
  yoktur.

### Yetki (`sudo`)
`/etc/sudoers.d/insomnia` dosyası tam olarak şu dört komuta izin verir, joker
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
  (`com.insomnia.backstop`). Girişte ve her 60 saniyede bir çalışır. Önce
  uygulamanın imzasını sabitlenmiş cdhash'e karşı `codesign --verify --strict`
  ile doğrular, ardından paketin içindeki mühürlü `backstop.sh` betiğini
  çalıştırır.
- **Olmayanlar:** LaunchDaemon, cron, kabuk profili değişikliği ya da
  `/Library` altına yazma yoktur.

### Veri
- **Ayarlar ve kayıtlar:** Ayarlar ve geri alma kayıtları
  `~/Library/Application Support/Insomnia/` altında tutulur. Dosyalar 0600,
  klasörler 0700 izinlidir.
- **Loglar:** Loglar `~/Library/Logs/Insomnia/` altındadır. Wi-Fi adı (SSID),
  uygulama adları ve aygıt adları burada açık metin olarak durur ama
  bilgisayardan çıkmaz.
- **Hotspot parolası:** Giriş Anahtar Zinciri'nde tek bir kayıt olarak
  saklanır (servis `insomnia-hotspot`). Hiçbir zaman loglanmaz ve komut
  satırına geçirilmez. Uygulama başka Anahtar Zinciri kayıtlarını okumaz.
- **Konum izni:** Yalnızca macOS'un Wi-Fi adlarını gösterebilmesi için istenir.
  Konum verisi okunmaz ya da saklanmaz.
- **Okunmayan veriler:** Pano, ekran içeriği, tarayıcı geçmişi ya da sekmeleri,
  SSH anahtarları ve kabuk geçmişi okunmaz.

### Diğer uygulamalar
- **Dondurma:** `SIGSTOP`/`SIGCONT` sinyalleri yalnızca dondurma listesindeki
  uygulamalara gönderilir; varsayılan liste Slack, WhatsApp ve Discord'dur. Her
  süreç, başlangıç zamanı ve önyükleme oturumuyla doğrulanır. Apple
  uygulamaları, ajan uygulamaları ve parola yöneticileri hiçbir zaman
  dondurulmaz.
- **Ajanlar için App Nap:** İsteğe bağlıdır ve varsayılan olarak kapalıdır.
  Açılırsa ajan uygulamalarının `NSAppSleepDisabled` tercihini yazar, oturum
  sonunda eski değeri geri koyar.
- **tmux dürtmesi:** İsteğe bağlıdır ve varsayılan olarak kapalıdır. Yalnızca
  sizin `@insomnia-nudge on` ile işaretlediğiniz bölmelere sabit `continue`
  kelimesini yazar.
- **Tarayıcıyı yeniden başlatma:** Yalnızca menüden seçip onay verdiğinizde
  çalışır. Tarayıcının yalnızca komut satırı bayraklarını okur; sekmelerine ya
  da geçmişine bakmaz.
- **Özel Apple API'leri:** Ekran ve klavye parlaklığı için DisplayServices ve
  CoreBrightness, sabit sistem yollarından `dlopen` ile yüklenir. Bunların
  dışında dışarıdan kod yüklenmez.

### REA bulguları (yayınlanan derleme)
- **İmza:** Ad-hoc imzalıdır (Team ID yok). Kimlik `com.kgarg.insomnia`,
  cdhash `ba6e339c1e4c57e58d7a178c1661a3ff45ab7ce5`. Entitlement ve hardened
  runtime yoktur.
- **Mimari:** Yalnızca arm64. Minimum sistem macOS 26.0, SDK 26.5.
- **Bağımlılıklar:** 39 dinamik kütüphanenin tamamı `/System/Library` ya da
  `/usr/lib` altındaki Apple kütüphaneleridir. Üçüncü taraf framework ya da
  `@rpath` kütüphanesi yoktur.
- **Ağ ile ilgili importlar:** Yalnızca `NSURLSession` (güncelleme denetimi) ve
  `NWPathMonitor` vardır. Soket, `NWConnection` ya da `posix_spawn` yoktur.
- **Gömülü adresler:** Binary'de yalnızca üç GitHub adresi vardır: upstream
  sürüm sayfası ve iki API ucu.
- **Info.plist:** Kaynaktaki dosyayla aynıdır.
- **Paket içeriği:** `MacOS/Insomnia`, `Info.plist`, `Resources/AppIcon.icns`
  ve `Resources/backstop.sh`. Yardımcı araç, XPC hizmeti ya da ayrıcalıklı
  yardımcı yoktur.

### REA karşılaştırması (bu fork'un Türkçe derlemesi)
Türkçe kaynak `scripts/build-app.sh` ile derlendi ve aynı REA komutlarıyla
yayınlanan derlemeyle karşılaştırıldı.

- **Hassas importlar birebir aynı.** Süreç ve sinyal (`libSystem`), Anahtar
  Zinciri ve imza (`Security`), güç (`IOKit`), `Network`, Wi-Fi (`CoreWLAN`),
  konum, giriş öğesi, bildirim, ses (`CoreAudio`) ve `AppKit` importlarında
  fark yok.
- **Gömülü adresler aynı:** Yalnızca üç GitHub adresi var.
- **Paket yapısı ve imza türü aynı:** Ad-hoc imza, entitlement yok.
- **`Info.plist` farkı yalnızca yerelleştirme:** `CFBundleDevelopmentRegion = tr`
  ve konum izni metni Türkçe.
- **Diğer farklar derleyiciden kaynaklanıyor:** Yerel SDK `NSURLSession`'ı ayrı
  `CFNetwork` kütüphanesi yerine `Foundation` üzerinden bağlıyor ve birkaç
  SwiftUI sembolü farklı. Yeni bir yetenek ya da kütüphane eklenmedi.

Kurulumda derleme makinenizde yeniden alındığı için cdhash her derlemede
farklı olur.

### Kötü amaçlı olmayan zayıf noktalar
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

## Bu fork'ta yapılanlar
- **GitHub Actions:** Upstream CI'ı gizli repoda her gün macOS üzerinde derleme
  yapıp Actions dakikası tüketeceği için Actions kapatıldı.
- **Dependabot:** `.github/dependabot.yml` kaldırıldı.
- **İtilenler:** Yalnızca `main` dalı itildi. Upstream'deki `pr-evidence`
  dalı, yazarın test sanal makineleri için hazırladığı ve gerçek bir Mac'te
  çalıştırılması zararlı olabilecek betikler içerdiğinden alınmadı.
- **Türkçeleştirme:** Arayüz, bildirimler, kurulum mesajları ve belgeler
  Türkçeleştirildi. Davranış değişmedi; yalnızca süre girişine Türkçe birimler
  (`30dk`, `2sa`, `3g`) eklendi.
