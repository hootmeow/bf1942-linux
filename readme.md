# 🪖 Battlefield 1942 Dedicated Server (Linux, Non-Privileged Runtime)

Automated setup and patching scripts for running a **Battlefield 1942 Dedicated Server** on modern 64-bit Linux systems — securely, without ever running the game or related services with elevated privileges.

These scripts install the legacy 32-bit Battlefield 1942 dedicated server using a dedicated, non-privileged account with limited `sudo` permissions, following best security practices.

---

## 🧩 Overview

- Installs and runs entirely under a **dedicated service account** (`bf1942_user`)
- Uses **limited sudoers permissions** for service control
- Works with **systemd** for clean background operation
- Tested on **Ubuntu 24.04.3 LTS**
- Uses **i386 multiarch** and legacy libraries for compatibility


---

## 🧪 Supported Distributions

| Distro | Version | Status | Notes |
|--------|----------|--------|-------|
| **Ubuntu 24.04.3 LTS** | ✅ Tested | Primary tested platform |
| Ubuntu 25.x | 📝 TODO | Expected to work unchanged |
| Ubuntu 22.04 LTS | 📝 TODO | Minor package name adjustments |
| Debian 12 (Bookworm) | 📝 TODO | Same multiarch flow |
| Debian 11 (Bullseye) | 📝 TODO | Legacy libc compatible |
| Fedora 40 | 📝 TODO | Requires dnf multilib equivalents |
| CentOS Stream 9 / Rocky / AlmaLinux 9 | 📝 TODO | Requires yum/dnf adaptation |

---

## 📦 Scripts Overview

### `<version>-setup_env.sh`

Prepares the system for a Battlefield 1942 server environment.

**What it does:**
- Creates a non-privileged user `bf1942_user`
- Prompts for a password for that user
- Enables i386 multiarch and installs required 32-bit libraries
- Downloads the **1.6 RC2 server installer** into `/home/bf1942_user/bf1942/downloads`
- Creates a `systemd` unit to run the server as `bf1942_user`
- Adds a limited sudoers entry so `bf1942_user` can:
  - start, stop, restart, or check the service
  - view logs
  - run patch scripts inside `~/bf1942`

🧱 **Important:** This script only sets up the environment and downloads the installer.  
You’ll download the patch script later in Step 4.

---

### `<version>-apply_patch.sh`

Applies the **1.61 update** to an existing Battlefield 1942 server installation.

**What it does:**
- Downloads `patched1.61.tar`
- Extracts `patched1.61/bf1942/` directly into the install directory (`/home/bf1942_user/bf1942`)
- Fixes permissions and ownership
- Cleans up temporary files
- Requires sudo but never runs as root

---

## 🚀 Usage (Example: Ubuntu 24.04.3 LTS)

> All commands should be run from a user account that has **sudo privileges**.

---

### **1️⃣ Download and run the setup script**

```bash
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux-server/main/ubuntu/24.0.3-setup_env.sh
chmod +x 24.0.3-setup_env.sh
sudo ./24.0.3-setup_env.sh
```

During setup, you’ll be asked to set a password for `bf1942_user`.  
This script installs dependencies, sets up systemd, and downloads the game installer into `/home/bf1942_user/bf1942/downloads`.

---

### **2️⃣ Install the game server**

Switch to the service user and run the installer:

```bash
su - bf1942_user
cd ~/bf1942
./downloads/gf-bf1942_lnxded-1.6-rc2.run
```

When asked for the installation path, enter:

```
/home/bf1942_user/bf1942
```

That ensures the game installs directly into the correct folder — no nested directories.

---

### **3️⃣ Verify the files**

After installation, you should see:

```bash
ls -l ~/bf1942
```

Typical contents:

```
bf1942_lnxded.dynamic
bf1942_lnxded.static
start.sh
mods/
pb/
readmes/
```

---

### **4️⃣ Download and apply the patch**

While still logged in as `bf1942_user`, download and apply the patch script:

```bash
cd ~
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux-server/main/ubuntu/24.0.3-apply_patch.sh
chmod +x 24.0.3-apply_patch.sh
sudo ./24.0.3-apply_patch.sh
```

This applies the 1.61 update directly into `~/bf1942`.

---

### **5️⃣ Start and manage the server**

```bash
su - bf1942_user

# Start the server
sudo systemctl start bf1942.service

# Check status
sudo systemctl status bf1942.service -l

# Restart or stop
sudo systemctl restart bf1942.service
sudo systemctl stop bf1942.service

# View logs
sudo journalctl -u bf1942.service -n 100 --no-pager
```

The `bf1942_user` account has the minimal sudo permissions required for these operations only.

---

## ⚙️ Systemd Unit

```ini
[Unit]
Description=Battlefield 1942 Dedicated Server
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/bf1942_user/bf1942
Environment=TERM=xterm
ExecStart=/bin/sh /home/bf1942_user/bf1942/start.sh +game BF1942 +statusMonitor 1
Restart=on-failure
RestartSec=5
User=bf1942_user
Group=bf1942_user

[Install]
WantedBy=multi-user.target
```

**Why:**  
- Runs the game under `bf1942_user` only  
- Uses `TERM=xterm` to prevent ncurses errors  
- Auto-restarts on failure  
- Fully managed via systemd

---

## 🧠 Troubleshooting

| Issue | Cause | Fix |
|-------|--------|-----|
| `Permission denied` on ~/bf1942 | Directory not owned by service account | `sudo chown -R bf1942_user:bf1942_user /home/bf1942_user` |
| `sudo: not allowed to execute systemctl` | Missing sudoers or wrong path | Verify `/etc/sudoers.d/bf1942_user` includes `/usr/bin/systemctl` |
| `Error opening terminal: unknown.` | Missing TERM variable | Already fixed by `Environment=TERM=xterm` in service unit |
| Patch didn’t overwrite binaries | Wrong tar depth | Script targets `patched1.61/bf1942/` correctly |

---

## 🧑‍🎨 Author

**OWLCAT**  
🔗 https://github.com/hootmeow

---

## 📜 License

Scripts released under the **MIT License**.  
Battlefield 1942 game assets remain © Electronic Arts Inc.

---

## 🌐 Related Resources

- http://master.bf1942.org  
- https://bflist.io  
- https://bf1942.online  
