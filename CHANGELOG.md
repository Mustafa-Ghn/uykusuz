# Sürüm notları

Uykusuz'un sürümleri, en yenisi en üstte. Sürüm numarası
`Resources/Info.plist` dosyasından gelir; kurulu sürüm Ayarlar > Uygulama'da
görünür.

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
