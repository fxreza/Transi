# Transi

A tiny menu-bar translator for macOS. Select text in any app — or just point at
it — press **⌥T**, and a floating popup shows translations from **Google, Bing,
and Gemini side by side**. No account, no Dock icon; Google and Bing need no API
key at all.

Inspired by the Windows tool QTranslate, but an independent project with no code
from it and no affiliation with its authors.

> **Heads up before you install:** the Google and Bing engines use those
> services' free public web endpoints, which are not supported APIs. See
> [How translation works](#how-translation-works) — it matters, and it can break.

## Features

- **Translate anything with one key** — **⌥T** cascades: selected text → the UI
  element under the mouse pointer (buttons, labels, dialogs, via Accessibility)
  → OCR of the area around the pointer → a type-it-yourself input box. Press
  **⌥T twice** to jump straight to the input box
- **Three engines, stacked** — every enabled engine answers on its own card,
  streaming in as each finishes. Drag a card by its name badge to reorder
  permanently; hide any card for the session or disable an engine for good
  - **Google** — keyless web endpoint; dictionary entries and spell suggestions
  - **Bing / Microsoft Translator** — keyless web endpoint; Persian
    transliteration, dictionary, and the **Casual / Formal tone** control from
    the Bing Translator website
  - **Gemini** — your own free [AI Studio](https://aistudio.google.com/apikey)
    key (stored in the Keychain), model selectable, honors the tone setting
- **~109 languages** with auto-detect, an enable/disable list so pickers stay
  short, a source⇄target swap, and per-language primary-engine overrides
- **Screenshot OCR translate** — **⌥S**, drag a rectangle over any on-screen
  text (image, video, unselectable UI). Recognized on-device via Vision, then
  translated
- **Speak it** — **⌥R** reads the selection aloud (press again for slow, again
  to stop); the popup's 🔊 speaks the translation in the target language
- **Translate the clipboard** — **⌥C**
- **Editable shortcuts** — every hotkey is rebindable in Settings → Shortcuts,
  live without a relaunch, with conflicts named ("Already used by macOS
  (Spotlight)")
- **A real Settings window** (⌘, from any Transi window): General, Languages,
  Engines, Shortcuts, Appearance, Permissions — launch at login, accent/theme,
  text and control sizes, popup auto-close delay
- **Popup niceties** — pin to keep it open, auto-close when the mouse leaves
  (configurable delay), auto language flip (Persian text auto-translates back
  to English and vice versa), "Did you mean…" spell suggestions, RTL rendering,
  per-card copy/speak
- **Built-in updates** — checks GitHub Releases daily; one-click install

Text capture uses [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit):
Accessibility API → menu-action copy → AppleScript (browsers) → simulated ⌘C fallback.

## How translation works

- **Google** — the unofficial `client=gtx` endpoint (with `clients5.google.com`
  as a hedged fallback), the same one used by a long line of free translator
  tools.
- **Bing** — the same `ttranslatev3` / `tlookupv3` endpoints the
  bing.com/translator page itself calls, including its tone (Casual/Formal)
  field; session tokens are scraped from that page and refreshed hourly.
- **Gemini** — the official `generateContent` API with your own free key, using
  a JSON response schema for clean translation + transliteration output.

Be aware of what that means:

- The Google and Bing endpoints are **not supported or documented APIs**, and
  using them is contrary to those services' Terms of Service. Either can be
  rate-limited, changed, or removed without notice — the affected card degrades
  to an error while the other engines keep working.
- Whatever you translate is **sent to Google and/or Microsoft** (and Google
  again, if Gemini is enabled). Don't run confidential text through it. On
  Gemini's free tier, Google may use submitted text to improve its products —
  the app shows this notice once before first use.
- Transi is **not affiliated with, sponsored by, or endorsed by** Google or
  Microsoft; their names are used only to say where the text goes.

The OCR step is fully on-device either way.

## How speech works

The 🔊 button and ⌥R use Google Translate's `translate_tts` endpoint, because
the built-in macOS voices read English noticeably worse. It is unofficial, and
the text is sent to Google. Every failure falls back to the offline macOS
voice — no network, a rate limit, or a language Google has no voice for
(Persian is one; it always speaks with the macOS voice).

## Install

Download the latest release zip, drop `Transi.app` into `/Applications`, then:

```bash
xattr -dr com.apple.quarantine /Applications/Transi.app
```

The app is not notarized, so without that step macOS will refuse to open it.

**First run:** grant Accessibility permission
(System Settings → Privacy & Security → Accessibility → enable Transi).
Safari capture may additionally ask for Apple Events (Automation) permission.
Screenshot OCR (⌥S) and pointer OCR also need Screen Recording permission;
macOS prompts on first use. The Settings → Permissions tab shows live status
for all of them.

### Build from source

```bash
./scripts/build-app.sh
```

Builds release, bundles `build.noindex/Transi.app`, code-signs it, and copies it
to `/Applications/Transi.app` (relaunching it if it was already running).
Requires only the Xcode Command Line Tools — pure SwiftPM, no Xcode project.

To hand a build to another Mac, sign ad-hoc instead (the local identity below
cannot be validated elsewhere): `TRANSI_DIST=1 ./scripts/build-app.sh`.

To cut a GitHub release: `./scripts/release.sh <version>`.

### Permissions survive rebuilds

By default the build is ad-hoc signed, which gets a new signature hash every
time you rebuild — macOS then treats it as a different app and drops the
Accessibility and Screen Recording grants (and Keychain access), forcing you to
re-grant after every build.

Fix it once with a stable local code-signing identity:

1. Open **Keychain Access** → **Keychain Access → Certificate Assistant →
   Create a Certificate…**
2. Name: `Transi Dev` · Identity Type: **Self Signed Root** · Certificate Type:
   **Code Signing**. Tick **Let me override defaults** and set the validity
   period to `3650` days.
3. Double-click **Transi Dev** in Keychain Access, expand **Trust**, set
   **Code Signing** to **Always Trust**, close the window and enter your
   password.
4. Rebuild. The script auto-detects the `Transi Dev` identity and signs with it.

Check it worked with `security find-identity -v -p codesigning`.
Custom identity name? `TRANSI_SIGN_IDENTITY=YourName ./scripts/build-app.sh`.
Build without installing? `TRANSI_NO_INSTALL=1`.

## Usage

| Action | How |
|---|---|
| Translate selection / thing under pointer | **⌥T** (cascades to pointer target, OCR, then input box) |
| Type or paste text to translate | **⌥T twice**, or menu → Type Text to Translate… |
| Screenshot OCR translate | **⌥S**, then drag a rectangle; Esc cancels |
| Read selection aloud | **⌥R** — again for slow, a third time to stop |
| Translate clipboard | **⌥C** |
| Change languages | Pickers in the popup header; swap with ⇄ (⌘⇧S) |
| Tone (Casual/Formal, Bing + Gemini) | `A` icon in the popup header, or Settings → Engines |
| Reorder engine cards | Drag a card by its name badge |
| Pin popup open | 📌 in the header (⌘P) |
| Copy translation | Copy button (⌘C) — ▾ menu for per-engine / all |
| Open Settings | Menu → Settings…, or ⌘, from any Transi window |
| Close popup | Esc, click outside, move mouse away, or ✕ |

All hotkeys rebindable in Settings → Shortcuts.

## Architecture

```
Sources/Transi/
  App.swift                    @main entry, NSApplication accessory app
  AppDelegate.swift            status item, menus, ⌥T cascade, Edit-menu shim
  LanguageCatalog.swift        ~109 languages, RTL/script data, per-engine codes
  ScriptDetector.swift         script-bucket heuristics for local auto-flip
  TextCapture.swift            SelectedTextKit-backed selection capture
  PointerTextCapture.swift     AX element under pointer + region-OCR fallback
  ScreenCaptureManager.swift   drag-to-select overlay + CGWindowListCreateImage
  OCRService.swift             Vision VNRecognizeTextRequest, on-device
  TranslationCoordinator.swift fan-out to engines, streaming, cache, failover
  Engines/
    TranslationEngine.swift    protocol, EngineID, results, errors, tone
    GoogleEngine.swift         keyless Google web endpoint (hedged dual-host)
    BingEngine.swift           keyless Bing endpoints + tone + dictionary
    BingConfigStore.swift      single-flight token scrape + expiry
    GeminiEngine.swift         Gemini API, JSON schema, Keychain key
  Popup/                       NSPanel controller + SwiftUI stacked-card UI
  Shortcuts/                   rebindable hotkeys: model, Carbon manager, recorder UI
  Views/Settings/              Settings window tabs
  SettingsStore.swift          ObservableObject over UserDefaults
  KeychainStore.swift          API keys (never in UserDefaults)
  UpdateService.swift          GitHub Releases check + staged install
  SpeechService.swift          Google translate_tts, AVSpeechSynthesizer fallback
  SystemSettings.swift         deep links into Privacy & Security panes
```

## Known limitations

- The keyless Google/Bing endpoints can rate-limit or break at any time (see
  above); the affected card degrades to an error while other engines continue.
- Gemini's free tier has tight per-model rate limits, and busy models
  (3.7 Flash at peak times) can hang or 503 — switch models in
  Settings → Engines when that happens.
- Pointer translate can't read a menu while it is open if macOS withholds the
  hotkey during menu tracking; buttons, labels, and dialogs work.
- Screen capture uses the deprecated-but-functional `CGWindowListCreateImage`
  (works down to macOS 13). ScreenCaptureKit is the replacement once the
  minimum target moves to macOS 14+.
- Secure input fields (passwords) can never be captured — macOS by design.
- Not notarized. Every install needs the `xattr` step above.

## License

[MIT](LICENSE) © fxreza.

Bundled dependencies are MIT too; their notices are in
[THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) and ship inside the `.app`.
