#!/bin/bash

# this file uses tabs
# do not substitute tabs for spaces

START_PORT=21111
DEFAULT_PROTOCOL=tcp
INTAKES=intakes.yaml
DOCKER_COMPOSE=docker-compose.yml
DOCKER_COMPOSE_TEMPLATE_URL='https://raw.githubusercontent.com/SEKOIA-IO/sekoiaio-docker-concentrator/main/docker-compose/docker-compose.yml'
SEKOIA_AGENT=agent-latest
SEKOIA_AGENT_URL='https://app.sekoia.io/api/v1/xdr-agent/download/agent-latest'

EXTRA_PORTS=0 # updated by script

function install_agent {
	echo "---->>> Downloading Sekoia Endpoint Agent..."
	wget "$SEKOIA_AGENT_URL"
	echo "---->>> Installing Sekoia Endpoint Agent..."
	sudo systemctl stop auditd
	sudo systemctl disable auditd
	read -p 'Sekoia endpoint agent intake key: ' agent_key
	chmod +x ./"$SEKOIA_AGENT"
	sudo ./"$SEKOIA_AGENT" install --intake-key "$agent_key"
	sudo systemctl status SEKOIAEndpointAgent.service
}

function make_intake_file {
	echo -e "---\nintakes:" > "$INTAKES"
	for i in {0..10000}; do
		echo '---->>> Adding new intake'
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
	echo -e "\n"
	echo "---->>> Wrote \`"$INTAKES"\`:"
	cat "$INTAKES"
	echo 
	echo "---->>> NOTE: Edit \`"$INTAKES"\` to change protocols or ports if required"
}

function make_docker_compose_file {
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

function start_docker {
	echo '---->>> Starting the forwarder'
	sudo docker compose up -d
}

# don't touch configuration if it already exists
warn_file_exists() {
	local file="$1"
	echo "---->>> $file is already configured."
	echo "  Edit \`$file\` to change configuration."
	echo "  Or delete/move \`$file\` and re-run to continue."
	echo
	exit 1
}

if [ "$1" = "install" ]; then
	install_agent

	mkdir -p sekoiaio-concentrator && cd sekoiaio-concentrator

	for f in "$INTAKES" "$DOCKER_COMPOSE"; do
		[ -f "$f" ] && warn_file_exists "$f"
	done

	make_intake_file
	make_docker_compose_file
	start_docker
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

