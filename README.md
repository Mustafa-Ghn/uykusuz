> **Bu depo hakkında:** Uykusuz, Krish Garg'ın geliştirdiği
> [Insomnia](https://github.com/krishhgg/Insomnia) uygulamasının kişisel
> kullanım için hazırlanmış özel (private) Türkçe çatalıdır (fork). Uygulama
> Uykusuz adıyla (`com.mustafaghn.uykusuz`) yeniden adlandırıldı; arayüzü,
> kurulum betiklerinin mesajları ve belgeler Türkçeye çevrilmiştir.
> Özgün proje MIT lisansıyla yayımlanır; bu çatal da aynı lisansı taşır
> ([LICENSE](LICENSE)). Bu çatalın GitHub sürümleri (release) yoktur: yalnızca
> bu depodan kaynak kod derlenerek kurulur. Çatala alınmadan önce yapılan
> güvenlik incelemesi: [GUVENLIK-INCELEMESI.md](GUVENLIK-INCELEMESI.md).

<p align="center">
  <img src="docs/assets/eye-open.svg" alt="Uykusuz: yuvarlak gözbebekli, üstünde beş kirpik olan açık bir göz" width="112">
</p>

<h1 align="center">Uykusuz</h1>

<p align="center">
  <strong>Mac'inizi uyanık tutun. Oturuma bir bitiş zamanı verin.</strong>
</p>

<p align="center">
  Süreli uyanık kalma oturumları için bir macOS menü çubuğu uygulaması.
  Uykusuz, MacBook'unuzun menü çubuğunda duran bir göz simgesidir. Dock simgesi
  ve ana penceresi yoktur. Mac'inizin ne kadar süre uyanık kalacağını ayarlayın,
  kapak kapanınca ne olacağını seçin ve geri alınamayan bir şey olduğunda bunu
  görün.
</p>

<p align="center">
  <a href="#kurulum"><strong>Kurulum</strong></a> ·
  <a href="#kullanım"><strong>Kullanım</strong></a> ·
  <a href="#kapak-kapanınca-neler-olur"><strong>Kapak kapanınca</strong></a> ·
  <a href="#kurtarma-nasıl-çalışır"><strong>Kurtarma</strong></a> ·
  <a href="#kaldırma"><strong>Kaldırma</strong></a> ·
  <a href="https://github.com/krishhgg/Insomnia"><strong>Özgün proje</strong></a>
</p>

> **Mac'i kapalı bir çantada değil, sabit ve iyi havalanan bir yüzeyde
> kullanın.** Uykusuz deneyseldir. Kurtarma başarısız olabilir ve çalışan bir
> zamanlayıcı bir güvenlik garantisi değildir.
> [Doğrulama durumu](docs/release-validation.md) (İngilizce) · [Apple'ın havalandırma önerileri](https://support.apple.com/en-us/102336)

<p align="center">
  <img src="docs/assets/session-flow.svg" alt="Menü çubuğu denetimlerinin çizimi: Gün, Saat ve Dakika girin, geri sayımı izleyin ve erken bitirmek için bitirme denetimini basılı tutun. Süre eklemek için göze ya da geri sayıma tıklayın. Kapağı kapatmak isteğe bağlıdır; tamamlanmamış bir kurtarma ilgilenmenizi gerektirir." width="880">
</p>

## Bu fork'a özel

Upstream Insomnia'dan farklı olarak Uykusuz'da:

- **Claude çalışırken otomatik oturum.** Claude bir görev yürüttüğü sürece
  oturum kendiliğinden 2 saatlik başlar, kalan süre 1 saatin altına indikçe 2
  saat uzar ve Claude 5 dakika çalışmayınca biter. Kapak kapansa da Mac
  uyanık kalır: **Mac'i kapalı bir çantaya koymayın.** Mac ısınıyorsa ya da
  pil bitiş eşiğinin 5 puan üstüne kadar düşmüşse otomatik oturum başlamaz.
  Otomatik oturumu siz bitirirseniz Claude bir kez durana kadar yenisi
  başlamaz. Elle başlattığınız oturumlara dokunulmaz.
- **Claude'un çalıştığını algılama.** Ayarlar > Claude ve kod modu bölümünden
  (ya da `~/Applications/Uykusuz.app/Contents/MacOS/Uykusuz
  --install-claude-hooks` ile) Claude Code hook'ları kurulur. Kuruluyken
  Claude yalnızca bir görev yürütürken çalışıyor sayılır: bir istek başlayıp
  Claude yanıtını bitirene kadar ya da Claude'un başlattığı bir komut (arka
  planda bile) çalışırken. Hook'lar `~/.claude/settings.json` dosyasına
  eklenir ve dosyanın eski hâli `settings.json.uykusuz-yedek` olarak saklanır.
  Kurulu değilken Claude masaüstü uygulaması açık olduğu sürece çalışıyor
  sayılır.
- **Kod modu.** Bir oturum sürerken kapak açıksa ve Claude çalışıyorsa
  Düşük Güç Modu açılır (pildeyken etkili).
- **Boşta siyah ekran.** Oturum sürerken kapak açıkken ekran koruyucu ve
  ekran uykusu çalışmaz. 60 sn girdi olmazsa ekran parlaklığı 0'a iner ve
  ekran hiç ışık vermez; 30 sn olmazsa klavye ışığı söner. Bir tuşa ya da
  fareye dokununca ikisi de eski seviyesine döner. Bu sırada ekran
  kendiliğinden kilitlenmez; Mac'in başından kalkarken Ctrl+Cmd+Q ile
  kilitleyin. Süreler Ayarlar > Claude, kod modu ve ekran bölümünden değişir.
- **Kapak kapalıyken sesli uyarı.** Kapak kapalıyken bildirimler
  görünmediği için pil eşiği, ısınma ve oturum sonu Türkçe sesle (Yelda)
  söylenir: Uykusuz sesi bir an açar, söyler ve eski ses ayarını geri koyar.
- **Varsayılanlar.** Pil eşikleri %30 (Düşük Güç Modu) ve %20 (oturum
  sonu). "Diğer tüm uygulamaları dondur" açık; dondurma listesinde WhatsApp,
  Word, Excel ve ParaView var. ProtonVPN ve AnyDesk hiç dondurulmaz.
- **Ağ isteği yok.** Upstream'in "güncellemeleri denetle" düğmesi kaldırıldı.
- **Arka plan öğesinin adı.** Kurtarma ajanı, Sistem Ayarları > Genel > Giriş
  Öğeleri ve Uzantılar'da `sh` yerine Uykusuz olarak görünsün diye
  uygulamanın kendi programından başlar (`--backstop-agent`). Program aynı
  imza doğrulamasını (`codesign`, sabitlenmiş cdhash) yapan upstream ajan
  komutunu çalıştırır. "Kimliği belirsiz geliştirici" yazısı ücretli bir
  Apple Developer ID imzası olmadan kalkmaz.

## Gereksinimler

- macOS 26 ya da üstü.
- Apple Silicon (Apple çipli) bir Mac. Intel bir Mac'te kaynaktan derleme
  denenmemiştir.
- Swift 6.2 ya da üstünü içeren Xcode.
- `git` ve bu özel depoya erişimi olan bir GitHub hesabı.

## Kurulum

Bu çatal yalnızca kaynak koddan kurulur. Depoyu klonlayın, kurulum betiğini
çalıştırın ve uygulamayı açın:

```bash
git clone https://github.com/Mustafa-Ghn/insomnia-tr.git && cd insomnia-tr && ./scripts/install.sh
open "$HOME/Applications/Uykusuz.app"
```

Depo özel olduğu için `git clone` sırasında GitHub kimlik doğrulaması gerekir
(örneğin önce `gh auth login` çalıştırarak; SSH anahtarı kullanıyorsanız
`git@github.com:Mustafa-Ghn/insomnia-tr.git` adresiyle klonlayın).

`./scripts/install.sh`, uygulamayı bu çalışma kopyasından derler
(`scripts/build-app.sh`, ad-hoc imzalı) ve kurar. sudoers kuralı için
parolanızı bir kez sorar; bu istem, derleme bittikten sonra ve önceki
kurulumdaki hiçbir şeye dokunulmadan önce gelir. Her adımın neyi denetlediği
[docs/install.md](docs/install.md) sayfasında anlatılır.

Ayarlar > Uygulama kurulu sürümü gösterir. Bu çatalda güncelleme denetimi
kaldırıldı: Uykusuz hiçbir ağ isteği yapmaz. Güncellemek için
[Güncelleme](#güncelleme) bölümündeki adımları izleyin.

<details>
<summary><strong>Kurulumun Mac'inizde değiştirdikleri</strong></summary>

sudoers kuralı bir sistem dosyası olduğu için kurulum betiği parolanızı ister.
Şunları kurar:

- Uygulamayı, `~/Applications/Uykusuz.app` konumuna.
- Bir **kurtarma ajanı**: her dakika çalışan bir `launchd` görevi. Bir oturumun
  bitmesi gerektiği hâlde uygulama artık çalışmıyorsa ajan, oturumun yaptığı
  değişiklikleri geri almaya çalışır.
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

Yeni değişiklikleri çekin ve kurulum betiğini yeniden çalıştırın:

```bash
cd insomnia-tr
git pull
./scripts/install.sh
```

Kurulum betiği çalışan uygulamadan kapanmasını ister. Geri alınmayı bekleyen
bir değişiklik varken uygulama kapanmayı reddeder; betik o zaman durur ve
uygulamaya da kurtarma ajanına da dokunmaz. Parolanız her çalıştırmada bir kez
istenir. Ayrıntılar: [docs/install.md](docs/install.md#yükseltmeler).

## Upstream değişikliklerini alma

Özgün projedeki (upstream) yenilikleri bu çatala almak için:

```bash
git remote add upstream https://github.com/krishhgg/Insomnia.git   # yalnızca ilk seferde
git fetch upstream
git merge upstream/main
```

> **Uyarı:** Bu çatalda arayüz metinleri (`Sources/`), betik mesajları
> (`scripts/install.sh`, `scripts/uninstall.sh`) ve belgeler Türkçeye
> çevrildiği için upstream'in bu satırlarda yaptığı değişiklikler birleştirme
> çakışmalarına (merge conflict) yol açar. Çakışan dosyaları elle birleştirin:
> Türkçe metni koruyun, upstream'in getirdiği yeni davranışı alın ve yeni ya da
> değişmiş İngilizce metinleri çevirin. Birleştirmeden sonra uygulamayı
> `./scripts/install.sh` ile yeniden derleyip kurun.

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

## Kapak kapanınca neler olur

<p align="center">
  <img src="docs/assets/lid-actions.svg" alt="Ayarlar varsayılanlarının çizimi: dondurma listesinde WhatsApp, Word ve Excel var, Docker'ın boşta kuralı kapalı, sesi kapatma açık. Oturum sırasında kapağın kapanması ayarlanan eylemleri uygular; kapağı yeniden açmak, Uykusuz'un yaptığı doğrulanmış dondurmaları çözmeye ve kaydedilmiş sesi geri yüklemeye çalışır. Oturum sürer. Etkin bir oturum yokken kapak değişiklikleri hiçbir şey yapmaz." width="880">
</p>

Oturum sırasında kapağı kapatmak aşağıdakilerin her birini yapar; kapağı açmak
bunları geri almaya çalışır. Kapak kapalıyken zamanlayıcı geri saymayı sürdürür.

- **Ekran ve klavye ışığı kapanır.** Uykusuz önce parlaklıklarını kaydeder.
  Uyku kapalıyken macOS bunu artık kendiliğinden yapmaz.
- **Dondurma listesindeki uygulamalar dondurulur.** Dondurma, bir uygulamanın
  süreçlerine `SIGSTOP` gönderir; süreçler kapak açılınca `SIGCONT`
  gönderilene kadar duraklar. Liste WhatsApp, Word, Excel ve ParaView ile başlar; bu fork'ta "diğer tüm
  uygulamaları dondur" de varsayılan olarak açıktır.
  "Diğer tüm uygulamaları dondur" varsayılan olarak kapalıdır. Açıkken bile
  toplantı, kayıt ve dikte uygulamalarını atlar: Zoom, Teams, Webex, FaceTime,
  Wispr Flow, Granola, Otter, OBS ve Loom.
- **Ses kapatılır.** Kapağı açmak, Uykusuz'un sesini kapattığı her çıkışın
  sesini, siz başka bir çıkışa geçmiş olsanız bile yeniden açar.
- **Düşük Güç Modu açılır.** Bir pil ya da ısı kuralı hâlâ gerektirmiyorsa
  kapak açılınca kapanır.
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
içerebilir; bu yüzden bir günlüğü paylaşmadan önce gözden geçirin.
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

## Geliştirme

```bash
swift build
swift test
```

Testler sahte araçlar ve geçici klasörler kullanır; bu yüzden güç ayarlarınızı
hiçbir zaman değiştirmez. Tasarım notları [docs/spec.md](docs/spec.md),
gerçek Mac doğrulamaları [docs/release-validation.md](docs/release-validation.md)
dosyasındadır (ikisi de İngilizce).

## Lisans

[MIT](LICENSE). Telif hakkı © 2026 Krish Garg. Bu Türkçe çatal da aynı lisans
altındadır.
