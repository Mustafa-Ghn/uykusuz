# Sürüm notları

Uykusuz'un sürümleri, en yenisi en üstte. Sürüm numarası
`Resources/Info.plist` dosyasından gelir; kurulu sürüm Ayarlar > Uygulama'da
görünür.

## 0.12.3 — 2026-11-01

### Değişenler

- **Uykusuz sesi daha yüksek.** Okuma ve uyarılar yaklaşık 10 dB, yani kulağa iki kat kadar yüksek duyulur: doğal ses müzik ve videoların, 0.11.0'a kadar kullanılan Mac sesinin de altında kalıyordu. En çok ünsüzler ve kelime sonları yükselir, bu yüzden gürültülü yerde daha iyi anlaşılır; tepe noktaları sınırlandığı için ses patlamaz. Sessiz bir yerde fazla gelirse Mac'in sesini kısın.

## 0.12.2 — 2026-11-01

### Düzeltilenler

- **Sen yokken özeti bütün oturumları sayar.** Özet yalnızca en yeni dört oturumu gördüğü için daha fazlası çalışırken "dört oturum" diyordu. Artık çalışan ve sizi bekleyen oturumların tamamı sayılır; uzun bir komutu bekleyen ya da siz gitmeden soru sormuş oturumlar da buna dahildir ve aynı oturum iki kez sayılmaz.
- **Sizi bekleyen oturum özetin dışında kalmaz.** Daha yeni oturumlar varken onayınızı bekleyen bir oturum özette hiç geçmeyebiliyor, özet "onay bekleyen yok" diyebiliyordu. Artık ayrıntısına önce sizi bekleyen oturumlar için bakılır; ayrıntısına bakılan oturum sayısı dörtten sekize çıktı, kalanlar adı ve durumuyla özete girer.
- **Kapanmış oturum çalışıyor görünmez.** Süreci biten bir oturum özette "hâlâ çalışıyor" diye geçmez.

## 0.12.1 — 2026-11-01

### Düzeltilenler

- **Şarj aleti takılınca otomatik oturum geri gelir.** Oturum pil alt sınırında bittikten sonra Claude çalışmayı hiç bırakmıyorsa otomatik oturum, Mac şarja takılsa bile yeniden açılmıyor ve menü çubuğundaki göz kapalı kalıyordu; birkaç Claude oturumu aynı anda çalışırken bu saatlerce sürebiliyordu. Artık şarj aleti takılınca ya da pil eşiğin 5 puan üstüne çıkınca oturum kendiliğinden açılır. Elle bitirdiğiniz ya da kritik ısı veya okunamayan pil yüzünden biten oturum, önceki gibi Claude bir kez durup yeniden başlayana kadar açılmaz.
- **Testler klavye odağını almaz.** Uygulamanın testleri süre kutularını açarken klavye odağını alıyor, o anlarda başka bir uygulamaya yazılanlar oraya ulaşmıyordu. Test sürecinde görünmez panel artık odak almaz; uygulamanın kendisinde süre kutuları eskisi gibi çalışır.

## 0.12.0 — 2026-11-01

### Eklenenler

- **Seçilen alanı dinleme.** ⌃⌥S kısayoluna ya da göze sağ tıklayınca açılan menüdeki Alan seçip dinle öğesine basınca ekran kararır; fareyle çizdiğiniz alandaki yazı, ekranın sağ üstündeki küçük pencerede okunur. Okunan kelime vurgulanır, ❚❚ durdurur, çubuk ve ileri geri düğmeleri çalışır. Tarayıcıda, PDF'te, terminalde ya da bir resimde aynı şekilde çalışır; sütunlar, liste maddeleri ve tablo hücreleri sırayla, ayrı ayrı okunur.
- **Ayarlar > Seçilen alanı dinle.** Kısayolu açıp kapatır; başka bir uygulama ⌃⌥S kısayolunu kendine ayırmışsa bunu söyler.

### Değişenler

- **Yeni izin: ekran kaydı.** Yalnızca bu özellik için gerekir ve ilk basışta sorulur. Uykusuz ekrana yalnızca siz alan çizdikten sonra bir kez bakar, kendi pencereleri görüntüye girmez; görüntü bellekte kalır, yazı bu Mac'te tanınır, hiçbir şey diske yazılmaz ya da gönderilmez. Uygulama her kurulumda yeniden imzalandığı için izni yeni bir kurulumdan sonra yenilemek gerekir.

## 0.11.0 — 2026-11-01

### Eklenenler

- **Doğal Türkçe ses.** Uyarıları, özeti ve Claude'un yanıtını artık Uykusuz'la gelen yapay zekâ sesi okur. Ses bu Mac'te çalışır, ağa çıkmaz, hiçbir şey indirmez ve yalnızca okurken yüklenir; okuma bittikten 30 saniye sonra bellekten çıkar.
- **Teknik metin düzgün okunur.** `README`, `commit`, `API` ya da `Keychain` gibi kelimeler Türkçe okunuşuyla söylenir ve ekleri okunuşa uyar; sayılar, tarihler ve saatler ekleriyle okunur, `SummaryPlayer` gibi adlar parçalarına ayrılır, parantez içindeki kod adları ve `>` gibi işaretler okunmaz.
- **`Uykusuz --voice-check`** sesin çalışıp çalışmadığını ses çıkarmadan söyler.

### Değişenler

- **Varsayılan ses değişti.** Ayarlar > Kapak kapanınca yapılacaklar bölümündeki Doğal Türkçe ses seçeneği varsayılan olarak açıktır; kapatınca Mac'in Türkçe sesi okur. Ses yüklenemez ya da ses çıkışı açılamazsa okumayı yine Mac'in sesi sürdürür.
- **Uygulama büyüdü.** Ses dosyaları uygulamaya yaklaşık 33 MB ekler.

## 0.10.4 — 2026-11-01

### Düzeltilenler

- **Kısayol çakışması bildirilir.** Başka bir uygulama ⌃⌥D kısayolunu kendine ayırmışsa Ayarlar > Claude'un yanıtını dinle bölümü artık bunu söyler; önceki sürümde bu uyarı hiç çıkmıyordu. macOS diğer durumları bildirmez; o uygulama da aynı kısayolu kullanıyorsa ikisi de tepki verebilir.

## 0.10.3 — 2026-11-01

### Düzeltilenler

- **Docker kuralı, kapsayıcısını bekleyen işi dondurmaz.** "Çalışan kapsayıcı yokken Docker Desktop'ı duraklat" açıkken, imajını indirdiği için kapsayıcısını henüz açmamış bir `docker run` ya da `docker compose up` sürerken kapak kapanırsa Docker duraklatılıyor ve iş kapak açılana kadar asılı kalıyordu. Artık iki denetim de `docker ps -q` boş döndüğünde bu komutlara bakar; biri sürüyorsa Docker çalışır durumda kalır.
- **Kapsayıcı olarak görünmeyen diğer uzun işler.** `docker create`, `start`, `restart`, `load`, `import`, `save`, `export`, `commit`, `cp`, `prune`, `rm`, `rmi` ile `docker compose scale`, `watch` ve `down` sürerken de Docker duraklatılmaz. iPhone'a giden Docker mesajları değişmedi: yine yalnızca `build`, `pull` ve `push` komutlarını iş sayar, günlerce açık kalan bir `docker compose up` için mesaj gitmez.

## 0.10.2 — 2026-11-01

### Düzeltilenler

- **Kapalı kapağın altında yanık kalan ekran.** Uykusuz'un ekranı karartamadığı durumlarda (henüz ölçülmemiş bir macOS sürümü ya da okunamayan parlaklık) klavye ışığı da zaten kapalıysa (macOS onu gün ışığında kapatır) ekrandan uyuması istenmiyor ve ekran kapak kapalıyken yanık kalıyordu; 0.7.1'den beri böyleydi. Artık Uykusuz ekranın uyumasını ister ve kapak açılınca uyandırır, klavye ışığına yine dokunmaz. Ekranı açık tutan bir uygulama varken macOS bu isteği yok sayar.

## 0.10.1 — 2026-11-01

### Düzeltilenler

- **Sen yokken özeti süreleri karıştırmaz.** Özet, uzakta kaldığınız süreyi Claude'un çalışma süresi gibi gösteriyor, kapak hiç kapanmamış olsa bile "Kapak kapalıyken" diyordu. Artık "9 saat 4 dakika uzaktaydınız. Bu sürede Claude ... üzerinde çalıştı." der ve Claude'un en son çalıştığı saati yazar. Özeti Claude yazıyorsa ona da bu sürenin çalışma süresi olmadığı söylenir.
- **Uyanışta gereksiz oturum açılmaz.** Açık bırakılmış bir komut (örneğin bir veritabanı bağlantı aracı) Mac uykudan uyanırken birkaç an işlemci kullanınca Claude çalışıyor sayılıyor, kapak kapalıyken bile otomatik oturum açılabiliyordu. Artık Mac uyandıktan sonraki ilk 2 dakikada böyle bir komutun işlemci kullanımı sayılmaz; yeni başlayan komutlar ve Claude'un yürüttüğü görevler bundan etkilenmez.

## 0.10.0 — 2026-11-01

### Değişenler

- **Claude'un yanıtı artık siz isteyince okunur.** Claude bir işi bitirince kendiliğinden okumak yerine, Claude uygulamasında baktığınız sohbetin son mesajı Control+Option+D (⌃⌥D) kısayoluna ya da göze sağ tıklayınca açılan menüdeki "Son yanıtı dinle" öğesine basınca okunur. Aynı sohbette okuma sürerken yeniden basınca durur; başka bir sohbete geçip basınca o sohbetin yanıtı okunur.
- **Kendiliğinden okuma kaldırıldı.** "Claude'un yanıtını sesli oku" ayarı yok; Claude'un yanıtı artık diske de yazılmaz. Kısayol Ayarlar > Claude'un yanıtını dinle bölümünden kapatılır.

## 0.9.4 — 2026-11-01

### Değişenler

- **Uzun süreler.** Sen yokken özetinde, Docker mesajında ve sesli uyarıda süre yalnızca dakikayla yazılıyordu ("544 dakika"). Artık gün, saat ve dakikayla yazılır: "9 saat 4 dakika", "1 gün 2 saat 5 dakika". Özeti Claude yazıyorsa ona verilen süre de böyledir.

## 0.9.3 — 2026-11-01

### Düzeltilenler

- **Docker kuralı süren işi dondurmaz.** "Çalışan kapsayıcı yokken Docker Desktop'ı duraklat" açıkken, kapsayıcı olarak görünmeyen bir `docker build`, `docker pull` ya da `docker push` sürerken kapak kapanırsa Docker duraklatılıyor ve iş kapak açılana kadar asılı kalıyordu. Artık iki denetim de bu komutlara bakar; biri sürüyorsa ya da süreç tablosu okunamıyorsa Docker çalışır durumda kalır.

## 0.9.2 — 2026-11-01

### Düzeltilenler

- **Kayıtlı klavye ışığı düzeyi.** Geri yüklemesi daha önce reddedilmiş bir klavye ışığı düzeyi kayıtlıyken kapak, ışık kapalıyken kapanırsa düzey artık kapak açılınca geri yüklenir. 0.7.1'den beri macOS'in uyanırken geri getirdiği düzey elle ayarlanmış sanılabiliyor ve kayıtlı düzey silinebiliyordu.

## 0.9.1 — 2026-11-01

### Düzeltilenler

- **Kurulumdaki derleme uyarıları.** Kurulum sırasında görünen iki derleme uyarısı giderildi; uygulamanın davranışı değişmedi.

## 0.9.0 — 2026-10-31

### Eklenenler

- **Docker kullanılırken iPhone'a haber.** iMessage açıkken ve Mac'in başında değilken Docker Desktop'ta bir iş sürüyorsa (yeni açılan ya da yoğun çalışan bir kapsayıcı, `docker build`, `pull` ya da `push`) bir mesaj, iş bitince bir mesaj daha gelir; mesajda kapsayıcıların adı ve işin süresi yazar. Boşta açık duran kapsayıcılar için mesaj gitmez. Ayarlar > Claude sizi beklerken iPhone'a haber ver > Docker kullanılırken de haber ver ile kapatılır.

### Düzeltilenler

- **Mesaj hangi oturumu söylüyor.** Aynı anda çok sayıda Claude oturumu çalışırken iMessage "Uykusuz: Claude işini bitirdi ve yeni isteğinizi bekliyor." diye, oturumun adı ve son mesajı olmadan geliyordu. Artık her mesaj ilgili oturumun adıyla başlar. Oturuma ad verilmemişse Claude'un ürettiği ad, o da yoksa klasörün adı yazılır.

## 0.8.0 — 2026-10-31

### Eklenenler

- **Claude'un yanıtını dinleme.** Claude bir işi bitirince yalnızca size yazdığı son mesaj, ekranın sağ üstündeki küçük pencerede sesli okunur; önceki adımlar okunmaz. Kod blokları atlanır, bağlantı adresleri okunmaz, dosya yollarının yalnızca adı söylenir. Varsayılan olarak kapalıdır; göze sağ tıklayınca açılan menüdeki "Claude'un yanıtını sesli oku" ya da Ayarlar > Claude'un yanıtını dinle ile açılır. Claude Code hook'larının kurulu olması gerekir.
- **Son yanıtı dinle.** Kapak kapalıyken ya da ekran kilitliyken okunmayan son yanıtı, göze sağ tıklayınca açılan menüden sonradan dinlersiniz.

### Değişenler

- **Okuma penceresi uzun metni kaydırır.** Pencereye sığmayan bir metin kaydırılır ve okunan paragrafı izler; kısa özetlerin görünümü aynı kalır.

## 0.7.5 — 2026-10-27

### Düzeltilenler

- **Video izlerken ekran kararmaz.** Bir video oynarken (tarayıcı ya da oynatıcı ekranı açık tutarken) boşta siyah ekran ekranı karartmaz ve oturumu kilitlemez. Karanlıkken bir video başlarsa ekran geri açılır; süreler video bitince yeniden başlar, böylece video biter bitmez ekran kararmaz.

## 0.7.4 — 2026-10-22

### Eklenenler

- **Kilit açılınca özet.** "Sen yokken" özeti artık kilit açılınca da gelir: ekran en az 3 dakika kilitli kaldıysa, ister Ctrl+Cmd+Q ile ister boşta siyah ekranın kilidiyle, döndüğünüzde Claude'un o sırada yaptıkları gösterilir. Boşta siyah ekranın kilidinde süre, Mac'e son dokunduğunuz andan sayılır.

### Değişenler

- **Özet kilit ekranının arkasında kalmaz.** Kapağı kilit ekranında açarsanız özet, kilidi açtığınızda gelir; kapak ve kilit aynı yokluk sayılır ve özet bir kez gösterilir.

## 0.7.3 — 2026-10-22

### Eklenenler

- **Kararmış ekranı kilitleme.** Oturum sürerken kapak açıkken ekran karardıktan sonra 15 dakika dönmezseniz Uykusuz oturumu kilitler. Ekran koruyucu açılmaz ve ekran karanlık kalır; döndüğünüzde kilit ekranı gelir. Claude ve oturum çalışmayı sürdürür. Süre Ayarlar > Claude, kod modu ve ekran bölümündeki "Karardıktan sonra kilitle" ile değişir; 0 kilitlemeyi kapatır.

## 0.7.2 — 2026-10-21

### Eklenenler

- **İzin isteklerini otomatik onaylama.** Ayarlar > Claude, kod modu ve ekran bölümündeki "Claude'un izin isteklerini otomatik onayla" açıkken Uykusuz, Claude'un komut çalıştırma, dosya düzenleme ve araç kullanma izinlerini sizin yerinize hemen onaylar; plan ya da auto modunda da onay penceresi sizi bekletmez. Claude'un soruları ve plan onayları size kalır, Claude ayarlarınızdaki deny kuralları yine geçerlidir. Varsayılan olarak kapalıdır ve yeni açılan oturumlarda geçerli olur.

### Değişenler

- **Onay penceresi hook'u.** Uykusuz açılışta, daha önce kurduğunuz Claude Code hook'larından onay penceresi olayınınkini, karar yazabilen yeni komutla yeniler; ayar kapalıyken bu hook da önceki gibi hiçbir şey yazmaz.

## 0.7.1 — 2026-10-21

### Düzeltilenler

- **Akşam klavye ışığı.** Kapak kapanırken klavye ışığı zaten kapalıysa (macOS onu gün ışığında kendisi kapatır) Uykusuz artık ona dokunmaz ve kapak açılınca kapalı düzeyi geri yazmaz. Önceden bu, ışığı kapalıya sabitliyordu ve akşam klavyeyi kullanmaya başlayınca ışık yanmıyordu.
- **Kilidi anında algılama.** Telefondan yanıt açıkken Uykusuz, ekranı kilitlediğiniz, kapağı kapattığınız ya da ekranlar karardığı anda Claude'un telefon bildirimlerini açar; döndüğünüzde de hemen susturur. Önceden bu 5 saniyeyi bulabiliyordu ve kilitler kilitlemez gelen bir soru telefona düşmeyebiliyordu.

## 0.7.0 — 2026-10-21

### Eklenenler

- **Telefondan yanıt.** Claude uygulamasının Remote Control'ü açıkken oturumlar iPhone'daki Claude uygulamasında kendi adlarıyla görünür; yanıt ya da onay doğrudan ilgili oturuma gider. Ayarlar > Telefondan yanıt açıkken Claude'un telefon bildirimleri yalnızca siz uzaktayken (kapak kapalı, ekran kilitli ya da 2 dakikadır dokunulmamış) gelir.
- **Yanıt için uyanık kalma.** Telefondan yanıt açıkken otomatik oturum, Claude durduktan ya da beklemeye başladıktan sonra seçilen süre (varsayılan 30 dakika) kadar sürer; böylece telefondan verilen yanıt Mac'i uyanık bulur.
- **Claude sizi beklerken iPhone'a haber.** Kapak kapalıyken, ekran kilitliyken ya da 2 dakikadır Mac'e dokunulmadıysa, bir Claude Code oturumu onay ya da yanıt beklemeye başlayınca veya işini bitirip yeni isteğinizi bekleyince Uykusuz, Ayarlar'da yazdığınız telefon numarasına ya da Apple ID e-postasına Mac'teki Mesajlar üzerinden bir iMessage gönderir. Varsayılan olarak kapalıdır; Ayarlar > Claude sizi beklerken iPhone'a haber ver bölümünden açılır.
- **Mesajı Claude yazar.** Her mesaj Claude'un kenar çubuğundaki oturum adıyla başlar. Claude API anahtarı kayıtlıysa gerisi Claude'un ne yaptığını ve sizden ne beklediğini en çok iki cümleyle anlatır; anahtar yoksa ya da istek başarısız olursa Claude'un son mesajının sonu gider.
- **Gereksiz mesaj yok.** Bekleme ya da bitiş 45 saniye sürmeden, Mac'in başındayken ya da aynı oturum için 10 dakika dolmadan mesaj gitmez; durdurulan bir tur, kapatılan bir oturum ve yanıtlanmadan kalan bir bekleme bitiş sayılmaz. Siz başındayken başlayan bir bekleme, 10 dakika içinde Mac'ten uzaklaşırsanız yine bildirilir.
- **Deneme mesajı.** Ayarlar'daki düğme bir deneme mesajı gönderir; macOS'un Mesajlar izni sorusu da ilk gönderimde çıkar.

## 0.6.0 — 2026-10-21

### Eklenenler

- **Bilinen Wi-Fi ağına geri dönüş.** Oturum sürerken hotspot'tayken Uykusuz 2 dakikada bir çevreyi tarar; daha önce bağlandığınız ve parolası olan bir ağ yeterince güçlüyse hotspot'tan ayrılır ve macOS o ağa kendi kayıtlı parolasıyla bağlanır. Uykusuz ağ seçmez, Wi-Fi parolalarını görmez ve daha önce bağlanmadığınız bir ağa yönelmez.
- **Parolasız ağa düşmeme.** Çevrede bilinen parolasız bir ağ varsa hotspot'tan ayrılmaz; macOS yine de parolasız bir ağa bağlanırsa Uykusuz oradan ayrılıp hotspot'a döner. Başarısız bir denemeden sonra 10 dakika bekler. Ayarlar > Ağ yedekleme'deki "Bilinen Wi-Fi ağına geri dön" ile kapatılır.

## 0.5.1 — 2026-10-21

### Eklenenler

- **Hotspot katılma ayarı denetimi.** Hotspot ayarlıyken Ayarlar > Ağ yedekleme, macOS'taki "Erişim noktalarına katılmak için sor" seçeneğinin Otomatik olup olmadığını gösterir; Otomatik değilse turuncu bir uyarı ve Wi-Fi ayarlarını açan bir düğme çıkar. Denetim hotspot parolası kaydedilince ve Uykusuz'a geri dönülünce yinelenir; oturum başlarken de günlüğe yazılır.

## 0.5.0 — 2026-10-21

### Değişenler

- **Özet artık kendiliğinden okunmaz.** Kapak açılınca "Sen yokken" özeti bildirim ve sesli okuma yerine ekranın sağ üstünde küçük bir pencerede görünür; siz ▶ düğmesine basmadan ses çıkmaz. Pencere öndeki uygulamanın odağını almaz; kapak yeniden kapanınca okuma durur ve pencere kapanır.

### Eklenenler

- **Özet oynatıcısı.** Okurken okunan kelime metinde vurgulanır; ❚❚ durdurur, ◀◀ ve ▶▶ beşer kelime geri ve ileri gider, çubuğu sürükleyince okuma o kelimeden sürer.
- **Son özeti göster.** Göze sağ tıklayınca açılan menüden son özet yeniden açılır.

## 0.4.0 — 2026-10-21

### Eklenenler

- **En iyi Türkçe ses.** Sesli uyarılar ve "Sen yokken" özeti artık Mac'te kurulu en iyi Türkçe sesle söylenir: Premium, yoksa Gelişmiş, yoksa macOS ile gelen basit Yelda. Sistem Ayarları > Erişilebilirlik > Seslendirilen İçerik bölümünden "Yelda (Gelişmiş)" indirilince Uykusuz onu yeniden başlatmadan kullanmaya başlar.
- **Ses satırı ve Dinle.** Ayarlar > Kapak kapanınca yapılacaklar bölümünde kullanılan ses görünür; Dinle düğmesi örnek bir cümleyi o sesle çalar. Yalnızca basit ses kuruluysa Gelişmiş sesin nereden indirileceği yazar.

## 0.3.2 — 2026-10-21

### Düzeltilenler

- **Özetin süresi.** Ayarlar'daki "Son 2 saati şimdi özetle" düğmesi ve --away-digest önizlemesi, kapak kapanmamışken de özete "Kapak kapalıyken" diye başlıyordu; artık "Son 120 dakikada" gibi başlar. Kapak açılışındaki özet değişmedi.

## 0.3.1 — 2026-10-21

### Düzeltilenler

- **Gece boyu uyanık kalma.** Claude'un arka planda başlatıp açık bıraktığı bir komut (örneğin günlerdir çalışan bir veritabanı bağlantı aracı) Claude çalışıyor sayılıyor ve otomatik oturumu hiç bitirmiyordu; Mac bu yüzden bütün gece uyanık kalabiliyordu. Arka plandaki bir komut artık yalnızca yeni başladıysa ya da son 5 dakikada işlemci kullandıysa sayılır; derleme ve test gibi işler sayılmaya devam eder.

## 0.3.0 — 2026-10-21

### Eklenenler

- **Claude yanıt beklerken.** Claude bir komut için onay, bir soru için yanıt ya da bir plan için onay beklerken çalışıyor sayılmaz; bekleme süresi (varsayılan 5 dakika) içinde yanıt gelmezse otomatik oturum biter ve Mac uyur, yanıt verince yeniden başlar. Kapak kapalıysa Uykusuz bunu sesle söyler. Ayarlar > Claude, kod modu ve ekran bölümünden kapatılır ya da süresi değiştirilir.
- **Sen yokken özeti.** Kapak en az 3 dakika kapalı kaldıysa, açılınca Claude'un o sırada yaptıkları bir bildirimde bir iki cümleyle anlatılır ve sesli okunur. Anahtar kayıtlı değilse özet bu Mac'te sayılarla yazılır ve hiçbir yere gönderilmez. Ayarlar > Sen yokken özeti bölümündeki düğme son 2 saati hemen özetler.
- **Claude API anahtarıyla özet.** Ayarlar'da bir Claude API anahtarı kaydederseniz özeti Claude yazar (varsayılan Claude Opus 5.5). Uygulamanın tek ağ isteği budur: yalnızca api.anthropic.com'a gider ve yalnızca oturum başlıklarını, araç sayılarını, düzenlenen dosyaların adlarını, komut açıklamalarını ve Claude'un son mesajlarının sonunu içerir; dosya içerikleri, komut satırları ve çıktıları gönderilmez. Anahtar giriş Anahtar Zinciri'nde saklanır.

### Değişenler

- **Daha fazla Claude Code hook'u.** Hook'lar artık onay penceresini, soruyu, plan onayını, reddedilen izni, onaydan sonra hata veren aracı ve API hatasıyla biten turu da bildirir. Uykusuz açılışta, daha eski bir sürümün kurduğu hook'lara eksik olayları kendiliğinden ekler.

### Düzeltilenler

- **Tek kopya.** Uykusuz zaten çalışırken ikinci bir kopyası açılmaz; bu sürümün tanımadığı bir seçenekle (örneğin --away-digest yazım hatasıyla) yapılan çalıştırma da uygulamayı açmaz. Programı doğrudan çalıştırmak ikinci bir kopya açabiliyordu ve iki kopya aynı oturum dosyalarını paylaşıp birbirinin işine karışıyordu.

## 0.2.0 — 2026-10-21

Sürüm notlarının başladığı sürüm. Öne çıkanlar:

- **Claude ile otomatik oturum.** Claude Code bir görev yürüttüğü sürece oturum kendiliğinden açılır, arka planda 2 saatlik dilimlerle uzar ve Claude 5 dakika çalışmayınca biter. Menü çubuğunda geri sayım yerine "Claude" yazar; yazıya tıklayıp süre girince oturum sizin olur.
- **Otomatik oturumu duraklatma.** Otomatik oturumu basılı tutarak bitirince ya da sağ tık menüsündeki "Otomatik oturumu duraklat" ile otomatik oturum 15 dakika, 1 saat, 3 saat ya da seçilen bir saate kadar duraklatılır. Duraklatma sürerken menü çubuğunda kapalı gözün yanında bir duraklatma işareti görünür.
- **Claude Code hook'larıyla görev algılama.** Kuruluyken Claude yalnızca bir görev yürütürken çalışıyor sayılır.
- **Kod modu.** Oturum sürerken kapak açıksa ve Claude çalışıyorsa Düşük Güç Modu açılır.
- **Boşta siyah ekran.** Oturum sürerken kapak açıkken ekran koruyucu ve ekran uykusu çalışmaz; 60 sn girdi olmazsa ekran kararır, 30 sn olmazsa klavye ışığı söner.
- **Türkçe sesli uyarılar.** Kapak kapalıyken pil, ısı ve oturum sonu uyarıları sesli söylenir.
- **Varsayılanlar.** Pil eşikleri %30 (Düşük Güç Modu) ve %20 (oturum sonu); "diğer tüm uygulamaları dondur" açık; dondurma listesinde WhatsApp, Word, Excel ve ParaView var.
- **Giriş öğesi.** Kurtarma ajanı Sistem Ayarları > Genel > Giriş Öğeleri ve Uzantılar'da Uykusuz adıyla görünür.
- **Ağ isteği yok.** Uykusuz hiçbir ağ isteği yapmaz.
- **Belgeler.** Türkçe README, kurulum, kapak ve kurtarma belgeleri ile yeniden çizilen görseller.
