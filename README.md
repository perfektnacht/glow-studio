# Glow Studio

A glowing peg board for [Omarchy](https://omarchy.org), in the spirit of the
1967 toy: a black perforated sheet, eight translucent peg colors, and a light
behind it. It opens pre-lit with the OMARCHY wordmark in green and you draw
over it, or clear it and start from nothing.

![the board](preview.png)

## Install

```bash
omarchy plugin add https://github.com/perfektnacht/glow-studio.git
omarchy plugin enable perfektnacht.glow-studio right
omarchy restart shell
```

`bin/omarchy-glow-studio` wraps the same call if you'd rather have a command
(`toggle`, `show`, `hide`) on your `PATH`. The other script in `bin/` is not
for you to run — `bin/omarchy-glow-studio-wallpaper` is how the plugin does its
own file handling, described under [Where it writes](#where-it-writes).

## Requirements

Omarchy 4 or newer, which provides `omarchy-shell` and the Quickshell runtime
this is written against. Nothing is bundled, vendored, or installed on your
behalf.

Three system commands are used, all already present on an Omarchy install,
plus `bash` and coreutils for the script in `bin/`:

| Command | Used for | Without it |
|---------|----------|------------|
| `notify-send` | Saying where an export or the wallpaper landed | Both still work, just silently |
| `mkdir` | Creating `~/Pictures` before the first export | The export fails rather than guessing another directory |
| `omarchy` | Setting the wallpaper from the toolbar | The button reports that it failed; nothing else changes |

Nothing else is read or written, and the plugin makes no network connections
of any kind.

## Where it writes

Four paths belong to it:

- `~/.local/state/omarchy/glow-studio.json` — your board as you draw it, plus
  the export size and OLED choice
- `~/.local/state/omarchy/glow-studio-wallpaper-<timestamp>-<n>.png` — the last
  wallpaper you applied. The desktop background is a symlink to it, so it has
  to stay put; a new apply writes a new file and deletes the one before it,
  leaving exactly one
- `$XDG_RUNTIME_DIR/glow-studio/render.png` — a wallpaper render on its way to
  the line above, replaced on every apply and gone once it lands
- `~/Pictures/glow-studio-<size>-<timestamp>.png` — exports, only when you ask

Everything the plugin creates, publishes or deletes in
`~/.local/state/omarchy` goes through `bin/omarchy-glow-studio-wallpaper`,
which opens that directory one component at a time — `~` then `.local` then
`state` then `omarchy` — refusing a symlink at any step and refusing any
component it does not own or that group or others can write, and then does its
work through the descriptor it opened rather than through the path again. The
point is that a path is resolved afresh on every use, so a symlink dropped
anywhere along one can send a write, or a deletion, somewhere the plugin never
meant to touch; a descriptor is pinned to the directory it was opened on and
cannot be redirected afterwards.

Renders are staged in `$XDG_RUNTIME_DIR` — a mode-0700 tmpfs owned by you,
under directories owned by root — because the render itself is written by Qt,
which takes a file name and not a descriptor. The bytes are then copied into
the state directory through the descriptor. If any of those checks fail
nothing is written and nothing is deleted: the wallpaper is refused, with a
notification saying which check it was.

If you ran this plugin under its previous name, the board saved back then is
read once and carried over the first time you open Glow Studio. The old file is
left on disk rather than deleted, so nothing is lost either way.

## Removal

```bash
omarchy plugin remove perfektnacht.glow-studio
```

That disables it and deletes the plugin directory. Your board is deliberately
kept: it lives outside the checkout, so removing and reinstalling brings the
drawing back exactly as you left it. The last wallpaper render is kept for the
same reason — the desktop background is a symlink to it. To clear those too:

```bash
rm ~/.local/state/omarchy/glow-studio.json
rm ~/.local/state/omarchy/glow-studio-wallpaper-*.png
```

Exports in `~/Pictures` are yours and are never touched by removal.

## Drawing

Mouse and keyboard steer the same cursor — the ring on the board is always
where the brush will land, whichever one you last touched.

| Input | Does |
|---|---|
| left drag | place pegs |
| right drag | erase, without switching tools |
| `←` `↑` `↓` `→` | move the cursor one peg |
| `Enter` | place pegs at the cursor — the same as a left click |
| shift + click, shift + `Enter` | straight line from the end of the last stroke |
| scroll | brush size |
| `K`, **Lock Brush** | lock the brush: while on, moving the pointer over the board lays the current brush or eraser down — no click, no wheel. The cursor ring fills in and the toolbar's status line says so. One continuous sweep is a single undoable stroke, ended by resting the pointer or leaving the board; Undo, Clear and Logo close the sweep first, so it stays one action. See [Lock Brush](#lock-brush) |
| `1`–`8` | pick a peg color |
| `E`, `0` | eraser — or the black swatch at the end of the palette |
| `[` `]` | brush size |
| `Ctrl+Z` / `Ctrl+Shift+Z` | undo / redo (60 strokes deep) |
| `C` | clear the board |
| `L` | put the OMARCHY logo back |
| `Ctrl+S` | export a PNG to `~/Pictures` |
| `Ctrl+W` | set the desktop wallpaper |
| `Shift + ?` | open the keyboard reference over the board; the same keys, `Esc`, or a click close it |
| `Esc` | close — the reference panel first, if it's open, then the plugin |

The board autosaves to `~/.local/state/omarchy/glow-studio.json` a moment after
every stroke, so it comes back exactly as you left it. Delete that file to
start over from the logo.

## The toolbar

The palette sits on its own centred row: eight peg colors and, at the end of
them, a black swatch for the eraser. The eraser is a ninth value rather than a
mode, so picking it is the same gesture as picking a color.

Underneath, the controls are grouped into captioned sections — **Brush**,
**Edit**, **Output** — which centre while they fit and wrap onto their own rows
once the window is too narrow to hold them side by side. Nothing is dropped at
laptop or tiled width.

The line under the buttons is the status line: `Shift + ?  for keyboard
shortcuts` normally, `brush locked — Lock Brush or K to release` while the lock
is on. It reads there rather than on the board, because the board is the
drawing surface. It replaced a single line carrying every binding, which could
only ever hold as many of them as the window was wide; the reference panel
wraps nothing and drops nothing.

### Lock Brush

`Lock Brush`, or `K`, makes the brush paint on motion alone: move the pointer
over the board and it lays pegs down with nothing held. It's there for
trackpads, where holding a click through a long drag is tiring, and for anyone
who hasn't got the click gesture yet.

The lock stays on until the button or `K` turns it off. Leaving the board does
not release it, so a hand that wanders off the pegboard and back keeps
painting. The cost is that crossing the board to reach a toolbar control paints
on the way; `Undo` takes it back, and a mode that switched itself off mid-stroke
would be the worse of the two.

## Wallpapers

`Export PNG` (or `Ctrl+S`) writes to `~/Pictures/glow-studio-<size>-<stamp>.png`
at whichever size is selected in the toolbar. Your choice is remembered.

`Set Wallpaper` renders the board the same way, at the same selected size, and
hands the file to `omarchy theme bg set` — Omarchy's own background command —
so the desktop changes immediately and the choice survives a reboot. The
render lands in `~/.local/state/omarchy/` (see [Where it writes](#where-it-writes))
under a fresh name each time — a
timestamp plus a counter, since a 2K render can finish inside the same second —
because the background system records a symlink to the file it is given and
ignores a path it is already showing: overwriting one fixed file in place would
leave the desktop on the previous render. Each successful apply deletes the
renders before it, so one file is kept — the one the symlink points at.

`Ctrl+W` does the same thing from the keyboard, the way `Ctrl+S` does for the
export.

| | |
|---|---|
| **2K** | 2560 × 1440 |
| **4K** | 3840 × 2160 (default) |
| **6K** | 5760 × 3240 |
| **OLED** | board goes true `#000000` instead of near-black `#08080b`, so an OLED panel actually switches those pixels off — most of the board is unlit, so it's most of the image |

Exports are **re-rendered** at the target size, not scaled up from the screen.
The board is discs on a grid, so painting it again at a bigger peg pitch costs
one repaint and gives clean edges; upscaling the ~2200px on-screen canvas to 6K
would just be a blurry 2200px canvas.

The board is 111:62 and the presets are 16:9, so they don't divide evenly. The
leftover margin gets filled with **more peg board** rather than a bare border —
the painter draws holes for every grid position the canvas covers, including
the ones past the edge of the board, and centers your drawing in it. OLED mode
applies to the screen too, so the preview is what you get.

## How it works

The grid is a fixed **111 × 62** regardless of monitor — a saved board reopens
identically on a different display, and the wordmark is guaranteed to fit. Cell
size is whatever makes that grid fill the screen.

All 6,882 holes are painted into `Canvas` tiles — a **6 × 4** grid of them
rather than one canvas the size of the board. Thousands of QML `Rectangle`s
would be hopeless, and the board is static between edits, so a stroke repaints
only the tiles it touched: usually one, a twenty-fourth of the board, instead
of the whole thing.

A touched tile repaints **whole**. `Canvas.markDirty` does not reliably repaint
the sub-rectangle it is handed — a single stamp could leave a block of flat
backing with no hole texture sitting over the pegboard until something forced a
full repaint — and the tiling is where the saving came from in the first place,
not from sub-tile rectangles. An untouched board paints **zero** frames, so
there's no idle GPU cost while it sits open.

The glow is stacked translucent discs rather than a per-peg radial gradient,
which lets every peg of a given color batch into one fill. Overlapping halos
accumulate, so dense areas of a drawing bloom the way the real toy does.

One painter serves both the screen and every export size — it takes a peg pitch
and a grid origin, so an export is the same code at a bigger pitch. The export
canvas uses `Canvas.Threaded`, which matters a lot: rasterizing 18.7 megapixels
on the scene-graph thread froze the whole shell for **~3.7s** at 6K, and moving
it to its own thread cuts that to **~600ms** for byte-identical output. Because
that thread can't safely read QML properties, everything the painter needs is
snapshotted into plain JS before the paint starts — which also means an export
captures the board as it was when you pressed the button.

What's left is the grab readback and the PNG encode, both unavoidably
synchronous on the GUI thread: roughly **150ms at 2K, 290ms at 4K, 600ms at
6K**. The export canvas is only mounted while an export is running — at 6K its
image buffer alone is ~75MB.

### The wordmark

`Board.js` carries the Omarchy screensaver's ASCII art verbatim and expands it
at load time. Each source character is one peg column and *two* peg rows: the
half-block characters (`▀`, `▄`) carry vertical sub-cell detail, so expanding
`▀` to (on, off) and `▄` to (off, on) recovers the letterforms at their true
2:1 aspect instead of squashing them onto the terminal's cell grid. The result
is 81 × 19 pegs, centered on the board.

## Security

Reviewed against the [Omarchy Plugin Marketplace][mp]'s pre-submission security
scan on 19 August 2026, at commit `d55e9dc`, and re-checked after the rename to
Glow Studio, which moved names and paths without changing what the plugin does.

**This is a self-review, not a marketplace audit.** Nobody from the marketplace
has reviewed this repository. Omarchy plugins run unsandboxed as upstream code,
so no scan — this one included — makes a plugin safe. It is published so you can
check the claims rather than take them.

**No code changes were needed.** What the scan confirmed:

- No network access of any kind — no URLs, no remote images, no downloads.
- No shell strings. The four external commands it runs, `notify-send`,
  `mkdir`, `find`, and `omarchy`, are passed as argument arrays; the only
  arguments that vary are the wallpaper's own file path, which the plugin just
  wrote, and the fixed name pattern `find` matches its renders by.
- Three paths are written, all listed under [Requirements](#requirements), and
  nothing outside them.
- No credentials, no privileged commands, no bundled binaries, no dependencies
  beyond what Omarchy already ships.

Found something this missed? Report it privately through the marketplace's
[security policy][sec], or open an issue here.

[mp]: https://github.com/omacom/omarchy-plugin-marketplace
[sec]: https://github.com/omacom/omarchy-plugin-marketplace/blob/main/SECURITY.md

## License

MIT
