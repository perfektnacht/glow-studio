import Quickshell
import Quickshell.Io
import QtQuick
import qs.Commons
import "Board.js" as Board

// Glow Studio — a peg board you draw on with colored lights, in an ordinary
// resizable window.
//
// The board is a fixed 111x62 logical grid rather than one sized to the
// window: a fixed grid means a saved board reopens identically at a different
// window size or on a different display, and it guarantees the OMARCHY
// wordmark always fits. Cell size is whatever makes that grid fill the space
// the window currently has.
//
// Everything is painted into one Canvas. ~6900 QML Rectangles would be
// hopeless, and the board is static between edits, so a Canvas with
// dirty-rect repaints costs exactly nothing while it sits there — an edit
// repaints only the cells it touched plus a glow margin.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  readonly property string pluginId: (manifest && manifest.id) || "perfektnacht.glow-studio"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/omarchy"
  readonly property string statePath: stateDir + "/glow-studio.json"

  // Where the wallpaper render lives. One fixed path rather than a fresh
  // timestamped file per apply: `omarchy theme bg set` records a symlink to
  // the file it is handed, so it has to stay put to still be the background
  // tomorrow, and overwriting it in place keeps old renders from piling up
  // in the state directory.
  readonly property string wallpaperPath: stateDir + "/glow-studio-wallpaper.png"

  // Pre-rename location. Read once, only if the current file is absent, so a
  // board drawn under the plugin's previous name survives the rename.
  readonly property string legacyStatePath: home + "/.local/state/omarchy/lite-brite.json"
  property string migrateFrom: ""

  // ------------------------------------------------------------ board model

  readonly property int cols: 111
  readonly property int rows: 62

  // Uint8Array of peg values, 0 = empty. Mutated in place: nothing binds to
  // it, repaints are driven explicitly, and copying 6900 bytes per peg would
  // be silly.
  property var cells: Board.logoBoard(cols, rows)

  // False until the saved board has resolved, so we never flash the logo over
  // someone's drawing on the way in.
  property bool restored: false

  // ---------------------------------------------------------- tool state

  property int activeColor: Board.LOGO_COLOR
  property bool eraser: false
  property int brushIndex: 0
  // Disc radii, chosen so each step is visibly wider than the last: 1, 3, 5,
  // and 7 pegs across. Radii past ~2.7 stop reading as discs (the corner test
  // passes and the footprint degenerates into a filled square), so the top of
  // the ladder is 3.2 rather than something rounder-sounding.
  readonly property var brushRadii: [0, 1, 2, 3.2]
  readonly property real brushRadius: brushRadii[brushIndex]

  // The footprints, built once. stamp() runs for every cell a Bresenham line
  // visits, on every motion event, so recomputing the disc there was churning
  // ~37 short-lived arrays per cell at the largest brush.
  readonly property var brushFootprints: brushRadii.map(function(r) { return Board.brushOffsets(r) })

  // Lock Brush mode: while it's on, the brush behaves as if the button
  // were held down — moving the pointer over the board paints, with no
  // click. Locked rather than hovered: nothing hovers on a laptop trackpad,
  // but a locked brush reads the way tap-lock does. The wheel keeps its own
  // job and still resizes the brush.
  property bool brushLocked: false

  // True from the first motion of a locked sweep until the pointer leaves
  // the board or rests, so a whole sweep lands in the journal as one
  // stroke — the same single-undo guarantee a drag has.
  property bool lockStrokeOpen: false

  property var undoStack: []
  property var redoStack: []

  // Non-null while a stroke is in progress; a flat [index, previousValue, ...]
  // journal so one drag undoes as one action.
  property var strokeJournal: null
  property int lastCol: -1
  property int lastRow: -1

  // The focus cell — where the brush lands. Pointer motion moves it and so do
  // the arrow keys: one cursor with two ways to steer it, so the ring can
  // never disagree with itself about where a click would go.
  property int cursorCol: Math.floor(cols / 2)
  property int cursorRow: Math.floor(rows / 2)

  // True once the keyboard has taken the cursor, false again the moment the
  // pointer moves. Decides whether the ring stays put with the mouse parked
  // off the board.
  property bool keyboardCursor: false

  // ------------------------------------------------------------- geometry

  readonly property int outerMargin: Style.space(28)
  readonly property int framePadding: Style.space(10)
  readonly property int stackGap: Style.space(14)

  readonly property int availableWidth: panel.width - outerMargin * 2 - framePadding * 2
  readonly property int availableHeight: panel.height - outerMargin * 2 - framePadding * 2
    - toolbar.height - stackGap

  readonly property int cell: Math.max(3, Math.floor(Math.min(
    availableWidth / cols, availableHeight / rows)))
  readonly property int boardWidth: cell * cols
  readonly property int boardHeight: cell * rows

  // How far a peg's glow reaches, in cells. Both the dirty rect we mark and
  // the cell range we repaint have to allow for it, or strokes leave square
  // scars where a neighbor's halo used to be.
  readonly property int glowCells: 3

  // OLED mode drops the board to true #000000 so the panel actually switches
  // those pixels off — most of the board is unlit, so it's most of
  // the image. The bevel ring survives, dimmed, or it stops reading as a peg
  // board at all. Applies to the screen as well as the export: the preview
  // should be what you get.
  property bool oled: false

  readonly property string backingHex: root.oled ? "#000000" : "#08080b"
  readonly property string bevelHex: root.oled ? "#14141a" : "#191920"
  readonly property string wellHex: root.oled ? "#000000" : "#020203"

  readonly property color boardBacking: root.backingHex

  onOledChanged: board.requestPaint()

  // ---------------------------------------------------------- export size

  property int exportPreset: 1   // 4K

  readonly property var exportPresets: [
    { label: "2K", width: 2560, height: 1440 },
    { label: "4K", width: 3840, height: 2160 },
    { label: "6K", width: 5760, height: 3240 }
  ]

  // Device pixels per logical pixel, as grabToImage actually applies it.
  // Measured by grabProbe below rather than read from a property; 0 until
  // that lands, which the export treats as 1.
  property real grabScale: 0

  // ---------------------------------------------------------- plugin API

  function open(payloadJson) {
    panel.closingFromHost = false
    root.opened = true
    root.cursorCol = Math.floor(root.cols / 2)
    root.cursorRow = Math.floor(root.rows / 2)
    root.keyboardCursor = false
    // Not keepLoaded, so this normally races the fresh FileView preload and
    // loses; reload() covers the keepLoaded case and any stale mount.
    if (root.restored) boardFile.reload()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.flushSave()
    panel.closingFromHost = true
    root.opened = false
  }

  function dismiss() {
    root.flushSave()
    // Hide the window now so dismissal feels instant, but let the shell tear
    // the plugin down a beat later — destroying the item out from under an
    // in-flight atomic write would lose the last stroke.
    panel.closingFromHost = true
    root.opened = false
    unloadTimer.restart()
  }

  function toggle() {
    if (root.opened) root.dismiss()
    else root.open("{}")
  }

  Timer {
    id: unloadTimer
    interval: 200
    onTriggered: {
      if (root.shell && typeof root.shell.hide === "function") root.shell.hide(root.pluginId)
    }
  }

  // ------------------------------------------------------------ mutation

  function indexOf(col, row) { return row * root.cols + col }

  function setCell(col, row, value) {
    if (col < 0 || col >= root.cols || row < 0 || row >= root.rows) return
    var i = root.indexOf(col, row)
    if (root.cells[i] === value) return
    if (root.strokeJournal) root.strokeJournal.push(i, root.cells[i])
    root.cells[i] = value
    root.touch(col, row)
  }

  // The peg value a brush lays down: a color, or 0 to clear the hole.
  readonly property int brushValue: root.eraser ? 0 : root.activeColor

  function stamp(col, row) {
    var offsets = root.brushFootprints[root.brushIndex]
    var value = root.brushValue
    for (var i = 0; i < offsets.length; i++) {
      root.setCell(col + offsets[i][0], row + offsets[i][1], value)
    }
  }

  // Arrow keys. One cell per press; autorepeat handles holding it down.
  function moveCursor(dx, dy) {
    root.keyboardCursor = true
    root.cursorCol = Math.max(0, Math.min(root.cols - 1, root.cursorCol + dx))
    root.cursorRow = Math.max(0, Math.min(root.rows - 1, root.cursorRow + dy))
  }

  // Enter, doing exactly what a left click does: stamp the brush at the
  // cursor as one undoable action. Shift extends from the last stroke's end,
  // mirroring shift+click.
  function pressCursor(extend) {
    root.keyboardCursor = true
    root.beginStroke(root.cursorCol, root.cursorRow, extend)
    root.endStroke()
  }

  // One pointer motion with the brush locked and no button held: the same
  // stamp a drag would make, at the pointer. Consecutive motions go
  // through extendStroke, so a sweep draws a continuous line rather than a
  // dotted one.
  function lockStamp() {
    if (root.lockStrokeOpen) {
      root.extendStroke(root.cursorCol, root.cursorRow)
    } else {
      // Flag after beginStroke, not before: beginStroke closes any open
      // locked stroke on the way in, and it must not close this one.
      root.beginStroke(root.cursorCol, root.cursorRow, false)
      root.lockStrokeOpen = true
    }
    lockStrokeEnd.restart()
  }

  // Ends the locked sweep when the pointer rests. 300ms is short enough
  // that the stroke finishes as soon as the motion does, and long enough
  // that a deliberate slow trace still lands as one action. Leaving the
  // board ends the stroke immediately, without waiting out the timer.
  function endLockStroke() {
    if (!root.lockStrokeOpen) return
    root.lockStrokeOpen = false
    lockStrokeEnd.stop()
    root.endStroke()
  }

  Timer {
    id: lockStrokeEnd
    interval: 300
    onTriggered: root.endLockStroke()
  }

  function beginStroke(col, row, connect) {
    // A click or Enter mid-sweep takes the board over: close the open
    // locked stroke as its own undo action first, or its journal is dropped
    // when the next line resets it.
    root.endLockStroke()
    root.strokeJournal = []
    if (connect && root.lastCol >= 0) root.extendStroke(col, row)
    else root.stamp(col, row)
    root.lastCol = col
    root.lastRow = row
    root.flushDirty()
  }

  function extendStroke(col, row) {
    Board.line(root.lastCol, root.lastRow, col, row, function(x, y) { root.stamp(x, y) })
    root.lastCol = col
    root.lastRow = row
    root.flushDirty()
  }

  function endStroke() {
    var journal = root.strokeJournal
    root.strokeJournal = null
    if (!journal || journal.length === 0) return
    var stack = root.undoStack.slice()
    stack.push(journal)
    if (stack.length > 60) stack.shift()
    root.undoStack = stack
    root.redoStack = []
    root.scheduleSave()
  }

  // Apply a journal in reverse, returning the inverse journal so undo and
  // redo are the same operation pointed the other way.
  function applyJournal(journal) {
    var inverse = []
    for (var i = journal.length - 2; i >= 0; i -= 2) {
      var index = journal[i]
      inverse.push(index, root.cells[index])
      root.cells[index] = journal[i + 1]
      root.touch(index % root.cols, Math.floor(index / root.cols))
    }
    root.flushDirty()
    root.scheduleSave()
    return inverse
  }

  function undo() {
    if (root.undoStack.length === 0) return
    var stack = root.undoStack.slice()
    var journal = stack.pop()
    root.undoStack = stack
    var redo = root.redoStack.slice()
    redo.push(root.applyJournal(journal))
    root.redoStack = redo
  }

  function redo() {
    if (root.redoStack.length === 0) return
    var stack = root.redoStack.slice()
    var journal = stack.pop()
    root.redoStack = stack
    var undoNext = root.undoStack.slice()
    undoNext.push(root.applyJournal(journal))
    root.undoStack = undoNext
  }

  // Whole-board replacements go through one journal so a mis-clicked Clear is
  // a single Ctrl+Z away.
  function replaceBoard(next) {
    var journal = []
    for (var i = 0; i < root.cells.length; i++) {
      if (root.cells[i] !== next[i]) {
        journal.push(i, root.cells[i])
        root.cells[i] = next[i]
      }
    }
    if (journal.length === 0) return
    var stack = root.undoStack.slice()
    stack.push(journal)
    if (stack.length > 60) stack.shift()
    root.undoStack = stack
    root.redoStack = []
    board.requestPaint()
    root.scheduleSave()
  }

  function clearBoard() { root.replaceBoard(Board.newBoard(root.cols, root.rows)) }
  function restoreLogo() { root.replaceBoard(Board.logoBoard(root.cols, root.rows)) }

  // ------------------------------------------------------- dirty tracking

  property int dirtyLeft: -1
  property int dirtyTop: 0
  property int dirtyRight: 0
  property int dirtyBottom: 0

  function touch(col, row) {
    if (root.dirtyLeft < 0) {
      root.dirtyLeft = col; root.dirtyRight = col
      root.dirtyTop = row; root.dirtyBottom = row
      return
    }
    if (col < root.dirtyLeft) root.dirtyLeft = col
    if (col > root.dirtyRight) root.dirtyRight = col
    if (row < root.dirtyTop) root.dirtyTop = row
    if (row > root.dirtyBottom) root.dirtyBottom = row
  }

  function flushDirty() {
    if (root.dirtyLeft < 0) return
    var pad = root.glowCells
    var left = Math.max(0, root.dirtyLeft - pad)
    var top = Math.max(0, root.dirtyTop - pad)
    var right = Math.min(root.cols - 1, root.dirtyRight + pad)
    var bottom = Math.min(root.rows - 1, root.dirtyBottom + pad)
    root.dirtyLeft = -1
    board.markDirty(Qt.rect(left * root.cell, top * root.cell,
                            (right - left + 1) * root.cell,
                            (bottom - top + 1) * root.cell))
  }

  // ------------------------------------------------------------ painting

  // A self-contained description of one paint. The export canvas rasterizes on
  // its own thread, where reaching back into QML properties is not safe, so
  // everything the painter needs is snapshotted into plain JS up front. It
  // also gives the export the right semantic for free: you get the board as it
  // was when you hit Export, even if you keep drawing while it renders.
  function boardSpec(cell, originX, originY, copyCells) {
    return {
      cells: copyCells ? new Uint8Array(root.cells) : root.cells,
      cols: root.cols,
      rows: root.rows,
      cell: cell,
      originX: originX,
      originY: originY,
      glowCells: root.glowCells,
      backing: root.backingHex,
      bevel: root.bevelHex,
      well: root.wellHex
    }
  }

  // One painter for both the screen and every export resolution. `spec.cell` is
  // the peg pitch in pixels and `spec.originX/originY` is where cell (0,0)
  // starts, so an export can use a bigger pitch and inset the grid to center it.
  //
  // Holes are drawn for *every* grid position the region covers, including
  // negative columns and rows past the board — that's what lets an export fill
  // a canvas wider than cols*cell with more peg board rather than a bare
  // margin. Only lit pegs are bounds-checked against the board.
  function paintBoard(ctx, region, spec) {
    var cell = spec.cell
    var originX = spec.originX, originY = spec.originY
    var cells = spec.cells, cols = spec.cols, rows = spec.rows
    if (cell <= 0) return

    var x0 = region.x, y0 = region.y
    var x1 = region.x + region.width, y1 = region.y + region.height

    ctx.save()
    ctx.beginPath()
    ctx.rect(x0, y0, region.width, region.height)
    ctx.clip()

    ctx.fillStyle = spec.backing
    ctx.fillRect(x0, y0, region.width, region.height)

    // Two cell ranges, because the passes need different reach.
    //
    // Holes are drawn at 0.30 * cell and never leave the cell they belong to,
    // so the hole passes only need the cells the region actually covers.
    var hc0 = Math.floor((x0 - originX) / cell)
    var hr0 = Math.floor((y0 - originY) / cell)
    var hc1 = Math.ceil((x1 - originX) / cell)
    var hr1 = Math.ceil((y1 - originY) / cell)
    //
    // Lit pegs do reach past their own cell, so the peg pass has to consider
    // every cell whose glow can land inside the region and let the clip
    // discard the rest. Applying that margin to the holes too was drawing 169
    // of them to show 49.
    var pad = spec.glowCells
    var c0 = hc0 - pad
    var r0 = hr0 - pad
    var c1 = hc1 + pad
    var r1 = hr1 + pad

    var tau = Math.PI * 2
    var holeR = cell * 0.30
    var pegR = cell * 0.34

    // Empty holes, batched into two paths. This is the pass that runs over
    // every cell on a full repaint, so it has to be one fill, not 6900.
    ctx.fillStyle = spec.bevel
    ctx.beginPath()
    for (var row = hr0; row <= hr1; row++) {
      for (var col = hc0; col <= hc1; col++) {
        var hx = originX + col * cell + cell / 2
        var hy = originY + row * cell + cell / 2
        ctx.moveTo(hx + holeR, hy)
        ctx.arc(hx, hy, holeR, 0, tau)
      }
    }
    ctx.fill()

    ctx.fillStyle = spec.well
    ctx.beginPath()
    for (row = hr0; row <= hr1; row++) {
      for (col = hc0; col <= hc1; col++) {
        var wx = originX + col * cell + cell / 2 - holeR * 0.10
        var wy = originY + row * cell + cell / 2 - holeR * 0.10
        ctx.moveTo(wx + holeR * 0.86, wy)
        ctx.arc(wx, wy, holeR * 0.86, 0, tau)
      }
    }
    ctx.fill()

    // Bucket the lit pegs by color so each color's five glow rings, body,
    // dome, and highlight are eight fills total instead of eight per peg.
    var pc0 = Math.max(0, c0), pc1 = Math.min(cols - 1, c1)
    var pr0 = Math.max(0, r0), pr1 = Math.min(rows - 1, r1)
    var buckets = {}
    for (row = pr0; row <= pr1; row++) {
      var rowBase = row * cols
      for (col = pc0; col <= pc1; col++) {
        var value = cells[rowBase + col]
        if (value === 0) continue
        var bucket = buckets[value]
        if (!bucket) { bucket = []; buckets[value] = bucket }
        bucket.push(originX + col * cell + cell / 2, originY + row * cell + cell / 2)
      }
    }

    function fillDiscs(points, radius, offsetX, offsetY) {
      ctx.beginPath()
      for (var i = 0; i < points.length; i += 2) {
        var px = points[i] + offsetX
        var py = points[i + 1] + offsetY
        ctx.moveTo(px + radius, py)
        ctx.arc(px, py, radius, 0, tau)
      }
      ctx.fill()
    }

    // Stacked translucent discs stand in for a per-peg radial gradient. They
    // batch, and overlapping halos accumulate — dense areas of the drawing
    // bloom, which is exactly what the real toy does.
    var glowRings = [[2.9, 0.05], [2.4, 0.055], [1.95, 0.07], [1.55, 0.09], [1.25, 0.12]]

    for (var key in buckets) {
      var points = buckets[key]
      var hex = Board.paletteHex(parseInt(key))

      for (var g = 0; g < glowRings.length; g++) {
        ctx.fillStyle = Board.rgba(hex, glowRings[g][1])
        fillDiscs(points, pegR * glowRings[g][0], 0, 0)
      }

      ctx.fillStyle = Board.shade(hex, 0.72)
      fillDiscs(points, pegR, 0, 0)

      ctx.fillStyle = hex
      fillDiscs(points, pegR * 0.82, -pegR * 0.06, -pegR * 0.08)

      ctx.fillStyle = Board.shade(hex, 1.55)
      fillDiscs(points, pegR * 0.42, -pegR * 0.18, -pegR * 0.22)

      ctx.fillStyle = "rgba(255,255,255,0.75)"
      fillDiscs(points, pegR * 0.17, -pegR * 0.26, -pegR * 0.30)
    }

    ctx.restore()
  }

  // ---------------------------------------------------------- persistence

  function scheduleSave() { saveTimer.restart() }

  function flushSave() {
    saveTimer.stop()
    if (!root.restored) return
    var payload = Board.encode(root.cells, root.cols, root.rows)
    payload.exportPreset = root.exportPreset
    payload.oled = root.oled
    boardFile.setText(JSON.stringify(payload) + "\n")
  }

  function restore(raw) {
    var parsed = null
    if (raw && raw.length > 0) {
      try { parsed = JSON.parse(raw) } catch (e) { parsed = null }
    }
    var decoded = parsed ? Board.decode(parsed, root.cols, root.rows) : null

    // The board can fail to decode (a grid-size change, say) while the export
    // settings are still perfectly good, so they're restored independently.
    if (parsed && typeof parsed.exportPreset === "number") {
      root.exportPreset = Math.max(0, Math.min(root.exportPresets.length - 1,
                                               Math.round(parsed.exportPreset)))
    }
    if (parsed && typeof parsed.oled === "boolean") root.oled = parsed.oled

    root.cells = decoded || Board.logoBoard(root.cols, root.rows)
    root.undoStack = []
    root.redoStack = []
    root.restored = true
    board.requestPaint()
  }

  Timer {
    id: saveTimer
    interval: 300
    onTriggered: root.flushSave()
  }

  FileView {
    id: boardFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.restore(text())
    // First run: no file yet — but before falling back to the logo, look for a
    // board saved under the plugin's previous name. A failure *after* we're
    // restored is a transient read problem on reopen — keep the board that's
    // already in memory rather than resetting someone's drawing to the logo.
    onLoadFailed: if (!root.restored) root.migrateFrom = root.legacyStatePath
  }

  // Only ever touched when boardFile reported the current path missing, so it
  // can't race the load above: its path stays empty until that happens, and an
  // empty path reads nothing. The legacy file is left on disk rather than
  // deleted — flushSave() writes the board to the new path from here on.
  FileView {
    id: legacyBoardFile
    path: root.migrateFrom
    watchChanges: false
    printErrors: false
    onLoaded: {
      if (root.restored) return
      root.restore(text())
      root.flushSave()
    }
    onLoadFailed: if (root.migrateFrom !== "" && !root.restored) root.restore("")
  }

  // ------------------------------------------------------------- export

  // Exports are re-rendered at the target resolution rather than scaled up
  // from the screen: the board is vector-ish (discs on a grid), so painting it
  // again at a bigger peg pitch costs one repaint and gives clean edges, where
  // upscaling a 2220px grab to 6K would just be a blurry 2220px grab.
  function exportPng(forWallpaper) {
    if (exportLoader.active) return   // one at a time; 6K is 75MB of buffer
    exportProc.wallpaper = forWallpaper
    exportProc.outputPath = forWallpaper
      ? root.wallpaperPath
      : root.home + "/Pictures/glow-studio-"
        + root.exportPresets[root.exportPreset].label.toLowerCase() + "-"
        + Qt.formatDateTime(new Date(), "yyyyMMdd-HHmmss") + ".png"
    exportProc.command = ["mkdir", "-p",
      forWallpaper ? root.stateDir : root.home + "/Pictures"]
    exportProc.running = true
  }

  function reportExport(ok, path) {
    var preset = root.exportPresets[root.exportPreset]
    Quickshell.execDetached(["notify-send", "-a", "Glow Studio",
      ok ? "Board exported at " + preset.width + "×" + preset.height : "Export failed",
      ok ? path : "Could not write " + path])
  }

  // Hand a finished wallpaper render to Omarchy's own background command
  // rather than reaching into Hyprland or the theme system from here:
  // `omarchy theme bg set` does both halves — points the shell's background
  // symlink at the file, and updates the running desktop — so the wallpaper
  // sticks across reboots and keeps working with the background switcher
  // afterwards.
  function applyWallpaper(ok, path) {
    if (!ok) {
      Quickshell.execDetached(["notify-send", "-a", "Glow Studio",
        "Wallpaper not set", "Could not write " + path])
      return
    }
    wallpaperProc.imagePath = path
    wallpaperProc.command = ["omarchy", "theme", "bg", "set", path]
    wallpaperProc.running = true
  }

  Process {
    id: exportProc
    property string outputPath: ""
    property bool wallpaper: false
    command: ["mkdir", "-p", root.home + "/Pictures"]
    onExited: exportLoader.active = true
  }

  Process {
    id: wallpaperProc
    // The path currently being applied, so the completion notification can
    // say what landed where.
    property string imagePath: ""
    command: ["omarchy", "theme", "bg", "set", ""]
    onExited: function(exitCode) {
      Quickshell.execDetached(["notify-send", "-a", "Glow Studio",
        exitCode === 0 ? "Wallpaper set" : "Wallpaper not set",
        exitCode === 0 ? imagePath : "omarchy theme bg set exited with " + exitCode])
    }
  }

  // The component the export Loader instantiates. The Loader itself lives
  // inside the PanelWindow: grabToImage needs the item to be in a scene graph,
  // and this plugin's root Item is not itself in a window — only the panel is.
  Component {
    id: exportCanvasComponent

    Canvas {
      readonly property var preset: root.exportPresets[root.exportPreset]
      // Largest peg pitch at which the whole board still fits. Floor, not
      // round: overshooting would crop pegs off the edges of someone's
      // drawing, and the leftover margin costs nothing because the painter
      // fills it with more peg board.
      readonly property int exportCell: Math.max(1, Math.floor(Math.min(
        preset.width / root.cols, preset.height / root.rows)))

      // Snapshotted on the GUI thread at construction, before any painting
      // starts. See boardSpec().
      property var spec: root.boardSpec(
        exportCell,
        Math.round((preset.width - root.cols * exportCell) / 2),
        Math.round((preset.height - root.rows * exportCell) / 2),
        true)

      property bool grabbed: false

      visible: false
      width: preset.width
      height: preset.height
      renderTarget: Canvas.Image
      // Threaded, not the default Cooperative. Rasterizing 18.7 megapixels on
      // the scene-graph thread stalls the entire shell for over a second at
      // 6K; measured here, moving it to its own thread takes the worst
      // main-thread gap from ~1250ms to ~20ms for identical output.
      renderStrategy: Canvas.Threaded

      onPaint: function(region) {
        root.paintBoard(getContext("2d"), Qt.rect(0, 0, width, height), spec)
      }

      // onPainted can fire more than once; the grab must not.
      onPainted: {
        if (grabbed) return
        grabbed = true
        var path = exportProc.outputPath
        // The target size is in logical pixels, because grabToImage
        // multiplies it by the display scale on the way out — the same
        // multiplication that made an unqualified grab of this canvas come
        // back at 4800x2700. Dividing first lands the file on the preset
        // exactly. The canvas itself stays at full preset size, so those
        // extra pixels the scaled render already paid for come back as
        // supersampling rather than going to waste.
        var scale = root.grabScale > 0 ? root.grabScale : 1
        var started = grabToImage(function(result) {
          var ok = result.saveToFile(path)
          if (exportProc.wallpaper) root.applyWallpaper(ok, path)
          else root.reportExport(ok, path)
          exportLoader.active = false
        }, Qt.size(Math.round(preset.width / scale),
                   Math.round(preset.height / scale)))
        if (!started) {
          if (exportProc.wallpaper) root.applyWallpaper(false, path)
          else root.reportExport(false, path)
          exportLoader.active = false
        }
      }

      Component.onCompleted: requestPaint()
    }
  }

  // ---------------------------------------------------------------- shell

  // A normal toplevel, not a layer-shell surface. As a PanelWindow anchored to
  // all four edges on the Overlay layer this was drawn above everything and
  // was present on every workspace at once, because layer surfaces belong to
  // the output rather than to a workspace — there was no way to put it behind
  // anything, move it, or leave it running on one desktop while you used
  // another. A FloatingWindow is tiled, floated, moved and closed by the
  // window manager like any other application window.
  FloatingWindow {
    id: panel

    visible: root.opened
    title: "Glow Studio"
    color: Color.menu.background

    // Enough to show the board at a usable peg pitch without covering the
    // screen; the window manager is free to override both.
    implicitWidth: 1280
    implicitHeight: 860
    // Below this the toolbar wraps to more rows than the board is tall.
    minimumSize: Qt.size(560, 460)

    // The window manager closes this one too — a titlebar button, a keybind,
    // or `hyprctl dispatch killactive`. Route that back through the host so
    // the shell drops the plugin instead of leaving it loaded and invisible.
    property bool closingFromHost: false
    onVisibleChanged: {
      if (visible || panel.closingFromHost) return
      root.flushSave()
      root.opened = false
      unloadTimer.restart()
    }

    // Only mounted while an export is running — at 6K the canvas image buffer
    // alone is ~75MB before the display scale, and more after it, which is not
    // something to keep around for a toy. It's invisible, so a 6K canvas never
    // flashes on screen.
    Loader {
      id: exportLoader
      active: false
      sourceComponent: exportCanvasComponent
    }

    // grabToImage renders an item at its size in *device* pixels, so an export
    // came back multiplied by the display scale: the 4K preset wrote 4800x2700
    // on a 1.25x monitor, contradicting the README, the preset labels and the
    // whole point of re-rendering at a fixed target size.
    //
    // The scale has to be measured rather than read. The ratios QML exposes
    // are the rounded integer one — Screen.devicePixelRatio and the Quickshell
    // screen both report 2 on a 1.25x output — while grabs use the fractional
    // scale the compositor actually set, and nothing exposes that number. So
    // grab a small probe of a known logical size and divide. It costs one
    // 64x64 grab per window, and the window has to be open to export anyway.
    //
    // Measured once, when the window opens. Dragging the window to a display
    // with a different scale and exporting without reopening would fall back
    // to the stale ratio.
    Item {
      id: grabProbe

      readonly property int side: 64

      // Holds the grab result alive until the Image has read its size.
      property var held: null

      Canvas {
        visible: false
        width: grabProbe.side
        height: grabProbe.side
        renderTarget: Canvas.Image

        property bool grabbed: false

        onPaint: {
          var ctx = getContext("2d")
          ctx.fillStyle = "#ffffff"
          ctx.fillRect(0, 0, width, height)
        }

        // A grab only succeeds once the item has really rendered, which is why
        // this hangs off onPainted instead of Component.onCompleted.
        onPainted: {
          if (grabbed) return
          grabbed = true
          grabToImage(function(result) {
            grabProbe.held = result
            grabProbeImage.source = result.url
          })
        }

        Component.onCompleted: requestPaint()
      }

      Image {
        id: grabProbeImage
        visible: false
        cache: false
        onStatusChanged: {
          if (status !== Image.Ready) return
          root.grabScale = implicitWidth / grabProbe.side
          grabProbe.held = null
        }
      }
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        var shift = (event.modifiers & Qt.ShiftModifier) !== 0

        if (event.key === Qt.Key_Escape) {
          root.dismiss()
        } else if (event.key === Qt.Key_Left) {
          root.moveCursor(-1, 0)
        } else if (event.key === Qt.Key_Right) {
          root.moveCursor(1, 0)
        } else if (event.key === Qt.Key_Up) {
          root.moveCursor(0, -1)
        } else if (event.key === Qt.Key_Down) {
          root.moveCursor(0, 1)
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          root.pressCursor(shift)
        } else if (ctrl && event.key === Qt.Key_Z && shift) {
          root.redo()
        } else if (ctrl && event.key === Qt.Key_Z) {
          root.undo()
        } else if (ctrl && (event.key === Qt.Key_Y)) {
          root.redo()
        } else if (ctrl && event.key === Qt.Key_S) {
          root.exportPng(false)
        } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_8) {
          root.activeColor = event.key - Qt.Key_1 + 1
          root.eraser = false
        } else if (event.key === Qt.Key_E || event.key === Qt.Key_0) {
          root.eraser = !root.eraser
        } else if (event.key === Qt.Key_BracketLeft) {
          root.brushIndex = Math.max(0, root.brushIndex - 1)
        } else if (event.key === Qt.Key_BracketRight) {
          root.brushIndex = Math.min(root.brushRadii.length - 1, root.brushIndex + 1)
        } else if (event.key === Qt.Key_K) {
          root.brushLocked = !root.brushLocked
        } else if (event.key === Qt.Key_C) {
          root.clearBoard()
        } else if (event.key === Qt.Key_L) {
          root.restoreLogo()
        } else {
          return
        }
        event.accepted = true
      }
    }

    // The toolbar spans the window and the board is centred above it, rather
    // than the two being stacked at the board's width. That keeps the
    // toolbar's height a function of the *window* width only: it wraps when
    // the window is narrow, and because the board's cell size is derived from
    // the height the toolbar leaves behind, letting the toolbar's width depend
    // on the board would close that circle into a binding loop.
    Item {
      id: content
      anchors.fill: parent
      anchors.margins: root.outerMargin

      // ------------------------------------------------------- the board

      Rectangle {
        id: frame
        width: root.boardWidth + root.framePadding * 2
        height: root.boardHeight + root.framePadding * 2
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(0, Math.round(
          (parent.height - toolbar.height - root.stackGap - height) / 2))
        radius: Style.cornerRadius > 0 ? Style.cornerRadius + root.framePadding : 0
        color: "#0c0c11"
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(Color.foreground, 0.18)

        // The board is a grid of Canvas tiles, not one Canvas.
        //
        // Qt uploads a Canvas.Image canvas to the GPU as a single texture, and
        // marking any part of it dirty re-uploads the whole thing. That upload
        // happens in the scene graph's sync phase, on the GUI thread, so every
        // repaint blocked input for as long as the upload took. Measured under
        // quickshell with QSG_RENDER_TIMING on a 1665x930 board, a six-second
        // drag spent 2635ms of its 2783ms of frame time in sync and managed 73
        // frames; the same drag with these tiles spends 0ms in sync and gets
        // 281 frames, with the worst single frame down from 109ms to 4ms.
        //
        // Tiling works because a stroke only ever dirties the few tiles it
        // touches, so the bytes re-uploaded scale with the size of the edit
        // rather than the size of the board. paintBoard already takes a grid
        // origin, so a tile is just the same painter with its origin shifted;
        // it draws any lit peg whose glow reaches into its region, which is
        // what keeps glow continuous across a tile seam.
        Item {
          id: board

          x: root.framePadding
          y: root.framePadding
          width: root.boardWidth
          height: root.boardHeight

          // Each tile paints on its own render thread and finishes on its own
          // schedule, so revealing the board the moment the state file decodes
          // shows it arriving a piece at a time. Wait until every tile has
          // painted the restored cells, then fade the whole board in as one.
          property int tilesPainted: 0
          property bool revealOverdue: false
          opacity: root.restored && (tilesPainted >= tilesX * tilesY || revealOverdue)
                   ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 140 } }

          // A tile that never reports a paint must not leave the board
          // invisible, so the reveal has a deadline as well as a condition.
          Timer {
            interval: 600
            running: root.restored && !board.revealOverdue
                     && board.tilesPainted < board.tilesX * board.tilesY
            onTriggered: board.revealOverdue = true
          }

          // Enough tiles that one stroke touches a small fraction of the
          // board, few enough that a full repaint isn't 24 separate uploads
          // of trivial size.
          readonly property int tilesX: 6
          readonly property int tilesY: 4

          // The two calls the rest of the file makes, fanned out over tiles so
          // callers keep talking to `board` as though it were still a Canvas.
          function requestPaint() {
            for (var i = 0; i < tiles.count; i++) {
              var t = tiles.itemAt(i)
              if (t) t.requestPaint()
            }
          }

          function markDirty(rect) {
            for (var i = 0; i < tiles.count; i++) {
              var t = tiles.itemAt(i)
              if (!t) continue
              var rx = rect.x - t.x
              var ry = rect.y - t.y
              if (rx + rect.width < 0 || ry + rect.height < 0
                  || rx > t.width || ry > t.height) continue
              t.markDirty(Qt.rect(rx, ry, rect.width, rect.height))
            }
          }

          Repeater {
            id: tiles
            model: board.tilesX * board.tilesY

            Canvas {
              required property int index

              readonly property int tx: index % board.tilesX
              readonly property int ty: Math.floor(index / board.tilesX)
              // Edges are computed from the neighbouring boundary rather than
              // from a tile width, so rounding can never open a seam between
              // two tiles or run the last one past the board.
              readonly property int px: Math.round(tx * board.width / board.tilesX)
              readonly property int py: Math.round(ty * board.height / board.tilesY)

              x: px
              y: py
              width: Math.round((tx + 1) * board.width / board.tilesX) - px
              height: Math.round((ty + 1) * board.height / board.tilesY) - py

              renderTarget: Canvas.Image
              renderStrategy: Canvas.Threaded

              // Counted once per tile, and only once the cells are restored,
              // so the empty board painted at startup can't tick the reveal
              // forward before there is anything to show.
              property bool everPainted: false
              onPainted: {
                if (root.restored && !everPainted) {
                  everPainted = true
                  board.tilesPainted++
                }
              }

              // Same painter as the export, with the grid origin pulled back
              // by this tile's position so cell (0,0) still lands at the
              // board's corner.
              onPaint: function(region) {
                var target = (region && region.width > 0)
                  ? region : Qt.rect(0, 0, width, height)
                root.paintBoard(getContext("2d"), target,
                                root.boardSpec(root.cell, -px, -py, false))
              }

              onWidthChanged: requestPaint()
              onHeightChanged: requestPaint()
            }
          }

          MouseArea {
            id: drawArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.BlankCursor
            preventStealing: true

            // Right-drag erases without switching tools, the way a thumb over
            // the pegs does on the real board.
            property bool erasingWithRight: false

            // Pointer motion takes the cursor back from the keyboard.
            function track(mouse) {
              root.keyboardCursor = false
              root.cursorCol = Math.max(0, Math.min(root.cols - 1, Math.floor(mouse.x / root.cell)))
              root.cursorRow = Math.max(0, Math.min(root.rows - 1, Math.floor(mouse.y / root.cell)))
            }

            onPressed: function(mouse) {
              track(mouse)
              erasingWithRight = mouse.button === Qt.RightButton
              if (erasingWithRight) root.eraser = true
              // Shift+click strokes a straight line from wherever the last
              // one ended — the cheap way to get clean geometry on a grid.
              root.beginStroke(root.cursorCol, root.cursorRow,
                               (mouse.modifiers & Qt.ShiftModifier) !== 0)
            }

            onPositionChanged: function(mouse) {
              var previousCol = root.cursorCol
              var previousRow = root.cursorRow
              track(mouse)
              if (pressed) {
                if (root.cursorCol === previousCol && root.cursorRow === previousRow) return
                root.extendStroke(root.cursorCol, root.cursorRow)
              } else if (root.brushLocked) {
                // A locked brush paints unpressed motion the way a drag
                // paints pressed motion.
                root.lockStamp()
              }
            }

            onReleased: function(mouse) {
              root.endStroke()
              if (erasingWithRight) {
                root.eraser = false
                erasingWithRight = false
              }
            }

            onWheel: function(wheel) {
              root.brushIndex = wheel.angleDelta.y > 0
                ? Math.min(root.brushRadii.length - 1, root.brushIndex + 1)
                : Math.max(0, root.brushIndex - 1)
            }

            // Leaving the board ends a locked sweep where it stands.
            onExited: root.endLockStroke()

            // Brush footprint at the cursor. A QML item rather than canvas
            // ink, so moving the cursor never repaints the board.
            Rectangle {
              // Exports render offscreen, so the ring never has to hide.
              visible: drawArea.containsMouse || root.keyboardCursor
              width: (root.brushRadius * 2 + 1.1) * root.cell
              height: width
              radius: width / 2
              x: (root.cursorCol + 0.5) * root.cell - width / 2
              y: (root.cursorRow + 0.5) * root.cell - height / 2
              color: "transparent"
              // Brighter while the keyboard is driving: there's no pointer
              // arrow to tell you where you are, so the ring is the only
              // thing marking the spot.
              border.width: Math.max(1, Style.space(root.keyboardCursor ? 2 : 1))
              border.color: root.eraser
                ? Qt.rgba(1, 1, 1, root.keyboardCursor ? 0.75 : 0.5)
                : Qt.rgba(1, 1, 1, root.keyboardCursor ? 0.6 : 0.32)

              // Snapping between cells looks broken at this size; a short
              // ease reads as the cursor travelling.
              Behavior on x { enabled: root.keyboardCursor; NumberAnimation { duration: 55 } }
              Behavior on y { enabled: root.keyboardCursor; NumberAnimation { duration: 55 } }
            }
          }
        }
      }

      // ----------------------------------------------------- the toolbar

      Rectangle {
        id: toolbar
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: controls.implicitHeight + Style.spacing.panelPadding * 2
        radius: Style.cornerRadius
        color: Color.menu.background
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(Color.menu.border, 0.5)

        Column {
          id: controls
          anchors.centerIn: parent
          width: parent.width - Style.spacing.panelPadding * 2
          spacing: Style.spacing.md

          // A Flow of labelled sections, not one flat Flow of controls: the
          // captions say what each cluster does, and because a section is a
          // single Flow child it wraps to the next line as a unit when the
          // window narrows, rather than spilling lone buttons across the
          // break. Flow positions its children, so nothing in here may
          // anchor itself — each control is given the shared control height
          // instead, which is what keeps a wrapped row aligned.
          Flow {
            width: parent.width
            spacing: Style.spacing.xl

            ToolbarSection {
              label: "Color"

              Repeater {
                model: Board.PALETTE
                Swatch {
                  required property var modelData
                  required property int index

                  pegColor: modelData.hex
                  selected: !root.eraser && root.activeColor === index + 1
                  height: Style.spacing.controlHeight
                  onClicked: {
                    root.activeColor = index + 1
                    root.eraser = false
                  }
                }
              }

              // The eraser, drawn as the peg it places: laying down an
              // unlit hole is effectively laying down a black peg, so it
              // sits at the end of the palette as what it is, rather than
              // apart from the colors as a text button.
              Swatch {
                pegColor: "#000000"
                selected: root.eraser
                height: Style.spacing.controlHeight
                onClicked: root.eraser = !root.eraser
              }
            }

            ToolbarSection {
              label: "Brush"

              Repeater {
                model: root.brushRadii.length
                ToolButton {
                  required property int index
                  label: String(index + 1)
                  active: root.brushIndex === index
                  height: Style.spacing.controlHeight
                  onClicked: root.brushIndex = index
                }
              }

              ToolButton {
                label: "Lock Brush"
                active: root.brushLocked
                height: Style.spacing.controlHeight
                onClicked: root.brushLocked = !root.brushLocked
              }
            }

            ToolbarSection {
              label: "Edit"

              ToolButton {
                label: "Undo"
                enabled: root.undoStack.length > 0
                height: Style.spacing.controlHeight
                onClicked: root.undo()
              }

              ToolButton {
                label: "Redo"
                enabled: root.redoStack.length > 0
                height: Style.spacing.controlHeight
                onClicked: root.redo()
              }

              ToolButton {
                label: "Clear"
                height: Style.spacing.controlHeight
                onClicked: root.clearBoard()
              }

              ToolButton {
                label: "Logo"
                height: Style.spacing.controlHeight
                onClicked: root.restoreLogo()
              }
            }

            ToolbarSection {
              label: "Wallpaper"

              Repeater {
                model: root.exportPresets
                ToolButton {
                  required property var modelData
                  required property int index

                  label: modelData.label
                  active: root.exportPreset === index
                  height: Style.spacing.controlHeight
                  onClicked: { root.exportPreset = index; root.scheduleSave() }
                }
              }

              ToolButton {
                label: "OLED"
                active: root.oled
                height: Style.spacing.controlHeight
                onClicked: { root.oled = !root.oled; root.scheduleSave() }
              }

              ToolButton {
                // Same render pipeline as Export PNG, so the button rides
                // the same unavoidably synchronous grab; the label says what
                // is happening before it lands.
                label: exportLoader.active && exportProc.wallpaper ? "Setting…" : "Set Wallpaper"
                active: exportLoader.active && exportProc.wallpaper
                enabled: !exportLoader.active
                height: Style.spacing.controlHeight
                onClicked: root.exportPng(true)
              }

              ToolButton {
                // The grab readback and PNG encode are unavoidably synchronous
                // — no QML API moves them off the GUI thread — so the last
                // ~600ms of a 6K export is a real hitch. The label at least
                // says what's happening before it lands.
                label: exportLoader.active && !exportProc.wallpaper ? "Exporting…" : "Export PNG"
                active: exportLoader.active && !exportProc.wallpaper
                enabled: !exportLoader.active
                height: Style.spacing.controlHeight
                onClicked: root.exportPng(false)
              }
            }

            ToolbarSection {
              ToolButton {
                label: "Close"
                height: Style.spacing.controlHeight
                onClicked: root.dismiss()
              }
            }
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "drag, or ←↑↓→ then Enter · shift+click / shift+Enter line · "
                + "right-drag erase · 1-8 color · E eraser · [ ] brush size · "
                + "K lock brush — the pointer paints as it moves, no click · "
                + "Ctrl+Z undo · C clear · L logo · "
                + "2K/4K/6K wallpaper size, OLED = true black · Ctrl+S export · Esc close"
            color: Util.alpha(Color.menu.text, 0.55)
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: Math.min(implicitWidth, parent.width)
            horizontalAlignment: Text.AlignHCenter
          }
        }
      }
    }
  }
}
