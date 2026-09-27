# Key format table

`Sources/KeyFormats.swift` is generated. Do not edit it by hand.

- `gitleaks-bare-rules.json` — the bare-token subset of the gitleaks rule set (MIT). Context rules that match variable names rather than key values are excluded. The Sourcegraph rule has its bare 40-hex branch removed because it matched any 40 hex characters.
- `curated-rules.json` — additions from trufflehog detectors, secrets-patterns-db (high confidence only), and vendor docs (Vercel, Supabase, Groq, xAI, Google service-account JSON). Every pattern is anchored to the whole trimmed value and must start with a literal prefix of at least four characters, except the two generic shapes (JWT, PEM), which are marked `generic` and never produce a destination-mismatch warning.
- Regenerate: `python3 scripts/keyformats/gen_keyformats.py`. The unit test `KeyRecognizerTests.testEveryFormatCompilesAndIDsAreUnique` fails on any pattern ICU cannot compile.
