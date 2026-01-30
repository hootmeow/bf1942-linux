# 🔥 Firewall Configuration Guide

## What Ports Does My Server Use?

Each BF1942 instance uses **3 ports** (BFSMD mode) or **2 ports** (Standalone mode):

### Port Assignment Formula

Ports are calculated from your instance name:
```
Instance Hash = hash(instance_name) % 100
Game Port     = 14567 + Hash
Query Port    = 23000 + Hash
Mgmt Port     = 14667 + Hash
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

When you install a server, you'll see:

```
Firewall Configuration
Configure UFW firewall rules? [y/N]
```

### If you answer "y" (Yes):

**For Standalone servers:**
- Opens Game port (14567/udp)
- Opens Query port (23000/udp)
- Done!

**For BFSMD servers:**
- Opens Game port automatically
- Opens Query port automatically
- **Then asks about Management port:**

```
Management Port Security:
  1) Open to all IPs (easier, less secure)
  2) Restrict to specific IP (more secure)
  3) Skip (use SSH tunnel instead - most secure)
Choice [1-3, default: 1]:
```

### If you answer "n" (No):
- No firewall rules created
- You configure manually later
- Good if: Using cloud firewall, custom setup

---

## Understanding the Management Port Options

### Option 1: Open to All IPs ✅ Easiest

**What happens:**
```bash
ufw allow 14700/tcp
```

**Means:**
- Anyone on the internet can connect to BFRM on this port
- Still protected by username/password
- Similar to a public website with login

**Best for:**
- Quick setup
- Testing
- Behind another firewall (router, cloud security group)
- Multiple admins from different locations

**Security:**
- 🟡 Medium - relies on password strength
- ⚠️ Exposed to brute-force attempts
- ✅ Still requires valid credentials

---

### Option 2: Restrict to Specific IP 🔒 More Secure

**What happens:**
```bash
Enter trusted IP address: 203.0.113.45
ufw allow from 203.0.113.45 to any port 14700 proto tcp
```

**Means:**
- ONLY that specific IP can connect
- All other IPs are blocked at firewall level
- Password protection is backup

**Best for:**
- Static admin IP (home internet, office)
- Single admin
- Known IP addresses

**Security:**
- 🟢 Good - two layers (firewall + password)
- ✅ Blocks unauthorized connection attempts
- ⚠️ Need to update if your IP changes

**How to update later:**
```bash
# Remove old rule
sudo ufw status numbered
sudo ufw delete [number]

# Add new rule
sudo ufw allow from NEW_IP to any port 14700 proto tcp
```

---

### Option 3: SSH Tunnel 🔐 Most Secure

**What happens:**
```
No firewall rule created for management port
```

**Means:**
- Management port NOT accessible from internet
- Must create SSH tunnel to access
- Zero attack surface

**Best for:**
- Maximum security
- Experienced users
- Remote management

**Security:**
- 🟢 Excellent - no direct access
- ✅ Uses SSH encryption
- ✅ No exposure to internet

**How to use:**
```bash
# On your computer (one-time per session):
ssh -L 14700:localhost:14700 your-user@your-server-ip

# Leave that terminal open
# In BFRM, connect to: localhost:14700
```

**Pros:**
- Most secure option
- All traffic encrypted
- No management port exposed

**Cons:**
- Requires SSH access
- Extra step to connect
- Need SSH tunnel running

---

## Quick Decision Guide

**Choose Option 1 if:**
- ✅ First time setting up
- ✅ Want simplest setup
- ✅ Behind cloud firewall already
- ✅ Multiple admins, different IPs
- ✅ Don't mind some exposure

**Choose Option 2 if:**
- ✅ Have static IP address
- ✅ Single admin location
- ✅ Want better security
- ✅ Comfortable updating firewall

**Choose Option 3 if:**
- ✅ Maximum security needed
- ✅ Comfortable with SSH
- ✅ Want zero exposure
- ✅ Already using SSH anyway

---

## Common Scenarios

### Home Server (Behind Router)

**Recommendation:** Option 1 or 2

Your router firewall provides first layer of protection. You'd need to port forward anyway, so Option 1 is often fine. Option 2 if you have static IP.

**Router Setup:**
- Forward Game port (UDP) → Local IP
- Forward Query port (UDP) → Local IP
- Forward Mgmt port (TCP) → Local IP (if using Option 1 or 2)

### Cloud Server (AWS, DigitalOcean, etc.)

**Recommendation:** Option 2 or 3

Cloud instances are directly exposed. Use Option 2 (restrict to your IP) or Option 3 (SSH tunnel).

**Cloud Firewall:**
- Allow Game port (UDP) from 0.0.0.0/0
- Allow Query port (UDP) from 0.0.0.0/0
- Allow Mgmt port (TCP) from YOUR_IP only (or don't allow)

### VPS with No Extra Firewall

**Recommendation:** Option 2 or 3

You're the only firewall. Don't use Option 1 unless you understand the risk.

---

## Changing Your Mind Later

### Switch from Open (1) to Restricted (2):

```bash
# Find the rule number
sudo ufw status numbered

# Delete the open rule
sudo ufw delete [number]

# Add restricted rule
sudo ufw allow from YOUR_IP to any port 14700 proto tcp
```

### Switch from Restricted (2) to Tunnel (3):

```bash
# Delete the rule
sudo ufw status numbered
sudo ufw delete [number]

# Now use SSH tunnel
ssh -L 14700:localhost:14700 user@server
```

### Switch from Tunnel (3) to Open (1):

```bash
# Add the rule
sudo ufw allow 14700/tcp
```

---

## Testing Your Configuration

### Check Firewall Rules
```bash
sudo ufw status numbered
```

### Check Port Listening
```bash
# Should show bfsmd listening on management port
sudo ss -tlnp | grep 14700
```

### Test Connection

**From another machine:**
```bash
# Should connect (if Option 1) or timeout (if Option 2/3)
telnet your-server-ip 14700
```

**If using SSH tunnel:**
```bash
# Create tunnel
ssh -L 14700:localhost:14700 user@server

# Test locally
telnet localhost 14700
```

---

## Security Best Practices

1. **Change default credentials immediately** after first BFRM login
2. **Use strong unique passwords** - at least 12+ characters with mixed case, numbers, symbols
3. **Monitor logs** for unauthorized attempts:
   ```bash
   journalctl -u bfsmd-server1.service | grep -i "failed\|denied"
   ```
4. **Consider SSH tunnel** even if using Option 1 or 2
5. **Update firewall rules** if your IP changes (Option 2)
6. **Run security audit regularly**:
   ```bash
   ./bf1942_manager.sh security
   ```

---

## TL;DR

- **Ports are assigned automatically** based on instance name
- **Script configures firewall** if you choose yes
- **Three security levels** for management port
- **Can change later** if needed
- **Use `./bf1942_manager.sh ports`** to see your ports

**Most users should:**
- Home server behind router → Option 1 or 2
- Cloud server → Option 2 or 3
- When in doubt → Choose Option 2

