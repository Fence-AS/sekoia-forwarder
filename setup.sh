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
	echo "---->>> Change password of user '$USER'"
	passwd 
}

function change_root_password {
	echo "---->>> Change password of user 'root' (first enter sudo password of user '$USER')"
	sudo passwd root
}

function install_dependencies {
	sudo apt-get update > /dev/null
	echo "---->>> Installing unattended upgrades..."
	sudo apt-get install -y unattended-upgrades
	echo "---->>> Installing prerequisite packages..."
	sudo apt-get install -y ca-certificates curl gnupg lsb-release wget > /dev/null
}

function docker_install {
	# from https://docs.sekoia.io/integration/ingestion_methods/sekoiaio_forwarder/#5-minutes-setup-on-debian
	sudo apt-get update > /dev/null
	sudo apt-get remove -y docker docker-engine docker.io containerd runc > /dev/null
	echo "---->>> Old docker version deleted"

	sudo mkdir -m 0755 -p /etc/apt/keyrings
	curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
	echo "---->>> Docker GPG key collected"

	echo \
	  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
	  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
	echo "---->>> Repository updated, ready to start docker installation"

	sudo apt-get update > /dev/null
	sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin > /dev/null
	echo "---->>> Docker packages installed"

	sudo docker run hello-world
}

function install_sekoia_agent {
	if systemctl is-active --quiet SEKOIAEndpointAgent.service; then
		echo "---->>> Sekoia Endpoint Agent already running, skipping install."
		return
	fi

	if [[ -f ./"$SEKOIA_AGENT" ]]; then
		echo "---->>> Sekoia Endpoint Agent installer already exists, removing..."
		rm -f ./"$SEKOIA_AGENT"
	fi

	echo "---->>> Downloading Sekoia Endpoint Agent..."
	if ! wget -O ./"$SEKOIA_AGENT" "$SEKOIA_AGENT_URL"; then
		echo "---->>> Sekoia Endpoint Agent download failed, skipping install."
		rm -f ./"$SEKOIA_AGENT"
		return
	fi

	if [[ -f "/opt/endpoint-agent/agent" ]]; then
		echo "---->>> Sekoia Endpoint Agent is already installed! Verify with 'systemctl status SEKOIAEndpointAgent.service'."
	else
		echo "---->>> Installing Sekoia Endpoint Agent..."
		
		if systemctl is-active --quiet auditd; then
			echo "---->>> auditd will be stopped and disabled for agent compatibility."
			sudo systemctl stop auditd
			sudo systemctl disable auditd
		fi

		# setup Sekoia agent with intake key
		read -r -p "Sekoia endpoint agent intake key: " agent_key
		chmod +x ./"$SEKOIA_AGENT"
		sudo ./"$SEKOIA_AGENT" install --intake-key "$agent_key"
		sudo systemctl status SEKOIAEndpointAgent.service --no-pager
		rm "$SEKOIA_AGENT"
	fi
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
	sleep 0.5
	read -r -p "  Sekoia.io forwarder logs intake key: " intake_key
	cat <<-EOF >> "$INTAKES"
	- name: Monitoring
	  stats: True
	  intake_key: "$(parse_input_to_yaml "$intake_key")"
	EOF
	echo "---->>> Wrote \`"$INTAKES"\`"
	sleep 0.5
}

function make_docker_compose_file {
	echo "---->>> Downloading docker-compose template..."
	mv  "$DOCKER_COMPOSE" "$DOCKER_COMPOSE".bck 2>/dev/null
	wget -O "$DOCKER_COMPOSE" "$DOCKER_COMPOSE_TEMPLATE_URL"
	grep -q "20516-20566:20516-20566" "$DOCKER_COMPOSE"
	
	if [[ $? -eq 0 ]]; then
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
}

function start_forwarder {
	echo "---->>> Starting the forwarder..."
	sudo docker compose up -d
}

function final_info {
	echo "---->>> Intake file in use:"
	cat "$INTAKES"
	echo; echo; echo
	sleep 0.5
	echo "---->>> NOTE: Edit \`"$INTAKES"\` to modify protocols, ports, intakes."
}

function execute_steps {
	for funct in "$@"; do
		read -r -p "Run step $funct? ([Y]/n): " answer
		
		# accepts y, Y, and [ENTER] (empty)
		if [[ "$answer" =~ ^[Yy] || -z "$answer" ]]; then
			"$funct"
		fi
	done 
}

function setup {
	debian=(
		change_user_password
		change_root_password
	)

	docker_sekoia=(
		docker_install
		install_sekoia_agent
		make_intake_file
		make_docker_compose_file
		start_forwarder
	)

	# create install dir
	mkdir -p "$INSTALL_DEST"
	cd "$INSTALL_DEST"

	# verify Debian state
	execute_steps "${debian[@]}"

	# install docker & sekoia deps before setup
	install_dependencies
	execute_steps "${docker_sekoia[@]}"
}

########################################
# Main
########################################

if [[ "$EUID" -eq 0 ]]; then
	echo "ERROR: Do not run this script as 'root' or with 'sudo'!"
	echo "         Run 'bash setup.sh' as user with sudo privileges."
	exit 1
fi

# run if user is in sudoers
if id -nG "$USER" | grep -qw sudo; then
	setup
	final_info
else
	echo "ERROR: User is not in sudoers group!"
	echo
	echo " 1) Login to root:"
	echo "      su -"
	echo " 2) Install sudo:"
	echo "      apt install sudo -y"
	echo " 3) Add '$USER' to sudo group:"
	echo "      usermod -aG sudo '$USER'"
	echo " 4) Logout of root and then '$USER'"
	echo "      exit"
	echo "      exit"
	echo " 5) login as '$USER'"
	echo " 6) re-run this script"
	echo
fi

