# Changelog

## 1.1 — Unreleased

- Vim-style navigation in the ⌘⇧V list: h/j/k/l act as ←/↓/↑/→ so the
  hand stays on the home row (j/k move the highlight, l opens an image
  preview, h closes it, Return copies). Implemented with a CGEvent tap
  that is active only while the menu is open, so it requires
  Accessibility permission — prompted once on first hotkey use; ↑/↓
  and 1–9 keep working without it. Typing in the search field is never
  remapped.

## 1.0 — 2026-07-25

Initial release.

- Clipboard history for text and images with de-duplication
- Menu bar list with fuzzy search; ⌘⇧V keyboard-first list with 1–9
  shortcuts
- Color previews for copied hex/rgb values; image thumbnails with
  hover preview
- Native Settings window (General / History / About) with start at
  login, history size, custom save folder, and browsable history with
  timestamps and character counts
- History persists to plain JSON/PNG on disk; concealed clipboard data
  (password managers) is never recorded
- Fallback for crowded menu bars: the list opens at the cursor when
  the status icon is hidden
- `build-app.sh` to build, package, sign, install, and cut release
  zips without an Xcode project
