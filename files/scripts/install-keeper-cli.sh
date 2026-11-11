#!/usr/bin/env bash
# Install Keeper Commander (the Keeper CLI) into the image at build time.
#
# Uses a dedicated venv at /opt/keeper so the system Python stays
# untouched (Fedora marks the system Python externally managed).
# The `keeper` command is symlinked into /usr/local/bin.
# First-run setup (`ujust setup`) logs in and pulls passwords and
# tokens from Keeper; nothing secret is baked into the image.
#
# The version is pinned (KEEPER_VERSION below, the version validated
# on the laptop). A weekly workflow checks PyPI for a newer release
# and opens a bump PR when one appears.

set -euo pipefail

# Single source of truth for the pinned version: KEEPER_VERSION
# below. The scheduled version-check workflow
# (.github/workflows/check-keeper-cli.yml) greps it from here.
KEEPER_VERSION="18.1.9"
# Pinned 2026-11-03T04:05:35Z: keepercommander 18.1.9 on PyPI
VENV="/opt/keeper"

if [ ! -x "${VENV}/bin/keeper" ]; then
    echo "keeper-cli: creating venv at ${VENV}"
    python3 -m venv "${VENV}"
    "${VENV}/bin/pip" install --quiet "keepercommander==${KEEPER_VERSION}"
fi
# /usr/local/bin does not exist in the image at script-module time.
mkdir -p /usr/local/bin
ln -sf "${VENV}/bin/keeper" /usr/local/bin/keeper
# Assert the pinned version actually installed (pip has no hash check
# here; the version pin plus this assertion is the practical guard —
# a full --require-hashes lockfile is a follow-up).
"${VENV}/bin/keeper" --version | grep -q "${KEEPER_VERSION}" || { echo "keeper-cli: expected version ${KEEPER_VERSION}"; exit 1; }
echo "keeper-cli: installed"
