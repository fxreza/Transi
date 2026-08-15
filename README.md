# QTranslate for macOS

A minimal macOS clone of QuestSoft's QTranslate (Windows): select text in any app,
press **⌥A**, and a floating popup shows the Google translation. Free, no API keys.

## Features

- **Select text anywhere** (browsers, Finder, editors) → **⌥A** → instant popup
- Capture uses [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) (MIT):
  Accessibility API → menu-action copy → AppleScript (browsers) → simulated ⌘C fallback
- **Screenshot OCR translate** — **⌥S**, drag a rectangle over any on-screen text
  (image, video, unselectable UI), and it's recognized on-device via Vision
  (`VNRecognizeTextRequest`, free, offline) then fed through the same translator.
  English always; Persian/Arabic-script recognition is enabled automatically when
  the running macOS's Vision build supports it
- **Google Translate, free** — unofficial `client=gtx` endpoint, no key; fallback to
  `clients5.google.com` on failure; results cached (200 entries)
- **Auto language flip**: target Persian by default; Persian text auto-translates to English
- **Spell check** — Google's `spell_res` shows "Did you mean …" for typos
- **English TTS** — 🔊 button speaks whichever side is English (built-in macOS voice, offline)
- **RTL rendering** for Persian output
- **Optional AI translation** — if the `claude` CLI is installed, an ✨AI button
  translates via `claude -p` (billed to your Claude subscription, no API key)
- Menu-bar-only app (no Dock icon), target language switchable from the menu

## Build & run

```bash
./scripts/build-app.sh        # → build/QTranslate.app
open build/QTranslate.app
```

Requires only Xcode Command Line Tools (pure SwiftPM; no Xcode project).

**First run:** grant Accessibility permission
(System Settings → Privacy & Security → Accessibility → enable QTranslate).
Safari capture may additionally ask for Apple Events (Automation) permission.
Screenshot OCR (⌥S) additionally needs Screen Recording permission
(System Settings → Privacy & Security → Screen Recording → enable QTranslate);
macOS prompts for it automatically on first launch or first ⌥S press.

### Permissions survive rebuilds

By default the build is ad-hoc signed, which gets a new signature hash every
time you rebuild — macOS then treats it as a different app and drops the
Accessibility/Screen Recording grants, forcing you to remove and re-add
QTranslate in System Settings after every build.

Fix it once with a stable local code-signing identity:

1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant →
   Create a Certificate…**
2. Name: `QTranslate Dev` · Identity Type: **Self Signed Root** · Certificate
   Type: **Code Signing** → Create (defaults are fine).
3. Rebuild: `./scripts/build-app.sh`. The script auto-detects the `QTranslate
   Dev` identity and signs with it instead of ad-hoc; the first codesign may
   trigger a one-time "codesign wants to access your keychain" prompt — choose
   **Always Allow**.

From then on, permissions persist across rebuilds. (Custom identity name?
`QTRANSLATE_SIGN_IDENTITY=YourName ./scripts/build-app.sh`.)

## Usage

| Action | How |
|---|---|
| Translate selection | Select text, press ⌥A (or menu-bar icon → Translate Selection) |
| Screenshot OCR translate | Press ⌥S, drag a rectangle (or menu-bar icon → Capture Screenshot to Translate); Esc cancels |
| Switch target fa/en | Segmented control in popup, or menu-bar menu |
| Speak English text | 🔊 button |
| Copy translation | Copy button |
| AI translation | ✨ AI button (needs `claude` CLI) |
| Close popup | Esc, click outside, or ✕ |

## Architecture

```
Sources/QTranslateMac/
  App.swift                @main entry, NSApplication accessory app
  AppDelegate.swift        status item, hotkey wiring, capture→popup flow
  HotkeyManager.swift      Carbon RegisterEventHotKey (⌥A, ⌥S), no deps
  ScreenCaptureManager.swift drag-to-select overlay + CGWindowListCreateImage capture
  OCRService.swift         Vision VNRecognizeTextRequest, on-device
  TranslationService.swift free Google endpoints + cache + spell suggestion
  PopupController.swift    non-activating NSPanel, monitors, state
  PopupView.swift          SwiftUI popup UI (RTL-aware)
  SpeechService.swift      AVSpeechSynthesizer English TTS
  ClaudeAIService.swift    optional `claude -p` shell-out
  Settings.swift           UserDefaults-backed target language
```

## Known limitations / next steps

- Unofficial Google endpoints can rate-limit or break at any time (ToS gray area);
  the app degrades with an error message. A Bing/Ollama fallback engine is a natural add.
- Screenshot OCR uses the deprecated-but-functional `CGWindowListCreateImage`
  (works down to macOS 13); a ScreenCaptureKit-based capture is the modern
  replacement once the minimum target moves to macOS 14+.
- Hotkeys are fixed at ⌥A / ⌥S (Carbon); a recorder UI needs full Xcode for the
  KeyboardShortcuts package (its #Preview macros don't compile with CLT alone).
- Secure input fields (passwords) can never be captured — macOS by design.
