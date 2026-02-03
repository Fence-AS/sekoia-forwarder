# Automated Sekoia Forwarder Setup

Installs prerequisites and guides the user through the configuration of the Sekoia Forwarder, Endpoint agent, and Forwarder Health agent.

It must be run on Debian (or Debian-based) distribution. We recommend a minimal software installation of Debian 13.
- Download the `netinst` (recommended) iso here: https://www.debian.org/download

Minimal recommended system requirements (for 1000 assets):
  |  vCPUs |  RAM (Go) | Disk size (Go) |
  |------|:---------:|:--------------:|
  |    2   |   4       |      200       |
  - _More information here: https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites_


---

## Installation

> Remember to set a [static IP address](set-a-static-ip-address-in-debian-13).

Download and run the setup script:
```
wget https://raw.githubusercontent.com/Fence-AS/sekoia-forwarder/refs/heads/main/setup.sh
bash setup.sh
```

During execution, the script prompts for confirmation to run the following steps:

- Change the user password
- Change the root password
- Install required dependencies
- Install Docker
- Install the Sekoia agent
- Configure intakes and forwarder monitoring
- Generate the docker-compose file
- Start the Sekoia forwarder

---

### Set a static IP address in Debian 13

Check IP address and interface name with:
```
ip -br a
```

Open this file with sudo:
```
sudo nano /etc/network/interfaces
```

Edit the part that says `iface <YOUR_INTERFACE_NAME> inet dhcp` (usually under `# The primary network interface`) to this:
```
iface <YOUR_INTERFACE_NAME> inet static
    address <IP_ADDRESS> (i.e. 192.168.1.234)
    netmask <NETMASK> (i.e. 255.255.255.0)
    gateway <GATEWAY> (i.e. 192.168.1.1)
    dns-nameservers <DNS_SERVERS> (i.e. 8.8.8.8 1.1.1.1)
```

Save changes and restart the interface:
```
sudo systemctl restart ifup@<YOUR_INTERFACE_NAME>
```

---
