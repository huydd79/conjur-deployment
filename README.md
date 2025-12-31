# CyberArk Conjur Enterprise - Deployment Scripts

This repository contains a professional suite of automated scripts designed to deploy and configure a **CyberArk Conjur Enterprise (Secrets Manager)** environment. It is optimized for Lab, Research, and Demo purposes, following CyberArk's production-grade recommendations and the latest v13.7/15.0 standards.



## 🚀 Overview

These scripts automate the complete lifecycle of a Conjur cluster, providing a "Ready-to-Demo" environment with minimal manual intervention.
* **Architecture:** Supports Leader (Primary), Standby (High Availability), and Follower (Read-scale) nodes.
* **Security:** Implements 3rd party SSL certificate management and Hardened container volumes.
* **Sync:** Ready for Vault Synchronizer integration (PAM Self-hosted integration).
* **Identity:** Configured for CyberArk Identity SSO scenarios.

---

## 📋 Prerequisites

Before starting, ensure the following are prepared:
1. **OS**: RHEL/CentOS 8+ or Ubuntu 20.04+.
2. **Container Engine**: Podman (recommended) or Docker installed.
3. **Appliance Image**: The Conjur Appliance tarball (v13.7.0+) must be placed in `/opt/upload`.
4. **Network**: SSH key-based authentication must be enabled between the Leader and other cluster nodes.
5. **Certificates**: If using 3rd party certs, place `ca-chain.pem`, `master-cert.pem`, and `master-key.pem` in the `./certs` directory.

---

## 🛠️ Configuration (The Source of Truth)

All scripts rely on **`00.config.sh`**. Modify this file first with your specific IPs, DNS names, and credentials. Ensure `READY=true` is set before execution.


## HOW TO:
Refer to this video recording for detail
https://youtu.be/2nvF2HD40o8

# Author: Huy Do (huy.do@cyberark.com)
# Tested: December 2025