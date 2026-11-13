# Ajan talimatları

Bu depoda çalışan kodlama ajanları (Claude Code, Codex ve diğerleri) için
kurallar. [CLAUDE.md](CLAUDE.md) bu dosyayı içe aktarır. Kullanıcı bir konuda
açıkça başka bir şey isterse onun isteği geçerlidir.

## Her değişiklikten sonra

1. **GitHub sayfasını güncelle.** Değişiklik kullanıcının gördüğü bir şeyi
   etkiliyorsa (özellik, varsayılan, arayüz metni, ayar, menü, kurulum adımı)
   aynı commit'te şunları da güncelle:
   - `README.md`: özellikler listesi, ilgili bölüm ve Ayarlar tablosu;
   - `docs/` altındaki ilgili sayfa (`install.md`, `lid-close.md`,
     `recovery.md`, `extras.md`);
   - `docs/assets/*.svg` çizimleri: metinler arayüzdeki Türkçe metinlerle
     birebir aynı olmalı. Çizimi açık ve koyu temada açıp taşan yazı
     olmadığını kontrol et;
   - `SECURITY.md` ve `GUVENLIK-INCELEMESI.md`: yetki, ağ, veri ya da kalıcı
     bir bileşen değiştiyse;
   - depo açıklaması ve konu etiketleri, uygulamanın tanımı değiştiyse:
     `gh repo edit Mustafa-Ghn/uykusuz --description "..."`.
2. **Sürümü artır ve `CHANGELOG.md`'ye yaz** (aşağıda).
3. **Commit'le ve beklemeden push'la.** Doğrudan `main` dalına çalış; ayrı dal
   ya da pull request açma. Push için kullanıcıya sorma: GitHub her zaman
   güncel kalmalı.
4. **Sürüm arttıysa** etiketi ve GitHub sürümünü yayımla:

   ```bash
   git tag v<sürüm> && git push origin v<sürüm>
   gh release create v<sürüm> --title "Uykusuz <sürüm>" --notes "<CHANGELOG.md'deki o sürümün maddeleri>"
   ```

## Sürüm numarası

- Sürüm `Resources/Info.plist` dosyasındadır: `CFBundleShortVersionString`
  (`MAJOR.MINOR.PATCH`) ve `CFBundleVersion` (derleme numarası). Kurulu sürüm
  Ayarlar > Uygulama'da görünür.
- Uygulamayı değiştiren her güncelleme (`Sources/`, `Resources/`, `scripts/`,
  `Package.swift`) sürümü artırır:
  - hata düzeltmesi, küçük iyileştirme ya da metin düzeltmesi: PATCH
    (`0.2.0` → `0.2.1`);
  - yeni özellik, yeni ayar ya da varsayılan değişikliği: MINOR
    (`0.2.1` → `0.3.0`; PATCH sıfırlanır);
  - kurulumu ya da kayıtlı ayarları geriye uyumsuz değiştiren büyük bir
    değişiklik: MAJOR (`0.3.0` → `1.0.0`).
- `CFBundleVersion` her sürüm artışında 1 artar ve hiç azalmaz.
- Yalnızca README, belge, çizim ya da test değiştiren bir commit sürümü
  artırmaz; yine de beklemeden push'lanır.
- Commit mesajı Türkçe olur: sürüm arttıysa `Uykusuz <sürüm>: <ne değişti>`,
  artmadıysa `Uykusuz: <ne değişti>`.

## CHANGELOG.md

- En yeni sürüm en üstte durur: `## <sürüm> — <YYYY-AA-GG>` başlığı ve altında
  kullanıcının anlayacağı Türkçe maddeler. Gerekirse `### Eklenenler`,
  `### Değişenler` ve `### Düzeltilenler` alt başlıklarını kullan; boş kalan
  alt başlığı yazma.
- Her madde tek satırdır (satırı bölme): GitHub sürüm notlarında satır
  sonları olduğu gibi görünür.
- GitHub sürümünün notları bu maddelerle aynıdır.

## Kurulum önerirken

Kullanıcıya kurulum ya da güncelleme önerdiğin her seferde şunları birlikte
ver:

- Komutları, her biri kendi kod bloğunda: önce `./scripts/install.sh`, sonra
  `open "$HOME/Applications/Uykusuz.app"`. Betik çalışan uygulamayı kapatır ama
  yenisini başlatmaz; ikinci komutu atlarsan Uykusuz kapalı kalır.
- Eski sürümün silinmesi gerekmediğini: betik yeni paketi eskisinin yerine
  koyar, Mac'te ikinci bir kopya ya da eski sürümden bir dosya kalmaz. Bunu
  söylemeden önce denetle:
  `mdfind "kMDItemCFBundleIdentifier == 'com.mustafaghn.uykusuz'"` tek satır
  (`~/Applications/Uykusuz.app`) döndürmelidir. Başka bir yerde kopya çıkarsa
  onu silecek komutu da ver; kullanıcının yerine silme.
- Uykusuz'u Mac'ten kaldıran komutu: `./scripts/uninstall.sh`; ayarlar ve
  günlüklerle birlikte `./scripts/uninstall.sh --purge`.
- Kurulumun sıfırladıklarını (ad-hoc imza her kuruluma yeni bir kimlik verir):
  Ekran Kaydı izni ilk kullanımda yeniden istenir, kayıtlı hotspot parolası
  okunamaz olur ve yeniden girilir. Claude Code hook'ları uygulama açılınca
  kendiliğinden yenilenir ve yalnızca sonradan açılan oturumlarda geçerlidir.

## macOS ve iOS güncellemeleri

Bazı özellikler macOS'in belgelenmemiş arayüzlerine dayanır ve bir macOS ya da
iOS güncellemesiyle bozulabilir: hotspot'u telefondan açtırma (Sharing),
hotspot katılma ayarını okuma (CoreWiFi), ekran ve klavye parlaklığı
(DisplayServices, CoreBrightness), kararmış ekranı kilitleme (login).

**Son denetim:** 2026-11-13 · macOS 26.6.2 (25G83) · iOS sürümü Mac'ten okunamıyor

- Bu depoda bir geliştirmeye başlarken bugünün tarihini bu satırla
  karşılaştır. 30 günden az geçtiyse denetleme, güncelleme çıkmış mı diye de
  arama. Yalnızca soru yanıtlanan, dosya değişmeyen bir sohbette hiç denetleme.
- 30 gün ya da daha fazla geçtiyse asıl işten önce denetle:
  1. Kurulu macOS: `sw_vers` çıktısını satırdaki sürümle karşılaştır.
  2. Yayımlanan sürümler: son denetim tarihinden beri yeni bir macOS ya da iOS
     sürümü çıkmış mı diye web'de bir kez ara. Web erişimin yoksa bu adımı
     atladığını söyle.
  3. İkisinden biri değiştiyse arayüzleri yokla:
     `swift test --filter "SystemInterfaceTests|PrivateDisplayGuardTests"`.
     Başarısız test, güncellemenin neyi götürdüğünü adıyla söyler; atlanan
     test, o özelliğin bu macOS sürümünde ölçülmediği için kapalı olduğunu
     gösterir.
  4. Hotspot'u telefondan açtırma için günlüğe bak
     (`~/Library/Logs/Uykusuz/uykusuz.log`, `hotspot wake:` satırları):
     güncellemeden sonra "turned its hotspot on" varsa çalışıyordur. Yoksa
     çalıştığını ancak canlı deneme gösterir; o deneme ağı keser ve telefonu
     etkiler, bu yüzden yalnızca kullanıcı izin verirse yap.
  5. Yeni bir büyük macOS sürümünde ölçülmemiş yollar kendiliğinden kapalıdır
     (`measuredMajorVersions`, `measuredDisplayServicesMajors`). Kullanıcıya
     hangi özelliklerin kapalı kaldığını söyle; sürümü listeye ancak o sürümde
     çağrıyı deneyip ölçtükten sonra ekle.
- Sonucu kullanıcıya bir iki cümleyle bildir: ne değişmiş, bozulan var mı.
  Bozulanı düzelt ya da düzeltmek için ne gerektiğini söyle.
- Sonra "Son denetim" satırını bugünün tarihi ve gördüğün sürümlerle güncelle,
  commit'le ve push'la. Hiçbir şey değişmemişse de tarihi güncelle: bir sonraki
  denetim böylece 30 gün sonraya kalır.

## Aynı anda çalışan oturumlar

Bu çalışma kopyasında birden fazla oturum aynı anda çalışabilir.

- `git add -A` ya da `git commit -a` kullanma; yalnızca kendi değiştirdiğin
  dosyaları commit'le: `git commit -- <yollar>`.
- Push'tan önce `git fetch`. `origin/main` ilerlediyse
  `git pull --rebase --autostash`.
- `Resources/Info.plist` ve `CHANGELOG.md` dosyalarını düzenlemeden hemen önce
  son hâllerini oku; iki oturum aynı sürüm numarasını kullanmasın.

## Depo kuralları

- Depo herkese açıktır (public); kullanıcı istemedikçe görünürlüğünü
  değiştirme.
- Uygulama da herkes içindir: bir özelliği tek bir kullanıcının kurulumuna
  göre yazma. Cihaz, ağ, klasör, hesap ya da uygulama adlarını koda gömme;
  değeri ayardan ya da çalışma anında bulunandan al ve o değer yokken ne
  olacağını da yaz. Yalnızca bir macOS sürümünde denenmiş bir yol başka
  sürümde sessizce devre dışı kalmalı, uygulamayı bozmamalıdır.
- Commit'lere, testlere ve belgelere kişisel ya da gizli veri koyma: gerçek
  Wi-Fi ağ adları, telefon numaraları, e-posta adresleri, API anahtarları,
  kişisel klasör yolları, iş ya da proje adları. Testlerde uydurma değerler
  kullan (`OrnekAg`, `+905550000000`, `/Users/me` gibi). Böyle bir şey
  yanlışlıkla commit'lenirse hemen kullanıcıya söyle: geçmişten silmek force
  push gerektirir.
- README, belgeler ve GitHub sayfası Uykusuz'u bağımsız bir proje olarak
  anlatır: başka bir projenin adını ya da adresini, "fork", "çatal",
  "upstream" gibi ifadeleri yazma. Tek istisna README'nin Lisans bölümündeki
  teşekkür satırıdır; onu silme.
- `LICENSE` lisans bildirimidir; kullanıcı açıkça istemedikçe silme ya da
  değiştirme.
- Arayüz, bildirimler, sesli uyarılar ve kullanıcı belgeleri Türkçedir; kod ve
  kod yorumları İngilizcedir.
- Değişikliğin dokunduğu testleri çalıştır (`swift test --filter ...`).
  README ya da `docs/install.md` metnini değiştirdiysen `ReleaseWorkflowTests`
  ve `LidCloseCopyTests` testlerini de çalıştır: README'deki bazı cümleleri
  denetliyorlar.
- Uygulamayı kurmak (`./scripts/install.sh`) yönetici parolası ister; bu adımı
  kullanıcıya bırak.
- GitHub Actions bu depoda kapalıdır. Açılırsa `v*` etiketleri Release iş
  akışını çalıştırır; o zaman `gh release create` adımını iş akışına bırak.
