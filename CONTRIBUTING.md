# Contributing to Jotter

Thanks for your interest! Jotter is intentionally small, and
contributions that keep it that way are the most welcome kind.

## Ground rules

- **One file, no dependencies.** The whole app lives in `Jotter.swift`
  and uses only Apple frameworks. Please don't add packages, package
  managers, or an Xcode project to the repo.
- **macOS 13+.** Use `#available` guards if you need newer APIs.
- **Match the existing style** — naming, comment density, and the
  `// MARK:` section layout.

## Developing

```sh
./build-app.sh              # build + install + relaunch
./build-app.sh --no-install # just produce ./build/Jotter.app
```

For fast iteration without touching /Applications:

```sh
swiftc -parse-as-library Jotter.swift -o jotter && ./jotter
```

There is no test suite; test by running the app. A useful manual
checklist before opening a PR:

1. Copy text, a color (`#ff5733`), and an image — all three appear in
   the menu and in Settings → History.
2. Re-copy an old item — it moves to the top without duplicating.
3. ⌘⇧V opens the list; 1–9 and ↑/↓ + Return copy items.
4. Quit and relaunch — history survives.
5. Settings: change the max-items stepper and the save folder; both
   take effect.

## Pull requests

- Keep PRs focused on one change.
- Describe what you tested (the checklist above, plus anything your
  change touches).
- For UI changes, include a screenshot.

## Reporting bugs

Open a GitHub issue with your macOS version, how you installed Jotter
(release zip / built from source), and steps to reproduce. For
anything sensitive, email
[ryanchankwanho@gmail.com](mailto:ryanchankwanho@gmail.com?subject=%5BJotter%20Support%5D%20)
with the subject prefix **[Jotter Support]**.
