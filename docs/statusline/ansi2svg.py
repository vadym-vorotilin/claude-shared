#!/usr/bin/env python3
"""Render ANSI-colored terminal text (stdin) as an SVG terminal card (stdout).

Understands the SGR codes the status line scripts emit: reset, bold, the
eight standard and eight bright foreground colors, and 256-color foregrounds
(38;5;N). Every character is placed on its own cell, so a glyph the font
lacks can't push the columns after it out of line.
"""
import re
import sys

CELL_W = 8.4          # px per cell at a 14px monospace font
LINE_H = 21
PAD_X = 16
PAD_Y = 14
FONT = "ui-monospace, SFMono-Regular, Menlo, Consolas, 'Liberation Mono', monospace"

BG = "#0d1117"
FG = "#c9d1d9"
BASIC = {
    30: "#484f58", 31: "#ff7b72", 32: "#3fb950", 33: "#d29922",
    34: "#58a6ff", 35: "#bc8cff", 36: "#39c5cf", 37: "#f0f6fc",
    90: "#6e7681", 91: "#ffa198", 92: "#56d364", 93: "#e3b341",
    94: "#79c0ff", 95: "#d2a8ff", 96: "#56d4dd", 97: "#ffffff",
}


def xterm256(n):
    if n < 16:
        return BASIC[(30 + n) if n < 8 else (90 + n - 8)]
    if n < 232:
        n -= 16
        steps = [0, 95, 135, 175, 215, 255]
        r, g, b = steps[n // 36], steps[(n // 6) % 6], steps[n % 6]
        return f"#{r:02x}{g:02x}{b:02x}"
    v = 8 + (n - 232) * 10
    return f"#{v:02x}{v:02x}{v:02x}"


SGR = re.compile(r"\x1b\[([0-9;]*)m")


def parse(line):
    """One line -> list of (text, color, bold) runs."""
    runs, color, bold, pos = [], FG, False, 0
    for m in SGR.finditer(line):
        if m.start() > pos:
            runs.append((line[pos:m.start()], color, bold))
        codes = [int(c) for c in m.group(1).split(";") if c] or [0]
        i = 0
        while i < len(codes):
            c = codes[i]
            if c == 0:
                color, bold = FG, False
            elif c == 1:
                bold = True
            elif c == 22:
                bold = False
            elif c == 39:
                color = FG
            elif c in BASIC:
                color = BASIC[c]
            elif c == 38 and i + 2 < len(codes) and codes[i + 1] == 5:
                color = xterm256(codes[i + 2])
                i += 2
            i += 1
        pos = m.end()
    if pos < len(line):
        runs.append((line[pos:], color, bold))
    return runs


def esc(ch):
    return {"&": "&amp;", "<": "&lt;", ">": "&gt;"}.get(ch, ch)


def main():
    lines = sys.stdin.read().split("\n")
    # Drop trailing blank lines, including the status line's U+2800 spacer.
    while lines and not lines[-1].replace("⠀", "").strip():
        lines.pop()
    parsed = [parse(l) for l in lines]
    cols = max((sum(len(t) for t, _, _ in runs) for runs in parsed), default=0)
    width = round(cols * CELL_W + 2 * PAD_X)
    height = len(parsed) * LINE_H + 2 * PAD_Y

    out = [
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" '
        f'viewBox="0 0 {width} {height}">',
        f'<rect width="{width}" height="{height}" rx="8" fill="{BG}"/>',
        f'<g font-family="{FONT}" font-size="14">',
    ]
    # One <text> per character: a per-glyph x list on a shared <text> is
    # dropped by some renderers once a glyph falls back to another font,
    # and every column after it drifts.
    for row, runs in enumerate(parsed):
        y = PAD_Y + row * LINE_H + 15
        col = 0
        for text, color, bold in runs:
            chars = [
                f'<text x="{PAD_X + (col + k) * CELL_W:.1f}" y="{y}">{esc(ch)}</text>'
                for k, ch in enumerate(text) if not ch.isspace()
            ]
            if chars:
                weight = ' font-weight="bold"' if bold else ""
                out.append(f'<g fill="{color}"{weight}>{"".join(chars)}</g>')
            col += len(text)
    out.append("</g></svg>")
    print("\n".join(out))


if __name__ == "__main__":
    main()
