# foliate-js (Foliate's reader without the app)

`fj-start` builds the reader page:
- It extracts `foliate-js/` and `reader/` from the installed Foliate flatpak's gresource into `$HARNESS_ROOT/fj/web`.
- It adds `reader/harness.html`: Foliate's unmodified `reader.html` plus `harness.js` (`scripts/fj-harness.js`), which plays the GTK side of the app (book file, uiText, `setAppearance`, `view.init`).
- `scripts/fj-session.py` loads that page in a WebKitGTK 6 view inside the GNOME runtime Foliate uses (`flatpak info --show-runtime`; override with `RUNTIME=`), so the WebKit version matches the app's.

Pagination, CSS injection, page turns and the footnote dialog are Foliate's own code.

## Start

```sh
H=.agents/skills/epub-reader-harness/scripts/harness
FONTSIZE=18 $H fj-start book.epub 'cols=1&at=EPUB/text/ch005.xhtml'
W=1920 H=1080 $H fj-start book.epub          # window px (default 1400x900)
$H fj-start --headless book.epub             # Broadway, no window; software paint, 1024x768
```

The default mode opens an XWayland window and renders on the GPU, like Foliate. It may sit behind other windows, because screenshots come from WebKit. Use `--headless` only when paint fidelity doesn't matter, e.g. counting layout or checking links. In headless mode, `http://127.0.0.1:8767/` shows the live window in a browser.

Query parameters default to Foliate 3.3's gschema defaults:

| Parameter | Default | Notes |
|---|---|---|
| `cols` | 2 | max-column-count |
| `gap` | 0.06 | |
| `maxInlineSize`, `maxBlockSize` | 720, 1440 | px |
| `flow` | `paginated` | or `scrolled` |
| `animated`, `justify`, `hyphenate`, `overrideFont` | 1, 1, 1, 0 | 0 or 1 |
| `lineHeight` | 1.5 | |
| `css` | empty | user stylesheet (URL-encoded) |
| `at` | start of book | href or CFI to open at |

Environment variables: `FONTSIZE`, `MONO_FONTSIZE` (default 16), and `SERIF`/`SANS`/`MONO` font families.

Mirror the user's Foliate by reading `~/.var/app/com.github.johnfactotum.Foliate/config/glib-2.0/settings/keyfile`. For example, `max-column-count=1` becomes `cols=1`, and `default-size=18` becomes `FONTSIZE=18`. A window width that can't fit the configured column count shows fewer columns, just as in the app.

## Drive

`harness fj-eval 'JS'` runs JS as the body of an async function, so it must `return` a value. The result is printed as JSON.

```sh
$H fj-eval 'return harness.state()'                       # section, href, page, pages, location, cfi, footnoteOpen
$H fj-eval 'return await harness.findSplit("pre", true)'  # turn until a <pre> wider than its box breaks across pages
$H fj-eval 'return await harness.turn(1)'                 # next page (-1 back); returns state
$H fj-eval 'return await harness.findLink("QQA")'         # turn until such a link is on the page
$H fj-eval 'return await harness.clickLink("QQA", "[Answer]")'  # Foliate's own link handling
$H fj-eval 'return harness.closeFootnote()'
$H fj-eval 'return await harness.goTo("EPUB/text/ch008.xhtml#autosec-545")'
$H fj-shot out.png
$H fj-stop
```

Other helpers and objects:
- `harness.splitHere(sel, overflowOnly)`: checks the current spread only.
- `harness.links(pattern)`: links on the current spread.
- `harness.doc`: the section document.
- `harness.r`: the paginator.
- `reader`, `reader.view`, `reader.book`: Foliate's own objects.
- `harnessEvents`: messages the reader sent to GTK.

## Gotchas

- **Hrefs are relative to the package root**, e.g. `EPUB/text/ch005.xhtml` (see `reader.book.sections[i].id` or `reader.book.toc[i].href`). An href relative to `text/` silently resolves to nothing, and the reader stays where it is.
- **A blank first page at a chapter start is real, not a harness fault.** Pandoc's stylesheet puts `page-break-before: always` on `h1`. foliate-js turns that into a column break, so the first column of the section is empty. The real Foliate shows the same blank page.
- Geometry: the paginator scrolls a container that starts one page (`harness.r.size`) before the section iframe. An element's `getBoundingClientRect().left + r.size` is therefore comparable with `r.start` and `r.end`, the visible spread. This holds for horizontal LTR books only.
- `fj-shot` writes inside the sandbox and moves the file to the requested path. Write custom snapshot code to `$HARNESS_ROOT/fj/…` for the same reason.
- If a session dies, `fj-start` prints the tail of `$HARNESS_ROOT/fj/session.log`. A busy port (`FJ_PORT`, `FJ_PORT+1`) is the usual cause.
