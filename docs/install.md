# Kurulum, yükseltme ve kaldırma

> **Bu çatal hakkında:** Bu Türkçe çatal
> ([Mustafa-Ghn/insomnia-tr](https://github.com/Mustafa-Ghn/insomnia-tr))
> yalnızca kaynak koddan derlenerek kurulur ve GitHub sürümü (release) yoktur.
> Aşağıdaki [Kanallar](#kanallar), [v0.1.0 farklıdır](#v010-farklıdır) ve
> [Bir sürümü kendiniz kurma](#bir-sürümü-kendiniz-kurma) bölümleri, özgün
> projenin ([krishhgg/Insomnia](https://github.com/krishhgg/Insomnia))
> yayımladığı İngilizce derlemeleri anlatır. Bu çatalı kurmak için
> [Kaynaktan derleme](#kaynaktan-derleme) bölümünü izleyin.

[README](../README.md#kurulum) kısa sürümü içerir. Bu sayfa her adımı ve her
adımın neyi denetlediğini anlatır. Bir kodlama ajanı, bu sayfadaki adımları
kullanan [skills/install-uykusuz](../skills/install-uykusuz/SKILL.md)
talimatlarını izleyebilir.

**macOS 26 ya da üstü ve Apple Silicon bir Mac** gerekir.

## Kanallar

Özgün Uykusuz,
[sürümler sayfasında](https://github.com/krishhgg/Insomnia/releases) iki
kanalda yayımlanır:

- Kararlı: GitHub'ın Latest olarak işaretlediği, `v<version>` etiketli sürüm.
  Henüz kararlı bir sürümde olmayan değişiklikleri denemek istemiyorsanız bunu
  kullanın.
- Gecelik: `main` dalında yeni commit olduğunda günde bir kez otomatik olarak
  derlenen, `nightly-<date>-<commit>` etiketli ön sürümler (prerelease). En yeni
  koddur; deneyseldir ve bozuk olabilir. Gecelik bir sürüm hiçbir zaman Latest
  olarak işaretlenmez.

## v0.1.0 farklıdır

Her sürümün notları o sürüme özgü komutları verir. Bir sürüm aşağıdaki
adımlardan ayrılır: ilk kararlı sürüm olan `v0.1.0`, Release iş akışıyla değil,
bakımcının kurulu uygulamasından elle paketlenmiştir. Kanıt kaydı (attestation)
yoktur ve zip dosyası `./scripts/install.sh --app ./Uykusuz.app` ile kurulur.
Seçtiğiniz sürüm `v0.1.0` ise (zip dosyası `Insomnia-0.1.0-macos-arm64.zip`),
2. ve 3. adımlar yerine sürüm notlarındaki kurulum adımlarını izleyin.

Bu sayfanın geri kalanı `v0.1.0` sürümünü değil, Release iş akışıyla derlenen
sürümleri ve güncel kaynak koddan yapılan derlemeleri anlatır. `v0.1.0` zip
dosyasındaki `README.md`, o sürümün neleri kurduğunu, kurtarmasının nasıl
çalıştığını ve sınırlarını anlatır. Özellikle kurulum betiğinin sürüm denetimi,
uygulamanın içine mühürlenen kurtarma betiği ve kurtarma ajanının sabitlediği
kod gereksinimi (aşağıda anlatılanlar) `v0.1.0` sürümünde yoktur.

## Bir sürümü kendiniz kurma

`gh`, yani [GitHub CLI](https://cli.github.com) gerekir.

1. Seçtiğiniz sürümün zip dosyasını ve `SHA256SUMS` dosyasını boş bir klasöre,
   sürümler sayfasından ya da `gh` ile indirin. Latest olarak işaretlenen
   kararlı sürüm için:

   ```bash
   gh release download --repo krishhgg/Insomnia --pattern '*.zip' --pattern SHA256SUMS
   ```

   En yeni gecelik sürüm için bu bloğun tamamını yapıştırın. Blok, sürüm
   listesinin her sayfasını okur ve en son yayımlanan gecelik sürümü seçer.
   Listeyi okuyamadığında, henüz hiçbir gecelik sürüm yayımlanmamışsa ya da
   seçtiği etiket `nightly-<YYYYMMDD>-<12 karakterlik commit>` biçiminde değilse
   hiçbir şey indirmez ve hata döndürür. Hiçbir zaman kararlı sürüme geri
   dönmez.

   ```bash
   uykusuz_nightly() {
     local list tag
     list="$(gh api --paginate 'repos/krishhgg/Insomnia/releases?per_page=100' \
       --jq '.[] | select(.prerelease and (.draft | not) and (.tag_name | startswith("nightly-")))
         | "\(.published_at) \(.tag_name)"')" ||
       { echo "Could not read the release list. Nothing was downloaded." >&2; return 1; }
     tag="$(printf '%s\n' "$list" | sort | tail -n 1)"
     tag="${tag#* }"
     if [ -z "$tag" ]; then
       echo "No nightly has been published yet. Nothing was downloaded." >&2
       echo "Wait for the next daily build, or build from source." >&2
       return 1
     fi
     if ! printf '%s\n' "$tag" | grep -Eqx 'nightly-[0-9]{8}-[0-9a-f]{12}'; then
       printf 'Unexpected nightly tag: %s. Nothing was downloaded.\n' "$tag" >&2
       return 1
     fi
     gh release download "$tag" --repo krishhgg/Insomnia --pattern '*.zip' --pattern SHA256SUMS
   }
   uykusuz_nightly
   ```

   Sürümler sayfasında henüz bir sürüm yoksa kaynaktan derleyin (aşağıda).
2. İndirilen dosyayı doğrulayın. `<zip>`, zip dosyasının adıdır. `<ref>`,
   kararlı bir sürüm için `refs/tags/v<version>`, gecelik bir sürüm için
   `refs/heads/main` olur. `<commit>`, sürümün derlendiği 40 karakterlik tam
   commit kimliğidir: sürüm notları onu "Built from" ifadesinden sonra verir ve
   bu komutu doldurulmuş olarak içerir. Gecelik bir sürümün etiketi bu kimliğin
   ilk 12 karakteriyle biter.

   ```bash
   shasum -a 256 -c SHA256SUMS
   gh attestation verify <zip> -R krishhgg/Insomnia \
     --signer-workflow krishhgg/Insomnia/.github/workflows/release.yml \
     --source-ref <ref> --source-digest <commit>
   ```

   İlk komut zip dosyasını onunla birlikte indirilen `SHA256SUMS` dosyasına
   göre denetler. İkincisi, özgün deponun Release iş akışının tam olarak bu zip
   dosyasını o commit'ten ve o ref için derlediğini denetler; böylece gecelik
   bir sürüm kararlı bir sürümün yerine geçemez. Her gecelik sürüm
   `refs/heads/main` için derlendiğinden, başka bir gecelik sürümün zip
   dosyasının bu denetimden geçmesini yalnızca `--source-digest` engeller: onu
   atlamayın ve commit kimliğini etiketteki 12 karaktere kısaltmayın.

3. Zip dosyasını açın ve içinden çıkan kurulum betiğini çalıştırın:

   ```bash
   ditto -x -k <zip> .
   cd <.zip uzantısı olmadan zip dosyasının adı>
   ./install.sh --allow-unverified-origin --app ./Uykusuz.app
   open "$HOME/Applications/Uykusuz.app"
   ```

   Sürümler ad-hoc imzalıdır ve Apple'ın onay sürecinden (notarization)
   geçmez. Kurulum betiği paketin bozulmadığını denetleyebilir ama onu kimin
   yaptığını denetleyemez; bu yüzden 2. adımdaki iki komutu çalıştırdığınızı
   belirten `--allow-unverified-origin` olmadan kurmayı reddeder. macOS,
   indirilen bir kopyanın ilk açılışını siz Sistem Ayarları > Gizlilik ve
   Güvenlik bölümünde izin verene dek engeller.

Kurulum betiği, sizden herhangi bir şey istemeden önce paketin imzasını,
tanımlayıcısını ve sürümünü denetler (`v0.1.0` kurulum betiği imzayı ve
tanımlayıcıyı denetler, sürümü denetlemez). Ardından uygulamayı ve arka planda
çalışan bir kurtarma ajanını kurar ve kapsamı dar tutulmuş bir sudoers kuralını
kurmak için yönetici erişimi ister. Bu kural, yalnızca Uykusuz'a değil,
**kullanıcı hesabınıza** dört güç ayarı komutunu parolasız çalıştırma izni
verir. Kurmadan önce bu izni gözden geçirin.

Sürüm zip dosyaları yalnızca arm64 için derlenir ve içlerindeki
`install.sh --app` Intel bir Mac'te durur. Intel'de tek seçenek kaynaktan
derlemedir (aşağıda) ve bu derleme orada denenmemiştir.

## Kaynaktan derleme

**Swift 6.2 ya da üstünü içeren Xcode** gerekir. Bu çatal şöyle kurulur:

```bash
git clone https://github.com/Mustafa-Ghn/insomnia-tr.git && cd insomnia-tr && ./scripts/install.sh
open "$HOME/Applications/Uykusuz.app"
```

Özgün projenin İngilizce kaynak kodunu derlemek için `main` yerine en son
kararlı etiketi ya da en yeni kod için bir gecelik etiketi klonlayın.
Sürümler sayfasında henüz bir sürüm yoksa `main` dalını derlemek için
`--branch v<version>` kısmını çıkarın:

```bash
git clone --branch v<version> --depth 1 https://github.com/krishhgg/Insomnia.git
cd Uykusuz
./scripts/install.sh
open "$HOME/Applications/Uykusuz.app"
```

`scripts/install.sh`, Release iş akışının derlediği paketin aynısını
(`scripts/build-app.sh`) ad-hoc imzalı olarak derler ve aynı şekilde kurar.
Yalnızca bir çalışma kopyasının `scripts` klasöründen, bir üst klasörde
`Package.swift` varken çalıştığında derleme yapar ve yanındaki `build-app.sh`
betiğini çalıştırır. Bir sürüm zip dosyasındaki `install.sh` ise, zip
açıldıktan sonra klasörüne bir `build-app.sh` eklenmiş olsa bile durur ve
`--app` ister. `v0.1.0` çalışma kopyasında o sürümün kurulum betiği vardır;
o sürümün README dosyası onu anlatır. Sürüm hattını
[docs/releasing.md](releasing.md) (İngilizce) anlatır.

Derleme, `swift --version` 6.2 ya da üstünü bildirdiği hâlde `Package.swift`
içinde "reference to member 'v26' cannot be resolved" ya da "has no member
'swiftLanguageMode'" hatasıyla durursa, araç zinciri PackageDescription
arayüzünü daha eski bir Swift sürümünden okumuştur. Command Line Tools ya da
Xcode güncellemesi, önceki sürümün `.private.swiftinterface` dosyalarını
yenilerinin yanında bırakabilir ve Swift önce bunları okur. Başarısız bir
derlemeden sonra `build-app.sh` bulduğu bu dosyaları listeler ve tam olarak
bu dosyaları silen `sudo rm` komutunu yazdırır; Command Line Tools ya da
Xcode'u yeniden kurmak da onları kaldırır.

## Neler kurulur

Bu bölüm, Release iş akışıyla derlenen sürümleri ve güncel kaynak koddan
yapılan derlemeleri (bu çatal dahil) anlatır. `v0.1.0` daha eski bir düzen
kurar. Onun uygulamasının içinde `backstop.sh` yoktur: kurulum betiği
`backstop.sh` dosyasını `~/Library/Application Support/Uykusuz/` konumuna
kopyalar ve kurtarma ajanı bu kopyayı hiçbir kod imzasını denetlemeden
`/bin/bash` ile çalıştırır. Aşağıda anlatılan mühürlü betik, sabitlenen kod
gereksinimi ve düzenlenmiş ya da yeniden imzalanmış bir paketin reddedilmesi
ona uygulanmaz; yükseltme yordamı da uygulanmaz. sudoers kuralı aynı dört
komuta izin verir. Zip dosyasındaki `README.md`, neleri kurduğunu ve
sınırlarını anlatır.

| Konum | Amaç |
| --- | --- |
| `~/Applications/Uykusuz.app` | Menü çubuğu uygulaması; `backstop.sh` içine, `Contents/Resources` konumuna mühürlenmiştir |
| `~/Library/Application Support/Uykusuz/` | Yapılandırma ile oturum ve kurtarma kayıt defterleri |
| `~/Library/LaunchAgents/com.mustafaghn.uykusuz.backstop.plist` | Kullanıcıya özel kurtarma ajanı: uygulamanın kendi programını `--backstop-agent` ile başlatır; o da upstream'in ajan komutunu çalıştırır, uygulamanın kod imzasını doğrular, ardından mühürlü `backstop.sh` betiğini çalıştırır |
| `~/Library/Logs/Uykusuz/` | `uykusuz.log` ve `handoffs.log`; her biri 1 MiB ile sınırlıdır ve bir eski kopyası `.1` olarak tutulur (dosyayı bir sembolik bağlantıyla değiştirmediyseniz) |
| `/etc/sudoers.d/uykusuz` | Aşağıdaki dört komut için izin |

```text
/usr/bin/pmset -a disablesleep 1
/usr/bin/pmset -a disablesleep 0
/usr/bin/pmset -b lowpowermode 1
/usr/bin/pmset -b lowpowermode 0
```

Bu izni, sizin hesabınızla çalışan diğer süreçler de kullanabilir. Uykusuz
korumalı alanda (sandbox) çalışmaz. Uygulama, betikler ve kayıt defterleri
yereldir; hotspot parolaları yapılandırma dosyasında değil, giriş anahtar
zincirinde tutulur.

Kurtarma ajanı girişte ve her 60 saniyede bir çalışır. Komut satırı, kurulu
paketin kod gereksinimini (ad-hoc bir derleme için o derlemenin cdhash
değerini) sabitler ve paketin içine mühürlenmiş `backstop.sh` betiğini
çalıştırmadan önce bu gereksinime karşı `codesign --verify --strict`
çalıştırır. Düzenlenmiş bir paket ya da betik bu denetimden geçemez: ajan
`uykusuz.log` dosyasına tek bir satır yazar ve siz yeniden kurana kadar hiçbir
şey çalıştırmaz. Başka bir hesap paketi düzenleyemesin diye kurulum betiği,
kurduğu paketten grup ve diğer kullanıcıların yazma iznini ve tüm ACL'leri
kaldırır. İmza bunların hiçbirini kapsamadığından paket yine doğrulanır;
indirilmiş bir dosyanın karantina bayrağı gibi genişletilmiş öznitelikler
korunur. Yazılabilir bir destek klasöründe hiçbir yürütülebilir dosya
tutulmaz. `~/Library/LaunchAgents` içindeki plist dosyası ise her LaunchAgent
gibi, sizin hesabınızla çalışan herhangi bir programın düzenleyebileceği
kullanıcıya özel bir dosyadır; eşleşmediğinde uygulama bir sonraki oturum
başlangıcında onu yeniden yazar. Bu bir onarımdır, kurcalama denetimi değildir.

Uygulamanın sabitlediği şey, kendisinin çalıştırdığı kodun gereksinimidir; bu
gereksinim, diskteki paketin hâlâ o kod olduğu ve ajanın denetiminden hâlâ
geçtiği doğrulandıktan sonra Security çerçevesi üzerinden okunur. Mühürlü
betiği düzenlenmiş ya da çalışan uygulamanın altında yeniden imzalanmış bir
paket sabitlenmez, reddedilir: siz yeniden kurana kadar uygulama oturum
başlatmaz ya da oturumun bitişini tamamlanmamış olarak bildirir ve nedenini
söyler. Ad-hoc imzalarla bu, kazara yapılan düzenlemelere ve uygulamanın
kurcalanmış bir paketi ajana aktarmasına karşı korur; sizin hesabınızla çalışan
bir sürece karşı korumaz: böyle bir süreç plist dosyasını düzenleyebilir, kendi
ajanını yükleyebilir, uygulamayı kapatıp yerine başkasını başlatabilir ve dört
`pmset` komutunu kendisi çalıştırabilir.

## Yükseltmeler

Ayarlar > Uygulama kurulu sürümü gösterir. Bu çatalda güncelleme denetimi
yoktur; yükseltme, yukarıdaki adımların yeniden çalıştırılmasıdır: çalışma
kopyasında `git pull` ve ardından `./scripts/install.sh`.

Bir yükseltme çalışan uygulamadan kapanmasını ister ve uygulama reddederse
durur. Yeni paket, uygulamanın yanındaki bir hazırlık klasöründe oluşturulur ve
kurtarma ajanını değiştiren adımla aynı adımda yerine taşınır. Bu adım ancak
`launchctl print` önceki ajanın devreden çıkarıldığını doğruladıktan sonra
başlar; aksi hâlde hiçbir şey değiştirilmez. Yeni ajan yüklenemezse ya da plist
dosyası kaydedilemezse kurulum betiği ajanı devreden çıkarır, `launchctl print`
bunu doğrulayana kadar bekler ve önceki paketi geri koyar; böylece yüklü ajan
her zaman kurulu uygulamayla eşleşir. O adım sırasında taşınamayan bir paket de
aynı şekilde ele alınır: önceki paket geri konur ve ajanı yeniden yüklenir.
Önceki paketin kendisi geri taşınamazsa hiçbir şey silinmez: paket
`~/Applications/.Uykusuz.app.previous` konumunda kalır, kurulum betiği onu
geri koyan ve ajanını yükleyen iki komutu yazdırır ve o zamana kadar ajan
hiçbir uygulama bulamaz; bu yüzden macOS oturumunuzu kapatmadan önce o
komutları çalıştırın ya da kurulum betiğini yeniden çalıştırın. Devreden
çıkarma doğrulanmazsa yeni paket, onu sabitleyen ajanla birlikte kalır ve
kurulum betiği yeniden çalıştırılmasını ister. Bundan sonra ya da o adımın
ortasında öldürülen bir kurulumdan sonra, bir sonraki çalıştırma ajanın
diskteki plist dosyasının sabitlediği paketi tutar. Bunu ancak kendi kurtarma
adımı başarılı olduktan sonra yapar: kurtarma çözülmemişken, önceki
çalıştırmanın yüklü bıraktığı bir ajan kurtarmayı yeniden deneyen ajan
olabilir; bu yüzden kurulum betiği o ajanı devreden çıkarmadan ve iki paketten
hiçbirini taşımadan durur. Kurtarma başarılı olunca o ajanı devreden çıkarır,
paketi geri taşır ve diskteki plist dosyasını yeniden yükler; `launchctl
print` devreden çıkarmayı ya da yeniden yüklemeyi doğrulamazsa durur.
Çözülmemiş bir kurtarma, ikisinin de değiştirilmesini engeller; yeniden
denemeden önce bildirilen talimatları izleyin. Kurulum betiği, kurtarma
kilidini aldıktan sonra sudoers kuralını yeniden denetler ve kural gitmişse
durur (örneğin kilidi ondan önce alan bir `uninstall.sh` çalıştırmasından
sonra). Kilidi tutarken `sudo`, `pgrep`, `launchctl` ya da `codesign` için
yaptığı her çağrının 30 saniyelik bir sınırı vardır; bu sınırı, kurulum betiği
bu arada öldürülse bile gözetmen bir süreç uygular. Çağrı, bitene ya da
durdurulana kadar kilidi tutar; böylece kilit bırakıldığında başlattığı hiçbir
`launchctl bootout` hâlâ çalışıyor olmaz. Zamanında yanıt vermeyen bir çağrıya
SIGTERM, bir iki saniye sonra da SIGKILL gönderilir ve kurulum durur; böylece
kilit bırakılır ve uygulama ile ajanın backstop betiği kilidi yeniden alıp bir
oturumu geri alabilir. `sudo` yalnızca SIGTERM alır: bunu yok sayan bir `sudo`
bitene kadar kilidi tutar ve kurulum betiği onun pid değerini yazdırır.

## Kaldırma

Çalışma kopyanızdan:

```bash
./scripts/uninstall.sh
# Uykusuz'a ait yapılandırma ve günlükleri de kaldırmak için:
./scripts/uninstall.sh --purge
```

Açılmış bir sürüm zip dosyasından kurduysanız, zip klasöründe
(`Uykusuz-<version>-macos` ya da gecelik sürümün adı) `./uninstall.sh` (ya da
`./uninstall.sh --purge`) çalıştırın. Bir çalışma kopyasının kaldırma betiği
(`scripts` içinde, bir üst klasörde `Package.swift` varken) yanındaki
`backstop.sh` betiğini çalıştırır. Başka her yerde, örneğin zip klasöründe,
kaldırma betiği yalnızca kurulu uygulamanın içinde mühürlü kopyayı ve onu da
ancak uygulama `codesign --verify --strict` denetiminden geçtikten sonra
çalıştırır; böyle bir kopya yoksa hiçbir şey kaldırmadan durur. Zip dosyasında
`backstop.sh` yoktur; bu yüzden kaldırma betiğinin yanına eklenmiş bir kopya
çalıştırılmaz. İki betik de kendi klasörünün üstündeki klasöre bakmaz.

`v0.1.0` zip dosyası farklıdır: sürüm notlarında yazdığı gibi, açılmış
`Insomnia-0.1.0-macos-arm64` klasöründe `./scripts/uninstall.sh` çalıştırın. O
eski kaldırma betiği aynı klasördeki `scripts/backstop.sh` betiğini çalıştırır.

Kaldırma betiği uygulamayı, ajanı ve sudoers kuralını kaldırmadan önce temizlik
ister. Kurtarma tamamlanmamışsa ya da uygulama kapanmayı reddederse durur;
bildirilen sorunu çözüp yeniden deneyin. Uygulamayla birlikte, yarıda kalmış
bir kurulumun onun yanında bıraktıklarını da kaldırır:
`~/Applications/.Uykusuz.app.previous` ve artık çalışmayan kurulumların
`.Uykusuz.app.staging.*` klasörleri. `~/Applications` içindeki başka hiçbir
şeye dokunulmaz. `--purge`, rastgele klasör içeriğini değil, Uykusuz'a ait
dosyaları kaldırır. Eşzamanlı kurtarma işlemlerinin eşgüdümünü korumak için
küçük bir ortak kilit dosyası bırakılır.
