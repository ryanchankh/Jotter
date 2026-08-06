# Changelog

## 1.3 — Unreleased

- Copying an item from the list bumps it to the top of the history
  with a fresh timestamp, as if it had just been copied. Favorites
  stay pinned; foldered items bump within their folder.

## 1.2 — 2026-08-05

- Settings → History is now a folder browser: a sidebar with All
  Items, Favorites, and every folder (with item counts) filters the
  list, and empty views explain how to file things. A one-time
  "Examples" folder with two sample snippets shows how the feature
  works — delete it whenever.
- The status bar list stays screen-sized: it shows the 15 most recent
  copies (and search matches), with the rest in a "More (N)…" submenu.

- Folders: copies can be filed into named folders. A single Storage
  row in the status bar list opens into every folder with item counts
  (click an item inside to copy it); foldered items are never evicted
  by the size limit. The ⌘⇧C
  window gets a "Save to" folder picker with inline "New Folder…";
  Settings → History shows each item's folder and adds a "Move to…"
  menu for the selection (with New Folder); Settings → General gets a
  Folders section to create and delete folders (deleting keeps the
  items, just unfiles them). Old history files load unchanged.

## 1.1 — 2026-08-01

- Favorites: ⌥-click any item in the list (or ⌥1–⌥9) to pin it — it
  shows a ★, stays above a separator at the top of the list, keeps the
  low 1–9 shortcuts, and is never evicted when history reaches its
  size limit. In Settings → History every row has a clickable star to
  pin/unpin in one click (plus a bulk ★ Favorite button), and the list
  shows a hint for the ⌥/⇧ gestures. Old history files load unchanged.
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
