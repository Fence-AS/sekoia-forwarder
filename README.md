# Automated Sekoia Forwarder Setup

Automates the installation and guides the user through the configuration of the **Sekoia Forwarder**, **Endpoint agent**, and **Forwarder Health agent**.

## Prerequisites

### Networking

- _INBOUND TCP/UDP_ flows from systems and applications to the forwarder on the ports of your choice
- _OUTBOUND TCP_ flow to `intake.sekoia.io` (FRA1) on port `10514` (only use the IP if absolutely necessary: `213.32.5.228`)

### System

Minimal recommended system requirements (1000 assets across all intakes):

|  vCPUs |  RAM (GB) | Disk size (GB) |
|--------|:---------:|:--------------:|
|    2   |   4       |      200       |

> _More information here: [https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites](https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites)_

This setup script must run on Debian (or a Debian-based) amd64/x86-64 system. _We recommend a minimal software installation of Debian 13._

- Download the `netinst` (recommended) ISO here: [https://www.debian.org/download](https://www.debian.org/download)

---

## Installation

> Remember to set a [static IP address](#set-a-static-ip-address-in-debian-13).

Download and run the setup script:

```bash
wget https://raw.githubusercontent.com/Fence-AS/sekoia-forwarder/refs/heads/main/setup.sh
bash setup.sh
```

> By default, minimal Debian 13 doesn't include `sudo`.
>
> - As `root`: `apt install sudo -y`
> - Add the forwarder user: `usermod -aG sudo <USERNAME>`
> - Log out and back in for changes to take effect.

During execution, the script prompts for confirmation to run the following steps:

- Change the user password
- Change the root password
- Install dependencies
- Install Docker
- Install the Sekoia agent
- Configure intakes and forwarder monitoring
- Generate the docker-compose file
- Start the Sekoia forwarder

---

### Set a static IP address in Debian 13

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
