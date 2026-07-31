# Changelog

## 1.1 — Unreleased

- Favorites: ⌥-click any item in the list (or ⌥1–⌥9) to pin it — it
  shows a ★, stays above a separator at the top of the list, keeps the
  low 1–9 shortcuts, and is never evicted when history reaches its
  size limit. Settings → History gets a ★ Favorite button and star
  badges. Old history files load unchanged.
- Edit before copy: ⌘⇧C opens the current clipboard text in a small
  editor; ⌘↩ copies the result and adds it to history without touching
  the original item, and a ★ Favorite checkbox pins (or unpins) the
  result as it's copied. ⇧-click any text row in the list (or ⇧1–⇧9)
  to edit that item instead. Jotter claims ⌘⇧C system-wide while
  running.
- The status bar list gets a History… item that opens the saved
  history browser directly (Settings now opens on the History tab,
  with General second).

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
