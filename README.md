# personal-blue

Scott's personal OS image, built with [BlueBuild](https://blue-build.org/) on top of [wayblue](https://github.com/wayblueorg/wayblue)'s `sway-nvidia` image (Fedora Atomic 44, Sway, Nvidia closed drivers).

## What's customized

Everything in `files/system/` is copied into the image root at build time:

- `etc/skel/.config/foot/foot.ini` — foot terminal defaults to monospace 12pt
- `etc/skel/.config/sway/config` — Scott's sway setup: kanshi autostart, workspace 8 on eDP-1, $mod+c opens the Firefox flatpak, $mod+w locks with swaylock, $mod+Shift+w suspends (swayidle locks on suspend), 50px resize steps

These live in `/etc/skel`, so they land in a new user's home directory on first login. An existing `~/.config` takes precedence over them.

## Installation

To rebase an existing Fedora Atomic installation to the latest build:

- First rebase to the unsigned image, to get the proper signing keys and policies installed:
  ```
  rpm-ostree rebase ostree-unverified-registry:ghcr.io/scottcrossen/personal-blue:latest
  ```
- Reboot, then rebase to the signed image:
  ```
  rpm-ostree rebase ostree-image-signed:docker://ghcr.io/scottcrossen/personal-blue:latest
  ```
- Reboot again.

## Builds

GitHub Actions rebuilds the image daily (06:00 UTC) and on every push, pulling the latest wayblue base each time, so it tracks Fedora, kernel, Nvidia driver, and wayblue updates automatically. The base is pinned to Fedora 44 via `image-version` in `recipes/recipe.yml` — bump that number when moving to a new Fedora release.

## Signing setup (before the first build)

The template ships a placeholder `cosign.pub`. Before the first signed build, generate your own cosign keypair, replace `cosign.pub` with your public key, and add the private key as a `SIGNING_SECRET` repository secret. See the [BlueBuild setup docs](https://blue-build.org/how-to/setup/).
