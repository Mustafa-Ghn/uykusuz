# Güvenlik politikası

Uykusuz deneysel bir yazılımdır ve güvenlik bildirimleri için bir yanıt süresi
taahhüdü (SLA) yoktur. Bir güvenlik açığından şüpheleniyorsanız onu `main`
dalının güncel hâline karşı; etkilenen commit'i ve en küçük, zarar vermeyen
bir yeniden üretme adımını ekleyerek bildirin.

## Bildirme

Parolaları, Anahtar Zinciri verilerini, kişisel günlükleri ya da silaha
dönüştürülmüş istismar ayrıntılarını bir issue'ya yazmayın. GitHub bu
deponun Security sayfasında **Report a vulnerability** düğmesini
gösteriyorsa o özel kanalı kullanın. Göstermiyorsa hassas ayrıntıları
yazmadan yalnızca özel bir güvenlik iletişimi isteyen bir issue açın ve
bakımcının bir kanal ayarlamasını bekleyin.

## Güvenlik modeli

**Yetki.** Kurulum betiği, kullanıcı hesabına README'de listelenen dört
`pmset` komutunu parolasız çalıştırma izni verir. Bu izin Uykusuz'a özel
değildir: aynı kullanıcıyla çalışan diğer süreçler de bu komutları
çalıştırabilir. Bu dört komut dışında root olarak çalışan bir şey yoktur.

**Ağ.** Uykusuz hiçbir ağ isteği yapmaz: güncelleme denetlemez, kullanım
verisi ya da çökme raporu göndermez. `NWPathMonitor` yalnızca Wi-Fi
bağlantısının durumunu izler.

**Yerel veriler.** Uygulama korumalı alanda (sandbox) çalışmaz; yerel
günlükler Wi-Fi adlarını, süreç bilgilerini ve tmux hedef adlarını
içerebilir. Uygulamanın `uykusuz.log` dosyasına yazdığı satırlar birleşik
günlüğe (unified log) de gider, ama gövdeleri özel olarak işaretlenir:
Mac'te özel veri günlüğü açılmadıkça `log show` okuyan programlar bu adlar
yerine `<private>` görür. Uykusuz'un oluşturduğu dosyalar (günlükler, kayıt
defteri, oturum, yapılandırma, kurtarma kilidi) 0600, klasörleri 0700
izinlidir; kurtarma betiği `umask 077` ile çalışır. Uykusuz yalnızca bu
izinleri ayarlar ve bu dosyalardaki erişim denetim listelerine (ACL)
dokunmaz; bu yüzden birinin eklediği bir ACL başka bir hesaba yine erişim
verebilir. Günlükler 1 MiB ile sınırlıdır ve bir eski kopyası tutulur.
Kullanıcının bir sembolik bağlantıyla değiştirdiği günlük döndürülmez
(rotate): işaret ettiği dosyayı yönetmek kullanıcıya kalır.

**Konum izni.** Konum Servisleri izni yalnızca bir hotspot kaydedildiğinde ya
da hotspot ayarlıyken bir oturum başladığında istenir. Wi-Fi ağ adlarını
okumak için kullanılır; uygulama hiçbir zaman konum güncellemesi istemez.

**Diğer uygulamalar.** App Nap ayarı açıkken (varsayılan olarak kapalı)
uygulama, ajan listesindeki her uygulamanın tercihlerine
`NSAppSleepDisabled` yazar; önce önceki değeri kayıt defterine kaydeder ve
oturum sonunda geri koyar. Dondurma, kapak kapalıyken uygulamaların
süreçlerine `SIGSTOP` gönderir; Uykusuz yalnızca kendi dondurduğunu
doğrulayabildiği süreçleri `SIGCONT` ile çözer ve her süreci başlangıç zamanı
ve önyükleme oturumuyla doğrular. Apple uygulamaları, ajan uygulamaları ve
parola yöneticileri hiçbir zaman otomatik olarak dondurulmaz.

**Claude entegrasyonu.** Otomatik oturum, güç kilitlerini IOKit üzerinden
yalnızca okur (`IOPMCopyAssertionsByProcess`). Claude Code hook'ları
isteğe bağlıdır ve Ayarlar'dan kurulur: `~/.claude/settings.json` dosyasına
hiçbir çıktı vermeyen ve hep başarılı dönen bir komut ekler, dosyanın eski
hâlini yedekler. Komut, uygulama destek klasörüne oturum başına 0600 izinli
bir işaret dosyası yazar ya da onu siler. Claude'un başlattığı komutları
algılamak için yalnızca kullanıcının kendi süreçlerinin adları ve
argümanları okunur.

**Ekran ve girdi.** Boşta siyah ekran yalnızca son girdiden geçen süreyi
okur (`CGEventSource.secondsSinceLastEventType`); bunun için tuş vuruşlarını
okumaz, sahte tuş ya da olay göndermez. Süre kutuları açıkken menü çubuğu, dışarı
tıklanınca kutuları kapatmak için yalnızca fare tıklamalarını dinler. Ekran
ve klavye parlaklığı için macOS'in özel DisplayServices ve CoreBrightness
çerçeveleri sabit sistem yollarından `dlopen` ile yüklenir; bunların dışında
dışarıdan kod yüklenmez. Sesli uyarılar `/usr/bin/say` ile söylenir; metin
tek bir argüman olarak, `--` ayıracından sonra verilir.

## Hotspot parolası

Hotspot parolası giriş Anahtar Zinciri'nde genel bir parola kaydıdır
(servis `uykusuz-hotspot`). Erişim listesi yalnızca onu kaydeden Uykusuz
derlemesini adlandırır; bu yüzden onu isteyen başka bir program, reddedebileceğiniz
sistem Anahtar Zinciri istemini alır. Uykusuz kaydı istemler kapalıyken
okur: okuyamadığı bir kayıt, istem gösterilmeden ya da sessizce yok
sayılmadan menüde ve Ayarlar'da bildirilir. İki sınır kalır. Ad-hoc imza her
kuruluma yeni bir kod kimliği verir; bu yüzden erişim listesi tek bir
derlemeyi sabitler ve parola yeniden kurulumdan sonra tekrar girilmelidir
(kararlı bir imza kimliği, yani Developer ID, erişim listesinin onunla
imzalanmış her derlemeyi adlandırmasını sağlardı). Ayrıca kayıt, veri
koruma erişilebilirlik sınıflarını (yalnızca bu aygıt, kilit açıkken) yok
sayan dosya tabanlı giriş Anahtar Zinciri'nde durur; diğer Anahtar
Zinciri'ni kullanmak bir erişim grubu yetkisi (entitlement) ve dolayısıyla
bir takım kimliği gerektirir. Uykusuz ad-hoc imzalandığı için iki sınır da
geçerlidir.

## Kurtarma ajanı ve kod imzası

Kurtarma LaunchAgent'ı yalnızca imzalı uygulama paketinin içine mühürlenmiş
`backstop.sh` betiğini çalıştırır; bunu da plist dosyasında sabitlenen kod
gereksinimine (ad-hoc bir imza için derlemenin cdhash değeri) karşı
`codesign --verify --strict` geçtikten sonra yapar. Düzenlenmiş bir paket ya
da betik reddedilir ve günlüğe yazılır. Uygulama, çalıştırdığı kodu sabitler
(diskteki paketin hâlâ o kod olduğunu ve ajanın denetiminden geçtiğini
doğruladıktan sonra kendi belirlenmiş gereksinimini); bu yüzden çalışan
uygulamanın altında düzenlenen ya da yeniden imzalanan bir paket yeniden
sabitlenmez, reddedilir. plist dosyası ise `~/Library/LaunchAgents` içinde
durur ve her kullanıcıya özel LaunchAgent gibi, o kullanıcıyla çalışan
herhangi bir program tarafından düzenlenebilir. Ad-hoc imzalarla bu
denetimler kazalara ve uygulamanın kurcalanmış bir paketi ajana aktarmasına
karşı bütünlük sağlar; aynı kullanıcıyla çalışan bir sürece karşı bir sınır
değildir: böyle bir süreç plist dosyasını düzenleyebilir, kendi ajanını
yükleyebilir, uygulamayı kapatıp yerine başkasını başlatabilir ve dört `pmset`
komutunu doğrudan çalıştırabilir.

## Derlemeler

Uykusuz hazır derlenmiş bir paket olarak yayımlanmaz; kurulum betiği
uygulamayı kaynak koddan ad-hoc imzalı olarak derler. Depodaki Release iş
akışıyla bir sürüm yayımlanırsa zip dosyası bir `SHA256SUMS` dosyası ve bir
GitHub derleme kanıtı (attestation) ile yayımlanır; doğrulama adımlarını
[docs/releasing.md](docs/releasing.md) anlatır. `install.sh --app`, parola
istemeden önce paketin özel bir kopyasının imzasını, tanımlayıcısını ve
sürümünü denetler, o kopyayı kurar ve bir paketin nereden geldiğini
doğrulayamadığı için `--allow-unverified-origin` verilmedikçe kurmayı
reddeder. Derleme kanıtı, baytları hangi iş akışı çalıştırmasının ürettiğini
gösterir; kodun kusursuz olduğunu göstermez. Paketler Apple'ın onay sürecinden
(notarization) geçmediği için macOS indirilen bir kopyanın ilk açılışını
engeller.

Otomatik denetimlerin ya da bir gizli bilgi taramasının geçmesi açık
olmadığını kanıtlamaz. Kurtarmayı başkasının süreçlerini, güç ayarlarını,
ağını ya da verilerini bozarak denemeyin.

Uygulamanın ayrıntılı incelemesi için:
[GUVENLIK-INCELEMESI.md](GUVENLIK-INCELEMESI.md).
