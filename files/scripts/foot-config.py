#!/usr/bin/env python3
"""Append the personal-blue font setting to the stock foot config.

Runs at image build time (BlueBuild script module) against the stock
/etc/xdg/foot/foot.ini from the base image. Appends a [main] section
with font=monospace:size=12, so the stock file stays intact and
upstream improvements flow through. foot's man page confirms the
default section can be explicitly named [main] to reopen it after
any other section.

Fails loudly if the stock file already has an active font= line, so
an upstream change to the font is reviewed by a human instead of
being silently overridden.

Usage: foot-config.py [path-to-foot.ini]
Default path: /etc/xdg/foot/foot.ini
"""
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else "/etc/xdg/foot/foot.ini"


def die(msg):
    sys.exit(f"foot-config: {msg}")


def active_font_lines(text):
    return [line for line in text.splitlines() if re.match(r"^font=", line)]


def main():
    with open(PATH) as f:
        text = f.read()

    if active_font_lines(text):
        die(f"stock config already has an active font line: {active_font_lines(text)[0]!r}")

    if not text.endswith("\n"):
        text += "\n"
    text += "\n# personal-blue: default font size\n[main]\nfont=monospace:size=12\n"

    # Validate: exactly one active font= line, and it is ours.
    if active_font_lines(text) != ["font=monospace:size=12"]:
        die(f"unexpected active font lines after edit: {active_font_lines(text)!r}")

    with open(PATH, "w") as f:
        f.write(text)
    print(f"foot-config: appended font setting to {PATH}")


if __name__ == "__main__":
    main()
