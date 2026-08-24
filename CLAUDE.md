# Transi - working rules

## After any code change: rebuild and install to /Applications

A change is not done until the app in `/Applications` is updated. `swift build`
alone only produces a debug binary in `.build/` - the user runs the installed
app, so they would see no change.

Always finish a code change by running:

```bash
./scripts/build-app.sh
```

The script builds release, bundles `build.noindex/Transi.app`, signs it with the
local `Transi Dev` identity (so Accessibility / Screen Recording grants
survive rebuilds), copies it over `/Applications/Transi.app`, and relaunches
it if it was running. No extra install step is needed.

Then tell the user the app was rebuilt and installed, and mention any hotkey or
permission change they need to know about.

## Why the build directory is named `build.noindex`

Do not rename it back to `build/`, and do not add a second output directory
without the `.noindex` suffix.

macOS Spotlight never indexes a directory whose name ends in `.noindex` (this is
the same mechanism Xcode uses for DerivedData). Before the rename there were two
`Transi.app` bundles in the Spotlight index - the real one in
`/Applications` and the build output here - so Spotlight and Raycast both showed
two identical results and the user could not tell which one they were launching.

The `.noindex` suffix hides the build output from that index. `/Applications/Transi.app`
is the only copy that appears in Spotlight/Raycast, which is the copy the user
actually runs. Source files are unaffected and stay searchable.

If you change the output path, keep the `.noindex` suffix and update
`scripts/build-app.sh`, `scripts/make-icon.swift`, `README.md` and `.gitignore`
together.
