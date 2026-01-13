This script automates the setup of a Sekoia Forwarder and Sekoia agent.

It must be run on Debian or a Debian-based distribution with a minimal software installation.

System requirements are documented here:

<https://docs.sekoia.io/integration/ingestion_methods/syslog/sekoiaio_forwarder/#prerequisites>

## Installation

Download and run the setup script:

```
wget <shortened-url>/setup.sh
bash setup.sh
```

## Setup steps

During execution, the script prompts for confirmation to run the following steps:

- Change the root password
- Install required dependencies
- Install Docker
- Install the Sekoia agent
- Configure intakes and forwarder monitoring
- Generate the docker-compose file
- Start the Sekoia forwarder

