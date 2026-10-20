# Kurulum, yükseltme ve kaldırma

[README](../README.md#kurulum) kısa sürümü içerir. Bu sayfa her adımı ve her
adımın neyi denetlediğini anlatır. Bir kodlama ajanı, bu sayfadaki adımları
kullanan [skills/install-uykusuz](../skills/install-uykusuz/SKILL.md)
talimatlarını izleyebilir.

**macOS 26 ya da üstü ve Apple Silicon bir Mac** gerekir.

## Kaynaktan derleme

**Swift 6.2 ya da üstünü içeren Xcode** gerekir. Uykusuz hazır derlenmiş bir
paket olarak yayımlanmaz; kaynak koddan derlenerek kurulur:

```bash
git clone https://github.com/Mustafa-Ghn/uykusuz.git && cd uykusuz && ./scripts/install.sh
open "$HOME/Applications/Uykusuz.app"
```

`scripts/install.sh`, uygulama paketini `scripts/build-app.sh` ile ad-hoc
imzalı olarak derler ve kurar. Yalnızca bir çalışma kopyasının `scripts`
klasöründen, bir üst klasörde `Package.swift` varken çalıştığında derleme yapar
ve yanındaki `build-app.sh` betiğini çalıştırır. Depodaki Release iş akışının
ürettiği bir zip paketindeki `install.sh` ise, zip açıldıktan sonra klasörüne
bir `build-app.sh` eklenmiş olsa bile derleme yapmaz ve `--app` ile hazır
paketi ister. Sürüm hattını [docs/releasing.md](releasing.md) (İngilizce)
anlatır.

Kurulum betiği, sizden herhangi bir şey istemeden önce paketin imzasını,
tanımlayıcısını ve sürümünü denetler. Ardından uygulamayı ve arka planda
çalışan bir kurtarma ajanını kurar ve kapsamı dar tutulmuş bir sudoers kuralını
kurmak için yönetici erişimi ister. Bu kural, yalnızca Uykusuz'a değil,
**kullanıcı hesabınıza** dört güç ayarı komutunu parolasız çalıştırma izni
verir. Kurmadan önce bu izni gözden geçirin.

Uygulama yalnızca Apple Silicon için denenmiştir; Intel bir Mac'te derleme
denenmemiştir.

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

| Konum | Amaç |
| --- | --- |
| `~/Applications/Uykusuz.app` | Menü çubuğu uygulaması; `backstop.sh` içine, `Contents/Resources` konumuna mühürlenmiştir |
| `~/Library/Application Support/Uykusuz/` | Yapılandırma ile oturum ve kurtarma kayıt defterleri |
| `~/Library/LaunchAgents/com.mustafaghn.uykusuz.backstop.plist` | Kullanıcıya özel kurtarma ajanı: uygulamanın kendi programını `--backstop-agent` ile başlatır; program, uygulamanın kod imzasını doğrulayan ajan komutunu çalıştırır, ardından mühürlü `backstop.sh` betiği çalışır |
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

Ayarlar > Uygulama kurulu sürümü gösterir. Uykusuz güncelleme denetlemez;
yükseltme, yukarıdaki adımların yeniden çalıştırılmasıdır: çalışma kopyasında `git pull` ve ardından
`./scripts/install.sh`.

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

Release iş akışının ürettiği açılmış bir zip paketinden kurduysanız, zip
klasöründe (`Uykusuz-<version>-macos`) `./uninstall.sh` (ya da
`./uninstall.sh --purge`) çalıştırın. Bir çalışma kopyasının kaldırma betiği
(`scripts` içinde, bir üst klasörde `Package.swift` varken) yanındaki
`backstop.sh` betiğini çalıştırır. Başka her yerde, örneğin zip klasöründe,
kaldırma betiği yalnızca kurulu uygulamanın içinde mühürlü kopyayı ve onu da
ancak uygulama `codesign --verify --strict` denetiminden geçtikten sonra
çalıştırır; böyle bir kopya yoksa hiçbir şey kaldırmadan durur. Zip dosyasında
`backstop.sh` yoktur; bu yüzden kaldırma betiğinin yanına eklenmiş bir kopya
çalıştırılmaz. İki betik de kendi klasörünün üstündeki klasöre bakmaz.

Kaldırma betiği uygulamayı, ajanı ve sudoers kuralını kaldırmadan önce temizlik
ister. Kurtarma tamamlanmamışsa ya da uygulama kapanmayı reddederse durur;
bildirilen sorunu çözüp yeniden deneyin. Uygulamayla birlikte, yarıda kalmış
bir kurulumun onun yanında bıraktıklarını da kaldırır:
`~/Applications/.Uykusuz.app.previous` ve artık çalışmayan kurulumların
`.Uykusuz.app.staging.*` klasörleri. `~/Applications` içindeki başka hiçbir
şeye dokunulmaz. `--purge`, rastgele klasör içeriğini değil, Uykusuz'a ait
dosyaları kaldırır. Eşzamanlı kurtarma işlemlerinin eşgüdümünü korumak için
küçük bir ortak kilit dosyası bırakılır.
