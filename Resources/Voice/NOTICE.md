# Uykusuz sesi: kullanılan bileşenler

Bu klasör Uykusuz'la gelen Türkçe sesin dosyalarını tutar. Hepsi veridir: uygulama
yalnızca okurken yükler ve hiçbir şey ağdan indirilmez. Nasıl üretildikleri
`tools/voice/README.md` dosyasındadır.

## Konuşma modeli

`text.mlmodelc`, `align.mlmodelc`, `step.mlmodelc`, `decode.mlmodelc`

- EMA Lightning: <https://github.com/canberk7/ema-lightning>,
  <https://huggingface.co/canberkkkkkk/ema-lightning>
- Lisans: Apache License 2.0 (`LICENSE-APACHE-2.0.txt`).
- Değişiklik: ağırlıklar aynıdır. `ema.pt` ve `decoder.pt`, Core ML programlarına
  çevrildi. `Sources/Uykusuz/Voice` altındaki `SpeechModel.swift` ve
  `SpokenPieces.swift`, projenin `engine.py`, `model.py`, `chunker.py` ve
  `frontend.py` dosyalarındaki hesapların Swift'e aktarılmış hâlidir.

## Sayı, tarih ve kısaltma kuralları

`trnorm.js`

- trnorm, ahenk-turkish-tts: Copyright 2026 Özgür Güler,
  <https://github.com/ozguradmin/ahenk-turkish-tts>
- Lisans: Apache License 2.0 (`LICENSE-APACHE-2.0.txt`).
- Değişiklik: modülleri tek dosyada birleştirildi, kodu değişmedi.
  `SpeechModel.swift` içindeki `TorchNoise`, aynı projenin `site/js/randn.js`
  dosyasının Swift'e aktarılmış hâlidir.

## İngilizce kelimelerin okunuşu

`english.tsv`, `Sources/Uykusuz/Voice/SpokenTurkish.swift`

- Sesleri Türkçe harflere çeviren kurallar ve İngilizce harf adları: Antalia-2 Mini,
  Copyright 2026 PatientDesk AI, <https://huggingface.co/cloud0day3/antalia-mini>
  (`antalia_mini/text/foreign.py`). Lisans: Apache License 2.0
  (`LICENSE-APACHE-2.0.txt`). Değişiklik: yalnızca kuralları kullanıldı ve seçilen
  kelimelerin sonucu bu dosyaya yazıldı.
- Kelimelerin okunuşu: CMU Pronouncing Dictionary. Lisansı aşağıdadır.

```text
Copyright (C) 1993-2015 Carnegie Mellon University. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions
are met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.
   The contents of this file are deemed to be source code.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in
   the documentation and/or other materials provided with the
   distribution.

This work was supported in part by funding from the Defense Advanced
Research Projects Agency, the Office of Naval Research and the National
Science Foundation of the United States of America, and by member
companies of the Carnegie Mellon Sphinx Speech Consortium. We acknowledge
the contributions of many volunteers to the expansion and improvement of
this dictionary.

THIS SOFTWARE IS PROVIDED BY CARNEGIE MELLON UNIVERSITY ``AS IS'' AND
ANY EXPRESSED OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL CARNEGIE MELLON UNIVERSITY
NOR ITS EMPLOYEES BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```

## Büyük harfli kelimeler

`caps.txt`: Türkçe metinlerde kelime olarak geçen, 4-6 harfli büyük yazılmış
kelimelerin listesi. Yalnızca kelimelerdir; kaynak metinlerden başka bir şey içermez.
