#!/usr/bin/env bash
# Run as your normal user on the Ubuntu 24.04 host. Sudo prompts in the terminal.
set -euo pipefail

if [[ $EUID -eq 0 ]]; then
  printf 'Run this script as your normal user, without sudo.\n' >&2
  exit 1
fi

source /etc/os-release
if [[ "$ID" != ubuntu || "$VERSION_ID" != 24.04 || "$(dpkg --print-architecture)" != amd64 ]]; then
  printf 'This setup script supports Ubuntu 24.04 on amd64.\n' >&2
  exit 1
fi

vagrant_version=2.4.9-1
plugin_version=0.12.2
deb_name="vagrant_${vagrant_version}_amd64.deb"
deb_sha256=42d830d05e6e9e647f8a5c854d9f5295e319dac74edd37d54b97b4f29cbbd70d
lab_user=$(id -un)
download_dir=$(mktemp -d)
trap 'rm -rf -- "$download_dir"' EXIT

sudo -v
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  ca-certificates curl git python3 openssh-client \
  qemu-system-x86 qemu-utils libvirt-daemon-system libvirt-clients dnsmasq-base \
  build-essential pkg-config libvirt-dev ruby-dev libxml2-dev libxslt1-dev zlib1g-dev

if [[ "$(dpkg-query -W -f='${Version}' vagrant 2>/dev/null || true)" != "$vagrant_version" ]]; then
  curl --fail --show-error --location --retry 3 \
    "https://apt.releases.hashicorp.com/pool/amd64/main/$deb_name" \
    --output "$download_dir/$deb_name"
  printf '%s  %s\n' "$deb_sha256" "$download_dir/$deb_name" | sha256sum --check --status
  chmod 755 "$download_dir"
  sudo apt-get install -y "$download_dir/$deb_name"
fi

sudo systemctl enable --now libvirtd
for group in libvirt kvm; do
  if ! id -nG "$lab_user" | tr ' ' '\n' | grep -qx "$group"; then
    sudo gpasswd -a "$lab_user" "$group"
  fi
done

if ! vagrant plugin list | grep -Fq "vagrant-libvirt ($plugin_version,"; then
  vagrant plugin install vagrant-libvirt --plugin-version "$plugin_version"
fi

printf '\nHost setup finished. Log out and back in to refresh group membership.\n'
printf 'Then run: bash scripts/preflight.sh\n'
