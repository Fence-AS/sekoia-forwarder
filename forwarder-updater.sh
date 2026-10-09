#!/bin/bash
# Weekly update of the Sekoia forwarder host and image.
# Started as root by forwarder-update.timer, INSTALL_DEST is set by the service unit.

set -euo pipefail

DOCKER_COMPOSE="docker-compose.yml"
# same template as in setup.sh
TEMPLATE_URL='https://raw.githubusercontent.com/SEKOIA-IO/sekoiaio-docker-concentrator/main/docker-compose/docker-compose.yml'

function forwarder_is_running {
	sleep 20
	[[ "$(docker compose ps --format '{{.State}}' | sort -u)" == "running" ]]
}

function rollback {
	echo "Update failed, restoring previous compose file"
	cp -p "$DOCKER_COMPOSE".bck "$DOCKER_COMPOSE"
	docker compose up -d || true
	echo "Rebooting..."
	systemctl reboot
	exit 1
}

cd "$INSTALL_DEST"

# fetch the image line from upstream and check it before touching anything
TEMP_COMPOSE=$(mktemp)
trap 'rm -f "$TEMP_COMPOSE"' EXIT
wget -qO "$TEMP_COMPOSE" "$TEMPLATE_URL"
IMAGE_LINE=$(grep -m1 -E '^[[:space:]]*image:' "$TEMP_COMPOSE" || true)

if [[ ! "$IMAGE_LINE" =~ ^[[:space:]]*image:[[:space:]]*[A-Za-z0-9./_:@-]+[[:space:]]*$ ]]; then
	echo "Unexpected or missing image line in upstream template, aborting"
	exit 1
fi

# upgrade system, kernel and other updates take effect with the reboot below
export DEBIAN_FRONTEND=noninteractive
APT_OPTIONS=(-o DPkg::Lock::Timeout=600 -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)
apt-get update -q "${APT_OPTIONS[@]}"
apt-get upgrade -y -q "${APT_OPTIONS[@]}"

# upgrade image, roll back if the new one does not come up
cp -p "$DOCKER_COMPOSE" "$DOCKER_COMPOSE".bck
sed -i "s|^[[:space:]]*image:.*|$IMAGE_LINE|" "$DOCKER_COMPOSE"
docker compose config -q && docker compose pull && docker compose up -d && forwarder_is_running || rollback

docker image prune -f
echo "Rebooting..."
systemctl reboot
