#!/bin/bash

# this file requires tabs for indentation
# do not replace tabs with spaces

START_PORT=22001
DEFAULT_PROTOCOL=tcp
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DEST="$HOME/sekoiaio-concentrator"
INTAKES="intakes.yaml"
DOCKER_COMPOSE="docker-compose.yml"
COMPOSE_OVERRIDE="docker-compose.override.yml"
IMAGE_VERSION=2.7.5
DOCKER_COMPOSE_TEMPLATE_URL='https://raw.githubusercontent.com/SEKOIA-IO/sekoiaio-docker-concentrator/main/docker-compose/docker-compose.yml'
SEKOIA_AGENT=agent-latest
SEKOIA_AGENT_URL='https://app.sekoia.io/api/v1/xdr-agent/download/agent-latest'
FORWARDER_UPDATER=/opt/forwarder-updater.sh

# a failing command inside a pipe (e.g. curl | gpg) must not be hidden
set -o pipefail


function display_welcome {
	cat <<'EOF'
          _         _
 ___  ___| | _____ (_) __ _
/ __|/ _ \ |/ / _ \| |/ _` |
\__ \  __/   < (_) | | (_| |
|___/\___|_|\_\___/|_|\__,_|
  __                                  _
 / _| ___  _ ____      ____ _ _ __ __| | ___ _ __
| |_ / _ \| '__\ \ /\ / / _` | '__/ _` |/ _ \ '__|
|  _| (_) | |   \ V  V / (_| | | | (_| |  __/ |
|_|  \___/|_|    \_/\_/ \__,_|_|  \__,_|\___|_|

EOF
echo "> Default choices are shown in brackets ([Y]/n = default Yes, y/[N] = default No)."
echo "> Remember to set a static IP address! (via DHCP or in Debian)"
echo && read -r -p "---->>> Start Sekoia Forwarder installation? (y/[N]): " answer

if [[ "$answer" =~ ^[Nn] || -z "$answer" ]]; then
	exit
fi
}

function validate_system {
	echo "---->>> Validating system..."

	if ! command -v apt-get > /dev/null; then
		echo "---->>> This is not a Debian-based system (apt-get not found), aborting..."
		exit 1
	fi

	if [[ "$(dpkg --print-architecture)" != amd64 ]]; then
		echo "---->>> Unsupported architecture, amd64 is required, aborting..."
		exit 1
	fi

	if ! timeout 5 bash -c "</dev/tcp/intake.sekoia.io/10514" 2>/dev/null; then
		echo "---->>> No outbound connection to intake.sekoia.io:10514"
		read -r -p "Continue anyway? (y/[N]): " answer
		if [[ !("$answer" =~ ^[Yy]) ]]; then
			exit 1
		fi
	fi

	echo "-->>> System validated."
}

function change_user_password {
	echo "---->>> Change password for user '$USER'"
	passwd || return 1
	echo "-->>> Password for user '$USER' has been changed."
}

function change_root_password {
	echo "---->>> Change password for 'root' user (first enter the sudo password for user '$USER')"
	sudo passwd root || return 1
	echo "-->>> Password for user 'root' has been changed."
}

function install_dependencies {
	echo "---->>> Installing dependencies; a sudo password prompt might appear"
	sudo apt-get update || return 1
	echo "---->>> Installing unattended upgrades..."
	sudo apt-get install -y unattended-upgrades || return 1
	echo "---->>> Installing prerequisite packages..."
	sudo apt-get install -y ca-certificates curl gnupg wget || return 1
	echo "-->>> Dependencies and prerequisite packages installed."
}

function docker_install {
	# from https://docs.sekoia.io/integration/ingestion_methods/sekoiaio_forwarder/#5-minutes-setup-on-debian
	local distro codename
	distro=$(. /etc/os-release && case "$ID $ID_LIKE" in *ubuntu*) echo ubuntu ;; *debian*) echo debian ;; esac)
	codename=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")

	if [[ -z "$distro" || -z "$codename" ]]; then
		echo "---->>> Could not determine a supported Debian/Ubuntu release from /etc/os-release."
		return 1
	fi

	sudo apt-get update
	sudo apt-get remove -y docker.io docker-compose docker-doc docker-buildx podman-docker containerd runc
	echo "---->>> Old docker versions removed"

	sudo mkdir -m 0755 -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/$distro/gpg | sudo gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg || return 1
	echo "---->>> Docker GPG key added"

	echo \
	  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$distro \
	  $codename stable" | sudo tee /etc/apt/sources.list.d/docker.list
	echo "---->>> Repository updated, ready to start Docker installation"

	sudo apt-get update
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || return 1
	echo "---->>> Docker packages installed"

	sudo docker run --rm hello-world || return 1
	echo "-->>> Docker installed and verified."
}

function install_sekoia_agent {
	if systemctl is-active --quiet SEKOIAEndpointAgent.service; then
		echo "---->>> Sekoia Endpoint Agent already running, skipping install."
		return
	fi

	if [[ -f "/opt/endpoint-agent/agent" ]]; then
		echo "---->>> Sekoia Endpoint Agent is already installed! Verify with 'systemctl status SEKOIAEndpointAgent.service'."
		return
	fi

	if [[ -f ./"$SEKOIA_AGENT" ]]; then
		echo "---->>> Sekoia Endpoint Agent installer already exists, removing..."
		rm -f ./"$SEKOIA_AGENT"
	fi

	echo "---->>> Downloading Sekoia Endpoint Agent..."
	if ! wget -O ./"$SEKOIA_AGENT" "$SEKOIA_AGENT_URL"; then
		echo "---->>> Sekoia Endpoint Agent download failed."
		rm -f ./"$SEKOIA_AGENT"
		return 1
	fi

	echo "---->>> Installing Sekoia Endpoint Agent..."

	if systemctl is-active --quiet auditd; then
		echo "---->>> auditd will be stopped and disabled for agent compatibility."
		sudo systemctl stop auditd
		sudo systemctl disable auditd

	elif systemctl is-enabled --quiet auditd; then
		echo "---->>> auditd is enabled and will be disabled for agent compatibility."
		sudo systemctl disable auditd
	fi

	# setup Sekoia agent with intake key
	read -r -p "Sekoia endpoint agent intake key: " agent_key
	chmod +x ./"$SEKOIA_AGENT"
	if ! sudo ./"$SEKOIA_AGENT" install --intake-key "$agent_key"; then
		echo "---->>> Sekoia Endpoint Agent installation failed."
		rm -f ./"$SEKOIA_AGENT"
		return 1
	fi
	sudo systemctl status SEKOIAEndpointAgent.service --no-pager
	rm -f ./"$SEKOIA_AGENT"
	# stop listening to audit events
	sudo systemctl stop systemd-journald-audit.socket
	sudo systemctl disable systemd-journald-audit.socket
	sudo systemctl mask systemd-journald-audit.socket
	sudo systemctl restart systemd-journald
	echo "-->>> Sekoia Endpoint Agent installation step complete."
}

function parse_input_to_yaml() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

function make_intake_file {
	echo "---->>> Configuring intakes"
	mv  "$INTAKES" "$INTAKES".bck 2>/dev/null

	# format file
	echo -e "---\nintakes:" > "$INTAKES"

	for i in {0..50}; do
		echo "---->>> Add new intake"

		# set name
		read -r -p "  A descriptive name: " intake_name
		intake_name_clean="${intake_name// /-}"

		# set protocol and calculate port
		read -r -p "  Network protocol to use, default is $DEFAULT_PROTOCOL (tcp/udp): " protocol_type

		if [[ !( $protocol_type =~ ^(tcp|udp)$ ) ]]; then
			protocol_type="$DEFAULT_PROTOCOL"
		fi

		current_port=$(( $START_PORT + i))

		# set intake key
		read -r -p "  Sekoia intake key: " intake_key

		# write changes
		cat <<-EOF >> "$INTAKES"
		- name: "$( parse_input_to_yaml "$intake_name_clean" )"
		  protocol: "$( parse_input_to_yaml "$protocol_type" )"
		  port: $current_port
		  intake_key: "$( parse_input_to_yaml "$intake_key" )"
		EOF

		echo "Added intake $intake_name ($current_port/$protocol_type)"
		sleep 0.5

		# break loop if more intakes are not needed
		read -r -p "More intakes? (y/[N]): " answer
		if [[ !("$answer" =~ ^[Yy]) ]]; then
			break
		fi
	done

	echo "---->>> Activating monitoring of forwarder logs"
	sleep 1
	read -r -p "  Sekoia.io forwarder logs intake key: " intake_key
	cat <<-EOF >> "$INTAKES"
	- name: Monitoring
	  stats: True
	  intake_key: "$(parse_input_to_yaml "$intake_key")"
	EOF
	echo "---->>> Wrote \`"$INTAKES"\`"
	sleep 1

	echo "-->>> Intake file configured."
}

function make_docker_compose_file {
	echo "---->>> Downloading docker-compose template..."
	mv "$DOCKER_COMPOSE" "$DOCKER_COMPOSE".bck 2>/dev/null
	if ! wget -O "$DOCKER_COMPOSE" "$DOCKER_COMPOSE_TEMPLATE_URL"; then
		echo "---->>> Download of the docker-compose template failed."
		rm -f "$DOCKER_COMPOSE"
		mv "$DOCKER_COMPOSE".bck "$DOCKER_COMPOSE" 2>/dev/null
		return 1
	fi

	if grep -q "20516-20566:20516-20566" "$DOCKER_COMPOSE"; then
		nr_of_ports=$(grep -c "port:" "$INTAKES")
		LAST_PORT=$(( START_PORT + nr_of_ports - 1 ))
		echo "---->>> Modifying ports in docker-compose file to match intake file"
		sed -i "s/20516-/$START_PORT-/g" "$DOCKER_COMPOSE"
		sed -i "s/-20566/-$LAST_PORT/g" "$DOCKER_COMPOSE"
	else
		echo "---->>> Layout of docker-compose template file has changed. This script must be updated"
		echo "---->>> Aborting..."
		exit 1
	fi

	set_image_version
	make_compose_override
	echo "-->>> Docker compose file configured."
}

function make_compose_override {
	# the upstream template does not rotate container logs, cap them so they cannot fill the disk
	if [[ -f "$COMPOSE_OVERRIDE" ]]; then
		echo "---->>> $COMPOSE_OVERRIDE already exists, leaving it untouched."
		return
	fi

	cat <<-EOF > "$COMPOSE_OVERRIDE"
	services:
	  rsyslog:
	    logging:
	      driver: json-file
	      options:
	        max-size: "50m"
	        max-file: "5"
	EOF
	echo "---->>> Wrote $COMPOSE_OVERRIDE"
}

function set_image_version {
	if [[ "$UPGRADE" == true ]] && ! grep -q "image:.*:$IMAGE_VERSION$" "$DOCKER_COMPOSE"; then
		cp -p "$DOCKER_COMPOSE" "$DOCKER_COMPOSE".bck || return 1
		echo "---->>> Backed up compose file to $INSTALL_DEST/$DOCKER_COMPOSE.bck"
	fi

	sed -i "s|^\([[:space:]]*image:.*:\).*|\1$IMAGE_VERSION|" "$DOCKER_COMPOSE" || return 1
	echo "---->>> Forwarder image set to $IMAGE_VERSION"
}

function start_forwarder {
	echo "---->>> Starting the forwarder..."
	sudo docker compose up -d || return 1

	echo "---->>> Verifying the forwarder, please wait..."
	sleep 10
	if [[ "$(sudo docker compose ps --format '{{.State}}' | sort -u)" != "running" ]]; then
		echo "---->>> The forwarder is not running!"
		sudo docker compose ps
		sudo docker compose logs --tail 20
		if [[ "$UPGRADE" == true ]]; then
			echo "---->>> To go back: cd $INSTALL_DEST && mv $DOCKER_COMPOSE.bck $DOCKER_COMPOSE && sudo docker compose up -d"
		fi
		return 1
	fi

	sudo docker compose ps
	echo "-->>> Forwarder is running. Logs from the monitoring intake should show up in Sekoia within a few minutes."
}

function make_upgrade_job {
	echo "---->>> Installing weekly update job"
	sudo install -m 700 -o root -g root "$SCRIPT_DIR/forwarder-updater.sh" "$FORWARDER_UPDATER" || return 1

	sudo tee /etc/systemd/system/forwarder-update.service > /dev/null <<-EOF || return 1
	[Unit]
	Description=Sekoia forwarder system update
	After=network-online.target docker.service
	Wants=network-online.target

	[Service]
	Type=oneshot
	ExecStart=$FORWARDER_UPDATER
	EOF

	sudo tee /etc/systemd/system/forwarder-update.timer > /dev/null <<-EOF || return 1
	[Unit]
	Description=Weekly Sekoia forwarder update

	[Timer]
	OnCalendar=Sun *-*-* 03:00:00
	Persistent=true

	[Install]
	WantedBy=timers.target
	EOF

	sudo systemctl daemon-reload || return 1
	sudo systemctl enable --now forwarder-update.timer || return 1
	echo "-->>> Weekly update job installed. Check with 'systemctl list-timers forwarder-update.timer'."
}

function final_info {
	if [[ ! -d "$INSTALL_DEST" ]]; then
		echo "---->>> No Sekoia Forwarder installation path found!"
		exit 1
	fi

	echo "---->>> Intake file in use:"
	cat "$INTAKES"
	echo; echo; echo
	sleep 1
	echo "-->>> NOTE: Edit \`"$INTAKES"\` to modify protocols, ports, and intakes."
}

function execute_steps {
	for funct in "$@"; do
		read -r -p "Run step $funct? ([Y]/n): " answer
		# accepts y, Y, and [ENTER] (empty)
		if [[ "$answer" =~ ^[Yy] || -z "$answer" ]]; then
			if ! "$funct"; then
				echo "---->>> Step $funct failed."
				read -r -p "Continue with the next step anyway? (y/[N]): " answer
				if [[ !("$answer" =~ ^[Yy]) ]]; then
					exit 1
				fi
			fi
		fi
	done
}

function setup {
	debian=(
		change_user_password
		change_root_password
		install_dependencies
	)

	docker_sekoia=(
		docker_install
		install_sekoia_agent
		make_intake_file
		make_docker_compose_file
		make_upgrade_job
		start_forwarder
	)

	# verify Debian state
	echo "-->>> Starting Debian configuration."
	sleep 1
	execute_steps "${debian[@]}"

	echo "-->>> Starting Docker and Sekoia Forwarder configuration."
	sleep 1

	# create install dir
	mkdir -p "$INSTALL_DEST"
	cd "$INSTALL_DEST"

	# install docker and forwarder
	execute_steps "${docker_sekoia[@]}"
}

function find_install_dir {
	# the compose label on the forwarder container tells where it was installed
	local dir
	dir=$(sudo docker ps -a --format '{{.Image}}|{{.Label "com.docker.compose.project.working_dir"}}' | grep -F 'sekoiaio-docker-concentrator' | head -n1 | cut -d'|' -f2-)

	if [[ -n "$dir" ]]; then
		INSTALL_DEST="$dir"
	fi

	if [[ ! -f "$INSTALL_DEST/$DOCKER_COMPOSE" ]]; then
		read -r -p "Could not find the forwarder, enter its install directory: " INSTALL_DEST
	fi

	[[ -f "$INSTALL_DEST/$DOCKER_COMPOSE" ]]
}

function upgrade_forwarder {
	# upgrade steps to do for "old" forwarders
	upgrade_steps=(
		make_upgrade_job
		set_image_version
		make_compose_override
		start_forwarder
	)

	echo "---->>> Upgrading existing Sekoia Forwarder installation"

	if ! find_install_dir; then
		echo "---->>> No Sekoia Forwarder installation found, aborting..."
		exit 1
	fi

	echo "---->>> Using install directory: $INSTALL_DEST"
	cd "$INSTALL_DEST"
	execute_steps "${upgrade_steps[@]}"
}

########################################
# Main
########################################

UPGRADE=false
if [[ "$1" == "--upgrade" ]]; then
	UPGRADE=true
elif [[ -n "$1" ]]; then
	echo "Usage: bash setup.sh [--upgrade]"
	exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
	echo "ERROR: Do not run this script as 'root' or with 'sudo'!"
	echo "         Run 'bash setup.sh' as user with sudo privileges."
	exit 1
fi

if [[ "$UPGRADE" == false ]]; then
	display_welcome
fi

# run if user is in sudoers
if id -nG "$USER" | grep -qw sudo; then
	if [[ "$UPGRADE" == true ]]; then
		upgrade_forwarder
	else
		validate_system
		setup
		final_info
	fi
else
	echo "ERROR: User is not in sudoers group!"
	echo
	echo " 1) Login as root:"
	echo "      su -"
	echo " 2) Install sudo:"
	echo "      apt install sudo -y"
	echo " 3) Add '$USER' to sudo group:"
	echo "      usermod -aG sudo '$USER'"
	echo " 4) Log out from root and then from '$USER'"
	echo "      exit"
	echo "      exit"
	echo " 5) Log in as '$USER'"
	echo " 6) Re-run this script"
	echo
fi

