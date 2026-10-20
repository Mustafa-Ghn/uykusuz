# Kurtarma nasıl çalışır

[README](../README.md#kurtarma-nasıl-çalışır) kısa sürümü içerir. Bu sayfa her
durumu anlatır.

Insomnia bekleyen değişiklikleri bir kurtarma kayıt defterine yazar. Oturum
bitince uygulama bunları geri almaya çalışır. Bağımsız bir `launchd` ajanı her
dakika denetler ve uygulama beklenmedik biçimde kapandıktan sonra, kaydedilmiş
bitiş zamanı geçtiğinde kurtarmayı deneyebilir. Geçerli ve süresi dolmamış bir
oturuma dokunmaz.

Uygulama ve backstop, kayıt defterini birbirinin üzerine geri yükleyip yeniden
yazmasınlar diye aynı kilidi kullanır. Başarısız bir geri yükleme ilgili
girdileri korur; okunamayan kayıt defterleri temiz sayılmaz, saklanır.
Ayrıştırılamayan bir oturum dosyası süresi dolmuş sayılır ve hiçbir şey
silinmeden ya da üzerine yazılmadan yanında `session.json.unreadable-<zaman>`
olarak yeniden adlandırılır: uygulama bunu açılışta, kayıt defterindeki her
şeyi geri yüklemeden önce yapar ve dosyanın nereye gittiğini söyler; ajan ise
bunu kayıt defteri temizlendiğinde yapar. Hiç okunamayan bir oturum dosyası
(izinler yüzünden ya da normal bir dosya olmadığı için; böyle bir dosya hiçbir
zaman açılmaz) da bitiş zamanı bilinmediğinden süresi dolmuş sayılır: kayıt
defteri geri yüklenir ve dosya açılmadan aynı şekilde yeniden adlandırılır;
böylece sonraki bir açılış, bitmiş sayılan bir oturumu sürdüremez. Uygulama
dosyanın nereye gittiğini söyler. Yeniden adlandırma başarısız olursa uygulama
denemeyi sürdürür ve dosya gidene kadar kapanmaz. `uninstall.sh --purge`,
yeniden adlandırılmış kopyalardan normal dosya olanları kaldırır; `--purge`
olmadan kopyalar kalır.

**Kurtarma, "her şey her zaman geri alınır" demek değildir.** Backstop pili ya
da sıcaklığı izlemez. Kaydedilmiş ses için uygulamanın yeniden açılması
gerekir ve doğrulanamayan süreç dondurmaları elle incelenmeyi gerektirebilir.
Bir uyarı kalırsa Mac'i başında kimse olmadan bırakmadan önce onu çözün. Her
sürümün gerçek Mac üzerindeki çökme, yeniden başlatma ve kurulum denetimleri
[sürüm doğrulaması](release-validation.md) sayfasındadır (İngilizce).

## Kurtarmanın sınırları ve elle ilgilenilmesi gerekenler

- **Süreç sahipliği:** otomatik çözme, kaydedilmiş süreç başlangıç zamanını ve
  önyükleme oturumunu denetler. Uygulama her pid değerini SIGSTOP göndermeden
  önce kayıt defterine yazar ve bu yazma başarısız olursa hiçbir şey göndermez.
  Kimlik bilgisi ancak çekirdek Insomnia'nın kendi durdurmasını doğruladıktan
  sonra eklenir; böylece başka birinin durdurduğu bir süreç hiçbir zaman
  çözülmez. Doğrulamayı kaydeden yazma başarısız olursa uygulama, az önce
  durdurduğu ve kimliği hâlâ eşleşen her pid değerine, henüz durdurulmuş
  görünmese bile hemen SIGCONT gönderir: SIGCONT hâlâ bekleyen bir durdurmayı
  da iptal eder. Ardından bu girdileri kayıt defterinden çıkarır, hatayı durum
  menüsünde gösterir ve disk bu yazmayı da reddetse bile onları dondurulmuş
  saymayı bırakır. Uygulama durdurma ile o yazma arasında ölürse durdurulan
  pid'ler, yalnızca pid kaydeden eski derlemelerin girdileri gibi kimliksiz
  olarak kayıt defterinde kalır ve durdurulmuş oldukları sürece otomatik olarak
  çözülmez. Canlı süreci ve çözülmesi gerekip gerekmediğini doğrulayın; eski bir
  günlükteki bir PID değerine asla körü körüne sinyal göndermeyin.
- **Kimlik doğrulaması atomik bir güvence değildir:** uygulama başlangıç
  zamanını mikrosaniyesine kadar denetler; backstop ise mikrosaniye kaydeden her
  girdi için aynı denetimi yapmasını ve sinyali göndermesini kurulu uygulama
  ikili dosyasından (`Insomnia --resume-frozen`) ister; bu türdeki tüm girdiler,
  30 saniyelik sınırı olan tek bir çağrıyla gider. Girdiler ikili dosyaya
  standart girdi üzerinden verilir; böylece uzun bir kayıt defteri argüman
  boyutu sınırını aşamaz. Backstop bu girdilere asla kendisi sinyal göndermez.
  İkili dosya yoksa, zamanında bitmezse ya da girdi başına beklenen tek satırdan
  başka bir yanıt verirse girdileri tutar. İkili dosyayı yalnızca kurulu paket
  `Info.plist` dosyasında `InsomniaResumeFrozenVersion` bildirdiğinde
  çalıştırır; böylece daha eski bir derlemeyi hiçbir zaman başlatmaz. İkili
  dosya, hâlâ sinyal gönderebildiği sürece kurtarma kilidini tutar ve aynı
  sınırdan sonra kendini sonlandırır; böylece çağrının ortasında öldürülen bir
  backstop çalıştırması, daha sonra kilit olmadan harekete geçebilecek bir
  yardımcı süreç bırakmaz. `uninstall.sh`, o sürümü bildirmeyen bir uygulamayla
  birlikte kurulmuş backstop.sh kopyasını kullanır. Böyle bir kopya yoksa
  çalışma kopyasındaki backstop.sh o girdileri tutar ve kaldırma, hiçbir şey
  kaldırmadan durur. Mikrosaniyeler kaydedilmeye başlanmadan önceki derlemelerin
  yazdığı girdiler için kabuktaki bir saniyelik `ps` karşılaştırması kullanılmaya
  devam eder. Bir arama ile bir sinyal yine de ayrı işlemlerdir ve her seferinde
  bir pid için yapılır.
- **Takılan güç komutları:** 20 saniye geçtiği hâlde bitmemiş bir `sudo pmset`
  komutuna SIGTERM gönderilir, asla SIGKILL gönderilmez: sudo'yu öldürmek,
  kayıt defteri ilerledikten sonra güç ayarlarını değiştiren bir root pmset
  süreci bırakabilir. Komut 3 saniye sonra hâlâ çalışıyorsa işlem, backstop.sh
  betiğinde olduğu gibi bulunduğu yerde durur: başka hiçbir şey geri alınmaz,
  kayıt defteri girdilerini korur ve kurtarma kilidi komut çıkana kadar tutulur.
  Komut kilidi kendisi tutar (standart girdisi kilit dosyasına açılmış bir
  tanımlayıcıdır); böylece Insomnia bu arada çökse ya da zorla kapatılsa bile
  backstop, komutun daha sonra geçersiz kılacağı bir geri alma çalıştırmak yerine
  komutu bekler. Bir bildirim ve bir menü uyarısı pid değerini ve
  `sudo kill <pid>` komutunu verir; komut çıkınca uyarı kaybolur. Pid ayrıca
  komutun başlangıç zamanı ve önyükleme oturumuyla birlikte
  `unfinished-command.json` dosyasına yazılır. Kilidi meşgul bulan bir yeniden
  açılış, komutu menüde adıyla belirtir. Pid değerini ve `sudo kill` komutunu,
  bir bildirimde de, yalnızca o pid hâlâ kaydedilmiş başlangıç zamanına ve
  önyükleme oturumuna sahipken verir; aksi hâlde pid artık başka bir sürece ait
  olabileceğinden komutun çıktığını söyler. Yeniden açılan uygulama her reddin
  ardından 30 saniye sonra yeniden dener. Komut çıktıktan sonra süresi dolmamış
  bir oturumu pil alt sınırlarıyla birlikte sürdürür ve Düşük Güç Modu durumunu,
  aşağıda anlatıldığı gibi kendi komutu çıktıktan sonra denetlediği şekilde
  denetler. Kullanıcının bu sonraki denemeden önce başlattığı bir oturum da aynı
  denetimden geçer. Komut çıkana kadar Insomnia kapanmayı ya da oturum
  başlatmayı reddeder ve reddettiği her bitiş ya da kapak olayını kaydeder.
  Çıkış kodu 0 olan bir `disablesleep 0` ya da `lowpowermode 0` yapılmış
  sayılır: kayıt defteri girdisi kilit bırakılmadan önce temizlenir ve komut
  yeniden çalıştırılmaz. O kayıt defteri yazması başarısız olursa menü bunu
  söyler ve geri alma yeniden çalışır; sonraki bir yazma girdiyi temizleyince
  satır kaybolur. Başka her çıkış kodu başarısızlık sayılır. O zaman bekleyen
  bir bitiş yeniden çalışır. Aksi hâlde Insomnia, Düşük Güç Modu durumunu okur.
  Mod kapalı görünürse kendi `lowpowermode 0` komutunu çalıştırır ve modu ancak
  bu başarılı olunca unutur. Ardından 2 saniyelik kapak sıçrama önleme
  (debounce) süresini bekledikten sonra reddedilmiş bir kapak olayını yeniden
  oynatır ve alt sınır kurallarını yeniden çalıştırır. Mod okunamaz ya da
  kapatılamazsa ya da kayıt defteri yazılamazsa oturum sürdükçe her 30 saniyede
  bir yeniden dener.
- **Ses:** backstop ses düzeyi ve sessiz girdilerini korur ama CoreAudio
  ayarlarını geri yükleyemez. Kurtarma için uygulamayı yeniden açın. Bağlı
  olmayan bir çıkış aygıtı yeniden bağlanana kadar girdisini korur ve bekleyen
  bir aygıt varken kaldırma durur: aygıtı bağlayıp Insomnia'yı açın ya da
  menüden "Beklemeyi bırak: <aygıt>" öğesini seçin.
- **Başka bir şeyin kapattığı uyku:** açılışta oturum ve kayıt defteri girdisi
  yokken `pmset -g` çıktısındaki `SleepDisabled 1` değerine dokunulmaz: onu
  Insomnia ayarlamamıştır ve yalnızca sahibi geri almalıdır. Menü bir uyarı
  gösterir ve bir bildirim `sudo pmset -a disablesleep 0` komutunu verir. Bir
  Insomnia oturumunu bitirmek, kim ayarlamış olursa olsun onu 0 yapar.
- **Düşük Güç Modu:** Insomnia, zaten açık olan bir tercihin sahipliğini
  üstlenmemek için mevcut ayarı denetler.
- **App Nap:** varsayılan olarak kapalı. Ayar açıkken Insomnia her ajan
  uygulamasının önceki `NSAppSleepDisabled` değerini, yazmadan önce kayıt
  defterine kaydeder ve oturum sonunda, backstop.sh içinde ve kaldırmada geri
  koyar. Daha eski bir derlemenin kayıt tutmadan yazdığı değerler tahmin
  edilmez: kaldırma betiği her biri için `defaults delete` komutunu yazdırır ve
  devam eder.
- **Kaldırma:** çözülmemiş değişiklikler kaldıkça kurtarma düzeneğini kaldırmayı
  reddeder. Başarısız bir kaldırma, güç ayarlarının normal olduğunun bir
  doğrulaması değildir.
