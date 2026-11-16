#!/usr/bin/env bash
# Install Keeper Commander (the Keeper CLI) into the image at build time.
#
# Uses a dedicated venv at /opt/keeper so the system Python stays
# untouched (Fedora marks the system Python externally managed).
# The `keeper` command is the launcher script shipped in
# files/system/usr/bin/keeper (copied by the files module), which
# execs the venv binary and works around two upstream annoyances
# (config-file permissions and a Python 3.14 SyntaxWarning).
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
    python3 -m venv "${VENV}"
    [ -f "${REQUIREMENTS_FILE}" ] || { echo "keeper-cli: requirements file ${REQUIREMENTS_FILE} is missing from the image"; exit 1; }
    grep -qF "keepercommander==${KEEPER_VERSION} " "${REQUIREMENTS_FILE}" || { echo "keeper-cli: ${REQUIREMENTS_FILE} does not pin keepercommander==${KEEPER_VERSION}; regenerate it for this KEEPER_VERSION"; exit 1; }
    "${VENV}/bin/pip" install --quiet --require-hashes -r "${REQUIREMENTS_FILE}"
fi
# The keeper command is the launcher at /usr/bin/keeper, shipped via
# the files module — NOT a symlink into /usr/local/bin (on this base
# /usr/local is a symlink into /var/usrlocal, whose image content is
# only seeded on fresh installs, so links there never reach upgraded
# systems; see PR #22) and no longer a plain symlink to the venv
# binary. Fail loudly if the files module did not land it.
[ -x /usr/bin/keeper ] || { echo "keeper-cli: /usr/bin/keeper launcher missing from the image"; exit 1; }
# Assert the pinned version actually installed. pip verified every
# artifact against the hashes in the requirements file; this
# assertion is the guard for anything hashes cannot express, e.g. a
# requirements set generated for the wrong version (also caught by
# the pin check before install).
"${VENV}/bin/keeper" --version | grep -q "${KEEPER_VERSION}" || { echo "keeper-cli: expected version ${KEEPER_VERSION}"; exit 1; }
echo "keeper-cli: installed"
