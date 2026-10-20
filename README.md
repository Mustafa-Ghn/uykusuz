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
  <img alt="Lisans: MIT" src="https://img.shields.io/badge/lisans-MIT-3da639">
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
  kendiliğinden açılır, uzar ve Claude durunca kapanır.
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
- **Gizlilik.** Uykusuz hiçbir ağ isteği yapmaz. Ayarlar ve günlükler yalnızca
  sizin hesabınızın okuyabildiği dosyalarda tutulur.

## Gereksinimler

- macOS 26 ya da üstü.
- Apple Silicon (Apple çipli) bir Mac. Intel bir Mac'te kaynaktan derleme
  denenmemiştir.
- Swift 6.2 ya da üstünü içeren Xcode.

## Kurulum

Uykusuz kaynak koddan derlenerek kurulur. Depoyu klonlayın, kurulum betiğini
çalıştırın ve uygulamayı açın:

```bash
git clone https://github.com/Mustafa-Ghn/insomnia-tr.git && cd insomnia-tr && ./scripts/install.sh
open "$HOME/Applications/Uykusuz.app"
```

SSH anahtarı kullanıyorsanız `git@github.com:Mustafa-Ghn/insomnia-tr.git`
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

Uykusuz güncelleme denetlemez; hiçbir ağ isteği yapmaz. Güncellemek için
çalışma kopyasında yeni değişiklikleri çekin ve kurulum betiğini yeniden
çalıştırın:

```bash
cd insomnia-tr
git pull
./scripts/install.sh
```

Kurulum betiği çalışan uygulamadan kapanmasını ister. Geri alınmayı bekleyen
bir değişiklik varken uygulama kapanmayı reddeder; betik o zaman durur ve
uygulamaya da kurtarma ajanına da dokunmaz. Parolanız her çalıştırmada bir kez
istenir. Kurulu sürümü Ayarlar > Uygulama gösterir. Ayrıntılar:
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
| Kapak kapanınca yapılacaklar | Ekran ve klavye ışığı, dondurma listesi, diğer tüm uygulamalar, Docker, ses, Düşük Güç Modu, sesli uyarı |
| Ajan uygulamaları | Hiçbir zaman dondurulmayan ya da kısıtlanmayan uygulamalar, App Nap |
| Pil ve ısı | Düşük Güç Modu ve oturum sonu eşikleri, ısı kuralları |
| Claude, kod modu ve ekran | Claude Code hook'ları, otomatik oturum, kod modu, boşta siyah ekran süreleri |
| Ağ yedekleme | iPhone kişisel erişim noktası, tmux dürtmesi |
| Uygulama | Girişte aç, yapılandırma klasörü, kurulu sürüm |

## Claude ile otomatik oturum

<p align="center">
  <img src="docs/assets/claude-auto-session.svg" alt="Dört adımlık akış: Claude Code hook'ları görevi Uykusuz'a bildirir; oturum kendiliğinden açılır ve menü çubuğunda geri sayım yerine Claude yazar; oturum Claude çalıştıkça 2 saatlik dilimlerle uzar; Claude 5 dakika çalışmayınca oturum biter. Altta: Claude yazısına tıklayıp süre girerseniz oturum sizin olur; basılı tutup bitirirseniz Claude yeniden başlayana kadar otomatik oturum açılmaz; pil eşiğe ya da Mac ısınma sınırına yakınken başlamaz; elle başlatılan oturumlar geri sayımla görünür." width="880">
</p>

Claude Code bir görev yürüttüğü sürece Uykusuz kendiliğinden bir oturum açar;
menü çubuğunda geri sayım yerine **Claude** yazar. Oturum Claude çalıştıkça
sürer (arka planda 2 saatlik dilimlerle uzar) ve Claude 5 dakika çalışmayınca
biter; Mac normal uykusuna döner. Sağ tık menüsü de "Claude çalıştıkça açık;
Claude durunca 5 dk sonra biter" satırını gösterir.

- **Oturumu devralma.** "Claude" yazısına tıklayıp bir süre girerseniz oturum
  sizin olur: girdiğiniz süre o andan itibaren sayılır ve geri sayım görünür.
  Claude bu oturumu artık uzatmaz ve bitirmez. Süreniz dolduğunda Claude hâlâ
  çalışıyorsa otomatik oturum yeniden başlar.
- **Erken bitirme.** Oturumu basılı tutarak bitirirseniz Claude bir kez durup
  yeniden başlayana kadar otomatik oturum açılmaz.
- **Güvenlik payı.** Mac ısınıyorsa ya da pil gücündeyken pil, bitiş eşiğinin
  (varsayılan %20) en çok 5 puan üstündeyse otomatik oturum başlamaz.
- **Elle başlatılan oturumlar.** Kendi başlattığınız oturumlar geri sayımla
  görünür; Claude onları uzatmaz ve bitirmez.

Kapak kapansa da Mac uyanık kalır: **Mac'i kapalı bir çantaya koymayın.**
Otomatik oturum Ayarlar > Claude, kod modu ve ekran bölümünden kapatılabilir.

### Claude'un çalıştığını algılama

Ayarlar > Claude, kod modu ve ekran bölümündeki **Kur** düğmesi (ya da
`~/Applications/Uykusuz.app/Contents/MacOS/Uykusuz --install-claude-hooks`)
Claude Code hook'larını kurar. Kuruluyken Claude yalnızca bir görev yürütürken
çalışıyor sayılır: bir istek başlayıp Claude yanıtını bitirene kadar ya da
Claude'un başlattığı bir komut (arka planda bile) çalışırken. Hook'lar
`~/.claude/settings.json` dosyasına eklenir ve dosyanın eski hâli
`settings.json.uykusuz-yedek` olarak saklanır; aynı düğme (ya da
`--remove-claude-hooks`) onları kaldırır. Hook'lar kurulu değilken Claude
masaüstü uygulaması açık olduğu sürece çalışıyor sayılır.

### Kod modu ve boşta siyah ekran

- **Kod modu.** Bir oturum sürerken kapak açıksa ve Claude çalışıyorsa Düşük
  Güç Modu açılır (pildeyken etkili).
- **Boşta siyah ekran.** Oturum sürerken kapak açıkken ekran koruyucu ve ekran
  uykusu çalışmaz. 60 sn girdi olmazsa ekran parlaklığı 0'a iner ve ekran hiç
  ışık vermez; 30 sn olmazsa klavye ışığı söner. Bir tuşa ya da fareye
  dokununca ikisi de eski seviyesine döner. Bu sırada ekran kendiliğinden
  kilitlenmez; Mac'in başından kalkarken Ctrl+Cmd+Q ile kilitleyin. Süreler
  Ayarlar > Claude, kod modu ve ekran bölümünden değişir.

## Kapak kapanınca neler olur

<p align="center">
  <img src="docs/assets/lid-actions.svg" alt="Ayarlar varsayılanlarının çizimi: ekranı ve klavye ışığını kapat açık; dondurma listesinde WhatsApp, Word, Excel ve ParaView var; diğer tüm uygulamaları dondur açık; boştaki Docker'ı duraklat kapalı; sesi kapat, Düşük Güç Modu ve sesli uyarı açık. Oturum sırasında kapağın kapanması bu eylemleri uygular; kapağı yeniden açmak ışığı, sesi ve Uykusuz'un yaptığı doğrulanmış dondurmaları geri yüklemeyi dener. Oturum sürer. Etkin bir oturum yokken kapak değişiklikleri hiçbir şey yapmaz." width="880">
</p>

Oturum sırasında kapağı kapatmak aşağıdakilerin her birini yapar; kapağı açmak
bunları geri almaya çalışır. Kapak kapalıyken zamanlayıcı geri saymayı sürdürür.

- **Ekran ve klavye ışığı kapanır.** Uykusuz önce parlaklıklarını kaydeder.
  Uyku kapalıyken macOS bunu artık kendiliğinden yapmaz.
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
  pil eşiği, ısınma ve oturum sonu Türkçe sesle (Yelda) söylenir: Uykusuz sesi
  bir an açar, uyarıyı söyler ve eski ses ayarını geri koyar.
- **Çalışan kapsayıcı yoksa Docker Desktop duraklatılır.** Bu seçenek
  varsayılan olarak kapalıdır.

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
parolayı yeniden girin.

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
içerebilir; bu yüzden bir günlüğü paylaşmadan önce gözden geçirin. Uykusuz
hiçbir ağ isteği yapmaz.
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

Uykusuz [MIT lisansı](LICENSE) ile dağıtılır.
