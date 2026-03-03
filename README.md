# Automated Sekoia Forwarder Setup

Automates the installation and guides the user through the configuration of the **Sekoia Forwarder**, **Endpoint agent**, and **Forwarder Health agent**.

## Contents
- [Prerequisites](#Prerequisites)
    - [Networking](#Networking)
    - [System](#System)
- [Installation](#Installation)
    - [Set a static IP address in Debian 13](#Set-a-static-IP-address-in-Debian-13)
 
---

## Prerequisites

### Networking

- _Inbound TCP/UDP_ flows from systems and applications to the forwarder on the ports of your choice
- _Outbound TCP_ flow to `intake.sekoia.io` (FRA1) on port `10514`

### System

- This setup script must run on Debian (or a Debian-based) `amd64`/`x86-64` system.
    - _We recommend a minimal software installation of Debian 13 (specifically the `netinst` ISO): [https://www.debian.org/download](https://www.debian.org/download)_
- Recommended system requirements (number of assets counts across all intakes):
  | Number of assets |  vCPUs |  RAM (GB) | Disk size (GB) |
  |------------------|:------:|:---------:|:--------------:|
  | `1000`  _(default)_ |   `2`  |   `4`     |     `200`      |
  | `10 000`         |   `4`  |   `8`     |     `1000`     |
  | `50 000`         |   `6`  |   `16`    |     `5000`     |

> [!NOTE]
> These data are recommendations based on standards and observed averages on Sekoia.io, so they may change depending on usecases.
> _More information: [https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites](https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites)_

---

## Installation

> [!TIP]
>  Remember to set a **static IP address** [in Debian](#set-a-static-ip-address-in-debian-13), via DHCP, or other methods.

Download and run the setup script:

```bash
wget https://raw.githubusercontent.com/Fence-AS/sekoia-forwarder/refs/heads/main/setup.sh
bash setup.sh
```
> [!IMPORTANT]
> By default, minimal Debian 13 **does not** include `sudo`.
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
