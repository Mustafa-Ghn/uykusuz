# Sürüm notları

Uykusuz'un sürümleri, en yenisi en üstte. Sürüm numarası
`Resources/Info.plist` dosyasından gelir; kurulu sürüm Ayarlar > Uygulama'da
görünür.

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
