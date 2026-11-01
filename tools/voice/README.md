# The voice's files

`Resources/Voice` holds what the app's natural voice reads with. It is made once by these
tools and committed; a build only copies it. None of this runs in the app or during a build.

| File | Made by | From |
| --- | --- | --- |
| `text`, `align`, `step`, `decode` `.mlmodelc` | `convert_ema.py` | `ema.pt` and `decoder.pt` of the speech model |
| `trnorm.js` | `bundle_trnorm.py` | the JavaScript port of the Turkish normalizer |
| `english.tsv`, `caps.txt` | `make_tables.py` | the CMU dictionary, this project's sources, Turkish text corpora |

`NOTICE.md` there says what each comes from and under which licence.

```bash
uv venv --python 3.12 venv && uv pip install --python venv/bin/python "torch==2.7.1" "numpy<2.3" "coremltools==9.0"
venv/bin/python tools/voice/convert_ema.py <folder holding ema_lightning/> <folder with ema.pt and decoder.pt> Resources/Voice
python3 tools/voice/bundle_trnorm.py <site/js/trnorm> Resources/Voice/trnorm.js
python3 tools/voice/make_tables.py <folder of foreign.py> <corpus folder> Sources Resources/Voice
```

`convert_ema.py` prints how far each program is from the PyTorch graph it came from. After changing
the programs, run `swift test --filter SpeechModelSumsTests`.
