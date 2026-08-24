# Transi

A tiny menu-bar translator for macOS. Select text in any app, press **⌥A**, and a
floating popup shows the translation. No API keys, no account, no Dock icon.

Inspired by the Windows tool QTranslate, but an independent project with no code
from it and no affiliation with its authors.

> **Heads up before you install:** Transi translates through Google Translate's
> free public web endpoint, which is not a supported API. See
> [How translation works](#how-translation-works) — it matters, and it can break.

## Features

- **Select text anywhere** (browsers, Finder, editors) → **⌥A** → instant popup
- **Screenshot OCR translate** — **⌥D**, drag a rectangle over any on-screen text
  (image, video, unselectable UI). Recognized on-device via Vision
  (`VNRecognizeTextRequest`) — free and offline — then translated. English always;
  Persian/Arabic-script recognition switches on automatically when the running
  macOS's Vision build supports it
- **Speak the selection** — **⌥S** reads the selected English text aloud
- **Auto language flip** — targets Persian by default; Persian text auto-translates
  back to English
- **Spell check** — shows "Did you mean …" for typos
- **English TTS** — 🔊 speaks whichever side is English (built-in macOS voice, offline)
- **RTL rendering** for Persian output
- **Optional AI translation** — if the `claude` CLI is installed, an ✨AI button
  translates via `claude -p`, billed to your own Claude subscription (no API key)
- Menu-bar-only, target language switchable from the menu

Text capture uses [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit):
Accessibility API → menu-action copy → AppleScript (browsers) → simulated ⌘C fallback.

## How translation works

Transi calls Google Translate's **unofficial** `client=gtx` endpoint (with
`clients5.google.com` as a fallback), the same one used by a long line of free
translator tools. Results are cached, 200 entries.

Be aware of what that means:

- It is **not a supported or documented API**, and using it is contrary to Google's
  Terms of Service. Google can rate-limit, change, or remove it without notice, and
  the app will simply start showing errors.
- Whatever you translate is **sent to Google**. Don't run confidential text through it.
- Transi is **not affiliated with, sponsored by, or endorsed by Google**. "Google
  Translate" is Google's trademark, used here only to say where the text goes.

If that trade-off is not for you, the ✨AI button routes through your own Claude
CLI instead, and the OCR step is fully on-device either way.

An engine that uses a proper key (Google Cloud Translation, DeepL) or a local model
via Ollama is the natural next step and would make this moot.

## Install

```bash
./scripts/build-app.sh
```

Builds release, bundles `build.noindex/Transi.app`, code-signs it, and copies it to
`/Applications/Transi.app` (relaunching it if it was already running). Requires only
the Xcode Command Line Tools — pure SwiftPM, no Xcode project.

**First run:** grant Accessibility permission
(System Settings → Privacy & Security → Accessibility → enable Transi).
Safari capture may additionally ask for Apple Events (Automation) permission.
Screenshot OCR (⌥D) also needs Screen Recording permission; macOS prompts for it on
first use.

### Giving a build to someone else

```bash
TRANSI_DIST=1 ./scripts/build-app.sh
```

This signs ad-hoc instead of with the local identity, which is what a *different*
Mac needs — the self-signed identity below cannot be validated there, so macOS
would refuse to register the app and permissions would never stick. Copy
`build.noindex/Transi.app` over, drop it in `/Applications`, then:

```bash
xattr -dr com.apple.quarantine /Applications/Transi.app
```

The app is not notarized, so without that step macOS will refuse to open it.

### Permissions survive rebuilds

By default the build is ad-hoc signed, which gets a new signature hash every time
you rebuild — macOS then treats it as a different app and drops the Accessibility
and Screen Recording grants, forcing you to remove and re-add Transi in System
Settings after every build.

Fix it once with a stable local code-signing identity:

1. Open **Keychain Access** → **Keychain Access → Certificate Assistant → Create a
   Certificate…**
2. Name: `Transi Dev` · Identity Type: **Self Signed Root** · Certificate Type:
   **Code Signing** → Create (defaults are fine).
3. Rebuild. The script auto-detects the `Transi Dev` identity and signs with it
   instead of ad-hoc; the first codesign may trigger a one-time keychain access
   prompt — choose **Always Allow**.

Custom identity name? `TRANSI_SIGN_IDENTITY=YourName ./scripts/build-app.sh`.
Build without installing to `/Applications`? `TRANSI_NO_INSTALL=1`.

## Usage

| Action | How |
|---|---|
| Translate selection | Select text, press ⌥A (or menu-bar icon → Translate Selection) |
| Screenshot OCR translate | ⌥D, then drag a rectangle; Esc cancels |
| Speak selection aloud | ⌥S |
| Switch target fa/en | Segmented control in popup, or menu-bar menu |
| Speak English text | 🔊 button |
| Copy translation | Copy button |
| AI translation | ✨ AI button (needs the `claude` CLI) |
| Close popup | Esc, click outside, or ✕ |

## Architecture

```
Sources/Transi/
  App.swift                  @main entry, NSApplication accessory app
  AppDelegate.swift          status item, hotkey wiring, capture→popup flow
  HotkeyManager.swift        Carbon RegisterEventHotKey (⌥A, ⌥D, ⌥S), no deps
  ScreenCaptureManager.swift drag-to-select overlay + CGWindowListCreateImage
  OCRService.swift           Vision VNRecognizeTextRequest, on-device
  ScriptDetector.swift       script/language heuristics
  TextCapture.swift          SelectedTextKit-backed selection capture
  TranslationService.swift   Google endpoints + cache + spell suggestion
  PopupController.swift      non-activating NSPanel, monitors, state
  PopupView.swift            SwiftUI popup UI (RTL-aware)
  SpeechService.swift        AVSpeechSynthesizer English TTS
  ClaudeAIService.swift      optional `claude -p` shell-out
  Settings.swift             UserDefaults-backed target language
  SystemSettings.swift       deep links into Privacy & Security panes
```

## Known limitations

- The Google endpoint can rate-limit or break at any time (see above); the app
  degrades to an error message.
- Screenshot OCR uses the deprecated-but-functional `CGWindowListCreateImage`
  (works down to macOS 13). ScreenCaptureKit is the modern replacement once the
  minimum target moves to macOS 14+.
- Hotkeys are fixed at ⌥A / ⌥D / ⌥S (Carbon). A recorder UI needs full Xcode for
  the KeyboardShortcuts package (its `#Preview` macros don't compile with the
  Command Line Tools alone).
- Secure input fields (passwords) can never be captured — macOS by design.
- Not notarized. Every install on another Mac needs the `xattr` step above.

## License

[MIT](LICENSE) © fxreza.

Bundled dependencies are MIT too; their notices are in
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) and ship inside the `.app`.
