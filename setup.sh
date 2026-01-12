#!/bin/bash

# this file uses tabs
# do not substitute tabs for spaces

START_PORT=22001
DEFAULT_PROTOCOL=tcp
INSTALL_DEST=sekoiaio-concentrator
INTAKES=intakes.yaml
DOCKER_COMPOSE=docker-compose.yml
DOCKER_COMPOSE_TEMPLATE_URL='https://raw.githubusercontent.com/SEKOIA-IO/sekoiaio-docker-concentrator/main/docker-compose/docker-compose.yml'
SEKOIA_AGENT=agent-latest
SEKOIA_AGENT_URL='https://app.sekoia.io/api/v1/xdr-agent/download/agent-latest'

EXTRA_PORTS=0 # updated by script

function initial_os_setup {
	echo '---->>> Installing sudo...'
	sudo apt-get install -y sudo
	echo "---->>> Change password of user $(whoami)"
	passwd
	echo "---->>> Adding $(whoami) as sudoer"
	usermod -aG sudo $(whoami)
	echo "---->>> Change password of user root (first enter sudo password of $(whoami))"
	sudo passwd root
	sudo apt-get install -y unattended-upgrades
	echo '---->>> Installing auditd...'
	sudo apt-get install -y auditd
}

function docker_install {
	sudo apt-get remove docker docker-engine docker.io containerd runc > /dev/null
	echo '---->>> Old docker version deleted'

	sudo apt-get update > /dev/null
	sudo apt-get install -y ca-certificates curl gnupg lsb-release > /dev/null
	echo '---->>> System updated and prerequisite packages intalled'

	sudo mkdir -m 0755 -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	echo '---->>> Docker GPG key collected'

	echo \
	  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
	  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	echo "---->>> Repository updated, ready to start docker installation"

	sudo apt-get update > /dev/null
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null
	echo '---->>> Docker packages intalled'

	sudo docker run hello-world
}

function install_sekoia_agent {
	echo '---->>> Downloading Sekoia Endpoint Agent...'
	wget "$SEKOIA_AGENT_URL"
	echo '---->>> Installing Sekoia Endpoint Agent...'
	sudo systemctl stop auditd
	sudo systemctl disable auditd
	read -p 'Sekoia endpoint agent intake key: ' agent_key
	chmod +x ./"$SEKOIA_AGENT"
	sudo ./"$SEKOIA_AGENT" install --intake-key "$agent_key"
	sudo systemctl status SEKOIAEndpointAgent.service
	rm "$SEKOIA_AGENT"
}

function make_intake_file {
	mkdir -p "$INSTALL_DEST" && cd "$INSTALL_DEST"
	mv  "$INTAKES" "$INTAKES".bck 2>/dev/null

	echo '---->>> Configuring intakes'
	echo -e "---\nintakes:" > "$INTAKES"
	for i in {0..10000}; do
		echo '---->>> Add new intake'
		read -p '  A descriptive name: ' intake_name
		read -p '  Sekoia intake key: ' intake_key
		cat <<-EOF >> "$INTAKES"
		- name: $(echo $intake_name | tr -s ' ' '-')
		  protocol: $DEFAULT_PROTOCOL
		  port: $(( $START_PORT + i))
		  intake_key: $intake_key
		EOF
		echo
		read -n1 -p 'More intakes? (y/n): ' answer
		case "$answer" in
			[Yy]* ) echo; echo; continue ;;
			* ) break ;;
		esac
	done
	EXTRA_PORTS=$i

	echo '---->>> Activating  monitoring of forwarder logs'
	read -p '  Sekoia.io forwarder logs intake key : ' intake_key
	cat <<-EOF >> "$INTAKES"
	- name: Monitoring
	   stats: True
	   intake_key: $intake_key
	EOF
	echo -e "\n"
	echo "---->>> Wrote \`"$INTAKES"\`"
}

function make_docker_compose_file {
	mkdir -p "$INSTALL_DEST" && cd "$INSTALL_DEST"
	mv  "$DOCKER_COMPOSE" "$DOCKER_COMPOSE".bck 2>/dev/null

	echo '---->>> Downloading docker-compose template...'
	wget "$DOCKER_COMPOSE_TEMPLATE_URL"
	grep -q '20516-20566:20516-20566' "$DOCKER_COMPOSE"
	if [ $? -eq 0 ]; then
		echo '---->>> Modifying ports in docker-compose file to match intake file'
		sed -i "s/20516/$START_PORT/g" "$DOCKER_COMPOSE"
		sed -i "s/20566/$(( START_PORT + EXTRA_PORTS))/g" "$DOCKER_COMPOSE"
	else
		echo '---->>> Layout of docker-compose file has changed. This script must be updated'
		echo '---->>> Aborting...'
		exit 1
	fi
}

function start_forwarder{
	mkdir -p "$INSTALL_DEST" && cd "$INSTALL_DEST"
	echo '---->>> Starting the forwarder...'
	sudo docker compose up -d
}

function final_info {
	echo "---->>> Intake file in use:"
	cat "$INTAKES"
	echo
	echo "---->>> NOTE: Edit \`"$INTAKES"\` to change protocols or ports if required"
}

function run_engine {
	declare -A steps=(
		[initial_os_setup]="Initial setup of  sudo etc."
		[docker_install]="Install Docker"
		[install_sekoia_agent]="Install Sekoia agent"
		[make_intake_file]="Configure ports and intake keys"
		[make_docker_compose_file]="Prepare docker-compose file"
		[start_fowarder]="Start fowarder"
	)

	for fun in "${!steps[@]}"; do
		echo "${steps[$fun]}"
		read -rp "Run $fun? [y/N] " answer
		[[ "$answer" =~ ^[Yy] ]] && "$fun"
	done
}

if [ "$1" = "install" ]; then

	if [[ "$EUID" -eq 0 ]]; then
		echo "ERROR: Do not run this script as root or with sudo."
		exit 1
	fi

	run_engine
	final_info
else
	echo
	echo '========================================'
	echo 'Sekoia Forwarder Setup'
	echo '========================================'
	echo
	echo 'Step 1. Change password'
	echo '------------------------------'
	echo 'Command: passwd'
	echo
	echo 'Step 2. Configure networking'
	echo '------------------------------'
	echo 'Edit IP, gateway and DNS of the existing interface.'
	echo 'Command: sudo nano /etc/network/interfaces'
	echo
	echo 'Step 3. Update the system'
	echo '------------------------------'
	echo 'Command: sudo apt-get update -y && sudo apt-get upgrade -y'
	echo
	echo 'Step 4. Launch setup'
	echo '------------------------------'
	echo 'Command: ./setup.sh install'
	echo
fi

