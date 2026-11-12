<p align="center">
  <img src="docs/assets/eye-open.svg" alt="Uykusuz simgesi: koyu bir karo üzerinde, yuvarlak gözbebekli ve üstünde beş kirpik olan açık bir göz" width="112">
</p>

<h1 align="center">Uykusuz</h1>

<p align="center">
  <strong>Mac'iniz uyanık kalsın, işiniz yarıda kalmasın.</strong>
</p>

<p align="center">
  <img alt="macOS 26 ve üstü" src="https://img.shields.io/badge/macOS-26%2B-1d1d1f?logo=apple&logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/Apple%20Silicon-arm64-1d1d1f">
  <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-F05138?logo=swift&logoColor=white">
  <img alt="Arayüz: Türkçe" src="https://img.shields.io/badge/aray%C3%BCz-T%C3%BCrk%C3%A7e-c8102e">
</p>

<p align="center">
  Uykusuz, Mac'inizi süreli oturumlarla uyanık tutan bir macOS menü çubuğu
  uygulamasıdır. Kapak kapalıyken bile uzun derlemeler, indirmeler ve Claude
  Code görevleri kesintisiz sürer; oturum bitince Uykusuz yaptığı
  değişiklikleri geri alır ve Mac normal uykusuna döner. Dock simgesi ve ana
  penceresi yoktur: menü çubuğunda duran bir gözden ibarettir.
</p>

<p align="center">
  <a href="#özellikler"><strong>Özellikler</strong></a> ·
  <a href="#kurulum"><strong>Kurulum</strong></a> ·
  <a href="#kullanım"><strong>Kullanım</strong></a> ·
  <a href="#claude-ile-otomatik-oturum"><strong>Claude ile otomatik oturum</strong></a> ·
  <a href="#kapak-kapanınca-neler-olur"><strong>Kapak kapanınca</strong></a> ·
  <a href="#kurtarma-nasıl-çalışır"><strong>Kurtarma</strong></a> ·
  <a href="#katkıda-bulunma"><strong>Katkıda bulunma</strong></a>
</p>

<p align="center">
  <img src="docs/assets/session-flow.svg" alt="Menü çubuğu denetimlerinin çizimi: kapalı göze tıklayıp Gün, Saat ve Dakika kutularına süreyi girin, açılan gözün yanında geri sayımı izleyin ve erken bitirmek için yanındaki çarpıyı basılı tutun." width="880">
</p>

> ⚠️ **Mac'i kapalı bir çantada değil, sabit ve iyi havalanan bir yüzeyde
> kullanın.** Uyku kapalıyken Mac kapak kapalıyken de çalışmayı sürdürür ve
> ısınabilir. Uykusuz deneysel bir yazılımdır: kurtarma başarısız olabilir ve
> çalışan bir zamanlayıcı bir güvenlik garantisi değildir.
> [Apple'ın havalandırma önerileri](https://support.apple.com/en-us/102336) ·
> [Gerçek Mac doğrulamaları](docs/release-validation.md) (İngilizce)

## Neden Uykusuz?

macOS, kapak kapanınca Mac'i uyutur. Çantadaki bir dizüstü için doğru davranış
budur; ama Claude Code saatlerdir bir görev yürütürken, bir derleme sürerken ya
da büyük bir indirme beklerken iş yarıda kalır. Uyku ayarını kalıcı olarak
kapatmak ise unutulduğunda pili bitirir ve Mac'i boşuna ısıtır.

Uykusuz ikisinin arasında durur: uykuyu yalnızca sizin belirlediğiniz süre
boyunca engeller, kapak kapalıyken gereksiz her şeyi (ekran, ses, arka plandaki
uygulamalar) susturur ve süre dolunca Mac'i bıraktığınız gibi geri verir.
Claude çalışırken bunu kendiliğinden de yapar.

## Özellikler

- **Süreli oturumlar.** Menü çubuğuna gün, saat ve dakika yazıp Enter'a basın.
  Süre eklemek bir tık, erken bitirmek basılı tutmak kadar kolaydır. Bir oturum
  en çok 30 gün sürer.
- **Kapak kapalıyken çalışma.** Oturum boyunca Mac, kapağı kapalıyken de uyumaz.
- **Claude ile otomatik oturum.** Claude Code bir görev yürüttüğü sürece oturum
  kendiliğinden açılır, uzar ve Claude durunca kapanır; Claude sizden yanıt
  beklerken bir süre sonra kapanır ve istediğinizde belli bir süre duraklatılır.
- **Ağ kesintisinden sonra kendiliğinden sürdürme.** İnternet kesildiği için
  yarıda kalan bir Claude oturumu, bağlantı geri gelince kendiliğinden sürer;
  "Try again" düğmesine basmanız gerekmez. Kullanım ya da kredi sınırı gibi
  başka bir nedenle duran oturum size kalır.
- **Sen yokken özeti.** Kapak ya da kilit açılınca Claude'un siz yokken yaptıkları küçük bir
  pencerede bir iki cümleyle anlatılır; ▶ ile dinlersiniz, okunan kelime
  vurgulanır ve çubukla ileri geri gidersiniz; bir Claude API anahtarı
  kaydederseniz özeti Claude yazar.
- **Defter.** Claude API anahtarı kayıtlıysa Uykusuz, siz başındayken iki saatte
  bir Mac'e bakar; boşuna açık duran bir simülatör ya da boşta bellek tutan Docker
  gibi bir şey görürse deftere yazar ve en fazla dört saatte bir haber verir.
  Bildirime yanıt yazarsınız, Claude yanıt verir; Uykusuz önerdiği işi yalnızca
  siz onaylarsanız yapar.
- **Claude'un yanıtını dinleme.** Baktığınız Claude sohbetinin son mesajını
  ⌃⌥D ile dinlersiniz; Claude bir planı onaylamanızı bekliyorsa plan okunur.
  Okunan kelime sohbetteki yazının üzerinde işaretlenir, sağ üstte durdurma
  düğmesi ve ileri geri çubuğu kalır. Ara adımlar okunmaz ve siz istemeden
  hiçbir şey okunmaz.
- **Seçilen alanı dinleme.** ⌃⌥S ile ekranda bir alan çizersiniz; o alandaki yazı
  aynı küçük pencerede okunur. Yazı bu Mac'te tanınır, görüntü hiçbir yere
  gönderilmez.
- **Doğal Türkçe ses.** Uyarıları, özeti, Claude'un yanıtını ve seçtiğiniz alanı
  Uykusuz'la gelen yapay zekâ sesi okur; `README` ya da `commit` gibi teknik
  kelimeler Türkçe okunuşuyla söylenir. Ses bu Mac'te çalışır, ağa çıkmaz ve
  yalnızca okurken yüklenir.
- **Telefondan yanıt.** Claude oturumlarını iPhone'daki Claude uygulamasından
  yanıtlar ve onaylarsınız; Uykusuz, Claude'un telefon bildirimlerini yalnızca
  siz uzaktayken gönderir ve yanıtınız gelene kadar Mac'i uyanık tutar.
- **Claude sizi beklerken iPhone'a haber.** Kapak kapalıyken, ekran kilitliyken
  ya da Mac'e bir süredir dokunulmadıysa, bir Claude oturumu onay ya da yanıt
  beklemeye başlayınca veya işini bitirince Uykusuz telefonunuza iMessage gönderir.
  Docker Desktop'ta bir iş sürerken ve o iş bitince de mesaj gelir.
- **Kapak eylemleri.** Kapak kapanınca ekran ve klavye ışığı söner, seçili
  uygulamalar dondurulur, ses kapanır ve Düşük Güç Modu açılır; kapağı açmak
  hepsini geri almaya çalışır.
- **Kod modu ve boşta siyah ekran.** Oturum sürerken kapak açıksa ve Claude
  çalışıyorsa Düşük Güç Modu açılır; bir süre girdi olmazsa ekran tamamen
  kararır ve bir tuşla geri gelir.
- **Türkçe sesli uyarılar.** Kapak kapalıyken bildirimler görünmediği için pil,
  ısı ve oturum sonu uyarıları sesli söylenir.
- **Pil ve ısı korumaları.** Pil %30'un altına inince Düşük Güç Modu açılır,
  %20'nin altında oturum biter; Mac aşırı ısınırsa oturum kendiliğinden kapanır.
- **Güvenli geri alma.** Her değişiklik önce diske kaydedilir. Uygulama çökse
  bile her dakika çalışan bir kurtarma ajanı Mac'i eski hâline döndürmeye
  çalışır.
- **Ağ yedekleme.** Wi-Fi koparsa iPhone'unuzun kişisel erişim noktasına
  geçebilir; isterseniz tmux'ta çalışan kodlama ajanınıza `continue` yazar.
- **Gizlilik.** Uykusuz yalnızca siz bir Claude API anahtarı kaydettiyseniz ve
  yalnızca "Sen yokken" özetini ve defteri yazdırmak için `api.anthropic.com`'a
  istek yapar. Bunun dışında yalnızca, ağ kesintisinden duran bir Claude
  oturumunu beklerken ağın geri gelip gelmediğine bakar: Claude'un API sunucusuna
  hiçbir veri göndermeden bağlanmayı dener. Ayarlar ve günlükler yalnızca sizin
  hesabınızın okuyabildiği dosyalarda, anahtar giriş Anahtar Zinciri'nde tutulur.

## Gereksinimler

- macOS 26 ya da üstü.
- Apple Silicon (Apple çipli) bir Mac. Intel bir Mac'te kaynaktan derleme
  denenmemiştir.
- Swift 6.2 ya da üstünü içeren Xcode.

## Kurulum

Uykusuz kaynak koddan derlenerek kurulur. Depoyu klonlayın, kurulum betiğini
çalıştırın ve uygulamayı açın:

```bash
git clone https://github.com/Mustafa-Ghn/uykusuz.git && cd uykusuz && ./scripts/install.sh
open "$HOME/Applications/Uykusuz.app"
```

SSH anahtarı kullanıyorsanız `git@github.com:Mustafa-Ghn/uykusuz.git`
adresiyle klonlayın.

`./scripts/install.sh`, uygulamayı bu çalışma kopyasından derler
(`scripts/build-app.sh`, ad-hoc imzalı) ve kurar. sudoers kuralı için
parolanızı bir kez sorar; bu istem, derleme bittikten sonra ve önceki
kurulumdaki hiçbir şeye dokunulmadan önce gelir. Her adımın neyi denetlediği
[docs/install.md](docs/install.md) sayfasında anlatılır.

<details>
<summary><strong>Kurulumun Mac'inizde değiştirdikleri</strong></summary>

sudoers kuralı bir sistem dosyası olduğu için kurulum betiği parolanızı ister.
Şunları kurar:

- Uygulamayı, `~/Applications/Uykusuz.app` konumuna.
- Bir **kurtarma ajanı**: her dakika çalışan bir `launchd` görevi. Bir oturumun
  bitmesi gerektiği hâlde uygulama artık çalışmıyorsa ajan, oturumun yaptığı
  değişiklikleri geri almaya çalışır. Ajan, uygulamanın kendi programından
  başladığı için Sistem Ayarları > Genel > Giriş Öğeleri ve Uzantılar'da
  Uykusuz adıyla görünür. Uygulama ücretli bir Apple Developer ID ile
  imzalanmadığından yanında "kimliği belirsiz geliştirici" yazar.
- `/etc/sudoers.d/uykusuz` konumunda bir **sudoers kuralı**. Bir sudoers kuralı,
  kimin neyi `sudo` ile çalıştırabileceğini belirler. Bu kural, yalnızca
  Uykusuz'a değil, kullanıcı hesabınıza şu dört komutu parolasız çalıştırma
  izni verir:

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -b lowpowermode 1
/usr/bin/pmset -b lowpowermode 0
```

Sizin hesabınızla çalışan her program da bu kuralı kullanabilir; bu yüzden
kurmadan önce kuralı gözden geçirin.
[docs/install.md](docs/install.md#neler-kurulur) her dosyayı listeler ve
yükseltmelerin onları nasıl değiştirdiğini açıklar.

</details>

## Güncelleme

Uykusuz güncelleme denetlemez. Güncellemek için
çalışma kopyasında yeni değişiklikleri çekin ve kurulum betiğini yeniden
çalıştırın:

```bash
cd uykusuz
git pull
./scripts/install.sh
```

Kurulum betiği çalışan uygulamadan kapanmasını ister. Geri alınmayı bekleyen
bir değişiklik varken uygulama kapanmayı reddeder; betik o zaman durur ve
uygulamaya da kurtarma ajanına da dokunmaz. Parolanız her çalıştırmada bir kez
istenir. Kurulu sürümü Ayarlar > Uygulama gösterir; her sürümde nelerin
değiştiği [CHANGELOG.md](CHANGELOG.md) dosyasındadır. Ayrıntılar:
[docs/install.md](docs/install.md#yükseltmeler).

## Kullanım

1. **Başlatın.** Menü çubuğundaki göze tıklayın, gün, saat ve dakikayı girin ve
   Enter'a basın.
2. **Süre ekleyin.** Oturum sırasında göze ya da geri sayıma tıklayın.
3. **Erken bitirin.** Geri sayımın yanındaki bitirme denetimini basılı tutun.
4. **Ayarlar ve durum.** Göze sağ tıklayın. "Uykusuz'dan Çık", Uykusuz'un
   önce oturumu geri almasını ister; geri alınmayı bekleyen bir değişiklik
   varken Uykusuz kapanmayı reddeder. Bağlı olmayan bir çıkış aygıtı için
   kaydedilmiş ses bunu engellemez. Uykusuz o aygıtı, uygulama çalışırken
   yeniden bağlanırsa ya da bir sonraki açılışta geri yükler.

Kapağı kapatmanız gerekmez; kapağı açmak da oturumu bitirmez.

Pil gücündeyken Uykusuz, pil düzeyi %30 eşiğinin altına inince Düşük Güç
Modu'nu açar ve %20 eşiğinin altında oturumu bitirir. Bunlar varsayılan
değerlerdir. İkisini de Ayarlar'da değiştirebilirsiniz; bitirme alt sınırını 0
yapmak pil nedeniyle bitirmeyi kapatır. Isı kuralları, Mac ciddi ölçüde
ısındığında Düşük Güç Modu'nu açar ve kritik ısıda oturumu bitirir. Bu kurallar
varsayılan olarak açıktır ve Ayarlar'dan kapatılabilir. Bu kuralların hepsi
yalnızca uygulama çalışırken işler.

İlk oturumunuzdan önce Ayarlar'ı gözden geçirin. Ardından başında
durabileceğiniz kısa bir oturum çalıştırın ve sonrasında
`~/Library/Logs/Uykusuz/uykusuz.log` dosyasını okuyun.

### Ayarlar

Ayarlar penceresi göze sağ tıklayınca açılan menüden (⌘,) açılır:

| Bölüm | İçindekiler |
| --- | --- |
| Oturum | Hazır süreler, varsayılan süre, açılışta odaklanan alan, en uzun oturum |
| Kapak kapanınca yapılacaklar | Ekran ve klavye ışığı, dondurma listesi, diğer tüm uygulamalar, Docker, ses, Düşük Güç Modu, sesli uyarı, doğal Türkçe ses, kullanılan ses ve Dinle |
| Ajan uygulamaları | Hiçbir zaman dondurulmayan ya da kısıtlanmayan uygulamalar, App Nap |
| Pil ve ısı | Düşük Güç Modu ve oturum sonu eşikleri, ısı kuralları |
| Claude, kod modu ve ekran | Claude Code hook'ları, izin isteklerini otomatik onaylama, ağ kesintisinden duran oturumu kendiliğinden sürdürme, otomatik oturum, yanıt beklerken bitirme ve bekleme süresi, kod modu, boşta siyah ekran süreleri ve kilitleme |
| Sen yokken özeti | Kapak ya da kilit açılınca özet penceresi, Claude API anahtarı, özeti yazan model, son 2 saati şimdi özetle |
| Defter | Mac'i arada bir gözden geçirip öneriyi deftere yazma, Defteri aç, Şimdi bak |
| Claude'un yanıtını dinle | ⌃⌥D kısayolunu açıp kapatma, okunan kelimeyi ekrandaki yazının üzerinde işaretleme |
| Seçilen alanı dinle | ⌃⌥S kısayolunu açıp kapatma |
| Telefondan yanıt | Claude'un telefon bildirimleri yalnızca uzaktayken, yanıt için Mac'in uyanık kalacağı süre |
| Claude sizi beklerken iPhone'a haber ver | iMessage gönder, alıcı (telefon numarası ya da Apple ID e-postası), deneme mesajı, Docker kullanılırken de haber ver |
| Ağ yedekleme | iPhone kişisel erişim noktası, bilinen Wi-Fi ağına geri dönüş, tmux dürtmesi |
| Uygulama | Girişte aç, yapılandırma klasörü, kurulu sürüm |

## Claude ile otomatik oturum

<p align="center">
  <img src="docs/assets/claude-auto-session.svg" alt="Dört adımlık akış: Claude Code hook'ları görevi Uykusuz'a bildirir; oturum kendiliğinden açılır ve menü çubuğunda geri sayım yerine Claude yazar; oturum Claude çalıştıkça 2 saatlik dilimlerle uzar; Claude 5 dakika çalışmayınca oturum biter. Altta: Claude yazısına tıklayıp süre girerseniz oturum sizin olur; basılı tutup bitirince ya da sağ tık menüsünden otomatik oturumu 15 dakika, 1 saat, 3 saat ya da seçtiğiniz saate kadar duraklatabilirsiniz; pil eşiğe ya da Mac ısınma sınırına yakınken başlamaz; elle başlatılan oturumlar geri sayımla görünür." width="880">
</p>

Claude Code bir görev yürüttüğü sürece Uykusuz kendiliğinden bir oturum açar;
menü çubuğunda geri sayım yerine **Claude** yazar. Oturum Claude çalıştıkça
sürer (arka planda 2 saatlik dilimlerle uzar) ve Claude 5 dakika çalışmayınca
biter; Mac normal uykusuna döner. Sağ tık menüsü de "Claude çalıştıkça açık;
Claude durunca 5 dk sonra biter" satırını gösterir. [Telefondan
yanıt](#telefondan-yanıt) açıkken bu süre, orada seçilen süredir (varsayılan
30 dakika).

- **Oturumu devralma.** "Claude" yazısına tıklayıp bir süre girerseniz oturum
  sizin olur: girdiğiniz süre o andan itibaren sayılır ve geri sayım görünür.
  Claude bu oturumu artık uzatmaz ve bitirmez. Süreniz dolduğunda Claude hâlâ
  çalışıyorsa otomatik oturum yeniden başlar.
- **Erken bitirme ve duraklatma.** Otomatik oturumu basılı tutarak bitirince
  menü çubuğunda bir menü açılır: otomatik oturumu **15 dakika**, **1 saat**,
  **3 saat** ya da **Saat seç…** ile seçtiğiniz saate kadar duraklatabilirsiniz
  (geçmiş bir saat seçerseniz yarının o saati kullanılır). **Duraklatma**'yı
  seçer ya da menüyü kapatırsanız Claude bir kez durup yeniden başlayana kadar
  otomatik oturum açılmaz.
- **Duraklatılmışken.** Claude çalışsa da otomatik oturum açılmaz. Menü
  çubuğunda kapalı gözün yanında küçük bir duraklatma işareti durur ve sağ tık
  menüsü "Otomatik oturum duraklatıldı; saat 23:20 itibarıyla yeniden açılır"
  gibi bir satır gösterir. Duraklatma uygulama yeniden açılsa da sürer; süre
  dolduğunda Claude hâlâ çalışıyorsa otomatik oturum hemen yeniden açılır. Sağ
  tık menüsündeki **Otomatik oturumu duraklat** alt menüsü aynı seçenekleri her
  zaman sunar (süren bir otomatik oturumu da bitirir); **Otomatik oturumu
  sürdür** duraklatmayı erken bitirir.
- **Claude yanıt beklerken.** Claude bir komut için onay, bir soru için yanıt
  ya da bir plan için onay beklerken çalışıyor sayılmaz. Bekleme süresi
  (varsayılan 5 dakika) içinde yanıt gelmezse otomatik oturum biter ve Mac
  uyur; yanıt verince oturum yeniden başlar. Kapak kapalıysa Uykusuz bunu sesle
  söyler: "Claude sizi bekliyor. 5 dakika içinde yanıt vermezseniz oturum
  biter ve Mac uyur." Onayı telefondan vermek için [Telefondan
  yanıt](#telefondan-yanıt)'ı açın; bekleme o zaman orada seçilen süre kadar
  (varsayılan 30 dakika) sürer.
- **Güvenlik payı.** Mac ısınıyorsa ya da pil gücündeyken pil, bitiş eşiğinin
  (varsayılan %20) en çok 5 puan üstündeyse otomatik oturum başlamaz. Oturum
  pil eşiğinde bittiyse ve Claude çalışmayı sürdürüyorsa, şarj aleti takılınca
  oturum kendiliğinden yeniden açılır. Kritik ısı ya da okunamayan pil yüzünden
  biten oturum ise Claude bir kez durup yeniden başlayana kadar açılmaz.
- **Elle başlatılan oturumlar.** Kendi başlattığınız oturumlar geri sayımla
  görünür; Claude onları uzatmaz ve bitirmez.

Kapak kapansa da Mac uyanık kalır: **Mac'i kapalı bir çantaya koymayın.**
Otomatik oturum Ayarlar > Claude, kod modu ve ekran bölümünden kapatılabilir.

### Claude'un çalıştığını algılama

Ayarlar > Claude, kod modu ve ekran bölümündeki **Kur** düğmesi (ya da
`~/Applications/Uykusuz.app/Contents/MacOS/Uykusuz --install-claude-hooks`)
Claude Code hook'larını kurar. Kuruluyken Claude yalnızca bir görev yürütürken
çalışıyor sayılır: bir istek başlayıp Claude yanıtını bitirene kadar ya da
Claude'un başlattığı bir komut (arka planda bile) iş yaptığı sürece. Açık
bırakılıp boşta bekleyen bir komut, örneğin bir veritabanı bağlantı aracı ya da
geliştirme sunucusu, son 5 dakikada işlemci kullanmadıysa sayılmaz; Mac uykudan
uyandıktan sonraki ilk 2 dakikadaki işlemci kullanımı da iş sayılmaz. Derleme ve
test gibi işler sayılır. Hook'lar ayrıca
Claude'un bir onay penceresi açtığını, soru sorduğunu ya da plan onayı
beklediğini bildirir. Hiçbir çıktı vermezler, bu yüzden bir izne yanıt vermez ve
bir aracı değiştirmezler; iki istisna aşağıdaki otomatik onay ve
[ağ kesintisinden sonra kendiliğinden sürdürme](#ağ-kesintisinden-sonra-kendiliğinden-sürdürme)'dir. Uykusuz
açılışta, daha eski bir sürümün kurduğu hook'lara eksik olayları ekler ve
komutu değişmiş olanı yeniler. Hook'lar
`~/.claude/settings.json` dosyasına eklenir ve dosyanın eski hâli
`settings.json.uykusuz-yedek` olarak saklanır; aynı düğme (ya da
`--remove-claude-hooks`) onları kaldırır. Hook'lar kurulu değilken Claude
masaüstü uygulaması açık olduğu sürece çalışıyor sayılır.

**İzin isteklerini otomatik onaylama.** Ayarlar > Claude, kod modu ve ekran
bölümündeki **Claude'un izin isteklerini otomatik onayla** açıkken Uykusuz,
Claude'un komut çalıştırma, dosya düzenleme ve araç kullanma izinlerini sizin
yerinize hemen onaylar; plan ya da auto modunda da onay penceresi sizi
bekletmez. Claude'un soruları ve plan onayları size kalır; Claude ayarlarınızdaki
deny kuralları yine geçerlidir. Bunu, onay penceresi açılırken çalışan hook
yapar: ayar açıksa Claude Code'a "onay" yanıtı yazar, kapalıysa hiçbir şey
yazmaz ve karar size kalır. Bu, bypass moduna yakın bir güvenlik düzeyidir:
Claude'un okuduğu bir içerik onu zararlı bir komuta yönlendirirse o komut da
onaylanır. Ayar varsayılan olarak kapalıdır, hook'ların kurulu olmasını ister ve
yeni açılan oturumlarda geçerli olur.

### Ağ kesintisinden sonra kendiliğinden sürdürme

İnternet kesilince Claude Code isteğini yaklaşık üç dakika boyunca on kez
yeniden dener, sonra turu "API Error: Can't reach the API server" hatasıyla
bitirir. Ağ birkaç dakika sonra geri gelse de oturum orada kalır ve siz **Try
again** düğmesine basana kadar bekler. Ayarlar > Claude, kod modu ve ekran
bölümündeki **Ağ kesintisinden duran Claude oturumunu kendiliğinden sürdür**
açıkken (varsayılan) Uykusuz bunu sizin yerinize yapar: tur bir ağ hatasıyla
bitince Claude'un API sunucusuna yeniden ulaşılana kadar bekler, sonra oturumu
uyandırır ve Claude yarım kalan işi kaldığı yerden sürdürür.

- **Yalnızca ağ kesintisi.** Uykusuz yalnızca Claude Code'un sunucu hatası
  saydığı ve o sırada API sunucusuna ulaşılamayan (ya da Claude Code'un son
  denemesinde ağı kapalı bulduğu) bir turu sürdürür. Oturum kullanım ya da
  harcama sınırı, biten kredi, oturum açma sorunu, reddedilen ya da geçersiz
  bir istek, güvenlik nedeniyle gelen bir kısıtlama ya da sunucunun aşırı
  yüklenmesi yüzünden durduysa Uykusuz dokunmaz; yeniden denemek size kalır.
- **Beklerken Mac uyanık kalır.** Ağ beklenirken oturum bir saate kadar
  çalışıyor sayılır; otomatik oturum açıksa kapak kapalıyken de Mac uyumaz ve
  [hotspot'a geçiş](#ek-özellikler) denenmeye devam eder. Bir saatin sonunda
  Mac uyuyabilir; Uykusuz ağı toplam altı saat (Mac'in uyanık geçirdiği süre)
  bekler ve ağ o arada gelirse oturumu yine sürdürür. Süre dolarsa oturum
  olduğu gibi kalır.
- **Siz araya girerseniz.** Beklerken o oturuma kendiniz bir şey yazarsanız ya
  da oturumu kapatırsanız Uykusuz hiçbir şey eklemez.
- **En çok üç kez.** Bir oturum art arda en çok üç kez kendiliğinden
  sürdürülür; ağ gidip geliyorsa dördüncüsünde size bırakılır. Claude bir araç
  çalıştırınca, bir turu hatasız bitirince ya da siz bir şey yazınca sayaç
  sıfırlanır.

Bunu `StopFailure` hook'u yapar: Claude Code bu hook'u arka planda çalıştırır
ve hook ağ gelince Claude'a sabit bir not bırakır ("İnternet bağlantısı
kesildiği için önceki istek yanıtsız kaldı; bağlantı geri geldi…"). Ağı
denetlemek için Uykusuz beş saniyede bir Claude'un API sunucusuna
(`api.anthropic.com`; oturumunuz başka bir adres kullanıyorsa o adrese)
bağlanmayı dener; bağlantı üzerinden hiçbir veri gönderilmez. Hook'ların kurulu
olması gerekir ve ayar yeni açılan oturumlarda geçerli olur. Arka planda çalışan
hook'ları tanıyan güncel bir Claude Code gerekir (2.1.321 ile denendi).

### Telefondan yanıt

Claude oturumlarını telefondan yanıtlamanın yolu Claude'un kendi **Remote
Control** özelliğidir. Claude uygulamasında Ayarlar > Claude Code > **Connect new
sessions to Remote Control** açıkken her yeni oturum, iPhone'daki Claude
uygulamasında Code sekmesinde kendi adıyla görünür. Yazdığınız mesaj, verdiğiniz
onay ya da bir sorunun yanıtı yalnızca açtığınız oturuma gider; birden çok oturum
birbirine karışmaz. Claude da onay ya da yanıt beklerken ve bir iş bitince
telefona kendisi bildirim gönderir (Claude Code ayarlarında "Push when actions
required" ve "Push when Claude decides").

Ayarlar > Telefondan yanıt bölümündeki **Claude'un telefon bildirimleri yalnızca
ben uzaktayken gelsin** seçeneği iki şey yapar:

- **Bildirimler yalnızca uzaktayken.** Siz Mac'in başındayken Claude'un telefon
  bildirimleri susar; kapak kapalıyken, ekran kilitliyken ya da 2 dakikadır Mac'e
  dokunulmadıysa gelir. Uykusuz bunun için Claude Code'un
  `CLAUDE_CLIENT_PRESENCE_FILE` ayarını `~/.claude/settings.json` dosyasına ekler
  (dosyanın eski hâli ilk değişiklikte `settings.json.uykusuz-yedek` olarak
  saklanır) ve siz Mac'in başındayken bu ayarın gösterdiği boş dosyayı tutar.
  Seçenek yalnızca açıldıktan sonra başlayan oturumlarda geçerlidir. Kapatınca
  satır silinir; Uykusuz kapanınca dosya da silinir ve bildirimler her zamanki
  gibi gelir.
- **Yanıt için uyanık kalma.** Otomatik oturum, Claude durduktan ya da beklemeye
  başladıktan sonra seçilen süre (varsayılan 30 dakika) kadar sürer. Böylece
  kapak kapalıyken telefondan verdiğiniz yanıt Mac'i uyanık bulur. Süre dolunca
  oturum biter ve Mac uyur; Claude Code, Mac uyanınca Remote Control'e
  kendiliğinden yeniden bağlanır.

Remote Control Claude'un özelliğidir: açıkken oturumun yazışması cihazlar arası
eşitleme için Anthropic sunucularında tutulur. Uykusuz bu yazışmayı okumaz ve
yanıtları aktarmaz; yalnızca bildirimlerin ne zaman gideceğini ve Mac'in ne kadar
uyanık kalacağını belirler.

### Claude sizi beklerken iPhone'a haber

Ayarlar > Claude sizi beklerken iPhone'a haber ver bölümünde **iMessage gönder**'i
açıp alıcıya telefon numaranızı ya da Apple ID e-postanızı yazın. Kapak
kapalıyken, ekran kilitliyken ya da 2 dakikadır Mac'e dokunulmadıysa, bir Claude Code oturumu onay
ya da yanıt beklemeye başlayınca (bir komut izni, bir soru, bir plan onayı) ya
da işini bitirip yeni isteğinizi bekleyince Uykusuz bu alıcıya Mac'teki Mesajlar
uygulaması üzerinden bir iMessage gönderir. Böylece Mac'e dönüp kaldığınız yerden
devam edebilirsiniz. [Telefondan yanıt](#telefondan-yanıt) açıksa Claude'un kendi
bildirimi de gelir; ikisini birden istemiyorsanız iMessage'ı kapatın.

- **Mesajın içeriği.** Her mesaj, Claude uygulamasının kenar çubuğunda görünen
  oturum adıyla başlar; böylece birden çok oturum varken hangisinin beklediği
  ya da işini bitirdiği bellidir. Oturuma ad verilmemişse Claude'un ürettiği ad,
  o da yoksa oturumun çalıştığı klasörün adı yazılır. API anahtarı kayıtlıysa
  gerisini Claude yazar: Claude'un ne yaptığı
  ve sizden ne beklediği, en çok iki cümle. Anahtar yoksa ya da istek başarısız
  olursa Claude'un son mesajının sonu gider.
- **Ne zaman.** Bekleme ya da bitiş 45 saniye sürmeli; hemen yeni bir tura
  geçen oturum için mesaj gitmez. Mac'in başındaysanız mesaj gitmez; ama Claude
  siz başındayken beklemeye başladıysa ve 10 dakika içinde kapağı kapatır ya da
  Mac'ten uzaklaşırsanız mesaj yine gider. Durdurduğunuz bir tur, kapatılan bir
  oturum ve yanıtlanmadan kalan bir bekleme "bitti" diye bildirilmez. Her oturum
  için en çok 10 dakikada bir mesaj gönderilir.
- **İzin.** Uykusuz mesajı Mesajlar'ın kendi AppleScript komutuyla gönderir;
  ekranı ya da klavyeyi denetlemez. İlk gönderimde macOS, Uykusuz'un Mesajlar'ı
  denetlemesine izin vermenizi ister. **Deneme mesajı gönder** düğmesiyle hem
  izni verip hem telefonunuza bildirim gelip gelmediğini görebilirsiniz; kendi
  numaranıza gönderilen mesaj kendinizle olan sohbete düşer. Uygulama her
  kurulumda yeniden imzalandığı için macOS bu izni yeni bir kurulumdan sonra
  yeniden sorabilir; kurulumdan sonra bir deneme mesajı gönderin.
- **Docker.** **Docker kullanılırken de haber ver** açıkken (varsayılan) Docker
  Desktop'ta bir iş sürüyorsa bir mesaj, iş bitince bir mesaj daha gelir:
  "Uykusuz · Docker: aktif kullanılıyor (kapsayıcının adı). İş bitince yine haber
  vereceğim." ve "Uykusuz · Docker: iş bitti, 12 dakika sürdü. Çalışan kapsayıcı
  kalmadı." Süre uzunsa gün, saat ve dakikayla yazılır: "9 saat 4 dakika sürdü".
  İş sayılanlar: yeni açılan bir kapsayıcı (ilk 15 dakika), bir
  çekirdeğin %10'undan fazlasını kullanan bir kapsayıcı ve sürmekte olan
  `docker build`, `docker pull` ya da `docker push`. Boşta açık duran bir
  veritabanı iş sayılmaz. İş en az 45 saniye sürmeli; bitmiş sayılması için 2
  dakika yeni iş olmamalı, böylece art arda çalışan kapsayıcılar tek iş sayılır.
  Mac'in başındaysanız mesaj gitmez; iş sürerken uzaklaşırsanız, ne zaman
  başlamış olursa olsun mesaj o an gider. "Aktif" mesajı gittiyse bitiş mesajı,
  Mac'e dönmüş olsanız da gider. En çok 10 dakikada bir iş bildirilir.

### Kod modu ve boşta siyah ekran

- **Kod modu.** Bir oturum sürerken kapak açıksa ve Claude çalışıyorsa Düşük
  Güç Modu açılır (pildeyken etkili).
- **Boşta siyah ekran.** Oturum sürerken kapak açıkken ekran koruyucu ve ekran
  uykusu çalışmaz. 60 sn girdi olmazsa ekran parlaklığı 0'a iner ve ekran hiç
  ışık vermez; 30 sn olmazsa klavye ışığı söner. Bir tuşa ya da fareye
  dokununca ikisi de eski seviyesine döner. Ekran karardıktan sonra 15 dakika
  dönmezseniz oturum kilitlenir: ekran koruyucu açılmaz ve ekran karanlık kalır,
  döndüğünüzde kilit ekranı gelir. Claude ve oturum çalışmayı sürdürür. Bir
  video oynarken (tarayıcı ya da oynatıcı ekranı açık tutarken) ekran kararmaz
  ve kilitlenmez; süreler video bitince yeniden başlar. Süreler
  Ayarlar > Claude, kod modu ve ekran bölümünden değişir; kilitleme süresi 0
  yapılırsa ekran kendiliğinden kilitlenmez.

### Sen yokken özeti

Kapak en az 3 dakika kapalı ya da ekran o kadar kilitli kaldıysa, döndüğünüzde
Claude Code oturumlarında o sırada olanlar ekranın sağ üstündeki küçük bir
pencerede bir iki cümleyle anlatılır. Döndüğünüz an, kapağın açık ve kilidin
açılmış olduğu andır; kapağı kilit ekranında açarsanız özet kilidi açınca gelir.
Boşta siyah ekranın kilidinde süre, Mac'e son dokunduğunuz andan sayılır.
Oturumun hâlâ sürmesi gerekmez; Uykusuz kapağı ve kilidi her zaman izler.
Özet o sırada çalışan ve sizi bekleyen oturumların hepsini sayar; uzun bir komutu
bekleyen ya da siz gitmeden soru sormuş oturumlar da bu sayıya girer. En çok 8
oturumun ayrıntısına bakılır; önce sizi bekleyenler seçilir, kalanlar adı ve
durumuyla sayılır.
Ayarlar > Sen yokken özeti bölümündeki **Son 2 saati şimdi özetle** düğmesi
özeti hemen dener; göze sağ tıklayınca açılan menüdeki **Son özeti göster** son
özeti yeniden açar.

- **Pencere.** Siz ▶ düğmesine basmadan ses çıkmaz:
  kapağı sessiz bir yerde ya da başka bir iş için açmış olabilirsiniz. Okurken
  okunan kelime metinde vurgulanır; ❚❚ durdurur, ◀◀ ve ▶▶ beşer kelime geri ve
  ileri gider, çubuğu sürükleyince okuma o kelimeden sürer. Pencere öndeki
  uygulamanın odağını almaz; kapak yeniden kapanınca okuma durur ve pencere
  kapanır. Okuyan, sesli uyarılardaki gibi [doğal Türkçe sestir](#doğal-türkçe-ses).

- **Anahtarsız.** Claude API anahtarı kayıtlı değilse özet bu Mac'te sayılarla
  yazılır (hangi oturum, kaç dosya, kaç komut, şu anki durum) ve hiçbir yere
  gönderilmez. Yazan süre Claude'un çalışma süresi değil, sizin uzakta kaldığınız
  süredir; gün, saat ve dakikayla yazılır, Claude'un en son çalıştığı saat de
  belirtilir: "9 saat 4 dakika uzaktaydınız. Bu sürede Claude ... üzerinde
  çalıştı. En son çalıştığı saat: 01:33."
- **Anahtarla.** Anahtar kayıtlıysa özeti Claude yazar (varsayılan Claude Opus
  5.5; Ayarlar'dan Sonnet 5.5 ya da Haiku 5.5 seçilebilir). Uykusuz
  `api.anthropic.com`'a tek bir istek gönderir. İstekte yalnızca oturum
  başlıkları, araçların kaç kez çalıştığı, düzenlenen dosyaların adları,
  Claude'un komutlarına yazdığı açıklamalar ve son mesajlarının sonu bulunur;
  dosya içerikleri, komut satırları ve komut çıktıları gönderilmez. İstek
  başarısız olursa yerel özet kullanılır. Gönderilecek metni önceden görmek
  için `~/Applications/Uykusuz.app/Contents/MacOS/Uykusuz --away-digest 60`
  son 60 dakikanın dökümünü ve yerel özetini yazdırır; hiçbir şey göndermez.
- **Anahtar.** Anahtar giriş Anahtar Zinciri'nde saklanır; config.json'a ve
  günlüğe yazılmaz. Uygulama her kurulumda yeniden imzalandığı için yeni bir
  kurulumdan sonra anahtarı Ayarlar'dan yeniden kaydetmek gerekir. Max ve Team
  planları her ay Claude Console'da kullanılabilen bir API kredisi içerir
  (claude.ai > Ayarlar > Faturalandırma > API credits); anahtarı harcama sınırı
  olan ayrı bir çalışma alanında oluşturun.

### Defter

Claude API anahtarı kayıtlıysa Uykusuz, siz Mac'in başındayken iki saatte bir
Mac'e bakar ve Claude'a boşuna kaynak harcayan bir şey olup olmadığını sorar:
kimsenin kullanmadığı bir iOS simülatörü, hiç kapsayıcı çalışmazken bellek tutan
Docker Desktop, takası dolduran bir uygulama gibi. Söylenecek bir şey varsa
menüdeki **Defter** penceresine yazar.

- **Az bildirim.** Söylenecek bir şey yoksa hiçbir şey yazılmaz. Yazılan her şey
  defterde kalır, ama bildirim en fazla dört saatte bir gelir. Claude aynı şeyi
  yeniden söylemez; istemediğiniz bir öneri bir gün boyunca yeniden yapılmaz.
  Menüdeki öğe görmediğiniz kayıt sayısını gösterir: **Defter (1 yeni)**.
- **Yanıt yazarsınız.** Bildirimdeki **Yanıtla** alanına ya da Defter penceresine
  yazarsınız, Claude yanıt verir. "Bu simülatör açık kalsın" gibi isteklerinizi
  kendi notlarına yazar ve sonraki bakışlarda hatırlar; notlar pencerede
  **Uykusuz'un notları** başlığında görünür.
- **Yalnızca siz onaylarsanız.** Uykusuz kendisi yalnızca önerdiği tek işi yapar,
  o da siz bildirimdeki ya da penceredeki düğmeye basınca ya da yanıtınızda kabul
  edince: bir simülatörü kapatmak (`xcrun simctl shutdown`), bir uygulamadan
  çıkmak (kaydedilmemiş bir şey varsa uygulama sorar) ya da bir Docker
  kapsayıcısını durdurmak (`docker stop`; `docker start` ile yeniden açılır).
  Hedef, o anki durumda gerçekten açık olan bir şey olmalıdır. Terminallerden,
  Claude, Codex ve kod düzenleyicileri gibi ajanların çalıştığı uygulamalardan ve
  Uykusuz'dan hiçbir zaman çıkılmaz; Ayarlar'daki ajan listesinde olsalar da Docker
  Desktop ya da bir tarayıcı önerilebilir. Bir Claude Code oturumunun çalıştığı ya
  da bir sürecin bağlı olduğu simülatör, Simulator uygulaması kapalı olsa bile
  önerilmez: Uykusuz bunun için son altı saatte yazılmış oturum kayıtlarının son
  2 MB'ında simülatörün kimliğini (UDID) arar ve süreçlerin argümanlarına bakar. **Gerek yok** öneriyi kapatır; yeni bir
  öneri gelince yanıtlanmamış eskisi kapanır, böylece "evet" hep son mesaja gider.
- **Claude'a giden.** Açık simülatörlerin adı, sürümü, içinde açık uygulamalar ve
  bir oturumun ya da sürecin onu kullanıp kullanmadığı; çalışan Docker
  kapsayıcılarının adı, imajı, durumu ve kullanımı; en çok bellek ve işlemci
  kullanan uygulamaların adı, bundle kimliği, kullanımı ve en son ne zaman öne
  geldiği; bellek, takas, pil, ısı ve disk durumu; defterin son kayıtları ve
  notlar. Pencere başlıkları, dosya adları, klasör yolları ve komut satırları
  gitmez. Gönderilecek dökümü görmek için
  `~/Applications/Uykusuz.app/Contents/MacOS/Uykusuz --mac-snapshot` hiçbir şey
  göndermeden yazdırır.
- **Dosya.** Defter `~/Library/Application Support/Uykusuz/defter.json`
  dosyasında, yalnızca sizin hesabınızın okuyabileceği izinlerle tutulur; en yeni
  300 kayıt kalır. `uninstall.sh --purge` onu da siler.
- **Model ve maliyet.** Her bakış ve her yanıt bir API isteğidir; özeti yazan
  model kullanılır. Ayarlar > Defter'den kapatılır; **Şimdi bak** beklemeden
  bakar.

### Claude'un yanıtını dinleme

Claude uygulamasında baktığınız sohbetin son mesajını dinlemek için **⌃⌥D**
kısayoluna basın ya da göze sağ tıklayınca açılan menüden **Son yanıtı dinle**
öğesini seçin. Yalnızca o mesaj ya da onayınızı bekleyen plan okunur; önceki
adımlar ve araç çıktıları okunmaz. Siz istemeden hiçbir şey okunmaz.

- **Hangi sohbet.** Uykusuz, Claude uygulamasının sohbet kayıtlarından en son
  odaklandığınız sohbeti bulur. Bu kayıtlar yoksa, örneğin Claude Code'u yalnızca
  terminalde kullanıyorsanız, en son yazılan oturumun yanıtı okunur.
  `~/Applications/Uykusuz.app/Contents/MacOS/Uykusuz --last-reply` okunacak
  sohbeti ve metni ses çıkarmadan yazdırır.
- **Onay bekleyen plan.** Claude bir plan sunup onayınızı bekliyorsa son
  mesajın yerine plan okunur ve pencerenin başlığında sohbetin adından önce
  "Plan" yazar. Plan, `~/.claude/plans` altındaki dosyasından okunur; dosya
  orada değilse Claude'un onaya sunduğu metin okunur. Bu yalnızca onay
  aşamasında olur: planı onaylayınca ya da geri çevirince yine son mesaj okunur,
  üzerinde çalışılan plan her basışta yeniden okunmaz.
- **Yeniden basınca.** Aynı sohbette okuma sürerken basmak okumayı durdurur.
  Başka bir sohbete geçip basmak o sohbetin yanıtını okur; Claude bu arada yeni
  bir şey yazdıysa yenisi okunur.
- **Ne okunur.** Markdown işaretleri okunmaz. Kod blokları "Kod bloğu atlandı"
  diye geçilir, bağlantı adresleri okunmaz, dosya yollarının yalnızca dosya adı
  söylenir. Parantez içindeki kod adları atlanır.
- **Okunan kelime ekranda.** Yanıt ekranda görünüyorsa okunan kelime sohbetteki
  yazının üzerinde saydam bir işaretle gösterilir. Sohbetin yazısı değişmez ve
  işaret tıklamaları engellemez. Uykusuz sohbeti kendisi kaydırmaz: okunan yer
  ekranda değilse yazı sağ üstteki pencerede görünür, pencere de hangi yöne
  kaydırmanız gerektiğini söyler; kaydırınca işaret yeniden sohbete geçer.
- **Nasıl bulunur.** Bir uygulama başka bir uygulamanın penceresine yazamadığı
  için Uykusuz kelimenin yerini ekrandan okuyarak bulur: okuma başlayınca, okuma
  sürerken iki saniyede bir ve siz kaydırınca ya da tıklayınca ekrana bakar. Her
  bakış işlemciden yaklaşık 0,1 saniye alır. Bunun için macOS ekran kaydı izni
  gerekir; okuma sırasında macOS menü çubuğunda kayıt simgesi gösterebilir. İzin
  yoksa pencere bunu söyler ve yazı orada izlenir. Ayarlar > Claude'un yanıtını
  dinle bölümünden kapatılınca Uykusuz ekrana bakmaz, yazı yine pencerede izlenir.
- **Pencere.** [Sen yokken özetinin](#sen-yokken-özeti) penceresidir: ❚❚ durdurur,
  ◀◀ ve ▶▶ beşer kelime gider, çubuk istediğiniz yere götürür. Yazı ekranda
  işaretlenirken pencerede yalnızca başlık, düğmeler ve çubuk kalır. Yazı pencerede
  görünürken sığmayan metin kaydırılır ve okunan paragrafı izler. Okuma bitince
  pencere birkaç saniye sonra kapanır.
- **Kısayol.** Hangi uygulamada olursanız olun çalışır; Ayarlar > Claude'un
  yanıtını dinle bölümünden kapatılır. Başka bir uygulama ⌃⌥D kısayolunu
  kendine ayırmışsa Ayarlar bunu söyler ve menü yine çalışır. macOS diğer
  durumları bildirmez; o uygulama da aynı kısayolu kullanıyorsa ikisi de tepki
  verebilir.
- **Gizlilik.** Yanıt bu Mac'te okunur, diske yazılmaz ve hiçbir yere
  gönderilmez. Ekranın görüntüleri de yalnızca bellekte kalır; yazıyı macOS'un
  metin tanıması bu Mac'te okur. Okuma sürerken Uykusuz, farenin kaydırıldığını ve
  tıklamanın bittiğini anlar. Başka hiçbir tuşu görmez ve kısayol için izin istemez.

### Seçilen alanı dinleme

Ekranda yalnızca bir bölümü dinlemek için **⌃⌥S** kısayoluna basın ya da göze sağ
tıklayınca açılan menüden **Alan seçip dinle** öğesini seçin. Ekran kararır;
okunacak alanı fareyle çizin ve alandaki yazı okunsun. Çizerken Esc ya da yeniden
⌃⌥S vazgeçer.

- **Ne okunur.** Yazı alanın görüntüsünden tanındığı için tarayıcıda, PDF'te,
  terminalde ya da bir resimde aynı şekilde çalışır. Türkçe ve İngilizce tanınır;
  sütunlar, liste maddeleri ve tablo hücreleri sırayla, ayrı ayrı söylenir.
  Bağlantı adresleri okunmaz, dosya yollarının yalnızca dosya adı söylenir.
  Alanın sınırının ortasından geçtiği bir satır okunmayabilir; satırları tam içine
  alacak şekilde çizin.
- **Pencere.** [Claude'un yanıtını dinlerken](#claudeun-yanıtını-dinleme) olduğu
  gibi okunan kelime ekrandaki yazının üzerinde işaretlenir; sağ üstteki pencerede
  ❚❚ durdurur, ◀◀ ve ▶▶ beşer kelime gider, çubuk istediğiniz yere götürür. Okuma
  sürerken yeniden ⌃⌥S okumayı durdurur.
- **İzin.** Görüntü için macOS ekran kaydı izni gerekir. İlk basışta Sistem
  Ayarları > Gizlilik ve Güvenlik > Ekran ve Sistem Sesi Kaydı açılır; orada
  Uykusuz'u açın ve macOS Uykusuz'u yeniden açmayı önerince kabul edin. macOS izni
  uygulamanın imzasına bağlar, Uykusuz da her kurulumda yeniden imzalanır: eski izin
  orada açık görünse de yeni kurulumda geçmez ve kapatıp açmak onu yenilemez. Bu
  yüzden Uykusuz yeni bir kurulumun ilk açılışında kendi eski izin kaydını siler ve
  ilk basışta izni yeniden verirsiniz. Uykusuz orada açık göründüğü hâlde pencere
  izin istiyorsa onu seçip – düğmesiyle kaldırın ve ⌃⌥S'ye yeniden basın. macOS bu
  izni zaman zaman yeniden sorabilir. İzin yoksa pencere bunu söyler, Uykusuz'un
  geri kalanı etkilenmez.
- **Gizlilik.** Uykusuz ekrana yalnızca siz okuma isteyince bakar: yazıyı almak
  için çizdiğiniz alana bir kez, okunan kelimeyi işaretlemek için okuma sürerken
  birkaç saniyede bir. Kendi pencereleri görüntüye girmez. Görüntü bellekte kalır,
  yazıyı macOS'un metin tanıması bu Mac'te okur. Görüntü ve yazı diske ya da
  günlüğe yazılmaz, hiçbir yere gönderilmez.
- **Kısayol.** Hangi uygulamada olursanız olun çalışır; Ayarlar > Seçilen alanı
  dinle bölümünden kapatılır. Başka bir uygulama ⌃⌥S kısayolunu kendine ayırmışsa
  Ayarlar bunu söyler ve menü yine çalışır.

### Doğal Türkçe ses

Uyarıları, özeti, Claude'un yanıtını ve seçtiğiniz alanı Uykusuz'la gelen yapay
zekâ sesi okur.
Ayarlar > Kapak kapanınca yapılacaklar bölümündeki **Doğal Türkçe ses** seçeneği
varsayılan olarak açıktır; kapatınca Mac'in Türkçe sesi okur.

- **Bu Mac'te çalışır.** Ses uygulamanın içindedir (yaklaşık 33 MB). Hiçbir şey
  indirilmez ve okunan metin ağa gitmez.
- **Yalnızca okurken yüklenir.** Arka planda çalışan bir şey yoktur: ses, okuma
  başlayınca yaklaşık yarım saniyede yüklenir ve okuma bittikten 30 saniye sonra
  bellekten çıkar.
- **Mac'i yormaz.** Bir saniyelik konuşma, M5 Pro'da yaklaşık 0,01 saniye
  işlemci harcar. Ses üretmek okumaktan çok daha hızlıdır.
- **Gürültülü yerde de duyulur.** Ses, müzik ve videolarla aşağı yukarı aynı
  yükseklikte çıkar. En çok ünsüzler ve kelime sonları yükselir, tepe noktaları
  sınırlandığı için ses patlamaz. Sessiz bir yerde fazla gelirse Mac'in sesini
  kısın.
- **Teknik metni düzgün okur.** `README` "ridmi", `commit` "komit", `API` "Ey Pi
  Ay" diye söylenir; `Keychain'den` gibi eklerin sesi de okunuşa uyar. Sayılar,
  tarihler ve saatler ekleriyle okunur: `14:30'da` "on dört otuzda" olur.
- **Okuyamazsa.** Ses yüklenemez ya da ses çıkışı açılamazsa okumayı Mac'in Türkçe
  sesi sürdürür. Kulaklık takıp çıkarınca okuma aynı kelimeden devam eder.
- **Deneme.** Ayarlar'daki **Dinle** düğmesi sesi çalar;
  `~/Applications/Uykusuz.app/Contents/MacOS/Uykusuz --voice-check` çalışıp
  çalışmadığını ses çıkarmadan söyler.

## Kapak kapanınca neler olur

<p align="center">
  <img src="docs/assets/lid-actions.svg" alt="Ayarlar varsayılanlarının çizimi: ekranı ve klavye ışığını kapat açık; dondurma listesinde WhatsApp, Word, Excel ve ParaView var; diğer tüm uygulamaları dondur açık; boştaki Docker'ı duraklat kapalı; sesi kapat, Düşük Güç Modu ve sesli uyarı açık. Oturum sırasında kapağın kapanması bu eylemleri uygular; kapağı yeniden açmak ışığı, sesi ve Uykusuz'un yaptığı doğrulanmış dondurmaları geri yüklemeyi dener. Oturum sürer. Etkin bir oturum yokken kapak değişiklikleri hiçbir şey yapmaz." width="880">
</p>

Oturum sırasında kapağı kapatmak aşağıdakilerin her birini yapar; kapağı açmak
bunları geri almaya çalışır. Kapak kapalıyken zamanlayıcı geri saymayı sürdürür.

- **Ekran ve klavye ışığı kapanır.** Uykusuz önce parlaklıklarını kaydeder.
  Uyku kapalıyken macOS bunu artık kendiliğinden yapmaz. Klavye ışığı zaten
  kapalıysa (macOS onu gün ışığında kendisi kapatır) Uykusuz ona dokunmaz;
  böylece akşam klavyeyi kullanmaya başlayınca macOS ışığı yine kendisi açar.
- **Uygulamalar dondurulur.** Dondurma, bir uygulamanın süreçlerine `SIGSTOP`
  gönderir; süreçler kapak açılınca `SIGCONT` gönderilene kadar duraklar.
  Dondurma listesi WhatsApp, Word, Excel ve ParaView ile başlar. "Diğer tüm
  uygulamaları dondur" da varsayılan olarak açıktır: ajan uygulamaları, Apple
  uygulamaları, Docker Desktop ve yerleşik olarak korunan uygulamalar dışındaki
  her Dock uygulaması da dondurulur. Korunanlar arasında düzenleyiciler,
  terminaller, tarayıcılar, yapay zekâ uygulamaları, parola yöneticileri,
  Tailscale, ProtonVPN, AnyDesk ve toplantı, kayıt ve dikte uygulamaları
  (Zoom, Teams, Webex, FaceTime, Wispr Flow, Granola, Otter, OBS ve Loom) vardır.
- **Ses kapatılır.** Kapağı açmak, Uykusuz'un sesini kapattığı her çıkışın
  sesini, siz başka bir çıkışa geçmiş olsanız bile yeniden açar.
- **Düşük Güç Modu açılır.** Bir pil ya da ısı kuralı hâlâ gerektirmiyorsa
  kapak açılınca kapanır.
- **Uyarılar sesli söylenir.** Kapak kapalıyken bildirimler görünmediği için
  pil eşiği, ısınma ve oturum sonu Türkçe sesle söylenir: Uykusuz sesi bir an
  açar, uyarıyı söyler ve eski ses ayarını geri koyar. Uyarıyı
  [doğal Türkçe ses](#doğal-türkçe-ses) söyler. O kapalıysa Mac'te kurulu en iyi
  Türkçe ses kullanılır: Premium, yoksa Gelişmiş, yoksa macOS ile gelen basit
  Yelda. Bu durumda daha iyi bir ses için Sistem Ayarları > Erişilebilirlik >
  Seslendirilen İçerik > Sistem sesi bölümünden "Yelda (Gelişmiş)" sesini
  indirin; Uykusuz onu yeniden başlatmadan kullanmaya başlar. Ayarlar'da
  kullanılan ses görünür ve **Dinle** düğmesi onu çalar.
- **Çalışan kapsayıcı ve süren bir docker işi yoksa Docker Desktop
  duraklatılır.** `docker build`, `pull` ya da `push`, kapsayıcısını henüz
  açmamış bir `docker run` ya da `docker compose up`, `docker load`, `save` ya da
  `commit` gibi bir iş sürerken Docker çalışmaya devam eder. Bu seçenek varsayılan
  olarak kapalıdır.

Apple çipli ya da T2 çipli Mac dizüstü bilgisayarlarda kapağı kapatmak,
yerleşik mikrofonun bağlantısını donanım düzeyinde keser. Kapak kapalıyken bir
toplantıyı kaydetmek için AirPods ya da harici bir mikrofon gerekir.

[docs/lid-close.md](docs/lid-close.md) ayrıntıları içerir: Docker'ın nasıl
denetlendiği, parlaklığın nasıl geri yüklendiği, yükseltmede bir kez yapılan
ayar değişikliği ve kapak eylemlerinin kapağı kapatmadan nasıl denendiği.

## Kurtarma nasıl çalışır

<p align="center">
  <img src="docs/assets/recovery-flow.svg" alt="Uygulama ve bir launchd kurtarma ajanı, ortak bir kilit ve kurtarma kayıt defteri üzerinden eşgüdüm sağlar. Normal temizliği uygulama yapar. Ajan her dakika denetler ve zamanı gelmiş kurtarmayı dener; geçerli ve etkin oturumlara dokunmaz. Başarısız ya da okunamayan kurtarma kanıtı diskte kalır; kaydedilmiş ses için uygulama gerekir, doğrulanamayan durdurulmuş süreçler ise incelenmelidir." width="880">
</p>

Uykusuz her değişikliği yapmadan önce bir **kurtarma kayıt defterine**, yani
diskteki bir dosyaya yazar. Oturumu bitirmek, kayıt defterinde listelenenleri
geri almayı dener. Uygulama çökerse ya da kapanırsa, oturumun bitiş zamanı
geçtikten sonra kurtarma ajanı aynısını dener.

Bazı durumlarda sizin ilgilenmeniz gerekir:

- Kurtarma ajanı sesi geri yükleyemez. Bunun için Uykusuz'u yeniden açın.
- Kurtarma ajanı pili ya da sıcaklığı izlemez.
- Uykusuz yalnızca dondurduğunu kanıtlayabildiği bir süreci çözer.
  Kanıtlayamadığı dondurulmuş bir süreç, siz denetleyene kadar donmuş kalır.

Menüde bir kurtarma uyarısı görünürse Mac'i başında kimse olmadan bırakmadan
önce onunla ilgilenin. [docs/recovery.md](docs/recovery.md) her durumu
açıklar.

## Ek özellikler

<details>
<summary><strong>iPhone kişisel erişim noktasına geçiş ve tmux</strong></summary>

Oturum sırasında Wi-Fi bağlantısı koparsa Uykusuz, iPhone'unuzun kişisel
erişim noktasına (hotspot) katılabilir. Sistem Ayarları > Wi-Fi >
"Erişim noktalarına katılmak için sor" (Ask to join hotspots) seçeneğini
Otomatik yapın, ardından hotspot adını ve parolasını Uykusuz'un Ayarlar
penceresine girin. Parola giriş anahtar zincirinizde saklanır. macOS, Wi-Fi
ağ adlarını okumak için Konum Servisleri iznini şart koştuğundan Uykusuz bu
izni ister. Konumunuzu hiçbir zaman okumaz. Uykusuz'u yeniden kurduktan sonra
parolayı yeniden girin. Hotspot ayarlıyken Ayarlar, "Erişim noktalarına katılmak
için sor" seçeneğinin Otomatik olup olmadığını denetler; değilse turuncu bir
uyarıyla Wi-Fi ayarlarını açan bir düğme gösterir ve oturum başlarken bunu
günlüğe yazar.

Hotspot'tayken bilinen bir Wi-Fi ağının yanına dönünce Uykusuz Wi-Fi'ye kendisi geri döner
(Ayarlar'daki **Bilinen Wi-Fi ağına geri dön**, varsayılan olarak açık). Oturum
sürerken 2 dakikada bir çevreyi tarar. Daha önce bağlandığınız ve parolası olan
bir ağ yeterince güçlüyse yalnızca hotspot'tan ayrılır; macOS o ağa kendi kayıtlı
parolasıyla bağlanır. Uykusuz ağ seçmez, Wi-Fi parolalarını görmez ve daha önce
bağlanmadığınız bir ağa hiçbir zaman yönelmez. Çevrede bilinen parolasız bir ağ
varsa hotspot'tan ayrılmaz; macOS yine de parolasız bir ağa bağlanırsa Uykusuz
oradan ayrılıp hotspot'a döner. Başarısız bir denemeden sonra 10 dakika bekler.
macOS'un parolasız ağlara hiç kendiliğinden katılmasını istemiyorsanız bu ağları
Sistem Ayarları > Wi-Fi > Bilinen Ağlar'dan unutun ya da Otomatik Katıl'ı kapatın.

Ağ 90 saniye boyunca kesik kalırsa Uykusuz, bir kodlama ajanının çalıştığı bir
tmux bölmesine `continue` da yazabilir. Yalnızca Ayarlar'da listelediğiniz ve
kendiniz işaretlediğiniz bölmelere yazar:

```bash
tmux set-option -p -t <oturum:pencere.bölme> @uykusuz-nudge on
```

Siz açmadıkça Enter'a basmaz. İçine yazı yazmadığınız bir bölmeyi işaretleyin.
[docs/extras.md](docs/extras.md) ayrıntıları içerir.

</details>

<details>
<summary><strong>Chrome, Chromium, Arc ve Comet kısıtlaması</strong></summary>

Bu tarayıcılar, macOS'in gizli olarak bildirdiği pencereleri yavaşlatır; kapak
kapalıyken bu, tüm pencereler demektir. Çalışan bir tarayıcıda
`--disable-backgrounding-occluded-windows` ya da
`--disable-renderer-backgrounding` yoksa sağ tıklama menüsü "Kısıtlamasız
yeniden başlat: [tarayıcı]" seçeneğini sunar. Yeniden başlatma tarayıcıyı
kapattığı için önce sorar; sekmeler yalnızca tarayıcı açılışta onları yeniden
açıyorsa geri gelir. Bazı web uygulamaları kapak kapalıyken yine de durabilir.
[docs/extras.md](docs/extras.md#chrome-chromium-arc-ve-comet-kısıtlaması)
ayrıntıları içerir.

</details>

<details>
<summary><strong>Yapılandırma ve gizlilik</strong></summary>

Ayarlar `~/Library/Application Support/Uykusuz/config.json` dosyasında,
günlükler `~/Library/Logs/Uykusuz/` klasöründe tutulur. Uykusuz iki klasörü
ve içlerindeki dosyaları yalnızca sahibinin erişebileceği izinlere ayarlar.
Sembolik bağlantılara ve erişim denetim listelerine (ACL'ler, hesap başına ek
izin girdileri) dokunmaz; bu yüzden başka bir hesap bunlardan biri aracılığıyla
yine de erişebilir. Günlükler Wi-Fi adları, süreç ayrıntıları ve tmux hedefleri
içerebilir; bu yüzden bir günlüğü paylaşmadan önce gözden geçirin. Uykusuz'un
ağ istekleri yalnızca isteğe bağlı iki özelliktedir: Claude API anahtarı
kaydettiyseniz "Sen yokken" özeti, iPhone'a gidecek mesaj ve defter için
`api.anthropic.com`'a gidilir (bkz. [Sen yokken özeti](#sen-yokken-özeti) ve
[Defter](#defter));
iMessage'ı Mac'teki Mesajlar uygulaması gönderir (bkz.
[Claude sizi beklerken iPhone'a haber](#claude-sizi-beklerken-iphonea-haber)).
Ağ kesintisinden duran bir Claude oturumu beklenirken ayrıca Claude'un API
sunucusuna veri göndermeden bağlanmak denenir (bkz.
[Ağ kesintisinden sonra kendiliğinden sürdürme](#ağ-kesintisinden-sonra-kendiliğinden-sürdürme)).
[docs/extras.md](docs/extras.md#yapılandırma-ve-gizlilik) ayrıntıları içerir.

</details>

## Kaldırma

Çalışma kopyanızdan:

```bash
./scripts/uninstall.sh          # uygulamayı, ajanı ve sudoers kuralını kaldırır
./scripts/uninstall.sh --purge  # ayarları ve günlükleri de kaldırır
```

Kaldırma betiği önce açık kalan oturumu geri alır ve bunu yapamazsa hiçbir şey
kaldırmadan durur. sudoers kuralını kaldırmak için parolanızı ister.
[docs/install.md](docs/install.md#kaldırma) ayrıntıları içerir.

## Proje yapısı

```text
Sources/Uykusuz/
  Core/      oturum yönetimi, uyku koruması, kapak eylemleri, Claude oturumu, kurtarma
  Model/     ayarlar, oturum ve kurtarma kayıt defteri
  Store/     dosyaların yeri ve yalnızca sahibine açık izinleri
  System/    macOS ile konuşan katman: güç, ekran, ses, dondurma, ağ, Claude hook'ları
  UI/        menü çubuğu, sağ tık menüsü ve Ayarlar penceresi (SwiftUI)
scripts/     kurulum, kaldırma, kurtarma (backstop.sh) ve simge betikleri
Tests/       XCTest paketi: sahte araçlar ve geçici klasörlerle çalışır
docs/        kullanım ve tasarım belgeleri
```

## Geliştirme

```bash
swift build
swift test
```

Testler sahte araçlar ve geçici klasörler kullanır; bu yüzden güç ayarlarınızı
hiçbir zaman değiştirmez. Tasarım notları [docs/spec.md](docs/spec.md),
gerçek Mac doğrulamaları [docs/release-validation.md](docs/release-validation.md)
dosyasındadır (ikisi de İngilizce).

## Katkıda bulunma

Hata bildirimleri ve öneriler için bir issue açın. Yeni bir özelliğe ya da bir
varsayılanı değiştirmeye başlamadan önce issue'da konuşmak işleri hızlandırır.
Kod göndermeden önce [CONTRIBUTING.md](CONTRIBUTING.md) dosyasını okuyun:
testler, betik denetimleri ve gerçek Mac'te doğrulama beklentileri orada
anlatılır.

## Güvenlik

Bir güvenlik açığı bulduğunuzu düşünüyorsanız herkese açık bir issue açmak
yerine [SECURITY.md](SECURITY.md) dosyasındaki yolu izleyin. Uygulamanın
yetkileri, kalıcı bileşenleri ve tuttuğu veriler
[GUVENLIK-INCELEMESI.md](GUVENLIK-INCELEMESI.md) dosyasında incelenir.

## Lisans

[MIT](LICENSE). Uykusuz, Krish Garg'ın MIT lisanslı Insomnia projesi üzerine
geliştirildi. Doğal Türkçe sesin bileşenleri kendi lisanslarıyla gelir:
[Resources/Voice/NOTICE.md](Resources/Voice/NOTICE.md).
