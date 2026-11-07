# Typist

Local-first AI dictation and meeting notes for macOS. Free and open source.

Typist turns your voice into clean text in any app and records meetings with speaker names and summaries. Everything runs on your Mac. Nothing leaves it unless you connect an external model yourself: your own Whisper server, Ollama, or a cloud API with your own key.

> **Status:** early development (milestone M0). There is nothing to install yet.

## Requirements

- macOS 15 Sequoia or later
- Apple Silicon

## Building from source

You need Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
git clone https://github.com/deb-space/typist.git
cd typist
make app        # generates Typist.xcodeproj and builds Typist.app into build/
```

To work in Xcode, run `make project` and open `Typist.xcodeproj`. The project is generated from `project.yml`, so edit that file instead of the project settings in Xcode.

Other commands:

| Command | What it does |
|---|---|
| `make build` | Build the Swift package |
| `make test` | Run unit tests |
| `make lint` / `make format` | Check / fix formatting with `swift format` |
| `make check` | Lint, tests and SPDX header check, as in CI |

Builds are signed ad-hoc by default, so macOS may ask for permissions again after a rebuild. To sign with your Apple Development certificate, create `Config/Local.xcconfig`:

```
DEVELOPMENT_TEAM = ABCDE12345
CODE_SIGN_IDENTITY = Apple Development
```

## Project layout

| Path | Contents |
|---|---|
| `App/` | The macOS app: SwiftUI views, Info.plist, entitlements |
| `Sources/TypistCore` | Domain types and service protocols |
| `Sources/TypistAudio` | Microphone and system audio capture |
| `Sources/TypistProviders` | Speech-to-text, LLM and diarization providers |
| `Sources/TypistStorage` | SQLite, audio files, Keychain |
| `docs/adr/` | Architecture decision records |

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Every commit must be signed off under the [Developer Certificate of Origin](https://developercertificate.org).

## License

Typist is licensed under the GNU General Public License, version 3 only, with the option to use later versions of the GPL approved by deb-space. See [COPYING](COPYING) and [LICENSE](LICENSE).
