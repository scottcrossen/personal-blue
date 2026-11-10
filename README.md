# personal-blue

This is my personal Universal Blue image, layered on wayblue's sway-nvidia.

## Switch to this image

Once the image is published:

```sh
# Rebase to the unsigned image first, so the signing keys and policies get installed
rpm-ostree rebase ostree-unverified-registry:ghcr.io/scottcrossen/personal-blue-sway-nvidia:latest
systemctl reboot

# Then rebase to the signed image
rpm-ostree rebase ostree-image-signed:docker://ghcr.io/scottcrossen/personal-blue-sway-nvidia:latest
systemctl reboot
```
