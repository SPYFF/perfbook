---
name: epub-reader-harness
description: Run an EPUB in KOReader or in Foliate's foliate-js/WebKitGTK reader, headless or windowed, to reproduce and screenshot rendering bugs (listings, page breaks, footnote popups, quiz answers) and to compare builds under different reader settings. Use when debugging how an EPUB renders in an e-reader, or when the user reports something wrong in KOReader or Foliate.
---

# EPUB reader harness

`scripts/harness` drives two engines against an EPUB, each in a throwaway profile under `$HARNESS_ROOT` (default `/tmp/epub-harness`):

- **KOReader**: the real AppImage (crengine), controlled through its HTTP inspector.
- **foliate-js**: Foliate's own reader code, extracted from the Foliate flatpak, running in the same WebKitGTK as the app and controlled over a small HTTP API. Use this for anything "Foliate". Leave the real Foliate app alone: it shares the user's library and reading positions.

Both run behind other windows and take screenshots of themselves, so the user's desktop stays usable. Run `scripts/harness help` for the command list.

Every fix is judged against a **red** baseline: a screenshot of the unfixed EPUB that shows the symptom. A fix with no red baseline is unverified.

## Steps

1. **Pick the two EPUBs.** One is the unfixed build (git stash, an older build, or a copy with the fix reverted inside the zip). The other is the candidate. Done when both files exist.
2. **Start a session** that matches the user's reader settings. Read the engine reference first: [koreader.md](koreader.md) or [foliate-js.md](foliate-js.md). Done when `harness ko-start` or `harness fj-start` prints `... up`.
3. **Navigate to the symptom** with the `find*` helpers, which turn pages until a condition holds (a listing split across pages, a footnote link on the page). Page numbers shift with font, screen size and style tweaks, so locate by content. Done when the helper returns a match rather than `null` or empty.
4. **Capture red.** Screenshot the page and the next page, or the popup, and look at the PNG with the read tool. Done when the image shows the reported symptom. If it doesn't, change settings until it does, or report that it doesn't reproduce.
5. **Capture the candidate** with the same settings and steps. Use `harness montage` for a side-by-side image. Done when the candidate image is green, meaning the symptom is gone and nothing else broke.
6. **Clean up** with `harness cleanup`. Done when `flatpak ps` lists no harness instance and `pgrep -f usr/lib/koreader` finds nothing.

## Desktop facts (GNOME Wayland)

These explain the harness design. Re-check them only if the desktop changes.

- **Screenshots of other apps' windows are impossible.** GNOME exposes no screenshot CLI for native Wayland windows, and `grim` is unsupported. So each engine captures itself: KOReader's framebuffer (`/koreader/device/screen/bb`) and WebKit's `get_snapshot`. For XWayland windows (`GDK_BACKEND=x11`, `SDL_VIDEODRIVER=x11`), `import -window <xid>` works even when the window is covered. Only XWayland windows show up in `wmctrl -l`.
- **Synthetic input is dropped.** XWayland ignores XTEST, so `ydotool`-style fake keys and clicks never reach the app. Drive the engines only through their APIs (taps, link clicks, page turns).
- **Headless options.** KOReader runs with `SDL_VIDEODRIVER=offscreen`. foliate-js runs on GTK's Broadway backend (`fj-start --headless`), but that paints in software and misses GPU paint bugs. The overflow-box listing bug, for example, shows only in the default XWayland mode, which uses the GPU.
- **Flatpak sandbox.**
  - `--env=XDG_*_HOME` is overridden by flatpak; set those variables inside `--command=sh -c 'export ...; exec ...'`.
  - The sandbox can only write paths passed with `--filesystem=`.
  - To stop an instance, record its ID with `--instance-id-fd` and run `flatpak kill <id>`.
- **Killing processes.** `pkill -f <pattern>` also matches the shell running the tool call when the pattern appears in the command line. The command then dies with exit 143. Kill by recorded PID or instance ID, as the harness does.
- **Ports** (loopback only): KOReader inspector 8099 (`KO_PORT`), foliate-js control 8766 (`FJ_PORT`), Broadway viewer 8767. `ko-start`/`fj-start` refuse to start when a port is busy.
