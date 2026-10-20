# Katkıda bulunma

Uykusuz'a ilginiz için teşekkürler. Hata bildirimleri, öneriler ve pull
request'ler memnuniyetle karşılanır. Bu sayfa, bir değişikliğin hangi
denetimlerden geçmesi gerektiğini anlatır.

## Başlamadan önce

- Bir hata bildirirken macOS sürümünü (`sw_vers`), Mac modelini ve
  `~/Library/Logs/Uykusuz/uykusuz.log` dosyasındaki ilgili satırları ekleyin.
  Günlükler Wi-Fi adları, süreç ayrıntıları ve tmux hedefleri içerebilir;
  paylaşmadan önce gözden geçirin.
- Yeni bir özelliğe ya da bir varsayılanı değiştirmeye başlamadan önce bir
  issue açın; değişikliğin Uykusuz'a uyup uymadığını önce konuşalım.
- Güvenlik açıklarını issue'da değil, [SECURITY.md](SECURITY.md) dosyasındaki
  yoldan bildirin.

## Geliştirme ortamı

Uykusuz yerel bir Swift macOS uygulamasıdır. macOS 26 ve paketin Swift 6.2
araç sürümünü destekleyen bir Xcode gerekir.

```bash
swift build
swift test
```

Uygulamayı kendi Mac'inizde denemek için `./scripts/install.sh` onu çalışma
kopyasından derleyip kurar ([docs/install.md](docs/install.md)).

## Bir pull request'in geçmesi gerekenler

- **Testler.** Davranışı değiştiren her değişiklik bir gerileme testi
  (regression test) içerir ve `swift test` geçer.
- **Uyarısız derleme.** Release derlemesi uyarıları hata sayar; bir derleyici
  uyarısı derlemeyi bozar:
  `swift build -c release -Xswiftc -warnings-as-errors`.
- **Betikler.** Kurtarma ajanı, `install.sh` ve `uninstall.sh` macOS'in sistem
  bash'i (3.2) ile çalışır. `scripts/*.sh` dosyaları `/bin/bash -n` ile
  ayrıştırılır ve bash 4 yapıları (`mapfile`, `declare -A`, `${x,,}`) için
  taranır; Linux'taki ShellCheck bunları yakalamaz. ShellCheck `scripts/` ve
  `.github/scripts/` üzerinde, actionlint ve zizmor `.github/workflows`
  üzerinde bulgu vermemelidir.
- **Gizlenen ShellCheck bulguları.** ShellCheck işi, `scripts/` içinde bir
  yönergenin (`# shellcheck ...`) gizlediği her bulguyu listeler ve liste
  `.github/shellcheck-hidden.txt` ile eşleşmezse başarısız olur. Bir yönerge
  bir sonraki komutu kapsar; bu yüzden var olan bir yönergenin ardından
  eklenen bir `{` ve sondaki bir `}`, yönergeye dokunmadan betiğin geri
  kalanını onun altına alabilir. Değişikliğiniz bilerek yeni bir şeyi
  gizliyorsa CI'ın yazdırdığı listeyi o dosyaya kopyalayın. Bir
  `# shellcheck` yorumun dışında (bir dizgede, bir here-document'ta ya da ters
  tırnaklar içinde) durursa da denetim başarısız olur.

Aynı denetimleri [.github/workflows/ci.yml](.github/workflows/ci.yml) iş
akışı tanımlar; GitHub Actions açıkken her pull request'te ve `main`'e her
push'ta çalışır.

## Testler

- Otomatik testlerde enjekte edilmiş sistem bağımlılıkları ve geçici kayıt
  defterleri kullanın. Test paketi UykusuzTestHome hedefini
  (`Tests/UykusuzTestHome`) bağlar; onun kurucusu paket yüklenirken, XCTest
  herhangi bir şey çalıştırmadan ve hangi `--filter` kullanılırsa kullanılsın,
  `UYKUSUZ_HOME` değişkenini geçici bir klasöre yöneltir. Böylece hiçbir test
  gerçek `~/Library/Logs` ya da `~/Library/Application Support` klasörüne
  yazmaz. TestIsolationTests, `UYKUSUZ_HOME` ayarlı değilse ya da uygulamanın
  çözdüğü bir yol onun dışına ya da gerçek `~/Library` içine düşerse başarısız
  olur.
- Test paketinin bir parçası olarak katkıcının kendi Mac'inde kurulum,
  kaldırma, güç ayarı değişikliği, süreç dondurma ya da hotspot geçişi
  çalıştırmayın. Test verilerine ya da günlüklere parola veya kişisel ağ adı
  koymayın.
- tmux tümleşik testleri, uygulamanın yokladığı yollardan birinde tmux
  gerektirir. Yerel bir çalıştırmada atlanan test sayısına bakın; tmux'un
  olmaması tümleşik test kapsamıyla karıştırılmasın. Testler katkıcının açık
  bölmelerini değil, özel tmux sunucularını kullanır.
- Yaşam döngüsünü değiştiren işlerde eşzamansız sınırlarda askıya alınmayı,
  süren iş sırasında kapanmayı, başarısız geri yüklemeyi, kalıcılık
  hatalarını ve kesintiden sonra kurtarmayı test edin. Yalnızca bir sahte
  yöntemin çağrıldığını değil, gözlemlenebilir ayarları ve kayıt defterinin
  tutarlılığını doğrulayın.

## Gerçek Mac'te doğrulama

Geçen otomatik denetimler bir güvenlik sertifikası değildir. Uyku, kapak, pil,
ekran, ses, dondurma, kurtarma, kurulum ya da hotspot davranışını değiştiren
bir pull request, en son commit'i için kendi Mac'inizden bir rapor gerektirir.
Raporu son push'unuzdan sonra yorum olarak ekleyin; yeniden push ederseniz
yenisini ekleyin. Yalnızca `docs/`, `Tests/`, `.github/`, README.md,
CONTRIBUTING.md, SECURITY.md ve .gitignore dosyalarını değiştiren bir
pull request rapor gerektirmez.

- **Derleme.** Başka hiçbir pull request uygulanmamış, en son commit'in temiz
  bir kopyası, `./scripts/install.sh` ile kurulmuş. `git rev-parse HEAD` ve
  hiçbir şey yazdırmaması gereken `git status --short` çıktısını ekleyin.
- **Mac.** `sw_vers`, `sysctl -n hw.model` ve
  `sysctl -n machdep.cpu.brand_string` çıktılarını ekleyin.
- **Denetimler.** [docs/releasing.md](docs/releasing.md) içindeki
  "Real-Mac checks before a release" listesinden değişikliğinizin
  etkileyebileceği her madde (değişikliğin eklediği maddeler dahil). Her biri
  için çalıştırdığınız adımları saatleriyle, geçti ya da kaldı sonucunu ve
  bunu gösteren ham çıktıyı ekleyin:
  - o çalıştırmanın `~/Library/Logs/Uykusuz/uykusuz.log` satırları;
  - denetimden önce başlatıp çalışır bıraktığınız bir örnekleyicinin pmset
    örnekleri:
    ```sh
    while :; do date '+%T'; pmset -g | grep SleepDisabled; pmset -g custom | sed -n '/Battery Power/,/AC Power/p' | grep -E 'powermode|lowpowermode'; sleep 5; done | tee -a ~/uykusuz-samples.txt
    ```
  - o zaman aralığı için Mac'in uyuyup uyumadığını gösteren
    `pmset -g log | grep -E ' (Sleep|Wake|DarkWake) '` çıktısı;
  - maddenin istediği diğer okumalar.
- **Çalıştırılmayanlar.** Çalıştıramadığınız her şeyi ve nedenini yazın.

Uzun günlükleri bir gist'e koyup bağlantısını verin. Denetimleri Mac'in
başındayken, sabit ve iyi havalanan bir yüzeyde, asla bir çantada değil ve
kaydedilmemiş iş açık değilken çalıştırın. Gerçek Mac'te denetim gerektiren
yeni bir davranış, docs/releasing.md içindeki listeye bir madde ekler;
sonuçlar [docs/release-validation.md](docs/release-validation.md) dosyasına
kaydedilir.

## Simge ve çizimler

Uygulama simgesi, menü çubuğundaki açık gözün koyu bir karo üzerindeki
hâlidir. [AppIconArtwork](Sources/Uykusuz/UI/AppIconArtwork.swift) onu menü
çubuğundaki kapalı gözle aynı
[vektör geometrisinden](Sources/Uykusuz/UI/EyeMarkGeometry.swift) çizer; göz
oturum sürerken açılır. Çizimi değiştirdikten sonra
`./scripts/generate-app-icon.sh` çalıştırın: paketlenen PNG ve ICNS
dosyalarını ve README'deki `docs/assets/eye-open.svg` dosyasını Xcode'un
swiftc ve iconutil araçlarıyla çevrimdışı yeniden üretir.

README'deki diğer çizimler (`docs/assets/*.svg`) elle yazılmış SVG'lerdir ve
açık ile koyu temayı `prefers-color-scheme` ile destekler. Bir arayüz metni ya
da bir varsayılan değiştiğinde ilgili çizimi de güncelleyin.

## Dil

Arayüz, bildirimler, sesli uyarılar, kurulum mesajları ve kullanıcı
belgeleri Türkçedir. Kod, kod içi yorumlar ve tasarım belgeleri
([docs/spec.md](docs/spec.md), [docs/releasing.md](docs/releasing.md),
[docs/release-validation.md](docs/release-validation.md)) İngilizcedir.
Commit mesajlarını Türkçe, `Uykusuz: <ne değişti>` biçiminde yazın.
