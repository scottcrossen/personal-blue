# Personal setup recipes for the personal-blue image.
# Shipped at /usr/share/ublue-os/just/60-custom.just and auto-imported
# by the base justfile (import? "60-custom.just").
# Run once on a fresh host: `ujust setup`. Every step is idempotent
# and skips work that is already done. Nothing here contains personal
# info: names, emails and tokens are prompted for at first run,
# never baked into the image.

# First-run setup: Keeper login, git identity, GitHub CLI, Muse SDK, Firefox flatpak.
setup: login-mode keeper-login git-identity gh-setup muse-sdk firefox-flatpak
    #!/usr/bin/bash
    set -euo pipefail
    # Stamp the booted image version into the login-mode state file:
    # the login configuration above is complete for this image, so
    # later setup runs on the same version have nothing to redo. A
    # failed step aborts setup before this body runs, leaving the old
    # version recorded so the next run asks again.
    state_file="$HOME/.config/personal-blue/login-mode"
    current_version="$(rpm-ostree status --json 2>/dev/null | python3 -c 'import json,sys; print(next((d.get("version","") for d in json.load(sys.stdin)["deployments"] if d.get("booted")), ""))' 2>/dev/null || true)"
    if [ -f "$state_file" ] && [ -n "$current_version" ]; then
        recorded_mode="$(sed -n '2p' "$state_file")"
        case "$recorded_mode" in
            keeper|sdk) printf '%s\n%s\n' "$current_version" "$recorded_mode" > "$state_file" ;;
        esac
    fi
    echo "Setup complete."

# Login mode: a machine is configured for Keeper OR for the Muse SDK,
# never both, and the configuration is scoped to the booted image
# version. The state file records the image version setup last
# configured for, plus the chosen mode. Same version: nothing to do.
# New version: setup asks again, logs the other side out, and the
# version is stamped once the whole setup has succeeded (in the setup
# recipe above). Delete the state file to choose again.
login-mode:
    #!/usr/bin/bash
    set -euo pipefail
    state_file="$HOME/.config/personal-blue/login-mode"
    current_version="$(rpm-ostree status --json 2>/dev/null | python3 -c 'import json,sys; print(next((d.get("version","") for d in json.load(sys.stdin)["deployments"] if d.get("booted")), ""))' 2>/dev/null || true)"
    recorded_version=""
    recorded_mode=""
    if [ -f "$state_file" ]; then
        recorded_version="$(sed -n '1p' "$state_file")"
        recorded_mode="$(sed -n '2p' "$state_file")"
        # State files from before version recording held only the mode.
        if [ -z "$recorded_mode" ]; then
            case "$recorded_version" in
                keeper|sdk) recorded_mode="$recorded_version"; recorded_version="" ;;
            esac
        fi
        case "$recorded_mode" in
            keeper|sdk) ;;
            *) echo "Login mode file $state_file does not contain a valid mode (keeper or sdk). Fix it by hand or delete it and rerun 'ujust setup'."; exit 1 ;;
        esac
    fi
    if [ -n "$current_version" ] && [ "$recorded_version" = "$current_version" ]; then
        echo "Login mode: $recorded_mode (already configured for image $current_version; recorded in $state_file, delete the file to choose again)."
        exit 0
    fi
    echo "This machine can be set up for one login, not both:"
    echo "  1) Keeper — log in to Keeper on this machine. The Muse SDK will be logged out and not set up."
    echo "  2) Muse SDK — pair the Muse SDK on this machine. Keeper will be logged out."
    read -rp "Choose 1 or 2: " choice
    case "$choice" in
        1) mode="keeper" ;;
        2) mode="sdk" ;;
        *) echo "Please answer 1 or 2."; exit 1 ;;
    esac
    # Enforce the choice: log the other side out. Both teardowns are
    # best-effort — the other side may never have been set up here.
    if [ "$mode" = "keeper" ]; then
        if systemctl cat musegadget.service >/dev/null 2>&1; then
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
    mkdir -p "$(dirname "$state_file")"
    printf '%s\n%s\n' "$recorded_version" "$mode" > "$state_file"
    echo "Login mode: $mode."

# Log in to Keeper CLI (once). Keeper credentials serve Keeper only:
# no other setup step reads anything from Keeper.
keeper-login:
    #!/usr/bin/bash
    set -euo pipefail
    state_file="$HOME/.config/personal-blue/login-mode"
    current_version="$(rpm-ostree status --json 2>/dev/null | python3 -c 'import json,sys; print(next((d.get("version","") for d in json.load(sys.stdin)["deployments"] if d.get("booted")), ""))' 2>/dev/null || true)"
    recorded_version=""
    recorded_mode=""
    if [ -f "$state_file" ]; then
        recorded_version="$(sed -n '1p' "$state_file")"
        recorded_mode="$(sed -n '2p' "$state_file")"
        # State files from before version recording held only the mode.
        if [ -z "$recorded_mode" ]; then
            case "$recorded_version" in
                keeper|sdk) recorded_mode="$recorded_version"; recorded_version="" ;;
            esac
        fi
        case "$recorded_mode" in
            keeper|sdk) ;;
            *) echo "Keeper: login mode file $state_file does not contain a valid mode (keeper or sdk). Fix it by hand or delete it and rerun 'ujust setup'."; exit 1 ;;
        esac
    fi
    if [ -n "$current_version" ] && [ "$recorded_version" = "$current_version" ]; then
        echo "Keeper: already configured for image $current_version (login mode: $recorded_mode; see 'ujust login-mode')."
        exit 0
    fi
    if [ "$recorded_mode" = "sdk" ]; then
        echo "Keeper: skipped — this machine is in Muse SDK mode (see 'ujust login-mode')."
        exit 0
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
    state_file="$HOME/.config/personal-blue/login-mode"
    current_version="$(rpm-ostree status --json 2>/dev/null | python3 -c 'import json,sys; print(next((d.get("version","") for d in json.load(sys.stdin)["deployments"] if d.get("booted")), ""))' 2>/dev/null || true)"
    recorded_version=""
    recorded_mode=""
    if [ -f "$state_file" ]; then
        recorded_version="$(sed -n '1p' "$state_file")"
        recorded_mode="$(sed -n '2p' "$state_file")"
        # State files from before version recording held only the mode.
        if [ -z "$recorded_mode" ]; then
            case "$recorded_version" in
                keeper|sdk) recorded_mode="$recorded_version"; recorded_version="" ;;
            esac
        fi
        case "$recorded_mode" in
            keeper|sdk) ;;
            *) echo "Muse SDK: login mode file $state_file does not contain a valid mode (keeper or sdk). Fix it by hand or delete it and rerun 'ujust setup'."; exit 1 ;;
        esac
    fi
    if [ -n "$current_version" ] && [ "$recorded_version" = "$current_version" ]; then
        echo "Muse SDK: already configured for image $current_version (login mode: $recorded_mode; see 'ujust login-mode')."
        exit 0
    fi
    if [ "$recorded_mode" = "keeper" ]; then
        echo "Muse SDK: skipped — this machine is in Keeper mode (see 'ujust login-mode')."
        exit 0
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
