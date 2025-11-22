# 🪖 Battlefield 1942 Dedicated Server (Linux, Non-Privileged Runtime)

Automated setup script for running a **Battlefield 1942 Dedicated Server** on modern 64-bit Linux systems.

This solution installs the legacy 32-bit Battlefield 1942 dedicated server using a dedicated, non-privileged account, following best security practices. It handles dependency resolution (including legacy libraries), user creation, and server installation in a single pass.

---

## 🧩 Overview

- **Single-Script Setup**: One script handles OS dependencies, user creation, and game installation.
- **Secure Runtime**: Runs entirely under a dedicated service account (`bf1942_user`).
- **Modern Compatibility**: Automatically installs required i386 libraries and legacy `libncurses5`/`libstdc++5` on Ubuntu 24.04+ / Debian 12+.
- **Systemd Integration**: Managed via standard `systemctl` commands.

---

## ⚙️ Configuration

The setup script contains several configuration variables at the top that you can customize before running.

| Variable | Default | Description |
| :--- | :--- | :--- |
| `BF_USER` | `bf1942_user` | The system username created to run the server. |
| `BF_HOME` | `/home/bf1942_user` | The home directory for the service user. |
| `BF_ROOT` | `~/bf1942` | The actual game installation directory. |
| `SERVER_TAR_URL` | `.../linux-bf1942-server.tar` | URL to the game server tarball. |


---

## 🚀 Usage

> **Prerequisite:** Commands must be run by a user with **sudo** privileges.

### 1️⃣ Download and Run
This install script is for Ubuntu 24.0.3 servers.  For others distro's select the appropriate install script from the project and adjust the file names and links accordingly.
Download the script to your server:

```bash
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/ubuntu/24.0.3_setup.sh
chmod +x 24.0.3_setup.sh
sudo ./24.0.3_setup.sh
```

---
## 🧑‍🎨 Author
OWLCAT 🔗 https://github.com/hootmeow

## 📜 License
Scripts released under the MIT License. All Battlefield 1942 game assets remain © Electronic Arts Inc.
