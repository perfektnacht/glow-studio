// Board model for the Lite-Brite plugin.
//
// A board is a flat Uint8Array of `cols * rows` peg slots. 0 means the hole is
// empty; 1..PALETTE.length is an index into PALETTE offset by one, so the
// empty state stays falsy and encoding stays compact.
//
// Deliberately free of QML dependencies (beyond Qt.* being unused) so the
// board, the logo, and the save format can be reasoned about on their own.

// -------------------------------------------------------------- the palette
//
// The eight peg colors a 1967 Lite-Brite shipped with, tuned for a backlit
// look on near-black rather than for print. Order is the order they appear
// in the toolbar and the order the number keys 1-8 select.
var PALETTE = [
  { name: "Red",    hex: "#ff2f3d", key: "1" },
  { name: "Orange", hex: "#ff8a1f", key: "2" },
  { name: "Yellow", hex: "#ffe234", key: "3" },
  { name: "Green",  hex: "#35ff5e", key: "4" },
  { name: "Blue",   hex: "#2f8bff", key: "5" },
  { name: "Violet", hex: "#a855ff", key: "6" },
  { name: "Pink",   hex: "#ff5fc8", key: "7" },
  { name: "White",  hex: "#f2f6ff", key: "8" }
]

// Green, to match the shipped screensaver logo.
var LOGO_COLOR = 4

function paletteHex(value) {
  var entry = PALETTE[value - 1]
  return entry ? entry.hex : "#000000"
}

// ----------------------------------------------------------------- the logo
//
// The Omarchy screensaver wordmark, verbatim. Each source character is one
// peg column and *two* peg rows: the half-block characters carry vertical
// sub-cell detail, so expanding `▀` to (on, off) and `▄` to (off, on)
// recovers the letterforms at their true 2:1 aspect instead of squashing
// them to the terminal's cell grid.
var LOGO_ART = [
  "                 ▄▄▄",
  " ▄█████▄    ▄███████████▄    ▄███████   ▄███████   ▄███████   ▄█   █▄    ▄█   █▄",
  "███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███",
  "███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███",
  "███   ███  ███   ███   ███ ▄███▄▄▄███ ▄███▄▄▄██▀  ███       ▄███▄▄▄███▄ ███▄▄▄███",
  "███   ███  ███   ███   ███ ▀███▀▀▀███ ▀███▀▀▀▀    ███      ▀▀███▀▀▀███  ▀▀▀▀▀▀███",
  "███   ███  ███   ███   ███  ███   ███ ██████████  ███   █▄   ███   ███  ▄██   ███",
  "███   ███  ███   ███   ███  ███   ███  ███   ███  ███   ███  ███   ███  ███   ███",
  " ▀█████▀    ▀█   ███   █▀   ███   █▀   ███   ███  ███████▀   ███   █▀    ▀█████▀",
  "                                       ███   █▀"
]

var HALF_TOP = { "█": 1, "▀": 1, "▄": 0, " ": 0 }
var HALF_BOTTOM = { "█": 1, "▀": 0, "▄": 1, " ": 0 }

// Expand LOGO_ART into a { width, height, rows: [[0|1, ...], ...] } bitmap
// with blank edges trimmed. Cached after the first call — the art never
// changes and the expansion is pure.
var _logoCache = null

function logoBitmap() {
  if (_logoCache) return _logoCache

  var width = 0
  for (var i = 0; i < LOGO_ART.length; i++) width = Math.max(width, LOGO_ART[i].length)

  var rows = []
  for (var l = 0; l < LOGO_ART.length; l++) {
    var top = []
    var bottom = []
    for (var c = 0; c < width; c++) {
      var ch = c < LOGO_ART[l].length ? LOGO_ART[l].charAt(c) : " "
      top.push(HALF_TOP[ch] || 0)
      bottom.push(HALF_BOTTOM[ch] || 0)
    }
    rows.push(top)
    rows.push(bottom)
  }

  // Trim blank rows top and bottom, then blank columns left and right, so the
  // caller can center the ink rather than centering the art's whitespace.
  function rowEmpty(row) {
    for (var i = 0; i < row.length; i++) if (row[i]) return false
    return true
  }
  while (rows.length && rowEmpty(rows[0])) rows.shift()
  while (rows.length && rowEmpty(rows[rows.length - 1])) rows.pop()

  function colEmpty(index) {
    for (var i = 0; i < rows.length; i++) if (rows[i][index]) return false
    return true
  }
  var left = 0
  while (left < width && colEmpty(left)) left++
  var right = width - 1
  while (right > left && colEmpty(right)) right--

  var trimmed = []
  for (var r = 0; r < rows.length; r++) trimmed.push(rows[r].slice(left, right + 1))

  _logoCache = { width: right - left + 1, height: trimmed.length, rows: trimmed }
  return _logoCache
}

// A fresh board with the wordmark lit in the center. Boards too small to hold
// the logo come back empty rather than clipped.
function logoBoard(cols, rows) {
  var cells = newBoard(cols, rows)
  var logo = logoBitmap()
  if (logo.width > cols || logo.height > rows) return cells

  var offsetX = Math.floor((cols - logo.width) / 2)
  var offsetY = Math.floor((rows - logo.height) / 2)
  for (var y = 0; y < logo.height; y++) {
    for (var x = 0; x < logo.width; x++) {
      if (logo.rows[y][x]) cells[(offsetY + y) * cols + offsetX + x] = LOGO_COLOR
    }
  }
  return cells
}

function newBoard(cols, rows) {
  return new Uint8Array(cols * rows)
}

// ----------------------------------------------------------- save format
//
// Run-length encoded as a flat [value, count, value, count, ...] array. A
// logo-only board is ~1.5k of JSON; a fully-covered one stays well under
// what a sparse index list would cost.

function encode(cells, cols, rows) {
  var runs = []
  var value = cells[0]
  var count = 0
  for (var i = 0; i < cells.length; i++) {
    if (cells[i] === value) {
      count++
    } else {
      runs.push(value, count)
      value = cells[i]
      count = 1
    }
  }
  runs.push(value, count)
  return { v: 1, cols: cols, rows: rows, rle: runs }
}

// Returns null for anything we can't faithfully restore — a different grid
// size, a newer format, or corrupt runs. Callers fall back to the logo.
function decode(payload, cols, rows) {
  if (!payload || payload.v !== 1) return null
  if (payload.cols !== cols || payload.rows !== rows) return null
  if (!Array.isArray(payload.rle) || payload.rle.length % 2 !== 0) return null

  var cells = newBoard(cols, rows)
  var at = 0
  for (var i = 0; i < payload.rle.length; i += 2) {
    var value = payload.rle[i] | 0
    var count = payload.rle[i + 1] | 0
    if (count < 0 || at + count > cells.length) return null
    if (value < 0 || value > PALETTE.length) return null
    if (value !== 0) {
      for (var n = 0; n < count; n++) cells[at + n] = value
    }
    at += count
  }
  return at === cells.length ? cells : null
}

// ------------------------------------------------------------- geometry

// Cells covered by a brush of the given radius, as offsets from its center.
// Radius 0 is a single peg; larger radii are discs, which is what reads as a
// "fat marker" on a peg grid (squares look like deliberate blocks).
function brushOffsets(radius) {
  var offsets = []
  var span = Math.ceil(radius)
  var limit = (radius + 0.25) * (radius + 0.25)
  for (var dy = -span; dy <= span; dy++) {
    for (var dx = -span; dx <= span; dx++) {
      if (dx * dx + dy * dy <= limit) offsets.push([dx, dy])
    }
  }
  return offsets
}

// Bresenham. Pointer motion arrives sampled, not continuous, so a fast drag
// visits a handful of cells; without interpolation the stroke comes out as
// dotted islands.
function line(x0, y0, x1, y1, visit) {
  var dx = Math.abs(x1 - x0)
  var dy = -Math.abs(y1 - y0)
  var sx = x0 < x1 ? 1 : -1
  var sy = y0 < y1 ? 1 : -1
  var err = dx + dy

  while (true) {
    visit(x0, y0)
    if (x0 === x1 && y0 === y1) return
    var e2 = 2 * err
    if (e2 >= dy) { err += dy; x0 += sx }
    if (e2 <= dx) { err += dx; y0 += sy }
  }
}

// ---------------------------------------------------------------- color

function _channels(hex) {
  return [
    parseInt(hex.substr(1, 2), 16),
    parseInt(hex.substr(3, 2), 16),
    parseInt(hex.substr(5, 2), 16)
  ]
}

function rgba(hex, alpha) {
  var c = _channels(hex)
  return "rgba(" + c[0] + "," + c[1] + "," + c[2] + "," + alpha + ")"
}

// factor < 1 darkens toward black, > 1 lightens toward white.
function shade(hex, factor) {
  var c = _channels(hex)
  for (var i = 0; i < 3; i++) {
    c[i] = factor <= 1
      ? Math.round(c[i] * factor)
      : Math.round(c[i] + (255 - c[i]) * (factor - 1))
    c[i] = Math.max(0, Math.min(255, c[i]))
  }
  return "rgb(" + c[0] + "," + c[1] + "," + c[2] + ")"
}
