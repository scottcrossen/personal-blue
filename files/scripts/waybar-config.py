#!/usr/bin/env python3
"""Mutate the stock waybar config into the personal-blue default.

Runs at image build time (BlueBuild script module) against the stock
/etc/xdg/waybar/config.jsonc from the base image. Applies the small
delta between the stock config and the personal-blue default, then
validates the result parses as JSONC.

Edits (each must match exactly once or the build fails loudly):
  1. Uncomment "position": "bottom".
  2. Replace the "clock" module with "clock#local" and "clock#utc"
     in modules-right.
  3. Insert a "sway/workspaces" block and replace the single "clock"
     block with "clock#local" and "clock#utc" blocks.
  4. Delete the "battery#bat2" block (dead: never referenced, and
     there is no BAT2 hardware).

Usage: waybar-config.py [path-to-config.jsonc]
Default path: /etc/xdg/waybar/config.jsonc
"""
import json
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "/etc/xdg/waybar/config.jsonc"


def die(msg):
    sys.exit(f"waybar-config: {msg}")


def find_line(lines, text, what):
    hits = [i for i, line in enumerate(lines) if line == text]
    if len(hits) != 1:
        die(f"expected exactly 1 line {what!r}, found {len(hits)}")
    return hits[0]


def find_block_end(lines, start, what):
    for i in range(start + 1, len(lines)):
        if lines[i] == "    },":
            return i
    die(f"no closing brace for {what}")


def strip_jsonc(s):
    out, i, n, in_str, esc = [], 0, len(s), False, False
    while i < n:
        c = s[i]
        if in_str:
            out.append(c)
            if esc:
                esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                in_str = False
            i += 1
        elif c == '"':
            in_str = True
            out.append(c)
            i += 1
        elif c == "/" and i + 1 < n and s[i + 1] == "/":
            while i < n and s[i] != "\n":
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main():
    with open(PATH) as f:
        lines = f.read().splitlines()

    # 1. Uncomment "position": "bottom".
    i = find_line(
        lines,
        '    // "position": "bottom", // Waybar position (top|bottom|left|right)',
        "commented position line",
    )
    lines[i] = '    "position": "bottom", // Waybar position (top|bottom|left|right)'

    # 2. "clock" -> "clock#local" + "clock#utc" in modules-right.
    i = find_line(lines, '        "clock",', "clock module entry")
    lines[i : i + 1] = ['        "clock#local",', '        "clock#utc",']

    # 3a. Insert the "sway/workspaces" block before "idle_inhibitor".
    i = find_line(lines, '    "idle_inhibitor": {', "idle_inhibitor block")
    lines[i:i] = [
        '    "sway/workspaces": {',
        '        "all-outputs": true,',
        '        "persistent-workspaces": {}',
        "    },",
    ]

    # 3b. Replace the single "clock" block with the two clock blocks.
    i = find_line(lines, '    "clock": {', "clock block")
    j = find_block_end(lines, i, "clock block")
    lines[i : j + 1] = [
        '    "clock#local": {',
        '        "format": "{:%I:%M %p}",',
        r'        "tooltip-format": "<big>{:%Y-%m-%d}</big>\n<tt><small>{calendar}</small></tt>",',
        '        "format-alt": "{:%Y-%m-%d}"',
        "    },",
        '    "clock#utc": {',
        '        "format": "{:%H:%M UTC}",',
        '        "timezone": "etc/utc",',
        r'        "tooltip-format": "<big>{:%Y-%m-%d} (UTC) </big>\n<tt><small>{calendar}</small></tt>",',
        '        "format-alt": "{:%Y-%m-%d} (UTC)"',
        "    },",
    ]

    # 4. Delete the "battery#bat2" block.
    i = find_line(lines, '    "battery#bat2": {', "battery#bat2 block")
    j = find_block_end(lines, i, "battery#bat2 block")
    del lines[i : j + 1]

    text = "\n".join(lines) + "\n"

    # Validate: must still parse as JSONC, with the expected shape.
    data = json.loads(re.sub(r",\s*([}\]])", r"\1", strip_jsonc(text)))
    if "clock#local" not in data.get("modules-right", []):
        die("clock#local missing from modules-right after edit")
    if "clock#utc" not in data.get("modules-right", []):
        die("clock#utc missing from modules-right after edit")
    if any("bat2" in key for key in data):
        die("battery#bat2 still present after edit")
    if data.get("position") != "bottom":
        die("position is not bottom after edit")

    with open(PATH, "w") as f:
        f.write(text)
    print(f"waybar-config: rewrote {PATH} ({len(lines)} lines)")


if __name__ == "__main__":
    main()
