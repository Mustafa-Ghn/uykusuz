# Ek özellikler

[README](../README.md#ek-özellikler) her birinin özetini içerir.

## iPhone kişisel erişim noktasına (hotspot) geçiş

**Sistem Ayarları → Wi-Fi → "Erişim noktalarına katılmak için sor" (Ask to
join hotspots) → Otomatik** ayarını yapın, ardından hotspot ağ adını (SSID) ve
parolasını Uykusuz'un Ayarlar penceresine girin. Parola giriş anahtar
zincirinde `uykusuz-hotspot` hizmet adıyla saklanır. Uykusuz, parolayı süreç
argümanlarına koymadan o ağı bulmak ve ona katılmak için CoreWLAN kullanır.

Anahtar Zinciri öğesinin erişim listesinde yalnızca onu kaydeden Uykusuz
derlemesi bulunur ve Uykusuz öğeyi Anahtar Zinciri istemleri kapalıyken okur;
böylece bir kesinti sırasında yapılan bir katılma hiçbir zaman bir iletişim
kutusu açmaz. Kurulum betiği her derlemeyi ad-hoc imzalar ve bu, her kuruluma
yeni bir kimlik verir: yeniden kurulumdan sonra kaydedilmiş parola yeni derleme
tarafından okunamaz. Uykusuz o zaman katılmayı atlar, sağ tıklama menüsünde ve
Ayarlar'da "Bu derleme hotspot parolasını okuyamıyor" uyarısını gösterir ve her
kesinti için bir bildirim gönderir. Uyarı, okunduğu SSID'ye
aittir. SSID'yi değiştirdiğinizde uyarı kalkar ve Ayarlar bunun yerine yeni
SSID'nin kayıtlı parolasını denetler. Parolayı Ayarlar'da yeniden girip
kaydedin; kaydetme, eski öğeyi kaldırmadan önce yeni parolayı yazar ve macOS,
Uykusuz'un eski öğeyi silmesine izin vermenizi ya da giriş anahtar
zincirinin kilidini açmanızı isteyebilir. Eski öğe gittikten sonra kaydetme
yarıda kesilirse parola eksik görünür ve onu bir kez daha girersiniz: Uykusuz
yarım kalmış bir kaydetmenin kopyasını hiçbir zaman okumaz. Kaydet düğmesi
macOS yanıt verene kadar "Kaydediliyor…" yazar; "Kaydedildi" ise yalnızca SSID
ve parola alanları kaydedileni içerdiği sürece görünür. SSID'yi değiştirdiğiniz
sırada bekleyen bir katılma bırakılır ve bir sonraki yeniden deneme yeni SSID'yi
kullanır. Bekleyen bir Ayarlar okuması da bırakılır ve Ayarlar bunun yerine yeni
SSID'nin parolasını okur. Ayarlar kayıtlı parolayı hâlâ yüklerken parola
alanına yazdığınız her şey, onu yeniden silseniz bile kalır. Pil alt sınırı ve
oturumu bitirme dahil Uykusuz'un geri kalanı, iletişim kutusu açıkken
çalışmayı sürdürür. Kararlı bir kimlikle imzalanmış bir derleme, öğeyi
yükseltmeler boyunca okunabilir tutardı.

macOS, ağ adlarını göstermek için Konum Servisleri izni ister. Uykusuz bu
izni yalnızca açılışta değil, ilk hotspot kaydetmede ya da hotspot ayarlanmışken
bir oturum başlatıldığında ister. İzin verilmezse **Gizlilik ve Güvenlik →
Konum Servisleri** bölümünü açmak için Ayarlar'daki Konum satırını kullanın.
Mac uygulamalarında "kullanılırken" türünde bir izin yoktur; bu yüzden Sistem
Ayarları bunu Uykusuz için Konum Servisleri erişimi olarak kaydeder. Uykusuz
bu izni yalnızca CoreWLAN üzerinden Wi-Fi ağ adlarını okumak için kullanır ve
konumunuzu hiçbir zaman istemez.

## tmux dürtmesi

Uzun bir kesintiden sonra (varsayılan olarak 90 saniye) Uykusuz ayarlanmış
her tmux hedefine `continue` yazar. Varsayılan hedef listesi boştur ve
listelenen bir bölme yalnızca onu kendiniz işaretlediyseniz dürtülür; bu
işaret, her göndermeden önce yeniden okunan bir bölme seçeneğidir:

```bash
tmux set-option -p -t <oturum:pencere.bölme> @uykusuz-nudge on
```

İçine yazı yazdığınız bir bölmeyi değil, ajana ayrılmış ve gözden
çıkarılabilir bir bölmeyi işaretleyin; çünkü bölmede bekleyen metni Uykusuz
göremez. Enter varsayılan olarak kapalıdır; bu yüzden sözcük yazılır ama hiçbir
şey onu göndermez. Göndermek için Ayarlar'da "continue yazdıktan sonra Enter'a
bas" seçeneğini açın; Enter'ın o bölmede önceden yazılmış her şeyi de
göndereceğini unutmayın. Seçeneğin bölmenin kendisinde (`-p`) ayarlanmış
olması gerekir; oturumda ya da pencerede ayarlanan bir seçenek sayılmaz. Bölme
seçenekleri tmux 3.0 ya da üstünü gerektirir. Bir oturumu bitirmek bekleyen
otomasyonu iptal eder ama gönderilmiş tuş vuruşlarını geri alamaz.

## Chrome, Chromium, Arc ve Comet kısıtlaması

Chromium tabanlı tarayıcılar, kapak kapalıyken de dahil olmak üzere macOS'in
gizli (occluded) saydığı pencereleri kısıtlayabilir. Uykusuz,
`--disable-backgrounding-occluded-windows` ya da
`--disable-renderer-backgrounding` bayrağı olmadan çalışan desteklenen
tarayıcıları algılar ve sağ tıklama menüsünde **Kısıtlamasız yeniden başlat:
[tarayıcı]** seçeneğini sunar. Öğe önce sorar, çünkü tarayıcı kapatılır ve
pencereleriyle sekmeleri yalnızca tarayıcı açılışta onları yeniden açacak
şekilde ayarlanmışsa geri gelir. Siz onaylayana kadar tarayıcı zaten
kapanmışsa hiçbir şey kapatılmaz ya da başlatılmaz ve bir bildirim bunu söyler.
Uykusuz kapatmadan önce tarayıcının profil argümanlarını okur ve onları yeni
açılışa taşır. Onları okuyamazsa, onları tarayıcıya bağlayan çekirdek
başlangıç zamanını okuyamazsa ya da tarayıcı onlar okunurken kendiliğinden
kapanırsa hiçbir şeyi kapatmaz ve bunu söyler. Tarayıcı 10 saniye sonra hâlâ
kapanmamışsa hiçbir şey başlatılmaz ve bir bildirim bunu söyler: ilkinin
yanında ikinci bir kopya, kısıtlanmış bir kopyadan daha kötü olurdu. Kapatma
isteği geçerli kalır; bu yüzden daha sonra kapanan bir tarayıcının elle
yeniden açılması gerekir. `open` döndükten sonra Uykusuz tarayıcının çalışır
görünmesini 5 saniyeye kadar bekler; görünmezse bildirim gönderir. Bu
nedenlerin her biri, o tarayıcının bir sonraki yeniden başlatılmasına ya da bir
sonraki oturuma kadar, tarayıcı başına bir satır olmak üzere sağ tıklama
menüsünde bir uyarı satırı olarak da kalır; böylece bildirimler kapalıyken bile
orada görünür. Oturumu bittikten sonra ya da aynı tarayıcının daha yeni bir
yeniden başlatması başladıktan sonra biten bir yeniden başlatma hiçbir şey
bildirmez. Bu, her web uygulamasının kapak kapalıyken çalışmayı sürdüreceğinin
garantisi değildir.

## Yapılandırma ve gizlilik

Yapılandırma `~/Library/Application Support/Uykusuz/config.json` dosyasında
tutulur. Uygulamanın denetimleri için Ayarlar'ı kullanın; tam yapılandırmayı
ve varsayılanları [Config.swift](../Sources/Uykusuz/Model/Config.swift)
tanımlar. Uygulamanın tek ağ isteği isteğe bağlı "Sen yokken" özetidir:
yalnızca Ayarlar'da bir Claude API anahtarı kaydettiyseniz `api.anthropic.com`'a
gider ve yalnızca oturum başlıklarını, araç sayılarını, düzenlenen dosyaların
adlarını, Claude'un komut açıklamalarını ve son mesajlarının sonunu içerir.
Anahtar giriş Anahtar Zinciri'nde tutulur; config.json'a ve günlüğe yazılmaz
(ayrıntılar: [Sen yokken özeti](../README.md#sen-yokken-özeti)). Yerel günlükler SSID'leri, süreç meta verilerini ve tmux hedeflerini
içerebilir. Herkese açık olarak paylaşmadan önce onları gözden geçirin.
Uygulamanın `uykusuz.log` dosyasına yazdığı satırlar, gövdeleri özel
(private) olarak işaretlenmiş biçimde birleşik günlüğe (unified log) de
gider; bu yüzden Mac'te özel veri günlüğe kaydı açık değilse `log show` ve
diğer yerel programlar metin yerine `<private>` görür. backstop.sh betiğinin
satırları yalnızca `uykusuz.log` dosyasına gider; bu dosya ikisinin de tam
metnini tutar. Application Support/Uykusuz ve Logs/Uykusuz içindeki dosyalar
(yapılandırma, oturum, kayıt defteri, kurtarma kilidi, çalışır durumda
bırakılmış bir güç komutunun kaydı, iki günlük) yalnızca sahibine açıktır:
dosyalar 0600, bu iki klasör 0700 izinlidir; daha eski bir derlemenin daha
gevşek bıraktığı bir dosya, uygulama ya da backstop onu bir sonraki açışında
sıkılaştırılır. Uykusuz yalnızca bu izinleri ayarlar ve bu dosya ve
klasörlerdeki erişim denetim listelerine (ACL) dokunmaz; bu yüzden birinin
eklediği ya da üst klasörden devralınan bir ACL başka bir hesaba yine de erişim
verebilir (`ls -le` bunu gösterir). LaunchAgent plist dosyası ve kurulu
betikler hiçbir özel veri tutmaz ve kurulum betiğinin verdiği izinleri korur.
`uykusuz.log` ve `handoffs.log` 1 MiB ile sınırlıdır: sınırı aşan bir günlük,
önceki kopyanın yerini alarak `uykusuz.log.1` ya da `handoffs.log.1` olarak
yeniden adlandırılır ve yeni bir dosya başlar. Sınır, bir sembolik bağlantıyla
değiştirdiğiniz bir günlüğe uygulanmaz. Uykusuz bağlantı üzerinden yazar ve
onu hiçbir zaman döndürmez (rotate), çünkü yeniden adlandırma bağlantının işaret
ettiği dosyayı değil bağlantının kendisini taşırdı; bunu da bir kez günlüğe
yazar. Bağlantıyı siz kurduğunuz için işaret ettiği dosyayı kırpmak size
kalmıştır.

Uykusuz hiçbir ağ isteği yapmaz: güncelleme denetlemez, kullanım verisi ya da
çökme raporu göndermez. Hotspot'a bağlanma ve Wi-Fi durumunu izleme yerel
işlemlerdir; dışarıya veri gitmez.

`UYKUSUZ_HOME`, test amacıyla uygulama destek dosyalarının, günlüklerin ve
LaunchAgents klasörünün yerini değiştirir. Bir **kurulum korumalı alanı
(sandbox) değildir**: kurulum ve kaldırma, uygulama paketini ve sudoers kuralını
da kapsar. Kurulum betiği yeri değiştirilmiş bir ana klasörü reddeder. Düzen
için [Paths.swift](../Sources/Uykusuz/Store/Paths.swift) dosyasına bakın.
