# Kartka

A small manga reader for Android and the desktop (a Flutter web build in a
Chrome app window, served by a local wrapper). "Kartka" is Polish for a page.

- Goal, stack and boundaries: [`SPEC.md`](SPEC.md)
- Interfaces between parts: [`docs/DOCS-contracts.md`](docs/DOCS-contracts.md)
- Working on it: [`CLAUDE.md`](CLAUDE.md)

## Run

```bash
./run.sh            # desktop: build web, start the wrapper, open the app window
./run.sh android    # release APK, adb install -r, launch
```

Needs `fvm` (Flutter 3.47.7 is pinned in `.fvmrc`; `run.sh` installs both
when missing) and a Chrome-family browser (`KARTKA_BROWSER` overrides the
lookup). OAuth client ids, when you have them, go in
`~/.config/kartka/oauth.json` and are passed as `--dart-define-from-file`.

The wrapper listens on `127.0.0.1:47391` and refuses to start when that port
is taken (the app's browser data and the OAuth redirect are tied to it).

## Test

```bash
fvm flutter test               # app
(cd desktop && fvm dart test)  # wrapper
scripts/coverage.sh            # both, 100 % line coverage required
```

## Desktop launcher

`desktop/install_desktop_entry.sh` installs the icon and a `.desktop` entry
(WM class `kartka`).
