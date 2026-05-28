# 🔥 Firewall Configuration Guide

## What Firewall Does My Distro Use?

| Distro | Firewall Tool | Configured By |
|--------|--------------|---------------|
| Ubuntu 24.04 / 22.04 | UFW | `ufw` |
| Debian 12 / 13 | UFW | `ufw` |
| Fedora 40 / 41 | firewalld | `firewall-cmd` |
| RHEL 9 | firewalld | `firewall-cmd` |
| CentOS Stream 9 | firewalld | `firewall-cmd` |

The installer detects your distro and uses the correct tool automatically. This guide covers both.

---

## What Ports Does My Server Use?

Each BF1942 instance uses **3 ports** (BFSMD mode) or **2 ports** (Standalone mode):

### Port Assignment Formula

Ports are calculated from your instance name:
```
Instance Hash = hash(instance_name) % 100
Game Port     = 14567 + Hash
Query Port    = 23000 + Hash
Mgmt Port     = 14667 + Hash  (BFSMD only)
```

### Examples

| Instance Name | Game Port | Query Port | Mgmt Port |
|---------------|-----------|------------|-----------|
| server1       | 14600     | 23033      | 14700     |
| server2       | 14605     | 23038      | 14705     |
| conquest      | 14620     | 23053      | 14720     |
| tdm           | 14589     | 23022      | 14689     |

**To see YOUR ports:**
```bash
./bf1942_manager.sh ports
```

---

## During Installation

The installer will ask:

```
# Ubuntu / Debian:
Configure UFW firewall rules? [y/N]

# Fedora / RHEL / CentOS:
Configure firewalld rules? [y/N]
```

### If you answer "y" (Yes):

**For Standalone servers:**
- Opens Game port (UDP)
- Opens Query port (UDP)
- Done

**For BFSMD servers:**
- Opens Game port automatically
- Opens Query port automatically
- **Then asks about the Management port:**

```
Management Port Security:
  1) Open to all IPs (easier, less secure)
  2) Restrict to specific IP (more secure)
  3) Skip (use SSH tunnel instead - most secure)
Choice [1-3, default: 1]:
```

### If you answer "n" (No):
- No firewall rules are created
- You configure manually later (see sections below)
- Good if: using a cloud firewall, custom setup

---

## Understanding the Management Port Options

### Option 1: Open to All IPs ✅ Easiest

**UFW:**
```bash
sudo ufw allow 14700/tcp
```

**firewalld:**
```bash
sudo firewall-cmd --permanent --add-port=14700/tcp
sudo firewall-cmd --reload
```

**Means:** Anyone on the internet can attempt to connect to BFRM on this port. Still protected by password.

**Best for:** Quick setup, testing, behind a cloud firewall, multiple admins from different locations.

**Security:** 🟡 Medium — relies on password strength, exposed to brute-force attempts.

---

### Option 2: Restrict to Specific IP 🔒 More Secure

**UFW:**
```bash
sudo ufw allow from 203.0.113.45 to any port 14700 proto tcp
```

**firewalld:**
```bash
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='203.0.113.45' port protocol='tcp' port='14700' accept"
sudo firewall-cmd --reload
```

**Means:** Only that specific IP can connect. All others blocked at the firewall level before they even reach the password prompt.

**Best for:** Static admin IP, single admin location.

**Security:** 🟢 Good — two layers (firewall + password). Update when your IP changes.

**How to update later (UFW):**
```bash
sudo ufw status numbered         # find the rule number
sudo ufw delete [number]
sudo ufw allow from NEW_IP to any port 14700 proto tcp
```

**How to update later (firewalld):**
```bash
# Remove old rule
sudo firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='OLD_IP' port protocol='tcp' port='14700' accept"
# Add new rule
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='NEW_IP' port protocol='tcp' port='14700' accept"
sudo firewall-cmd --reload
```

---

### Option 3: SSH Tunnel 🔐 Most Secure

**What happens:** No firewall rule is created for the management port at all.

**How to use:**
```bash
# On your local machine (run once per session):
ssh -L 14700:localhost:14700 your-user@your-server-ip

# Leave that terminal open, then point BFRM at: localhost:14700
```

**Best for:** Maximum security, experienced users, servers directly exposed to the internet.

**Security:** 🟢 Excellent — zero direct exposure, all traffic encrypted via SSH.

---

## Quick Decision Guide

| Situation | Recommended Option |
|-----------|-------------------|
| First-time setup / testing | Option 1 |
| Home server behind router | Option 1 or 2 |
| Static admin IP | Option 2 |
| Cloud server (AWS, DigitalOcean, etc.) | Option 2 or 3 |
| Maximum security / experienced user | Option 3 |

---

## Manual Configuration

### Ubuntu / Debian (UFW)

```bash
# Check current rules
sudo ufw status numbered

# Open a port to all
sudo ufw allow 14567/udp
sudo ufw allow 14700/tcp

# Restrict a port to one IP
sudo ufw allow from YOUR_IP to any port 14700 proto tcp

# Remove a rule
sudo ufw delete [rule_number]

# Enable / disable UFW
sudo ufw enable
sudo ufw disable
```

### Fedora / RHEL / CentOS (firewalld)

```bash
# Check current rules
sudo firewall-cmd --list-all

# Open a port to all
sudo firewall-cmd --permanent --add-port=14567/udp
sudo firewall-cmd --permanent --add-port=14700/tcp
sudo firewall-cmd --reload

# Restrict a port to one IP
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='YOUR_IP' port protocol='tcp' port='14700' accept"
sudo firewall-cmd --reload

# Remove a port rule
sudo firewall-cmd --permanent --remove-port=14700/tcp
sudo firewall-cmd --reload

# Remove a rich rule
sudo firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='YOUR_IP' port protocol='tcp' port='14700' accept"
sudo firewall-cmd --reload

# Check if firewalld is running
sudo systemctl status firewalld
```

---

## Switching Options Later

### Open → Restricted (UFW)
```bash
sudo ufw status numbered
sudo ufw delete [rule_number_for_open_rule]
sudo ufw allow from YOUR_IP to any port 14700 proto tcp
```

### Open → Restricted (firewalld)
```bash
sudo firewall-cmd --permanent --remove-port=14700/tcp
sudo firewall-cmd --permanent --add-rich-rule="rule family='ipv4' source address='YOUR_IP' port protocol='tcp' port='14700' accept"
sudo firewall-cmd --reload
```

### Restricted → SSH Tunnel (UFW)
```bash
sudo ufw status numbered
sudo ufw delete [rule_number]
# Management port is now closed — use SSH tunnel to connect
```

### Restricted → SSH Tunnel (firewalld)
```bash
sudo firewall-cmd --permanent --remove-rich-rule="rule family='ipv4' source address='YOUR_IP' port protocol='tcp' port='14700' accept"
sudo firewall-cmd --reload
```

### Tunnel → Open (UFW)
```bash
sudo ufw allow 14700/tcp
```

### Tunnel → Open (firewalld)
```bash
sudo firewall-cmd --permanent --add-port=14700/tcp
sudo firewall-cmd --reload
```

---

## Testing Your Configuration

### Check What's Listening
```bash
sudo ss -tulnp | grep 14700
```

### Check Firewall Status

**UFW:**
```bash
sudo ufw status numbered
```

**firewalld:**
```bash
sudo firewall-cmd --list-all
```

### Test Connection From Another Machine
```bash
# Should connect (Option 1) or time out (Option 2/3)
telnet your-server-ip 14700
```

**If using SSH tunnel:**
```bash
ssh -L 14700:localhost:14700 user@server   # run first
telnet localhost 14700                      # then test locally
```

---

## Security Best Practices

1. **Change default credentials immediately** after first BFRM login
2. **Use strong passwords** — 12+ characters with mixed case, numbers, symbols
3. **Monitor for unauthorized attempts:**
   ```bash
   journalctl -u bfsmd-server1.service | grep -i "failed\|denied"
   ```
4. **Run security audit regularly:**
   ```bash
   ./bf1942_manager.sh security
   ```
5. **Consider SSH tunnel** even if using Option 1 or 2 for day-to-day management

---

## TL;DR

- Ports are assigned automatically based on instance name — use `./bf1942_manager.sh ports` to see them
- Ubuntu/Debian use **UFW**, Fedora/RHEL/CentOS use **firewalld** — the installer handles this automatically
- Three security levels for the management port: open / restricted to IP / SSH tunnel only
- When in doubt: home server → Option 1 or 2, cloud server → Option 2 or 3
