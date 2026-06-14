# ADS Security Experiments

## Folder Descriptions
- `/SROS2-XML` - XML configurations for setting up Secure ROS2 for Autoware.
- `/Spring2026-Demo` - Relevant files for setting up and replicating the Autoware unauthenticated service endpoints attack demo from Spring 2026.

## Recommended Machines Specs
The workstation we used in the SORA Labspace had the following specifications:
- Ubuntu 22.04.5 LTS, Jammy Jellyfish
- NVIDIA GeForce RTX 3090 Ti
	- Driver version: 575.51.03
	- CUDA version: 12.9
- 32 GB of RAM
- 2 TB of disk space
- ROS 2 Humble

We also got Autoware on the Cyber@UCI server infrastructure on a dedicated VM with the following specs:
- Ubuntu 22.04.3 LTS, Jammy Jellyfish
- (No GPU)
- 16 GB of RAM
- 40 GB of disk space
	- NOTE: This amount of disk space is far from ideal, and I had to resize once already.
- ROS 2 Humble

