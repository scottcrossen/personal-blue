#!/usr/bin/env bash
# Install Keeper Commander (the Keeper CLI) into the image at build time.
#
# Uses a dedicated venv at /opt/keeper so the system Python stays
# untouched (Fedora marks the system Python externally managed).
# The `keeper` command is symlinked into /usr/bin.
#
# The venv runs on Python 3.13 (the python3.13 package, installed by
# keeper-modules.yml), NOT the image's Python 3.14: keeper-mlkem
# ships compiled wheels only up to 3.13 — on 3.14 pip builds it from
# source, the compiled accelerator silently never gets built, and
# every keeper run prints "QRC encryption failed: ML-KEM
# implementation not available" before falling back to EC. Python
# 3.13 also predates the SyntaxWarning that 3.14 raises on
# keepercommander's 'return' in a 'finally' block. The requirements
# file is therefore generated for Python 3.13 (see its header).
# First-run setup (`ujust setup`) logs in and pulls passwords and
# tokens from Keeper; nothing secret is baked into the image.
#
# The version is pinned (KEEPER_VERSION below, the version validated
# on the laptop). A weekly workflow checks PyPI for a newer release
# and opens a bump PR when one appears.
#
# The install is hash-verified against the pinned dependency set in
# /usr/share/personal-blue/keeper-requirements.txt, which ships in
# the image (files/system/usr/share/personal-blue/, copied by the
# files module before this script runs). See that file for how it
# was generated and how to regenerate it. The install fails loudly
# if the file is missing or its keepercommander pin disagrees with
# KEEPER_VERSION.

set -euo pipefail

# Single source of truth for the pinned version: KEEPER_VERSION
# below. The scheduled version-check workflow
# (.github/workflows/check-keeper-cli.yml) greps it from here.
KEEPER_VERSION="18.1.9"
# Pinned 2026-11-03T04:05:35Z: keepercommander 18.1.9 on PyPI
VENV="/opt/keeper"
REQUIREMENTS_FILE="/usr/share/personal-blue/keeper-requirements.txt"

if [ ! -x "${VENV}/bin/keeper" ]; then
    echo "keeper-cli: creating venv at ${VENV}"
    python3.13 -m venv "${VENV}"
    [ -f "${REQUIREMENTS_FILE}" ] || { echo "keeper-cli: requirements file ${REQUIREMENTS_FILE} is missing from the image"; exit 1; }
    grep -qF "keepercommander==${KEEPER_VERSION} " "${REQUIREMENTS_FILE}" || { echo "keeper-cli: ${REQUIREMENTS_FILE} does not pin keepercommander==${KEEPER_VERSION}; regenerate it for this KEEPER_VERSION"; exit 1; }
    "${VENV}/bin/pip" install --quiet --require-hashes -r "${REQUIREMENTS_FILE}"
fi
# Symlink into /usr/bin, not /usr/local/bin: on this base /usr/local
# is a symlink into /var/usrlocal, and image /var content is only
# seeded on fresh installs — a /usr/local/bin symlink never reaches
# upgraded systems. /usr/bin is image territory and lands everywhere.
ln -sf "${VENV}/bin/keeper" /usr/bin/keeper
# Assert the pinned version actually installed. pip verified every
# artifact against the hashes in the requirements file; this
# assertion is the guard for anything hashes cannot express, e.g. a
# requirements set generated for the wrong version (also caught by
# the pin check before install).
"${VENV}/bin/keeper" --version | grep -q "${KEEPER_VERSION}" || { echo "keeper-cli: expected version ${KEEPER_VERSION}"; exit 1; }
echo "keeper-cli: installed"
