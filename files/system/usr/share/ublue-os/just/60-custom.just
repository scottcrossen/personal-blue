# Personal setup recipes for the personal-blue image.
# Shipped at /usr/share/ublue-os/just/60-custom.just and auto-imported
# by the base justfile (import? "60-custom.just").
# Run once on a fresh host: `ujust setup`. Every step is idempotent
# and skips work that is already done. Nothing here contains personal
# info: names, emails and tokens are prompted for or pulled from
# Keeper at first run, never baked into the image.

# First-run setup: Keeper login, git identity, GitHub CLI, Muse SDK, Firefox flatpak.
setup: keeper-login git-identity gh-setup muse-sdk firefox-flatpak
    @echo "Setup complete."

# Log in to Keeper CLI (once). Later steps pull passwords/tokens from Keeper.
keeper-login:
    #!/usr/bin/bash
    set -euo pipefail
    if keeper whoami </dev/null >/dev/null 2>&1; then
        echo "Keeper: already logged in."
        exit 0
    fi
    echo "Keeper: log in now (this opens the Keeper shell; log in, then type exit)."
    keeper shell
    keeper whoami </dev/null >/dev/null 2>&1 || { echo "Keeper login did not complete; rerun 'ujust setup'."; exit 1; }

# Git identity (name + email). Prompts; nothing is baked into the image.
git-identity:
    #!/usr/bin/bash
    set -euo pipefail
    if [ -n "$(git config --global user.name 2>/dev/null || true)" ] && [ -n "$(git config --global user.email 2>/dev/null || true)" ]; then
        echo "Git: identity already set ($(git config --global user.name) <$(git config --global user.email)>)."
        exit 0
    fi
    read -rp "Git name: " git_name
    read -rp "Git email: " git_email
    [ -n "$git_name" ] && [ -n "$git_email" ] || { echo "Name and email are required."; exit 1; }
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    git config --global url."git@github.com:".insteadOf "https://github.com/"
    git config --global core.editor vim
    echo "Git: identity set."

# GitHub CLI: log in and add an SSH key if there is none.
gh-setup:
    #!/usr/bin/bash
    set -euo pipefail
    if ! gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI: log in now."
        gh auth login
    else
        echo "GitHub CLI: already logged in."
    fi
    if [ ! -f ~/.ssh/id_ed25519.pub ]; then
        echo "GitHub CLI: creating an SSH key (you will be prompted for a passphrase)."
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
    fi
    key_title="$(hostname)-$(whoami)"
    if gh ssh-key list 2>/dev/null | grep -q "$key_title"; then
        echo "GitHub CLI: SSH key already on GitHub."
    else
        echo "GitHub CLI: adding the SSH key to GitHub."
        gh ssh-key add ~/.ssh/id_ed25519.pub --title "$key_title"
    fi

# Muse SDK: fetch the token from Keeper, pair, set the run-as user, enable the service.
muse-sdk:
    #!/usr/bin/bash
    set -euo pipefail
    if ! systemctl cat musegadget.service >/dev/null 2>&1; then
        echo "Muse SDK: not installed in this image; skipping (install the SDK first)."
        exit 0
    fi
    if sudo test -s /var/lib/musegadget/pairing.json && systemctl is-enabled musegadget.service >/dev/null 2>&1; then
        echo "Muse SDK: already paired and enabled."
        exit 0
    fi
    read -rp "Set up the Muse SDK (fetch the token from Keeper, pair, and enable the service)? [Y/n] " answer
    case "$answer" in ""|y|Y|yes|YES) ;; *) echo "Muse SDK: skipped."; exit 0 ;; esac
    # Override the build-time placeholder run-as user (muse) with this account.
    sudo mkdir -p /etc/systemd/system/musegadget.service.d
    printf '[Service]\nEnvironment=MUSEGADGET_RUN_AS=%s\n' "$(whoami)" | sudo tee /etc/systemd/system/musegadget.service.d/10-run-as.conf >/dev/null
    sudo systemctl daemon-reload
    if sudo test -s /var/lib/musegadget/pairing.json; then
        echo "Muse SDK: already paired."
    else
        echo "Muse SDK: fetching the SDK token from Keeper."
        read -rp "Keeper record for the Muse SDK token (title or UID): " record
        token=$(keeper get "$record" --format password)
        [ -n "$token" ] || { echo "Could not read a password from that Keeper record."; exit 1; }
        sudo install -d -m 0700 /var/lib/musegadget
        printf '%s\n' "$token" | sudo install -m 0600 /dev/stdin /var/lib/musegadget/sdk_token
        echo "Muse SDK: token saved. Pairing now — follow the prompts in the Muse app."
        sudo musegadget pair
    fi
    sudo systemctl enable --now musegadget.service
    echo "Muse SDK: service enabled."

# Firefox flatpak (the $mod+c binding in the sway drop-in expects it).
firefox-flatpak:
    #!/usr/bin/bash
    set -euo pipefail
    if flatpak list --app 2>/dev/null | grep -q org.mozilla.firefox; then
        echo "Firefox: flatpak already installed."
        exit 0
    fi
    flatpak install -y flathub org.mozilla.firefox
    echo "Firefox: flatpak installed."
