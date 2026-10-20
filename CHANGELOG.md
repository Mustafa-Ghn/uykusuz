# Sürüm notları

Uykusuz'un sürümleri, en yenisi en üstte. Sürüm numarası
`Resources/Info.plist` dosyasından gelir; kurulu sürüm Ayarlar > Uygulama'da
görünür.

## 0.2.0 — 2026-10-21

Sürüm notlarının başladığı sürüm. Öne çıkanlar:

- **Claude ile otomatik oturum.** Claude Code bir görev yürüttüğü sürece oturum
  kendiliğinden açılır, arka planda 2 saatlik dilimlerle uzar ve Claude 5
  dakika çalışmayınca biter. Menü çubuğunda geri sayım yerine "Claude" yazar;
  yazıya tıklayıp süre girince oturum sizin olur.
- **Otomatik oturumu duraklatma.** Otomatik oturumu basılı tutarak bitirince
  ya da sağ tık menüsündeki "Otomatik oturumu duraklat" ile otomatik oturum 15
  dakika, 1 saat, 3 saat ya da seçilen bir saate kadar duraklatılır. Duraklatma
  sürerken menü çubuğunda kapalı gözün yanında bir duraklatma işareti görünür.
- **Claude Code hook'larıyla görev algılama.** Kuruluyken Claude yalnızca bir
  görev yürütürken çalışıyor sayılır.
- **Kod modu.** Oturum sürerken kapak açıksa ve Claude çalışıyorsa Düşük Güç
  Modu açılır.
- **Boşta siyah ekran.** Oturum sürerken kapak açıkken ekran koruyucu ve ekran
  uykusu çalışmaz; 60 sn girdi olmazsa ekran kararır, 30 sn olmazsa klavye
  ışığı söner.
- **Türkçe sesli uyarılar.** Kapak kapalıyken pil, ısı ve oturum sonu
  uyarıları sesli söylenir.
- **Varsayılanlar.** Pil eşikleri %30 (Düşük Güç Modu) ve %20 (oturum sonu);
  "diğer tüm uygulamaları dondur" açık; dondurma listesinde WhatsApp, Word,
  Excel ve ParaView var.
- **Giriş öğesi.** Kurtarma ajanı Sistem Ayarları > Genel > Giriş Öğeleri ve
  Uzantılar'da Uykusuz adıyla görünür.
- **Ağ isteği yok.** Uykusuz hiçbir ağ isteği yapmaz.
- **Belgeler.** Türkçe README, kurulum, kapak ve kurtarma belgeleri ile
  yeniden çizilen görseller.
