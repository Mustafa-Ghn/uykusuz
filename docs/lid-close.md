# Kapak kapanınca neler olur

[README](../README.md#kapak-kapanınca-neler-olur) varsayılanları listeler. Bu
sayfa ayrıntıları içerir.

Oturum sırasında Uykusuz ekranı ve klavye arka ışığını kapatır (önce
parlaklıklarını kaydeder), dondurma listesindeki uygulamaları dondurur (ve
seçerseniz ajan uygulaması olmayan diğer tüm Dock uygulamalarını da), Docker
Desktop'ı duraklatmadan önce boşta olup olmadığını denetler ve sesi kaydedip
kapatır. Kapağı yeniden açmak bu kapak eylemlerini geri almaya çalışır.
Uykusuz hâlâ Docker'ı denetlerken kapak açılırsa Docker çalışır durumda
bırakılır ve geri alma hemen başlar. **Kapak kapalıyken zamanlayıcı geri
saymayı sürdürür**; yalnızca ekrandaki yeniden çizim duraklar, kapak zaten
kapalıyken başlatılan bir oturumda da.

## Ekran ve klavye arka ışığı

Ekran adımı, uyku koruması macOS'in bunu yapmasını engellediği için vardır:
uyku kapalıyken kapağı kapatmak paneli ya da tuşları artık kendiliğinden
kapatmaz. Uykusuz ikisini de sıfıra ayarlar ve kapak açılınca geri yükler.
İkisi de macOS'in özel (private) çerçeveleri üzerinden çalışır. Ekran
çağrıları yalnızca üzerinde ölçüldükleri macOS ana sürümlerinde (26 ve 27)
çalışır. Klavye çağrıları, macOS sürümü ne olursa olsun, yalnızca özel klavye
sınıfı macOS 26 üzerinde ölçülen yöntem imzalarına sahipken çalışır. Bu
denetimlerden biri bir aygıtı reddederse Uykusuz o aygıta dokunmaz ve Ayarlar
nedenini anahtarın altında söyler. Bir güncellemeden önce kaydedilmiş ve
denetimin artık reddettiği bir düzey, onu geri yükleyebilecek bir sürüm için
kayıtlı kalır; menü de bu arada düzeyi parlaklık tuşlarıyla ayarlamanızı
söyler. O sürüm, elle ayarladığınız bir düzeye dokunmaz ve kararını yalnızca
ekran uyanıkken ve tuşlar kısılmamışken alınan bir okumaya göre verir.
Kaydedilmiş bir ekran düzeyi varken Uykusuz'un kendi Düşük Güç Modu bir kez
açık kaldıysa Uykusuz, uygulama yeniden açılsa bile, Mac yeniden başlayana
kadar o düzeyi kararsız bırakır; o zamana kadar bir kapak kapanışı o ekranı
yanık bırakır ve yalnızca uyumasını ister. Aynısı, kurtarma ajanı bu modu
Uykusuz yeniden başlamadan önce kapattığında ve Uykusuz bir yeniden
başlatmadan önceden kalma, hâlâ sahiplenilmiş bir modu kapattığında da
geçerlidir. Mod o anda kapalı görünebilir, ama yalnızca bir an önce kapanmış
olabilir; bu yüzden mod günlerdir kapalı olsa bile düzey bir sonraki yeniden
başlatmayı bekler. Uykusuz o ekranı sıfırın üzerinde yanık gördükten sonra,
bir yeniden açılış ya da yeniden başlatmadan sonra da, elle ayarladığınız bir
sıfırın üzerine kaydedilmiş düzeyi hiçbir zaman yazmaz. O sıfırı, otomatik
parlaklığın kapanan bir kapağın altında bıraktığı bir sıfırdan ayıramaz; bu
yüzden siz ekranı sıfırın üzerine çıkarana kadar kaydedilmiş düzey, hiçbir şey
yazılmadan kararsız kalır. Uykusuz ekranı yanık gördüğünü ya da kaydedilmiş
düzeyin karara bağlandığını kaydedemezse "Uykusuz'dan Çık" bunu
kaydedebilene kadar bekler.
Ekran, kapanma anındaki okumaya değil, kapak açıkken örneklenen parlaklığa
döner (otomatik parlaklık o ana kadar paneli kapanan kapağın altında zaten
kısmıştır ve Düşük Güç Modu onu yeniden ölçeklendirir). Kapak kapalıyken
Uykusuz'un kendi Düşük Güç Modu açıksa değer, mod bittiğinde bir kez daha
yazılır. Kapağı açtığınızda Uykusuz çalışmıyorsa parlaklık artırma tuşuna
basın.

## Varsayılanlar

Varsayılanları bilmekte yarar var:

- **Seçili uygulamalar:** Slack, WhatsApp ve Discord dondurma listesindedir.
  Ayarlanmış ajan uygulamaları bu sıradan listenin dışında tutulur.
- **Diğer tüm uygulamalar:** "Kapak kapalıyken diğer tüm uygulamaları dondur"
  kapalıdır; bu yüzden yeni bir kurulum yalnızca dondurma listesini dondurur.
  Ajan uygulaması, Apple uygulaması, Docker Desktop ya da yerleşik korumalı bir
  uygulama (düzenleyiciler, terminaller, tarayıcılar, yapay zekâ uygulamaları,
  parola yöneticileri, yerel veritabanları, Tailscale, yerel model sunucuları;
  paket kimliği önekine göre JetBrains IDE'leri) olmayan her Dock uygulamasını
  da dondurmak için bu seçeneği açın; böylece kapak kapalıyken yalnızca ajanlar
  çalışmayı sürdürür. Menü çubuğu uygulamaları hiçbir zaman otomatik olarak
  seçilmez; dondurulmalarını istiyorsanız onları dondurma listesine ekleyin.
  Ayarlar, otomatik kapsamın o anda neleri donduracağını listeleyen bir
  "Şu anda dondurulacaklar" satırı gösterir.
- **Toplantı, kayıt ve dikte uygulamaları:** "Diğer tüm uygulamaları dondur"
  bunları ve yardımcı uygulamalarını hiçbir zaman dondurmaz: Zoom, Microsoft
  Teams (yeni ve klasik), Webex (ve daha eski Webex Meetings uygulaması),
  FaceTime, Wispr Flow, Granola, Otter, OBS ve Loom. Bunlardan birini
  dondurmak, kapak kapanınca görüşmeyi, kaydı ya da toplantı notlarını
  sonlandırır. Birini dondurma listesine elle eklemek onu yine de dondurur;
  bunun tek istisnası bir Apple uygulaması olan FaceTime'dır.
- **Docker kuralı:** kapalı. Hiçbir kapsayıcı çalışmıyorken Docker Desktop'ı
  kapak kapanınca duraklatmak için açın. Yerel Desktop soketine bir kez
  Docker'ı seçmek için, bir kez de duraklatmadan hemen önce sorulur; bu iki
  noktadan birinde meşgul yanıtı, başarısız bir `docker ps` ya da zaman aşımı
  Docker'ı çalışır durumda bırakır. İkinci denetim ile duraklatma arasında
  başlayan bir kapsayıcı da Desktop ile birlikte duraklatılır; bu yüzden
  beklenmedik bir duraklatmanın zarar vereceği Docker iş yükleri için kuralı
  kapalı bırakın.
- **Kapak kapanınca sesi kapat:** açık; böylece kapak kapanınca ses durur.
  Kapağı açmak, sesi kapatılan her çıkışı, o sırada başka biri kullanılıyor
  olsa bile geri yükler. Bağlı olmayan bir çıkış yeniden bağlanana kadar sessiz
  kalır: Uykusuz çalışıyorsa onu o zaman, çalışmıyorsa bir sonraki açılışta
  geri yükler. Oturumu bitirmek ya da Uykusuz'dan çıkmak bunu beklemez. Bitiş
  bildirimi ve menü o çıkışı adıyla belirtir; menüdeki
  "Beklemeyi bırak: <aygıt>" onu olduğu gibi bırakır. Bağlı bir çıkışta
  başarısız olan bir geri yüklemeyi Uykusuz çalıştığı sürece ve bir sonraki
  açılışta yeniden dener.
- **Mikrofon:** Apple çipli ya da T2 çipli Mac dizüstü bilgisayarlarda kapağı
  kapatmak, yerleşik mikrofonun bağlantısını donanım düzeyinde keser. Kapak
  kapalıyken bir toplantıyı kaydetmek için AirPods ya da harici bir mikrofon
  gerekir; Ayarlar da kapak kapanınca yapılacaklar seçeneklerinin yanında
  aynısını söyler.
- **Ekran ve klavye arka ışığı:** açık (Ayarlar'da "Ekranı ve klavye arka
  ışığını kapat"). İki değer de değiştirilmeden önce kayıt defterine
  kaydedilir.
- **Kapak kapalıyken Düşük Güç Modu:** açık. Uyku kapalıyken kapalı bir Mac
  aksi hâlde tam hızda çalışmayı sürdürür; bir pil ya da ısı kuralı hâlâ
  istemiyorsa mod kapak açılınca yeniden kapatılır.
- **Pil kuralları:** pil gücündeyken pil düzeyi %40 eşiğinin altına inince
  Düşük Güç Modu istenir; %10 eşiğinin altında oturum biter. Pil gücündeyken
  var olan ama art arda iki okumada okunamayan bir pil de oturumu bitirir ve
  nedenini söyleyen bir bildirim gösterilir: kimsenin okuyamadığı bir düzeye
  alt sınır uygulanamaz. Tek bir başarısız okumaya göz yumulur ve düzey yeniden
  okunabilir hâle gelene kadar her 30 saniyede bir yeniden okunur. Masaüstü bir
  Mac'te pil ve alt sınır yoktur. Ciddi ısı durumu Düşük Güç Modu ister;
  kritik ısı durumu oturumu bitirir. Bu kurallar uygulamanın çalışıyor olmasını
  gerektirir.
  Bitirme alt sınırını 0 yapmak pil nedeniyle bitirmeyi kapatır. Aksi hâlde
  bitirme alt sınırı Düşük Güç Modu alt sınırının altında kalır. İki sınır
  kesişecek olduğunda Ayarlar'daki artırma/azaltma düğmeleri diğer sınırı da
  kaydırır; alt sınırları sırası bozuk biçimde elle düzenlenmiş bir
  `config.json` ise açılışta Düşük Güç Modu alt sınırı yükseltilerek düzeltilir
  ve bu durum günlüğe yazılır.

## Önceki bir derlemeden yükseltme

Önceki bir derlemeden yükseltmek bu ayarlardan ikisini bir kez değiştirir. Bu
sürümün ilk açılışında, önceki bir derlemenin kaydettiği config.json
dosyasında "Kapak kapalıyken diğer tüm uygulamaları dondur" kapatılır ve
"Kapak kapanınca sesi kapat" açılır; Uykusuz neyin değiştiğini belirten bir
bildirim gösterir. Bildirimleri kapalı olan kullanıcılar için Ayarlar da aynı
satırı, siz kapatana kadar Kapak kapanınca yapılacaklar bölümünün en üstünde
gösterir. İlgili anahtarlar hemen altındadır. config.json bu güncellemenin
çalıştığını kaydeder (`lidCloseDefaultsApplied`); böylece eski hâline
getirdiğiniz bir ayar sizin bıraktığınız gibi kalır. Yeni bir kurulum yeni
varsayılanlarla ve bildirim olmadan başlar.

## Kapak eylemlerini kapağı kapatmadan deneme

Kapak eylemlerini kapağı kapatmadan denemek için bir oturum sırasında
`scripts/simulate-lid.sh closed` ve ardından `scripts/simulate-lid.sh open`
çalıştırın; uygulama gerçek bir kapak olayında yapacağı eylemlerin aynısını
yapar. Bu tetikleyiciyi yalnızca dosya izleyicisi derlemeye dahil edilmiş bir
derleme okur: bir hata ayıklama (debug) derlemesi ya da
`UYKUSUZ_LID_SIMULATION=1 ./scripts/install.sh` ile kurulmuş bir release
derlemesi. Normal bir kurulumda izleyici yoktur; bu yüzden sizin hesabınızla
çalışan hiçbir program bir dosya yazarak kapak eylemlerini yeniden
oynatamaz. İzleyicisi olan bir derleme açılışta günlüğe "Kapak simülasyonu
derlemesi" ile başlayan bir satır yazar ve aynı satırı durum menüsünde ve
Ayarlar'da gösterir.
