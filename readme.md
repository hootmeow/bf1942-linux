# 🪖 Battlefield 1942 Dedicated Server (Linux, Non-Privileged Runtime)

Automated setup script for running a **Battlefield 1942 Dedicated Server** on modern 64-bit Linux systems.

This solution installs the legacy 32-bit Battlefield 1942 dedicated server using a dedicated, non-privileged account, following best security practices. It handles dependency resolution (including legacy libraries), user creation, and server installation in a single pass.

---

## 🧩 Overview

- **Single-Script Setup**: One script handles OS dependencies, user creation, and game installation.
- **Secure Runtime**: Runs entirely under a dedicated service account (`bf1942_user`).
- **Modern Compatibility**: Automatically installs required i386 libraries and legacy `libncurses5`/`libstdc++5` on Ubuntu 24.04+ / Debian 12+.
- **Systemd Integration**: Managed via standard `systemctl` commands.
- **Optional Manager**: Option to install **BFSMD** (Battlefield Server Manager Daemon) for easy remote GUI management.

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

You have two options for installation. **We recommend using the BFSMD version** for the ease of server and player management. The installation scripts in this ReadMe are for Ubuntu 24.0.3 LTS.  For others distro's select the appropriate install script from the project and adjust the file names and links accordingly. 

#### Option A: Install with BFSMD (Recommended)
This version installs the Battlefield Server Manager Daemon, allowing you to manage the server remotely via the Windows client.

```bash
curl -O https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/ubuntu/24.0.3_bfsmd_setup.sh
chmod +x 24.0.3_bfsmd_setup.sh
sudo ./24.0.3_bfsmd_setup.sh
```

#### Option B: Standard Installation
This version installs the base dedicated server without the remote manager daemon.

```bash
curl -# -O https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/ubuntu/24.0.3_setup.sh
chmod +x 24.0.3_setup.sh
sudo ./24.0.3_setup.sh
```

---
### 2️⃣ Connect to Server Manager (BFSMD Only)
If you installed the BFSMD version, open your Battlefield Server Manager client (Windows) and connect using your server's IP address. Use the default credentials below:

```text
Default Username : bf1942
Default Password : battlefield
```
![BFSMD Login](images/bfsmd_password.png)

### 3️⃣ Set Server IP
Once connected, navigate to the IP settings tab. You must set the server's IP address explicitly under the **IP Address** field to ensure it binds correctly to your network interface.

![Set Server IP](images/bfsmd_ip_addr.png)

### 4️⃣ Secure Remote Console & Admin
Go to the **Remote Console** or **Admin** tab. Change the default passwords immediately to something secure. This protects your server from unauthorized rcon commands.

![Remote Console Security](images/bfsmd_remoteconsole.png)

### 5️⃣ Set a Default Map
The server requires a map rotation to start effectively. Go to the **Maps** list and add at least one map to the rotation to set it as the default map.

![Set Default Map](images/bfsmd_setmap.png)

### 6️⃣ Server Manager Users
For security, do not keep using the default account.
1.  Change the password for the `bf1942` user from the default (`battlefield`).
2.  Create new accounts for any other admins if needed.
3.  Ensure you set appropriate permissions for each user.

![Set Admin Users](images/bfsmd_adminpassword.png)
---

## 🧪 Supported Distributions

| Distro | Status | Notes |
| :--- | :--- | :--- |
| **Ubuntu 24.04.3 LTS** | ✅ Tested | Primary tested platform. |
| **Ubuntu 22.04 LTS** | 📝 TODO | Likely works; may need minor package name adjustments. |
| **Debian 12 (Bookworm)** | 📝 TODO | Uses the same multiarch structure as Ubuntu. |
| **Fedora** | 📝 TODO | Requires converting `apt` commands to `dnf`. |
| **CentOS Stream / RHEL** | 📝 TODO | Requires converting `apt` commands to `yum/dnf`. |

---

## 🧑‍🎨 Author
OWLCAT 🔗 https://github.com/hootmeow

## 📜 License
Scripts released under the MIT License. All Battlefield 1942 game assets remain © Electronic Arts Inc.
