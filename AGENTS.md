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
- GitHub sürümünün notları bu maddelerle aynıdır.

## Aynı anda çalışan oturumlar

Bu çalışma kopyasında birden fazla oturum aynı anda çalışabilir.

- `git add -A` ya da `git commit -a` kullanma; yalnızca kendi değiştirdiğin
  dosyaları commit'le: `git commit -- <yollar>`.
- Push'tan önce `git fetch`. `origin/main` ilerlediyse
  `git pull --rebase --autostash`.
- `Resources/Info.plist` ve `CHANGELOG.md` dosyalarını düzenlemeden hemen önce
  son hâllerini oku; iki oturum aynı sürüm numarasını kullanmasın.

## Depo kuralları

- Depo gizli (private) kalır; görünürlüğünü değiştirme.
- README, belgeler ve GitHub sayfası Uykusuz'u bağımsız bir proje olarak
  anlatır: başka bir projenin adını ya da adresini, "fork", "çatal",
  "upstream" gibi ifadeleri yazma.
- `docs/LICENSE` lisans bildirimidir; kullanıcı açıkça istemedikçe silme ya da
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
