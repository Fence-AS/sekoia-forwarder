#!/bin/bash

# this file requires tabs for indentation
# do not replace tabs with spaces

START_PORT=22001
DEFAULT_PROTOCOL=tcp
BASE_DIR="$(pwd)"
INSTALL_DEST="$BASE_DIR/sekoiaio-concentrator"
INTAKES="intakes.yaml"
DOCKER_COMPOSE="docker-compose.yml"
DOCKER_COMPOSE_TEMPLATE_URL='https://raw.githubusercontent.com/SEKOIA-IO/sekoiaio-docker-concentrator/main/docker-compose/docker-compose.yml'
SEKOIA_AGENT=agent-latest
SEKOIA_AGENT_URL='https://app.sekoia.io/api/v1/xdr-agent/download/agent-latest'

function change_user_password {
	echo "---->>> Change password of $USER"
	passwd 
}

function change_root_password {
	echo "---->>> Change password of user root (first enter sudo password of $USER)"
	sudo passwd root
}

function install_dependencies {
	sudo apt-get update > /dev/null
	echo '---->>> Installing unattended upgrades...'
	sudo apt-get install -y unattended-upgrades
	echo '---->>> Installing prerequisite packages...'
	sudo apt-get install -y ca-certificates curl gnupg lsb-release wget > /dev/null
	echo '---->>> Installing auditd...'
	sudo apt-get install -y auditd
}

function docker_install {
	# from https://docs.sekoia.io/integration/ingestion_methods/sekoiaio_forwarder/#5-minutes-setup-on-debian
	sudo apt-get update > /dev/null
	sudo apt-get remove docker docker-engine docker.io containerd runc > /dev/null
	echo '---->>> Old docker version deleted'

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
	mv  "$INTAKES" "$INTAKES".bck 2>/dev/null

	echo '---->>> Configuring intakes'
	echo -e "---\nintakes:" > "$INTAKES"
	for i in {0..50}; do
		echo '---->>> Add new intake'
		read -r -p '  A descriptive name: ' intake_name
		read -r -p "  Network protocol (tcp/udp default: $DEFAULT_PROTOCOL): " protocol_type

		if [[ !( $protocol_type =~ ^(tcp|udp) ) ]]; then
			protocol_type="$DEFAULT_PROTOCOL"
		fi

		read -r -p '  Sekoia intake key: ' intake_key
		cat <<-EOF >> "$INTAKES"
		- name: $(echo "$intake_name" | tr -s ' ' '-')
		  protocol: $protocol_type
		  port: $(( $START_PORT + i))
		  intake_key: $intake_key
		EOF
		echo
		read -r -n1 -p 'More intakes? (y/n): ' answer
		case "$answer" in
			[Yy] ) echo; echo; continue ;;
			* ) echo; break ;;
		esac
	done

	echo '---->>> Activating monitoring of forwarder logs'
	read -r -p '  Sekoia.io forwarder logs intake key: ' intake_key
	cat <<-EOF >> "$INTAKES"
	- name: Monitoring
	  stats: True
	  intake_key: $intake_key
	EOF
	echo "---->>> Wrote \`"$INTAKES"\`"
}

function make_docker_compose_file {
	mv  "$DOCKER_COMPOSE" "$DOCKER_COMPOSE".bck 2>/dev/null

	echo '---->>> Downloading docker-compose template...'
	wget -O "$DOCKER_COMPOSE" "$DOCKER_COMPOSE_TEMPLATE_URL"
	grep -q '20516-20566:20516-20566' "$DOCKER_COMPOSE"
	if [[ $? -eq 0 ]]; then
		nr_of_ports=$(grep -c 'port:' "$INTAKES")
		LAST_PORT=$(( START_PORT + nr_of_ports - 1 ))
		echo '---->>> Modifying ports in docker-compose file to match intake file'
		sed -i "s/20516/$START_PORT/g" "$DOCKER_COMPOSE"
		sed -i "s/20566/$LAST_PORT/g" "$DOCKER_COMPOSE"
	else
		echo '---->>> Layout of docker-compose template file has changed. This script must be updated'
		echo '---->>> Aborting...'
		exit 1
	fi
}

function start_forwarder {
	echo '---->>> Starting the forwarder...'
	sudo docker compose up -d
}

function final_info {
	echo "---->>> Intake file in use:"
	cat "$INTAKES"
	echo
	echo "---->>> NOTE: Edit \`"$INTAKES"\` to change protocols or ports if required"
}

function runner {
	mkdir -p "$INSTALL_DEST"
	cd "$INSTALL_DEST"

	ordered_steps=(
		change_user_password
		change_root_password
		install_dependencies
		docker_install
		install_sekoia_agent
		make_intake_file
		make_docker_compose_file
		start_forwarder
	)

	for funct in "${ordered_steps[@]}"; do
		read -r -p "Run step $funct? ([Y]/n): " answer
		
		if [[ "$answer" =~ ^[Yy] || -z "$answer" ]]; then
			"$funct"
		fi

	done
}

########################################
# Main
########################################

if [[ "$EUID" -eq 0 ]]; then
	echo "ERROR: Do not run this script as root or with sudo."
	exit 1
fi

# run if user is in sudoers
if id -nG "$USER" | grep -qw sudo; then
	runner
	final_info
else
	echo 'ERROR: User is not in sudoers'
	echo
	echo ' 1) su -'
	echo ' 2) apt install -y sudo'
	echo " 3) usermod -aG sudo $USER"
	echo ' 4) exit'
	echo ' 5) exit'
	echo
	echo 'Log in and re-run this script'
fi

