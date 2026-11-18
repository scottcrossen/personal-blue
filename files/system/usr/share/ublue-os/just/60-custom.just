# Personal setup recipes for the personal-blue image.
# Shipped at /usr/share/ublue-os/just/60-custom.just and auto-imported
# by the base justfile (import? "60-custom.just").
# Run once on a fresh host: `ujust setup`. Every step is idempotent
# and skips work that is already done. Nothing here contains personal
# info: names, emails and tokens are prompted for at first run,
# never baked into the image.

# First-run setup: Keeper login, git identity, GitHub CLI, Muse SDK, Muse distrobox, Firefox flatpak.
setup: login-mode keeper-login git-identity gh-setup muse-sdk muse-code-distrobox firefox-flatpak
    @echo "Setup complete."

# Login mode: a machine is set up for Keeper OR for the Muse SDK,
# never both. Setup asks once and records the choice; the two login
# steps below honor it, and this step enforces it on every run by
# logging the other side out. Delete the mode file to choose again.
login-mode:
    #!/usr/bin/bash
    set -euo pipefail
    mode_file="$HOME/.config/personal-blue/login-mode"
    mode=""
    if [ -f "$mode_file" ]; then
        recorded_mode="$(cat "$mode_file")"
        case "$recorded_mode" in
            keeper|sdk) mode="$recorded_mode" ;;
            *) echo "Login mode file $mode_file contains '$recorded_mode', which is not a valid mode (keeper or sdk). Fix it by hand or delete it and rerun 'ujust setup'."; exit 1 ;;
        esac
        echo "Login mode: $mode (recorded in $mode_file; delete the file to choose again)."
    else
        echo "This machine can be set up for one login, not both:"
        echo "  1) Keeper — log in to Keeper on this machine. The Muse SDK will be logged out and not set up."
        echo "  2) Muse SDK — pair the Muse SDK on this machine. Keeper will be logged out."
        read -rp "Choose 1 or 2: " choice
        case "$choice" in
            1) mode="keeper" ;;
            2) mode="sdk" ;;
            *) echo "Please answer 1 or 2."; exit 1 ;;
        esac
        mkdir -p "$(dirname "$mode_file")"
        printf '%s\n' "$mode" > "$mode_file"
        echo "Login mode: $mode."
    fi
    # Enforce the mode: log the other side out. This runs on every
    # setup run, so a side that was logged back in by hand is logged
    # out again here. The checks are prompt-free; sudo is only touched
    # when the SDK is actually set up and has to be torn down.
    if [ "$mode" = "keeper" ]; then
        if systemctl cat musegadget.service >/dev/null 2>&1 && { systemctl is-enabled musegadget.service >/dev/null 2>&1 || systemctl is-active musegadget.service >/dev/null 2>&1; }; then
            echo "Muse SDK: logging out (disabling the service and forgetting the pairing)."
            sudo systemctl disable --now musegadget.service >/dev/null 2>&1 || true
            sudo musegadget unpair </dev/null >/dev/null 2>&1 || true
            sudo rm -f /var/lib/musegadget/pairing.json /var/lib/musegadget/sdk_token
        fi
    else
        if keeper whoami </dev/null >/dev/null 2>&1; then
            echo "Keeper: logging out."
            keeper logout </dev/null >/dev/null 2>&1 || true
            if keeper whoami </dev/null >/dev/null 2>&1; then
                echo "Keeper: WARNING — still logged in after 'keeper logout'; run 'keeper logout' by hand to finish."
            fi
        fi
    fi

# Log in to Keeper CLI (once). Keeper credentials serve Keeper only:
# no other setup step reads anything from Keeper.
keeper-login:
    #!/usr/bin/bash
    set -euo pipefail
    mode_file="$HOME/.config/personal-blue/login-mode"
    if [ -f "$mode_file" ]; then
        recorded_mode="$(cat "$mode_file")"
        case "$recorded_mode" in
            keeper) ;;
            sdk)
                echo "Keeper: skipped — this machine is in Muse SDK mode (see 'ujust login-mode')."
                exit 0
                ;;
            *)
                echo "Keeper: login mode file $mode_file contains '$recorded_mode', which is not a valid mode (keeper or sdk). Fix it by hand or delete it and rerun 'ujust setup'."
                exit 1
                ;;
        esac
    fi
    if keeper whoami </dev/null >/dev/null 2>&1; then
        echo "Keeper: already logged in."
        exit 0
    fi
    read -rp "Keeper email: " keeper_email
    [ -n "$keeper_email" ] || { echo "Keeper email is required."; exit 1; }
    echo "Keeper: logging in (Keeper prompts for your master password and any 2FA)."
    keeper login "$keeper_email"
    keeper whoami </dev/null >/dev/null 2>&1 || { echo "Keeper login did not complete; rerun 'ujust setup'."; exit 1; }

# Git identity (name + email). Prompts only for what is missing and
# sets only what differs, so reruns are no-ops. Nothing is baked into
# the image.
git-identity:
    #!/usr/bin/bash
    set -euo pipefail
    changed=0
    git_name="$(git config --global user.name 2>/dev/null || true)"
    if [ -z "$git_name" ]; then
        read -rp "Git name: " git_name
        [ -n "$git_name" ] || { echo "Git name is required."; exit 1; }
        git config --global user.name "$git_name"
        changed=1
    fi
    git_email="$(git config --global user.email 2>/dev/null || true)"
    if [ -z "$git_email" ]; then
        read -rp "Git email: " git_email
        [ -n "$git_email" ] || { echo "Git email is required."; exit 1; }
        git config --global user.email "$git_email"
        changed=1
    fi
    if [ "$(git config --global url."git@github.com:".insteadOf 2>/dev/null || true)" != "https://github.com/" ]; then
        git config --global url."git@github.com:".insteadOf "https://github.com/"
        changed=1
    fi
    if [ "$(git config --global core.editor 2>/dev/null || true)" != "vim" ]; then
        git config --global core.editor vim
        changed=1
    fi
    if [ "$changed" = 0 ]; then
        echo "Git: identity already set ($git_name <$git_email>)."
    else
        echo "Git: identity set ($git_name <$git_email>)."
    fi

# GitHub CLI: log in and add an SSH key if there is none.
gh-setup:
    #!/usr/bin/bash
    set -euo pipefail
    command -v gh >/dev/null 2>&1 || { echo "GitHub CLI: 'gh' is not installed (it ships in the image); cannot continue."; exit 1; }
    if ! gh auth status >/dev/null 2>&1; then
        echo "GitHub CLI: log in now."
        # The flags pre-answer the interactive prompts (host, protocol,
        # web auth). --skip-ssh-key leaves the key upload to the step
        # below; --scopes requests the key scope up front, which the
        # login flow otherwise only grants when it uploads a key itself.
        gh auth login --hostname github.com --git-protocol ssh --web --skip-ssh-key --scopes admin:public_key
    else
        echo "GitHub CLI: already logged in."
    fi
    if [ ! -f ~/.ssh/id_ed25519.pub ]; then
        echo "GitHub CLI: creating an SSH key (you will be prompted for a passphrase)."
        ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519
    fi
    # Listing and adding keys needs the admin:public_key scope; a login
    # from before this recipe requested it may not have it.
    if ! gh auth status 2>&1 | grep -q "admin:public_key"; then
        echo "GitHub CLI: authorizing SSH key access (browser step)."
        gh auth refresh --hostname github.com --scopes admin:public_key
    fi
    # Presence is checked by the key itself, not its title: the key may
    # already be on the account under any title. An empty blob means the
    # .pub file is unreadable or corrupt — fail loudly rather than let
    # an empty pattern "match" every key on the account.
    key_blob="$(awk '{print $2}' ~/.ssh/id_ed25519.pub)"
    [ -n "$key_blob" ] || { echo "GitHub CLI: ~/.ssh/id_ed25519.pub has no key in it; fix or regenerate the key, then rerun 'ujust setup'."; exit 1; }
    # A failed keys listing must not be read as "key absent": that path
    # ends in a redundant upload attempt and a confusing 422.
    if ! account_keys="$(gh api user/keys --jq '.[].key' 2>/dev/null)"; then
        echo "GitHub CLI: could not list your GitHub SSH keys; check the connection and rerun 'ujust setup'."
        exit 1
    fi
    if printf '%s\n' "$account_keys" | grep -qF "$key_blob"; then
        echo "GitHub CLI: SSH key already on GitHub."
    else
        echo "GitHub CLI: adding the SSH key to GitHub."
        gh ssh-key add ~/.ssh/id_ed25519.pub --title "Personal Computer"
    fi

# Muse SDK: prompt for the token directly, pair, set the run-as user, enable the service.
muse-sdk:
    #!/usr/bin/bash
    set -euo pipefail
    mode_file="$HOME/.config/personal-blue/login-mode"
    if [ -f "$mode_file" ]; then
        recorded_mode="$(cat "$mode_file")"
        case "$recorded_mode" in
            sdk) ;;
            keeper)
                echo "Muse SDK: skipped — this machine is in Keeper mode (see 'ujust login-mode')."
                exit 0
                ;;
            *)
                echo "Muse SDK: login mode file $mode_file contains '$recorded_mode', which is not a valid mode (keeper or sdk). Fix it by hand or delete it and rerun 'ujust setup'."
                exit 1
                ;;
        esac
    fi
    if ! systemctl cat musegadget.service >/dev/null 2>&1; then
        echo "Muse SDK: not installed in this image; skipping (install the SDK first)."
        exit 0
    fi
    # Already-set-up check, deliberately sudo-free: a status check must
    # not demand a password. This recipe only enables the service after
    # a successful pairing, so enabled + active means paired. The exact
    # pairing-file check runs further down, inside the setup path, where
    # sudo is already needed for the real work.
    if systemctl is-enabled musegadget.service >/dev/null 2>&1 && systemctl is-active musegadget.service >/dev/null 2>&1; then
        echo "Muse SDK: already paired and enabled."
        exit 0
    fi
    read -rp "Set up the Muse SDK (pair and enable the service)? [Y/n] " answer
    case "$answer" in ""|y|Y|yes|YES) ;; *) echo "Muse SDK: skipped."; exit 0 ;; esac
    # Override the build-time placeholder run-as user (muse) with this account.
    sudo mkdir -p /etc/systemd/system/musegadget.service.d
    printf '[Service]\nEnvironment=MUSEGADGET_RUN_AS=%s\n' "$(whoami)" | sudo tee /etc/systemd/system/musegadget.service.d/10-run-as.conf >/dev/null
    sudo systemctl daemon-reload
    if sudo test -s /var/lib/musegadget/pairing.json; then
        echo "Muse SDK: already paired."
    else
        echo "Muse SDK: enter the SDK token (from the Muse app; input is hidden, and the token is saved under /var/lib/musegadget, never in Keeper)."
        read -rsp "Muse SDK token: " token
        echo
        [ -n "$token" ] || { echo "No token entered."; exit 1; }
        sudo install -d -m 0700 /var/lib/musegadget
        printf '%s\n' "$token" | sudo install -m 0600 /dev/stdin /var/lib/musegadget/sdk_token
        echo "Muse SDK: token saved. Pairing now — follow the prompts in the Muse app."
        sudo musegadget pair
    fi
    sudo systemctl enable --now musegadget.service
    echo "Muse SDK: service enabled."

# Muse distrobox: a default Fedora distrobox named "muse-code"
# with its own home directory, Muse and the Dev Containers CLI
# installed inside it. Independent of the login mode above: the box
# holds no Keeper or Muse SDK credentials, and Muse is signed
# in inside the box on its first run there.
muse-code-distrobox:
    #!/usr/bin/bash
    set -euo pipefail
    box_name="muse-code"
    box_image="registry.fedoraproject.org/fedora-toolbox:44"
    box_home="$HOME/distrobox/muse-code"
    if ! command -v distrobox >/dev/null 2>&1; then
        echo "Muse distrobox: distrobox is not installed on this host; skipping."
        exit 0
    fi
    mkdir -p "$box_home"
    if podman container exists "$box_name" 2>/dev/null; then
        echo "Muse distrobox: '$box_name' already exists."
    else
        echo "Muse distrobox: creating '$box_name' from $box_image (home: $box_home)."
        distrobox create --yes --name "$box_name" --image "$box_image" --home "$box_home"
    fi
    # Check and install inside the box through a login shell: a plain
    # 'distrobox enter -- cmd' exec uses the image's stock PATH, which
    # does not include the box home's ~/.local/bin, so 'muse' would
    # not be found there even when it is installed.
    distrobox enter "$box_name" -- bash -lc '
        set -euo pipefail
        if ! command -v muse >/dev/null 2>&1; then
            echo "Muse: installing inside the distrobox."
            curl -fsSL https://dev.meta.ai/install.sh | sh
        else
            echo "Muse: already installed in the distrobox."
        fi
        if ! command -v devcontainer >/dev/null 2>&1; then
            if ! command -v npm >/dev/null 2>&1; then
                echo "Dev Containers CLI: installing Node.js and npm first."
                sudo dnf -y install nodejs npm
            fi
            echo "Dev Containers CLI: installing inside the distrobox."
            npm install -g --prefix "$HOME/.local" @devcontainers/cli
        else
            echo "Dev Containers CLI: already installed in the distrobox."
        fi
        command -v muse >/dev/null
        command -v devcontainer >/dev/null
    '
    echo "Muse distrobox: ready. Enter it with 'distrobox enter muse-code'; the first 'muse' run inside signs you in."

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
