#!/bin/bash
# Weekly system update of the Sekoia forwarder host.
# Started as root by forwarder-update.timer. The image version is set by setup.sh --upgrade.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
APT_OPTIONS=(-o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

# full-upgrade installs new kernels, they take effect with the reboot below
apt-get update -q "${APT_OPTIONS[@]}"
apt-get full-upgrade -y -q "${APT_OPTIONS[@]}"
apt-get autoremove -y -q "${APT_OPTIONS[@]}"

echo "Rebooting..."
systemctl reboot
