# KOReader

The harness runs the AppImage at `$KOREADER` (default `~/.local/bin/koreader`) with `KO_HOME=$HARNESS_ROOT/ko`. That profile holds settings, patches, cache and history, so the user's `~/.config/koreader` is never touched. The book is copied to `$HARNESS_ROOT/ko/books/book.epub` because KOReader writes a `book.sdr/` sidecar next to the book.

## Start

```sh
H=.agents/skills/epub-reader-harness/scripts/harness
$H ko-start book.epub                          # offscreen, KOReader defaults
$H ko-start book.epub 'style_tweaks.footnote-inpage_epub=nil' hide_nonlinear_flows=true copt_font_size=20
$H ko-start --interactive book.epub            # real window for a human to click
W=1072 H=1448 $H ko-start book.epub            # screen size in px (default 700x1000)
```

Each `key=value` is a `settings.reader.lua` entry written as a Lua literal. A dotted key edits one field of a table setting, and `nil` deletes it (`scripts/ko-settings.py`). The profile always gets:
- `quickstart_shown_version` (no quickstart page);
- `plugins_disabled={statistics=true}` (the statistics plugin errors on a fresh profile);
- `footnote_link_in_popup=true`;
- KOReader's default global style tweaks, which include the in-page EPUB footnotes tweak;
- the inspector itself, `httpinspector={port=…,autostart=true}`.

The `--interactive` window is native Wayland, so it is missing from `wmctrl`. `ko-shot` still works.

## Settings that matter for EPUB debugging

| Setting | Meaning |
|---|---|
| `style_tweaks.<id>=true\|nil` | Global style tweak. IDs are in KOReader's `frontend/ui/data/css_tweaks.lua`, e.g. `footnote-inpage_epub` ("In-page EPUB footnotes", on by default: footnote text at the page bottom). |
| `footnote_link_in_popup` | "Show footnotes in popup" (Settings › Taps and gestures › Links). |
| `link_prefer_footnote` | "Show more links as footnotes" (looser detection). |
| `hide_nonlinear_flows` | Default for "Hide non-linear fragments" (Navigation menu). `aside[epub:type=footnote]` is non-linear in KOReader's `html5.css`, so this keeps footnote bodies out of the page flow. |
| `copt_font_size`, `copt_line_spacing`, `copt_h_page_margins`, `copt_embedded_css`, `copt_view_mode` (0 page, 1 scroll), `copt_visible_pages` | Document defaults (prefix `copt_` + option names from `creoptions.lua`). |

Mirror the user's setup by reading `~/.config/koreader/settings.reader.lua` and the book's `<book>.sdr/metadata.epub.lua`. Copy values, not files: the real files contain paths and history.

## Drive

```sh
$H ko-ev GotoPage 80                     # UIManager events; also GotoViewRel 1, Close
$H ko-call harness_find_link QQA 40      # turn pages until a link target contains "QQA"
$H ko-call harness_tap 323 457           # tap_x/tap_y from harness_links/harness_find_link
$H ko-shot out.png
$H ko-call harness_state                 # page, pages, xpointer, font, tweaks, open widgets
$H ko-stop
```

The `harness_*` Lua globals live in `scripts/ko-patch.lua`, installed as a late user patch:
- `harness_links [pattern]`, `harness_find_link pattern [max]`: links on the page, each with a tap point at the middle of its first line.
- `harness_tap x y`: a real tap gesture, so footnote popups, menus and page-turn zones all react.
- `harness_state`: page, pages, xpointer, font, tweaks, open widgets.
- `harness_page xpointer`, `harness_goto_xp xpointer`.
- `harness_tweak id 0|1`, `harness_hide_nonlinear 0|1`, `harness_font_size n`: per-book toggles; they re-render the book.
- `harness_gset key value`: global setting, saved immediately.
- `harness_close`: close the top widget (popup).

To add a helper, edit `ko-patch.lua` and restart the session.

## Gotchas

- UI-changing helpers run on the next UI tick. Wait about 1.5 s before `ko-shot`, longer after a re-render (tweak, font size, hide non-linear).
- **Page numbers shift** with screen size, font and tweaks. Locate by content with `harness_find_link`, or by xpointer with `harness_page '/body/DocFragment[N]'`. `DocFragment[N]` follows spine order, but confirm N with `harness_page` before relying on it.
- A popup counts as open when `harness_state.widgets` has more than `ReaderUI` in it.
- In the inspector's object browser (`/koreader/ui/document/<method>/`), calls to `CreDocument` methods fail with "attempt to index local 'self'" because those methods are wrapped. Use `ui/rolling/<method>/` or a patch helper instead. Append `?` to any inspector path to get its signature as HTML.
- `/koreader/globals/f/'a'/'b'/` passes quoted arguments as strings. `/koreader/event/Name/12/` guesses types. `ko-call` quotes everything, and the helpers convert.
