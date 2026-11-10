#!/usr/bin/env bash
# Install the Muse Linux Device SDK into the image at build time.
#
# Runs the upstream install.sh at a PINNED commit of the SDK repo
# (the repo has no releases or tags, so the commit SHA is the pin).
# No SDK token and no pairing here: the token is a credential and
# pairing needs a phone + Bluetooth, so both happen at first run
# via `ujust setup`.
#
# What the installer does in a container (no systemd running):
#   - installs the missing system packages (dnf; only
#     python3-cryptography is extra, and the recipe installs it too)
#   - installs uv 0.9.9 and the musegadget package from the pinned
#     source into /opt/musegadget, symlinked at /usr/local/bin
#   - writes the musegadget systemd unit (MUSEGADGET_RUN_AS=muse)
#     but does NOT enable or start it (no systemd); `ujust setup`
#     enables it and overrides the run-as user to the real account
#   - edits /etc/bluetooth/main.conf (ExchangeMTU=256)
# The one thing the installer cannot do without systemd is write the
# BlueZ battery-plugin drop-in (it reads the unit via systemctl),
# so this script writes it from the unit file directly.
#
# Single source of truth for the pinned commit:
#   MUSE_SDK_PIN below. The scheduled version-check workflow
#   (.github/workflows/check-muse-sdk.yml) greps it from here.

set -euo pipefail

MUSE_SDK_PIN="ebefd65decf5380de46efa6524b1ae53641a29b6"
# Pinned 2026-11-10T19:50:58Z: Tuya cloud skill: confirm risky switching and label it as cloud (#373)

REPO="https://github.com/facebookincubator/muse-gadget-sdk"
INSTALLER_URL="https://raw.githubusercontent.com/facebookincubator/muse-gadget-sdk/${MUSE_SDK_PIN}/linux/install.sh"

echo "muse-sdk: pinned commit ${MUSE_SDK_PIN}"

# The installer requires the run-as account to exist. It is a
# placeholder here: `ujust setup` overrides MUSEGADGET_RUN_AS to the
# real user account via a systemd drop-in at first run.
if ! id muse >/dev/null 2>&1; then
    echo "muse-sdk: creating the muse service account"
    useradd -m -s /bin/bash muse
fi

echo "muse-sdk: fetching install.sh at the pinned commit"
curl -fsSL "${INSTALLER_URL}" -o /tmp/muse-install.sh
# The download must be the real installer, not an error page: it must
# carry the installer's distinctive markers.
grep -q '^DEFAULT_SOURCE=' /tmp/muse-install.sh || { echo "muse-sdk: downloaded file is not install.sh (no DEFAULT_SOURCE)"; exit 1; }
grep -q '^install_musegadget()' /tmp/muse-install.sh || { echo "muse-sdk: downloaded file is not install.sh (no install_musegadget)"; exit 1; }

echo "muse-sdk: running the installer (no token, no pairing)"
# /usr/local/bin does not exist in the image at script-module time,
# and the installer symlinks /usr/local/bin/musegadget into it.
mkdir -p /usr/local/bin
bash /tmp/muse-install.sh \
    --from "git+${REPO}@${MUSE_SDK_PIN}#subdirectory=linux" \
    --run-as muse --no-pair --yes

# BlueZ battery-plugin drop-in: the installer skips this without
# systemd (it reads the unit via systemctl). Replicate it from the
# unit file so phones are never asked to bond during pairing.
python3 - <<'PYEOF'
import os, sys

unit = "/usr/lib/systemd/system/bluetooth.service"
dropin = "/etc/systemd/system/bluetooth.service.d/zz-musegadget.conf"
if not os.path.exists(unit):
    print("muse-sdk: no bluetooth.service unit; skipping BlueZ drop-in")
    sys.exit(0)
if os.path.exists(dropin):
    print("muse-sdk: BlueZ drop-in already present")
    sys.exit(0)
exec_start = None
for line in open(unit):
    if line.startswith("ExecStart="):
        exec_start = line[len("ExecStart="):].strip()
        break
if exec_start is None:
    print("muse-sdk: no ExecStart in bluetooth.service; skipping drop-in")
    sys.exit(0)
# Merge "battery" into any existing --noplugin list (same as the
# installer's own logic); otherwise append --noplugin=battery.
args = exec_start.split()
def has_battery(args):
    for i, a in enumerate(args):
        if a.startswith("--noplugin="):
            if "battery" in a.split("=", 1)[1].split(","):
                return True
        elif a == "--noplugin" and i + 1 < len(args):
            if "battery" in args[i + 1].split(","):
                return True
    return False
if has_battery(args):
    print("muse-sdk: bluetooth.service already disables the battery plugin; skipping drop-in")
    sys.exit(0)
for i, a in enumerate(args):
    if a == "--noplugin" and i + 1 < len(args):
        args[i + 1] = args[i + 1] + ",battery" if args[i + 1] else "battery"
        break
    if a.startswith("--noplugin="):
        args[i] = a + ",battery"
        break
else:
    args.append("--noplugin=battery")
exec_start = " ".join(args)
os.makedirs(os.path.dirname(dropin), exist_ok=True)
with open(dropin, "w") as f:
    f.write("# Written by the musegadget installer: never ask phones to bond.\n")
    f.write("[Service]\nExecStart=\nExecStart=" + exec_start + "\n")
print(f"muse-sdk: wrote BlueZ drop-in {dropin}")
PYEOF

# Verify the install landed.
test -x /usr/local/bin/musegadget
test -f /etc/systemd/system/musegadget.service
grep -q "MUSEGADGET_RUN_AS=muse" /etc/systemd/system/musegadget.service
echo "muse-sdk: installed; service is present but not enabled (ujust setup enables it)"
