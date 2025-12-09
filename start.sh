#!/bin/bash

if [ "$1" = "setup" ]; then
	# download the setup script
	# run the setup script
else
	echo
	echo "========================================"
	echo "Sekoia Forwarder Setup"
	echo "========================================"
	echo
	echo "Step 1. Change password"
	echo "------------------------------"
	echo "Command: passwd"
	echo
	echo "Step 2. Configure networking"
	echo "------------------------------"
	echo "Edit IP, gateway and DNS of the existing interface."
	echo "Command: sudo nano /etc/network/interfaces"
	echo
	echo "Step 3. Update the system"
	echo "------------------------------"
	echo "Command: sudo apt-get update -y && sudo apt-get upgrade -y"
	echo
	echo "Step 4. Launch setup"
	echo "------------------------------"
	echo "Command: ./start.sh setup"
	echo
fi

