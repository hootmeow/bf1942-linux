# 🪖 Battlefield 1942 Dedicated Server (Linux) - Enhanced Multi-Instance

Automated setup for running **Battlefield 1942 Dedicated Servers** on modern 64-bit Linux systems with **multi-instance support**.

This solution installs the legacy 32-bit Battlefield 1942 dedicated server using a dedicated, non-privileged account, following best security practices. It handles dependency resolution (including legacy libraries), user creation, and server installation in a single pass.

✨ **Features**: Multi-instance support, smart IP detection, automatic port management, CPU affinity tuning, and comprehensive management tools.

---

## 🧩 Overview

- **Single-Script Setup**: One unified script handles everything - standalone or BFSMD modes
- **Multi-Instance Support**: Run unlimited servers on one machine with automatic port allocation
- **Smart Configuration**: Interactive IP detection, port conflict prevention, resource validation
- **Performance Optimized**: CPU affinity, memory limits, I/O tuning automatically configured
- **Secure Runtime**: Runs entirely under dedicated service account (`bf1942_user`)
- **Modern Compatibility**: Automatically installs required i386 libraries on Ubuntu, Debian, Fedora, RHEL, and CentOS
- **Systemd Integration**: Managed via standard `systemctl` commands
- **Management Tools**: Comprehensive CLI tool for monitoring and managing all instances

---

## 📁 Repository Structure

```
bf1942-linux/
├── bf1942_manager.sh          # Shared management tool (all distros)
├── installers/
│   ├── ubuntu/
│   │   ├── ubu_24.0.3_bfsmd_setup.sh   # Ubuntu 24.04 LTS
│   │   └── ubu_22.04_bfsmd_setup.sh    # Ubuntu 22.04 LTS
│   ├── debian/
│   │   └── deb_12_bfsmd_setup.sh       # Debian 12 (Bookworm) / 13 (Trixie)
│   ├── fedora/
│   │   └── fed_40_bfsmd_setup.sh       # Fedora 40 / 41
│   ├── rhel/
│   │   └── rhel_9_bfsmd_setup.sh       # RHEL 9
│   └── centos/
│       └── centos_stream9_bfsmd_setup.sh  # CentOS Stream 9
├── patches/                   # Optional server bug fix patches
├── firewall_guide.md
└── readme.md
```

`bf1942_manager.sh` lives at the root and works with servers installed by any distro's setup script — you only ever need one copy.

---

## 🎯 Features

### Multi-Instance Capabilities
- **Automatic port allocation** - Each instance gets unique ports based on name hash
- **CPU core assignment** - Automatic CPU affinity for optimal performance
- **Resource management** - Memory limits and I/O priority per instance
- **Centralized management** - Single tool to control all servers

### Network Intelligence
- **Smart IP detection** - Auto-detects local and public IP addresses
- **Network scenario support** - Works with NAT, LAN, cloud, and direct public IPs
- **Port conflict detection** - Prevents failed installations due to port conflicts
- **Firewall integration** - Interactive UFW (Debian/Ubuntu) or firewalld (Fedora/RHEL/CentOS) configuration

### Security & Monitoring
- **Input validation** - Comprehensive validation of all user inputs
- **Security audit** - Check process ownership, file permissions, passwords
- **Health monitoring** - Real-time status of all running instances
- **Non-root execution** - All services run as bf1942_user

---

## ⚙️ Configuration

Each instance gets automatically calculated ports based on its name:

| Port Type | Formula | Example (server1) | Example (server2) |
|-----------|---------|-------------------|-------------------|
| Game Port | 14567 + hash | 14600 (UDP) | 14605 (UDP) |
| Query Port | 23000 + hash | 23033 (UDP) | 23038 (UDP) |
| Management Port | 14667 + hash | 14700 (TCP) | 14705 (TCP) |

View all ports: `./bf1942_manager.sh ports`

---

## 🚀 Quick Start (Ubuntu 24.04 LTS)

> **Prerequisite:** User with **sudo** privileges

### 1️⃣ Download Scripts

```bash
# Download setup script
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/installers/ubuntu/ubu_24.0.3_bfsmd_setup.sh

# Download management tool
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/bf1942_manager.sh

# Make executable
chmod +x ubu_24.0.3_bfsmd_setup.sh bf1942_manager.sh
```

### 2️⃣ Install Your First Server

```bash
sudo ./ubu_24.0.3_bfsmd_setup.sh
```

**Interactive Setup:**
- Choose installation mode (Standalone or BFSMD)
- Select IP address (auto-detected options provided)
- Choose BFSMD version (if applicable)
- Configure firewall rules (optional)

**For BFSMD Mode**, you'll be prompted for:
1. **Instance name** - Choose a unique name (e.g., "server1", "conquest", "tdm")
2. **IP address** - Select from detected IPs or enter custom
3. **BFSMD version** - Choose v2.0 (recommended) or v2.01 (patched)
4. **Firewall rules** - Optional UFW configuration with security levels

### 3️⃣ Create Additional Instances (BFSMD Only)

```bash
# Add more servers with different names
sudo ./ubu_24.0.3_bfsmd_setup.sh server2
sudo ./ubu_24.0.3_bfsmd_setup.sh hootmeow
```

Each instance:
- Gets unique ports automatically
- Runs independently
- Can be managed separately
- Has dedicated CPU cores (when available)

---

## 🐧 Debian 12 / 13 Quick Start

> **Prerequisite:** User with **sudo** privileges

### 1️⃣ Download Scripts

```bash
# Download setup script
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/installers/debian/deb_12_bfsmd_setup.sh

# Download management tool
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/bf1942_manager.sh

# Make executable
chmod +x deb_12_bfsmd_setup.sh bf1942_manager.sh
```

### 2️⃣ Install Your First Server

```bash
sudo ./deb_12_bfsmd_setup.sh
```

The Debian script automatically detects which version of `libcurl4` your system uses — Debian 12 (Bookworm) and Debian 13 (Trixie) have different package names due to the `time_t64` ABI transition, and the script handles both without any manual changes.

Everything else — modes, IP selection, port management, credentials — works identically to the Ubuntu version.

### 3️⃣ Create Additional Instances (BFSMD Only)

```bash
sudo ./deb_12_bfsmd_setup.sh server2
sudo ./deb_12_bfsmd_setup.sh hootmeow
```

> **Note:** The management tool (`bf1942_manager.sh`) is shared. If you have both Ubuntu and Debian servers on the same machine, one copy of the manager controls all of them.

---

## 🐧 Ubuntu 22.04 LTS Quick Start

### 1️⃣ Download Scripts

```bash
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/installers/ubuntu/ubu_22.04_bfsmd_setup.sh
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/bf1942_manager.sh
chmod +x ubu_22.04_bfsmd_setup.sh bf1942_manager.sh
```

### 2️⃣ Install

```bash
sudo ./ubu_22.04_bfsmd_setup.sh
```

Functionally identical to Ubuntu 24.04. The only internal difference is that 22.04 uses `libcurl4:i386` (the `t64` package rename didn't happen until 24.04).

---

## 🎩 Fedora 40 / 41 Quick Start

### 1️⃣ Download Scripts

```bash
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/installers/fedora/fed_40_bfsmd_setup.sh
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/bf1942_manager.sh
chmod +x fed_40_bfsmd_setup.sh bf1942_manager.sh
```

### 2️⃣ Install

```bash
sudo ./fed_40_bfsmd_setup.sh
```

Key differences from the Debian/Ubuntu scripts:
- Uses `dnf` with `.i686` packages — no multiarch setup needed
- `ncurses-compat-libs.i686` provides the legacy `libncurses5`/`libtinfo5` natively
- `libstdc++.so.5` (GCC 3.3) is extracted from a Debian package using `ar` — works on any Linux
- Firewall is configured via `firewalld` / `firewall-cmd` instead of UFW
- SELinux file contexts are set automatically with `restorecon`
- Detects `zlib.i686` vs `zlib-ng-compat.i686` at runtime (Fedora 36+ uses zlib-ng)

---

## 🎩 RHEL 9 Quick Start

### 1️⃣ Download Scripts

```bash
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/installers/rhel/rhel_9_bfsmd_setup.sh
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/bf1942_manager.sh
chmod +x rhel_9_bfsmd_setup.sh bf1942_manager.sh
```

### 2️⃣ Install

```bash
sudo ./rhel_9_bfsmd_setup.sh
```

Same as Fedora but the script also enables EPEL and CRB (CodeReady Linux Builder) automatically before installing packages — required for some 32-bit compat libraries on RHEL.

---

## 🎩 CentOS Stream 9 Quick Start

### 1️⃣ Download Scripts

```bash
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/installers/centos/centos_stream9_bfsmd_setup.sh
wget https://raw.githubusercontent.com/hootmeow/bf1942-linux/main/bf1942_manager.sh
chmod +x centos_stream9_bfsmd_setup.sh bf1942_manager.sh
```

### 2️⃣ Install

```bash
sudo ./centos_stream9_bfsmd_setup.sh
```

Same as RHEL 9 — enables EPEL and CRB, then installs i686 packages. Firewall uses `firewall-cmd`, SELinux contexts set with `restorecon`.

---

## 🎮 Connect to BFRM (BFSMD Mode)

### Default Credentials
All servers use default credentials initially:

```text
Username: bf1942
Password: battlefield
```

⚠️ **CRITICAL**: Change password immediately via BFRM after first login!

### Connection Steps

1. **Open BFRM client** (Windows)
2. **Connect** to `your-server-ip:management-port`
3. **Login** with default credentials
4. **Change password** immediately (Admin tab)

![BFSMD Login](images/bfsmd_password.png)

### First-Time Configuration

#### Set Server IP
Navigate to IP settings and set your server's IP address explicitly:

![Set Server IP](images/bfsmd_ip_addr.png)

#### Secure Remote Console & Admin
Change default remote console password and create secure admin accounts:

![Remote Console Security](images/bfsmd_remoteconsole.png)

#### Set Default Map
Add at least one map to rotation:

![Set Default Map](images/bfsmd_setmap.png)

#### Update Admin Passwords
Create secure admin accounts and disable defaults:

![Set Admin Users](images/bfsmd_adminpassword.png)

---

## 🛠️ Management Commands

`bf1942_manager.sh` is at the repository root and manages all instances regardless of which distro's setup script was used to create them.

### Using bf1942_manager.sh

```bash
# View all instances
./bf1942_manager.sh list

# Check port assignments
./bf1942_manager.sh ports

# View detailed status
./bf1942_manager.sh status server1

# Show configuration paths
./bf1942_manager.sh config server1

# Health check all instances
./bf1942_manager.sh health

# Security audit
./bf1942_manager.sh security

# Service control
sudo ./bf1942_manager.sh start server1
sudo ./bf1942_manager.sh stop server1
sudo ./bf1942_manager.sh restart server1

# View live logs
./bf1942_manager.sh logs server1

# Remove instance (with confirmation)
sudo ./bf1942_manager.sh remove server2
```

### Direct Systemd Commands

```bash
# Standalone server
sudo systemctl status bf1942.service
sudo systemctl restart bf1942.service
journalctl -u bf1942.service -f

# BFSMD instance
sudo systemctl status bfsmd-server1.service
sudo systemctl restart bfsmd-server1.service
journalctl -u bfsmd-server1.service -f
```

---

## 📁 Configuration Files

### Standalone Server
```
/home/bf1942_user/bf1942/mods/bf1942/settings/
├── ServerSettings.con  # Game settings
└── MapList.con        # Map rotation
```

### BFSMD Instance
```
/home/bf1942_user/instances/<name>/mods/bf1942/settings/
├── servermanager.con  # BFSMD settings
├── useraccess.con     # Admin accounts
├── ServerSettings.con # Game settings
└── MapList.con       # Map rotation
```

### Edit Configuration

```bash
# Example: Change server name
nano /home/bf1942_user/instances/server1/mods/bf1942/settings/ServerSettings.con

# Find and edit:
game.serverName "Your Server Name Here"

# Restart to apply
sudo systemctl restart bfsmd-server1.service
```

---

## 🔒 Security Best Practices

### Immediate Actions After Installation
1. ✅ Connect to BFRM with default credentials
2. ✅ Change password immediately (Admin tab)
3. ✅ Create unique admin accounts
4. ✅ Disable or remove default bf1942 account
5. ✅ Configure firewall restrictions

### Firewall Configuration

During installation, you can choose management port security:

**Option 1: Open to All** (Easiest)
- Anyone can attempt connection
- Still requires password
- Good for: Testing, behind other firewall

**Option 2: Restrict to IP** (Recommended)
- Only specified IP can connect
- Firewall + password protection
- Good for: Static admin IP

**Option 3: SSH Tunnel** (Most Secure)
- No direct internet access
- All traffic encrypted via SSH
- Good for: Maximum security

### SSH Tunnel Example
```bash
# On your local machine
ssh -L 14700:localhost:14700 user@your-server-ip

# Then connect BFRM to localhost:14700
```

### Security Audit
```bash
./bf1942_manager.sh security
```

Checks:
- Process ownership (should be bf1942_user, not root)
- File permissions
- Default password usage
- Firewall configuration
- Port exposure

---

## 🌐 Network Scenarios

### Home Server (Behind Router)

**During Installation:**
- Choose: **Local IP** (192.168.x.x)

**Router Configuration:**
- Forward Game port (UDP)
- Forward Query port (UDP)  
- Forward Management port (TCP) - optional

**Players Connect To:**
- Your public IP (google "what is my ip")

### Cloud Server (AWS, DigitalOcean, Linode, etc.)

**During Installation:**
- Choose: **Local IP** (typically 10.x.x.x or private IP)

**Cloud Firewall:**
- Allow Game + Query ports from 0.0.0.0/0
- Allow Management port from YOUR_IP only

**Players Connect To:**
- Your cloud instance's public IP

### VPS with Direct Public IP

**During Installation:**
- Choose: **Public IP** (if no NAT)
- Or: **Local IP** (if behind cloud firewall)

**Firewall:**
- Use UFW to restrict management access

---

## 🔧 Troubleshooting

### "Internal error!" Messages
**This is normal!** BFSMD v2.0/v2.01 shows these continuously when reading `/proc` on modern kernels. The server functions perfectly despite these messages.

To filter them out:
```bash
journalctl -u bfsmd-server1.service -f | grep -v "Internal error"
```

### Can't Connect to Server
```bash
# 1. Check service is running
systemctl is-active bfsmd-server1.service

# 2. Check firewall
sudo ufw status

# 3. Check ports are listening
sudo ss -tulnp | grep 14567

# 4. View logs
./bf1942_manager.sh logs server1
```

### Port Conflict During Installation
If you get "port already in use":
- Try a different instance name (generates different ports)
- Check existing assignments: `./bf1942_manager.sh ports`
- Remove conflicting instance if needed

### Can't Login to BFRM
1. Verify credentials: `bf1942` / `battlefield`
2. Check management port is correct
3. Verify firewall allows connection
4. Check service is running
5. Review logs for authentication errors

### Performance Issues
```bash
# Run health check
./bf1942_manager.sh health

# Check CPU affinity
./bf1942_manager.sh security

# Monitor resources
htop

# Check for errors
journalctl -u bfsmd-server1.service -n 100
```

---

## 🛠️ Advanced Usage

### Maximum Recommended Instances

**Formula**: `CPU Cores × 2 = Recommended Max`

Examples:
- 2 cores → 4 instances max
- 4 cores → 8 instances max
- 8 cores → 16 instances max

The script warns if you exceed recommended limits but allows you to proceed.

### View Port Assignments
```bash
./bf1942_manager.sh ports
```

Example output:
```
Instance: server1
  Game:  14600 (UDP)
  Query: 23033 (UDP)
  Mgmt:  14700 (TCP)

Instance: server2
  Game:  14605 (UDP)
  Query: 23038 (UDP)
  Mgmt:  14705 (TCP)
```

### Backup Instance Configuration
```bash
# Backup
sudo tar -czf server1-backup-$(date +%F).tar.gz \
  /home/bf1942_user/instances/server1/mods/bf1942/settings/

# Restore
sudo tar -xzf server1-backup-*.tar.gz -C /
sudo systemctl restart bfsmd-server1.service
```

### Clone Instance Settings
```bash
# Copy settings from one instance to another
sudo cp -r /home/bf1942_user/instances/server1/mods/bf1942/settings/* \
           /home/bf1942_user/instances/server2/mods/bf1942/settings/

# Important: Update the game port in ServerSettings.con
sudo nano /home/bf1942_user/instances/server2/mods/bf1942/settings/ServerSettings.con

# Restart
sudo systemctl restart bfsmd-server2.service
```

---

## 🧪 Supported Distributions

| Distro | Status | Script | Notes |
|--------|--------|--------|-------|
| **Ubuntu 24.04 LTS** | ✅ Supported | `installers/ubuntu/ubu_24.0.3_bfsmd_setup.sh` | Primary platform |
| **Ubuntu 22.04 LTS** | ✅ Supported | `installers/ubuntu/ubu_22.04_bfsmd_setup.sh` | Uses `libcurl4:i386` |
| **Debian 12 (Bookworm)** | ✅ Supported | `installers/debian/deb_12_bfsmd_setup.sh` | Uses `libcurl4:i386` |
| **Debian 13 (Trixie)** | ✅ Supported | `installers/debian/deb_12_bfsmd_setup.sh` | Auto-detects `libcurl4t64:i386` |
| **Fedora 40 / 41** | ✅ Supported | `installers/fedora/fed_40_bfsmd_setup.sh` | dnf, firewalld, SELinux |
| **RHEL 9** | ✅ Supported | `installers/rhel/rhel_9_bfsmd_setup.sh` | Enables EPEL + CRB automatically |
| **CentOS Stream 9** | ✅ Supported | `installers/centos/centos_stream9_bfsmd_setup.sh` | Enables EPEL + CRB automatically |

---

## 🛠️ Applying Patches

The patches folder contains Python scripts to improve various server bugs. Please see individual patch files for additional details and how to apply.

---

## 📚 Additional Resources

- **firewall_guide.md** - Detailed firewall configuration
- **bf1942.online** - Community resources and downloads

---

## 🧑‍🎨 Author

**OWLCAT**  
🔗 GitHub: https://github.com/hootmeow  
🌐 Website: https://www.bf1942.online

---

## 📥 BFRM Downloads (Windows)

1. **BFRM v2.0 (Final)** - Recommended  
   https://files.bf1942.online/server/tools/BFRemoteManager20final-patched.zip

2. **BFRM v2.01 (Patched)** - Fixes admin bugs  
   https://files.bf1942.online/server/tools/BFRemoteManager201-patched.zip

---

## 🤝 Contributing

Contributions welcome! Please:
1. Test your changes on the relevant distribution(s)
2. Update documentation
3. Follow existing code style
4. Submit pull requests

---

## 📜 License

Scripts released under the **MIT License**.  
All Battlefield 1942 game assets remain © Electronic Arts Inc.

---

## 🆘 Support

**Issues**: https://github.com/hootmeow/bf1942-linux/issues  
**Community**: www.bf1942.online

---

## ⭐ Star This Project

If you find this useful, please star the repository!

---

**Happy Gaming! 🎮**
