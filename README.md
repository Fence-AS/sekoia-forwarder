# Automated Sekoia Forwarder Setup

Automates the installation and guides the user through the configuration of the **Sekoia Forwarder**, **Endpoint agent**, and **Forwarder Health agent**.

## Contents
- [Prerequisites](#Prerequisites)
    - [Networking](#Networking)
    - [System](#System)
- [Installation](#Installation)
    - [Minimal software installation](#minimal-software-installation)
    - [Set a static IP address in Debian 13](#Set-a-static-IP-address-in-Debian-13)
- [Updates](#updates)
    - [Upgrading the script](#upgrading-the-script)
    - [Migration from `wget`](#migration-from-wget)
 
---

## Prerequisites

### Networking

- _Inbound TCP/UDP_ flows from systems and applications to the forwarder on the ports of your choice
- _Outbound TCP_ flow to `intake.sekoia.io` (FRA1) on port `10514`
- _Outbound HTTPS_ (`443`) for installation and the weekly update, to the Debian package mirrors, `download.docker.com`, `ghcr.io`, `raw.githubusercontent.com`, `github.com` and `app.sekoia.io`. If this is blocked, the forwarder keeps running but the weekly update will fail (see `journalctl -u forwarder-update`).

### System

- This setup script must run on Debian (or a Debian-based) `amd64`/`x86-64` system.
    - We recommend a [minimal software installation](#minimal-software-installation) of Debian 13.
      - Use the `netinst` ISO: [https://www.debian.org/download](https://www.debian.org/download)
- Recommended system requirements (number of assets counts across all intakes):
  | Number of assets    |  vCPUs |  RAM (GB) | Disk size (GB) |
  |---------------------|:------:|:---------:|:--------------:|
  | `1000`  _(default)_ |   `2`  |   `4`     |     `200`      |
  | `10 000`            |   `4`  |   `8`     |     `1000`     |
  | `50 000`            |   `6`  |   `16`    |     `5000`     |

> [!NOTE]
> These data are recommendations based on standards and observed averages on Sekoia.io, so they may change depending on usecases.
> _More information: [https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites](https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites)_

---

## Installation

> [!TIP]
>  Remember to set a **static IP address** [in Debian](#set-a-static-ip-address-in-debian-13), via DHCP, or other methods.

> [!IMPORTANT]
> Unless the root account was disabled during installation by leaving its password blank, `sudo` must be installed manually and your user added to the sudo group.
>
> - As `root`: `apt install sudo -y`
> - Add the forwarder user: `usermod -aG sudo <USERNAME>`
> - Log out and back in for changes to take effect.

Clone the repository and run the setup script:

```bash
sudo apt install -y git
git clone https://github.com/Fence-AS/sekoia-forwarder.git
bash sekoia-forwarder/setup.sh
```

The script first validates the system: Debian-based with `apt-get`, `amd64`, and an outbound connection to `intake.sekoia.io:10514`. If only the connection check fails, it asks whether to continue.

During execution, the script prompts for confirmation to run the following steps:

- Change the user password
- Change the root password
- Install dependencies
- Install Docker
- Install the Sekoia agent
- Configure intakes and forwarder monitoring
- Generate the docker-compose file (including log rotation for the container)
- Install the weekly update job
- Start the Sekoia forwarder

---

### Minimal software installation


<img width="1460" height="471" alt="image" src="https://github.com/user-attachments/assets/26ec6b3f-2682-44d2-9741-049b924816da" />
<br/>
<img width="2058" height="1158" alt="image" src="https://github.com/user-attachments/assets/adfa8f40-29ea-463f-9933-caedd8c186e1" />

---

### Set a static IP address in Debian 13

If a different method is used to achieve a static IP address, this step can be skipped. 

Check IP address and interface name with:

```bash
ip -br a
```

Open this file with sudo:

```bash
sudo nano /etc/network/interfaces
```

Edit the part that says `iface <YOUR_INTERFACE_NAME> inet dhcp` (usually under `# The primary network interface`) to this:

```conf
iface <YOUR_INTERFACE_NAME> inet static
    address <IP_ADDRESS>          # e.g. 192.168.1.234
    netmask <NETMASK>             # e.g. 255.255.255.0
    gateway <GATEWAY>             # e.g. 192.168.1.1
    dns-nameservers <DNS_SERVERS> # e.g. 8.8.8.8 1.1.1.1
```

Save changes and restart the interface:

```bash
sudo systemctl restart ifup@<YOUR_INTERFACE_NAME>
```

---

## Updates

A systemd timer (`forwarder-update.timer`) runs every Sunday at 03:00 and:

1. Upgrades the operating system packages.
2. Updates the forwarder image version from the upstream docker-compose template and restarts the forwarder. If the new version does not come up, the previous compose file is restored.
3. Reboots the server.

Check the schedule and the result of the last run:

```bash
systemctl list-timers forwarder-update.timer
journalctl -u forwarder-update
```

To run an update immediately (the server reboots when it finishes):

```bash
sudo systemctl start forwarder-update.service
```

### Upgrading the script

To get the latest script run:

```bash
cd sekoia-forwarder
git pull
bash setup.sh --upgrade
```

This locates the install directory from the running container, installs the upgrade and may recreate the container (a few seconds of downtime).

### Migration from `wget`

A forwarder installed with the old `wget` method has no clone yet. Do not run the commands from [Installation](#installation), they start a new installation.

Instead clone the repository and only run #setup.py with `--upgrade`. It will automatically find the existing installation, wherever it was installed:

```bash
sudo apt install -y git
git clone https://github.com/Fence-AS/sekoia-forwarder.git
bash sekoia-forwarder/setup.sh --upgrade
```
