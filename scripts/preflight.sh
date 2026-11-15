#!/usr/bin/env bash
# Read-only checks for the local Vagrant/libvirt host.
set -euo pipefail

missing=0
for tool in git curl python3 vagrant virsh qemu-system-x86_64 timeout; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf 'OK      %s\n' "$tool"
  else
    printf 'MISSING %s\n' "$tool"
    missing=1
  fi
done

if [[ -r /dev/kvm && -w /dev/kvm ]]; then
  printf 'OK      KVM device access\n'
else
  printf 'MISSING read/write access to /dev/kvm\n'
  missing=1
fi

if command -v vagrant >/dev/null 2>&1; then
  if [[ "$(vagrant --version)" == 'Vagrant 2.4.9' ]]; then
    printf 'OK      Vagrant 2.4.9\n'
  else
    printf 'MISSING required Vagrant version 2.4.9\n'
    missing=1
  fi
  if vagrant plugin list | grep -Fq 'vagrant-libvirt (0.12.2,'; then
    printf 'OK      vagrant-libvirt 0.12.2\n'
  else
    printf 'MISSING vagrant-libvirt 0.12.2\n'
    missing=1
  fi
fi

if command -v virsh >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
  if timeout 5 virsh --readonly --connect qemu:///system list >/dev/null 2>&1; then
    printf 'OK      system libvirt connection\n'
  else
    printf 'MISSING access to system libvirt (qemu:///system)\n'
    missing=1
  fi
fi

printf '\nMemory (MiB):\n'
free -m
printf '\nDisk space for this checkout:\n'
df -h "$(dirname -- "${BASH_SOURCE[0]}")/.."
printf '\nVM RAM allocation: 8704 MiB. Before a cold start, aim for 10240 MiB available.\n'
printf 'Available RAM is informational; running lab VMs already use this allocation.\n'
exit "$missing"
