#!/usr/bin/env python3
"""Flattens the trnorm JavaScript modules into the one classic script JavaScriptCore evaluates.

    bundle_trnorm.py <site/js/trnorm of ahenk-turkish-tts> <out file>

Every module becomes a function that returns its exports, in dependency order. Only `normalize` is reached from
outside, so the modules it does not need (index, itn) stay out. Nothing else about the code changes.
"""
import re
import sys
from pathlib import Path

SOURCE, OUT = Path(sys.argv[1]), Path(sys.argv[2])
COMMIT = "8981df9354a6dc95a3a2b4730b7fbff196dda219"
ORDER = ["case_tables", "unassigned", "py", "casing", "lexicon", "numbers", "normalizer"]
IMPORT_ALL = re.compile(r"^import \* as (\w+) from '\./(\w+)\.js';\s*$", re.M)
IMPORT_SOME = re.compile(r"^import \{([^}]*)\} from '\./(\w+)\.js';\s*$", re.M)
EXPORT_DECL = re.compile(r"^export (function\*?|const|let|class) (\w+)", re.M)
EXPORT_LIST = re.compile(r"^export \{([^}]*)\};\s*$", re.M)


def names(text):
    return [n.strip() for n in text.split(",") if n.strip()]


HEADER = """// trnorm, Turkish text normalization for speech. Copyright 2026 Ozgur Guler.
// https://github.com/ozguradmin/ahenk-turkish-tts (site/js/trnorm, commit %s).
// Licensed under the Apache License, Version 2.0 (LICENSE-APACHE-2.0.txt beside this file).
// Changed: its modules are flattened into this one script by tools/voice/bundle_trnorm.py; the code is theirs.
""" % COMMIT
parts = [HEADER + "var trnorm = (function () {", "'use strict';", "const __modules = {};"]
for name in ORDER:
    code = (SOURCE / f"{name}.js").read_text(encoding="utf-8")
    exports = []

    def one_import(match):
        pairs = [n.replace(" as ", ": ") for n in names(match.group(1))]
        return f"const {{ {', '.join(pairs)} }} = __modules.{match.group(2)};"

    code = IMPORT_ALL.sub(lambda m: f"const {m.group(1)} = __modules.{m.group(2)};", code)
    code = IMPORT_SOME.sub(one_import, code)

    def declaration(match):
        exports.append(match.group(2))
        return f"{match.group(1)} {match.group(2)}"

    code = EXPORT_DECL.sub(declaration, code)

    def export_list(match):
        for n in names(match.group(1)):
            local, _, public = n.partition(" as ")
            exports.append(f"{public.strip()}: {local.strip()}" if public else local.strip())
        return ""

    code = EXPORT_LIST.sub(export_list, code)
    if re.search(r"^\s*(import|export)\s", code, re.M):
        raise SystemExit(f"{name}.js still has an import or export this script did not understand")
    parts.append(f"// ---- {name}.js")
    parts.append(f"__modules.{name} = (function () {{\n{code}\nreturn {{ {', '.join(exports)} }};\n}})();")
parts.append("return { normalize: __modules.normalizer.normalize };")
parts.append("})();")
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text("\n".join(parts) + "\n", encoding="utf-8")
print(OUT, OUT.stat().st_size // 1024, "KB")
