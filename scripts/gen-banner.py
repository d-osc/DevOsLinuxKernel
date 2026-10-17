#!/usr/bin/env python3
"""Generate the DEVOS boot banner (ANSI Shadow style) — prints to stdout.

Usage: python3 gen-banner.py [TEXT]   (default: DEVOS)
Only the glyphs below are available; add more if you change the name.
"""
import sys

GLYPHS = {
    "D": ["██████╗ ", "██╔══██╗", "██║  ██║", "██║  ██║", "██████╔╝", "╚═════╝ "],
    "E": ["███████╗", "██╔════╝", "█████╗  ", "██╔══╝  ", "███████╗", "╚══════╝"],
    "V": ["██╗   ██╗", "██║   ██║", "██║   ██║", "╚██╗ ██╔╝", " ╚████╔╝ ", "  ╚═══╝  "],
    "O": [" ██████╗ ", "██╔═══██╗", "██║   ██║", "██║   ██║", "╚██████╔╝", " ╚═════╝ "],
    "S": ["███████╗ ", "██╔════╝ ", "███████╗ ", "╚════██║ ", "███████║ ", "╚══════╝ "],
}


def render(text: str) -> str:
    rows = []
    for i in range(6):
        rows.append(" ".join(GLYPHS[ch][i] for ch in text))
    return "\n".join(rows)


if __name__ == "__main__":
    text = sys.argv[1] if len(sys.argv) > 1 else "DEVOS"
    print(render(text))
