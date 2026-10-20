---
name: install-insomnia
description: Insomnia'nın Türkçe çatalını (bir Mac'i süreli bir oturum boyunca uyanık tutan macOS menü çubuğu uygulaması) Mustafa-Ghn/insomnia-tr deposunun bir çalışma kopyasından kaynak koddan derleyerek kurar ya da yükseltir. Kullanıcı Insomnia'yı kurmak, güncellemek ya da yeniden kurmak istediğinde kullanın.
---

# Insomnia'yı kurma (Türkçe çatal)

Bu çatalın GitHub sürümleri (release) yoktur; yalnızca
https://github.com/Mustafa-Ghn/insomnia-tr deposunun bir çalışma kopyasından
`./scripts/install.sh` ile derlenerek kurulur. Özgün projenin
(krishhgg/Insomnia) sürüm zip dosyalarını indirmeyin. Ayrıntılar çalışma
kopyasındaki `docs/install.md` dosyasının "Kaynaktan derleme", "Neler kurulur"
ve "Yükseltmeler" bölümlerindedir. O sayfayı okuyun, ardından bu adımları
izleyin. `sudo` komutunu asla kendiniz çalıştırmayın ve ona asla parola
vermeyin. Bir adım yönetici parolası gerektirdiğinde kullanıcıya Terminal'de
çalıştıracağı komutun tam hâlini verin ve bittiğini söylemesini bekleyin.

1. **Mac'i denetleyin.** Insomnia macOS 26 ya da üstünü gerektirir
   (`sw_vers -productVersion`). Apple Silicon bir Mac'te
   `sysctl -n hw.optional.arm64` komutu `1` yazdırır. Intel bir Mac'te
   kaynaktan derleme denenmemiştir; kullanıcıya bunu söyleyin. Derleme için
   Swift 6.2 ya da üstünü içeren Xcode gerekir (`swift --version`).
2. **Çalışma kopyasını hazırlayın.** Kullanıcının bu deponun bir çalışma
   kopyası zaten varsa onu kullanın ve `git pull` ile güncelleyin. Yoksa
   klonlayın:

   ```bash
   git clone https://github.com/Mustafa-Ghn/insomnia-tr.git
   cd insomnia-tr
   ```

   Depo özeldir. Klonlama GitHub kimlik doğrulaması isterse bunu kullanıcının
   kendisinin yapmasını isteyin (örneğin `gh auth login`); kimlik bilgilerini
   sormayın ve hiçbir yere girmeyin.
3. **Kurulumu kullanıcıya bırakın.** `./scripts/install.sh` uygulamayı
   derler ve sudoers kuralı için yönetici parolasını sorar; bu yüzden bu komutu
   kullanıcıya verin, kendiniz çalıştırmayın. Kullanıcı çalıştırmadan önce ona
   kurulum betiğinin bir sudoers kuralı eklediğini söyleyin. Bu kural, hesabının
   şu dört `pmset` güç komutunu parolasız çalıştırmasına izin verir (sayfanın
   "Neler kurulur" bölümü de bunları listeler):

   ```text
   /usr/bin/pmset -a disablesleep 1
   /usr/bin/pmset -a disablesleep 0
   /usr/bin/pmset -b lowpowermode 1
   /usr/bin/pmset -b lowpowermode 0
   ```

   Kuralı yalnızca Insomnia değil, kullanıcının hesabıyla çalışan her program
   kullanabilir; bunu da söyleyin. Kullanıcının çalışma kopyasının kök
   klasöründe çalıştıracağı komut:

   ```bash
   ./scripts/install.sh
   ```

   `--app` ya da `--allow-unverified-origin` önermeyin: bu çatalda doğrulanacak
   bir indirme yoktur ve bu bayraklar yalnızca özgün projenin sürüm zip
   dosyaları içindir.
4. **İlk açılış.** Kullanıcı uygulamayı
   `open "$HOME/Applications/Insomnia.app"` ile açar. macOS ilk açılışı
   engellerse kullanıcı Sistem Ayarları > Gizlilik ve Güvenlik bölümünden izin
   verir.
5. **Doğrulayın.** Göz simgesi menü çubuğunda görünür ve
   `launchctl print gui/$(id -u)/com.insomnia.backstop` kurtarma ajanını bulur.
   Kullanıcıdan ilk oturumdan önce Ayarlar'daki "Kapak kapanınca yapılacaklar"
   seçeneklerini gözden geçirmesini isteyin.

Yükseltme aynı adımlardır: çalışma kopyasında `git pull`, ardından kullanıcının
çalıştıracağı `./scripts/install.sh`. Kurulum betiği çalışan uygulamadan
kapanmasını ister ve geri alınmayı bekleyen bir oturum değişikliği varsa durur.
O zaman nedenini bulmak için maintain-insomnia becerisini kullanın.

Kullanıcı özgün projedeki değişiklikleri de almak isterse README'deki
"Upstream değişikliklerini alma" bölümünü izleyin. Çevrilmiş metinler
çakışacağından çakışmaları kullanıcıyla birlikte, elle çözün.
