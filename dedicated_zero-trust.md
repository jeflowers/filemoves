# Dedicated Server with Restricted Landing Zone Runbook

This runbook provides step-by-step instructions for setting up a dedicated server with zero-trust security principles and a restricted file access landing zone. The document is structured for future implementation as Infrastructure as Code (Terraform).

| Symbol | Meaning |
|--------|---------|
| ⚠️ | Critical security step |
| 📝 | Documentation step |
| 🧪 | Testing step |

## Table of Contents

1. [Initial Server Setup](#1-initial-server-setup)
2. [Host Firewall Configuration](#2-host-firewall-configuration)
3. [Docker Setup](#3-docker-setup)
4. [Restricted Landing Zone Implementation](#4-restricted-landing-zone-implementation)
5. [SSH Configuration for Restricted Access](#5-ssh-configuration-for-restricted-access)
6. [Teleport Implementation for Zero-Trust Security](#6-teleport-implementation-for-zero-trust-security)
7. [Security Enhancements](#7-security-enhancements)
8. [Monitoring and Alerting](#8-monitoring-and-alerting)
9. [Backup Strategy](#9-backup-strategy)
10. [Performance Tuning](#10-performance-tuning)
11. [Administrative Network Configuration](#11-administrative-network-configuration)
12. [Testing](#12-testing)

## 1. Initial Server Setup

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 1.1 | Update the system | 15m | |
| 1.2 | Install essential packages | 10m | |
| 1.3 | Create documentation of initial configuration | 5m | |

```bash
# Update the system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y ufw fail2ban curl wget git htop ntp acl

# Document the initial system state
uname -a > /root/system_info.txt
lsb_release -a >> /root/system_info.txt
```

## 2. Host Firewall Configuration

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 2.1 ⚠️ | Configure UFW default policies | 5m | |
| 2.2 ⚠️ | Allow necessary services | 10m | |
| 2.3 ⚠️ | Configure IP-based restrictions | 15m | |
| 2.4 | Enable and verify firewall | 5m | |

```bash
# Configure UFW default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow necessary services with updated ports
sudo ufw allow 22/tcp comment 'SSH access - Teleport'
sudo ufw allow 2201/tcp comment 'Ubuntu container SSH via NAT'
sudo ufw allow 2202/tcp comment 'Windows container SSH via NAT'
sudo ufw allow 2222/tcp comment 'Admin SFTP access'
sudo ufw allow 3080/tcp comment 'Teleport Web UI'
sudo ufw allow 80/tcp comment 'HTTP for certbot'
sudo ufw allow 443/tcp comment 'HTTPS'

# Allow SSH (port 22) only from specific IPv4 range
# Replace with your actual allowed IP ranges
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp

# Allow Admin SFTP (port 2222) only from specific admin IPv4 range
# Replace with your actual allowed admin IP ranges
sudo ufw allow from 10.10.0.0/24 to any port 2222 proto tcp

# Allow SSH (port 22) only from specific IPv6 range
# Replace with your actual allowed IP ranges
sudo ufw allow from 2001:db8::/64 to any port 22 proto tcp

# Enable and verify firewall
sudo ufw enable
sudo ufw status verbose
```

## 3. Docker Setup

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 3.1 | Install Docker | 15m | |
| 3.2 | Configure user permissions | 5m | |
| 3.3 | Install Docker Compose | 5m | |
| 3.4 | Create Docker networks | 5m | |
| 3.5 | Configure LANDINGZONE as shared volume | 10m | |
| 3.6 | Configure port NAT for containers | 15m | |

```bash
# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add your user to the docker group
sudo usermod -aG docker $USER
newgrp docker

# Install Docker Compose
sudo apt install -y docker-compose

# Create isolated networks for different container types
docker network create --driver bridge --subnet=172.20.0.0/24 ubuntu-network
docker network create --driver bridge --subnet=172.21.0.0/24 windows-network
docker network create --driver bridge --subnet=172.22.0.0/24 admin-network
```

### 3.5 Configure LANDINGZONE as Shared Volume

```bash
# Ensure proper permissions for Docker to access the LANDINGZONE
sudo chmod 775 /opt/LANDINGZONE
# Add the Docker group to the LANDINGZONE directory
sudo chown filetransfer:docker /opt/LANDINGZONE
```

### 3.6 Configure Port NAT for Docker Containers

Create a Docker Compose file for container setup:

```bash
# Create a directory for Docker configuration
sudo mkdir -p /opt/docker
sudo nano /opt/docker/docker-compose.yml
```

Add the following content:

```yaml
version: '3'

networks:
  ubuntu-network:
    external: true
  windows-network:
    external: true
  admin-network:
    external: true

services:
  ubuntu-container:
    image: ubuntu:22.04
    container_name: ubuntu-ssh
    restart: always
    volumes:
      - /opt/LANDINGZONE:/LANDINGZONE:rw
    networks:
      - ubuntu-network
    ports:
      - "2201:22"  # NAT port 2201 to container's 22
    command: >
      bash -c "
        apt-get update && 
        apt-get install -y openssh-server && 
        mkdir -p /run/sshd && 
        echo 'PermitRootLogin no' >> /etc/ssh/sshd_config &&
        useradd -m -s /bin/bash ubuntu-user &&
        mkdir -p /home/ubuntu-user/.ssh &&
        echo 'CONTAINER_USER_SSH_KEY' > /home/ubuntu-user/.ssh/authorized_keys &&
        chmod 700 /home/ubuntu-user/.ssh &&
        chmod 600 /home/ubuntu-user/.ssh/authorized_keys &&
        chown -R ubuntu-user:ubuntu-user /home/ubuntu-user/.ssh &&
        /usr/sbin/sshd -D
      "

  windows-container:
    image: mcr.microsoft.com/windows/servercore:ltsc2022
    container_name: windows-ssh
    restart: always
    volumes:
      - /opt/LANDINGZONE:/LANDINGZONE:rw
    networks:
      - windows-network
    ports:
      - "2202:22"  # NAT port 2202 to container's 22
    command: powershell -Command "
      # Install OpenSSH Server
      Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0;
      # Set SSH service to start automatically
      Set-Service sshd -StartupType Automatic;
      # Start SSH service
      Start-Service sshd;
      # Create user for SSH access
      New-LocalUser -Name 'windows-user' -NoPassword;
      # Create .ssh directory and authorized_keys
      New-Item -Path 'C:\\Users\\windows-user\\.ssh' -ItemType Directory -Force;
      Set-Content -Path 'C:\\Users\\windows-user\\.ssh\\authorized_keys' -Value 'CONTAINER_USER_SSH_KEY';
      # Set appropriate permissions
      icacls 'C:\\Users\\windows-user\\.ssh' /inheritance:r /grant:r 'windows-user:(OI)(CI)F';
      icacls 'C:\\Users\\windows-user\\.ssh\\authorized_keys' /inheritance:r /grant:r 'windows-user:F';
      # Create landing zone directory
      New-Item -Path 'C:\\LANDINGZONE\\windows' -ItemType Directory -Force;
      # Keep container running
      while($true) { Start-Sleep -Seconds 3600 }
    "

  admin-container:
    image: ubuntu:22.04
    container_name: admin-sftp
    restart: always
    volumes:
      - /opt/LANDINGZONE:/LANDINGZONE:rw
    ports:
      - "2222:22"  # Admin SFTP port
    networks:
      - admin-network
      - ubuntu-network
    command: >
      bash -c "
        apt-get update && 
        apt-get install -y openssh-server && 
        mkdir -p /run/sshd && 
        echo 'PermitRootLogin no' >> /etc/ssh/sshd_config &&
        useradd -m -s /bin/bash admin-user &&
        mkdir -p /home/admin-user/.ssh &&
        echo 'ADMIN_SSH_KEY' > /home/admin-user/.ssh/authorized_keys &&
        chmod 700 /home/admin-user/.ssh &&
        chmod 600 /home/admin-user/.ssh/authorized_keys &&
        chown -R admin-user:admin-user /home/admin-user/.ssh &&
        chown -R admin-user:admin-user /LANDINGZONE &&
        chmod -R 770 /LANDINGZONE &&
        /usr/sbin/sshd -D
      "
```

```bash
# Start the containers
cd /opt/docker
sudo docker-compose up -d
```

## 4. Restricted Landing Zone Implementation

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 4.1 | Create dedicated user | 5m | |
| 4.2 | Create landing zone directory | 5m | |
| 4.3 | Set appropriate permissions | 5m | |
| 4.4 | Create monitoring scripts | 15m | |
| 4.5 | Configure systemd service | 10m | |
| 4.6 | Configure Docker container access | 15m | |
| 4.7 | Set up file ownership synchronization | 20m | |

```bash
# Create a dedicated user for file transfers
sudo useradd -m -s /bin/bash filetransfer

# Create the landing zone directory
sudo mkdir -p /opt/LANDINGZONE
sudo mkdir -p /opt/LANDINGZONE/windows

# Set ownership to the filetransfer user and docker group
sudo chown filetransfer:docker /opt/LANDINGZONE

# Set appropriate permissions (770 allows the user and group to read, write, execute)
sudo chmod 770 /opt/LANDINGZONE

# Create directory for monitoring scripts
sudo mkdir -p /opt/scripts
```

### 4.4 Landing Zone Monitor Script

```bash
# Create monitoring script
sudo nano /opt/scripts/monitor_landingzone.sh
```

Add this content:

```bash
#!/bin/bash

LANDINGZONE="/opt/LANDINGZONE"
SEMAPHORE="$LANDINGZONE/.ready"

# Function to check if files exist in the landing zone
check_for_files() {
    file_count=$(find "$LANDINGZONE" -type f -not -name ".*" | wc -l)
    if [ "$file_count" -gt 0 ]; then
        # Files exist, create semaphore if it doesn't exist
        if [ ! -f "$SEMAPHORE" ]; then
            touch "$SEMAPHORE"
            chmod 644 "$SEMAPHORE"
            echo "$(date): Files found, semaphore created" >> "$LANDINGZONE/.log"
        fi
    else
        # No files exist, remove semaphore if it exists
        if [ -f "$SEMAPHORE" ]; then
            rm "$SEMAPHORE"
            echo "$(date): No files found, semaphore removed" >> "$LANDINGZONE/.log"
        fi
    fi
}

# Main loop
while true; do
    check_for_files
    sleep 10  # Check every 10 seconds
done
```

```bash
# Make the script executable
sudo chmod +x /opt/scripts/monitor_landingzone.sh
```

### 4.5 Systemd Service Configuration

```bash
# Create a systemd service
sudo nano /etc/systemd/system/landingzone-monitor.service
```

Add this content:

```
[Unit]
Description=Landing Zone File Monitor
After=network.target

[Service]
Type=simple
User=filetransfer
Group=filetransfer
ExecStart=/opt/scripts/monitor_landingzone.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
# Enable and start the service
sudo systemctl enable landingzone-monitor
sudo systemctl start landingzone-monitor
```

### 4.6 Configure Docker Container Access

```bash
# Create script to check for container connectivity to LANDINGZONE
sudo nano /opt/scripts/check_container_access.sh
```

Add this content:

```bash
#!/bin/bash

# Check if containers can access the landing zone
for container in ubuntu-ssh windows-ssh admin-sftp; do
  docker exec $container ls -la /LANDINGZONE > /dev/null 2>&1
  if [ $? -eq 0 ]; then
    echo "$(date): $container successfully accessed LANDINGZONE" >> /opt/LANDINGZONE/.log
  else
    echo "$(date): WARNING - $container cannot access LANDINGZONE" >> /opt/LANDINGZONE/.log
    # Alert administrators (modify with your preferred alert method)
    # mail -s "LANDINGZONE access issue for $container" admin@example.com
  fi
done
```

```bash
# Make script executable
sudo chmod +x /opt/scripts/check_container_access.sh

# Add to crontab to run hourly
(crontab -l 2>/dev/null; echo "0 * * * * /opt/scripts/check_container_access.sh") | crontab -
```

### 4.7 Set Up File Ownership Synchronization

```bash
# Create script to synchronize file permissions
sudo nano /opt/scripts/sync_permissions.sh
```

Add this content:

```bash
#!/bin/bash

# Set proper permissions for all files in the landing zone
find /opt/LANDINGZONE -type f -exec chmod 664 {} \;
find /opt/LANDINGZONE -type d -exec chmod 775 {} \;

# Ensure correct ownership - files accessible by both admin and transfer users
chown -R filetransfer:docker /opt/LANDINGZONE

# Ensure admin container user has access
if docker ps | grep -q admin-sftp; then
  docker exec admin-sftp chown -R admin-user:admin-user /LANDINGZONE
fi

# Special handling for windows directory
if [ -d "/opt/LANDINGZONE/windows" ]; then
  chmod -R 775 /opt/LANDINGZONE/windows
fi

# Log the sync operation
echo "$(date): Permission sync completed successfully" >> /var/log/landingzone-sync.log
```

```bash
# Make script executable
sudo chmod +x /opt/scripts/sync_permissions.sh

# Add to crontab to run every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/scripts/sync_permissions.sh") | crontab -
```

## 5. SSH Configuration for Restricted Access

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 5.1 ⚠️ | Generate SSH keys | 5m | |
| 5.2 ⚠️ | Configure authorized keys | 10m | |
| 5.3 ⚠️ | Configure SSH chroot jail | 15m | |
| 5.4 | Restart SSH service | 5m | |
| 5.5 | Change default SSH port | 10m | |
| 5.6 ⚠️ | Additional SSH hardening | 15m | |

### 5.1 & 5.2 SSH Key Setup

On the external client:

```bash
# Generate SSH key pair
ssh-keygen -t ed25519 -f ~/.ssh/filetransfer_key -C "filetransfer@externalhost"

# Copy the public key
cat ~/.ssh/filetransfer_key.pub
```

On the IONOS server:

```bash
# Set up authorized keys for the filetransfer user
sudo mkdir -p /home/filetransfer/.ssh
sudo touch /home/filetransfer/.ssh/authorized_keys
# Paste the public key into this file
sudo nano /home/filetransfer/.ssh/authorized_keys

# Set proper permissions
sudo chmod 700 /home/filetransfer/.ssh
sudo chmod 600 /home/filetransfer/.ssh/authorized_keys
sudo chown -R filetransfer:filetransfer /home/filetransfer/.ssh
```

### 5.3 SSH Chroot Configuration

```bash
# Edit SSH server configuration
sudo nano /etc/ssh/sshd_config
```

Add the following at the end of the file:

```
# Restrict filetransfer user to LANDINGZONE
Match User filetransfer
    ChrootDirectory /opt
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
```

### 5.4 & 5.5 SSH Hardening and Teleport Integration

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 5.4.1 | Harden SSH configuration | 10m | |
| 5.4.2 | Configure Teleport for port 22 access | 15m | |
| 5.5.1 | Update firewall rules | 5m | |
| 5.5.2 | Restart services | 5m | |

```bash
# Edit SSH config for hardening but maintain compatibility
sudo nano /etc/ssh/sshd_config

# Add/modify these lines:
Port 2223              # Change admin SSH port to non-standard port
PermitRootLogin no     # Disable root login
MaxAuthTries 3         # Limit authentication attempts
MaxSessions 2          # Limit max sessions
LoginGraceTime 30      # Shorter grace period

# Set up Teleport to handle standard port 22 for external clients
sudo nano /etc/teleport/teleport.yaml

# Modify the ssh_service section to handle port 22:
# ssh_service:
#   enabled: true
#   listen_addr: 0.0.0.0:22  # Teleport handles standard port
#   # Rest of teleport SSH configuration...

# Update firewall to allow both ports
sudo ufw allow 22/tcp comment 'Teleport SSH for clients'
sudo ufw allow 2223/tcp comment 'Admin SSH access'

# Restart services
sudo systemctl restart sshd
sudo systemctl restart teleport
```

This approach provides several benefits:
1. Administrative access uses a non-standard port (2223) for reduced automated attacks
2. External clients can still connect via the standard port 22
3. Teleport provides enhanced security features for standard port access:
   - Certificate-based authentication with automatic rotation
   - Fine-grained access controls and session recording
   - Detailed audit logging
4. Zero-trust security model maintained for all access paths

## 6. Teleport Implementation for Zero-Trust Security

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 6.1 | Install Teleport | 15m | |
| 6.2 ⚠️ | Configure Teleport | 20m | |
| 6.3 | Generate SSL certificates | 15m | |
| 6.4 | Configure Teleport service | 10m | |

```bash
# Install Teleport
curl -O https://get.gravitational.com/teleport-v10.3.2-linux-amd64-bin.tar.gz
tar -xzf teleport-v10.3.2-linux-amd64-bin.tar.gz
cd teleport
sudo ./install

# Configure Teleport
sudo mkdir -p /etc/teleport
```

### 6.2 Teleport Configuration

```bash
sudo nano /etc/teleport/teleport.yaml
```

Add this content:

```yaml
teleport:
  nodename: ssh-server
  data_dir: /var/lib/teleport
  auth_token: your-auth-token
  auth_servers:
    - 127.0.0.1:3025
auth_service:
  enabled: true
  listen_addr: 0.0.0.0:3025
  tokens:
    - "proxy,node:your-auth-token"
proxy_service:
  enabled: true
  listen_addr: 0.0.0.0:3023
  ssh_public_addr: your-server-ip:3023
  web_listen_addr: 0.0.0.0:3080
  https_cert_file: /var/lib/teleport/fullchain.pem
  https_key_file: /var/lib/teleport/privkey.pem
ssh_service:
  enabled: true
  listen_addr: 0.0.0.0:3022
```

### 6.3 SSL Certificate Generation

```bash
# Install certbot
sudo apt install -y certbot

# Generate certificates
sudo certbot certonly --standalone --preferred-challenges http -d your-domain.com

# Copy certificates to Teleport directory
sudo cp /etc/letsencrypt/live/your-domain.com/fullchain.pem /var/lib/teleport/
sudo cp /etc/letsencrypt/live/your-domain.com/privkey.pem /var/lib/teleport/
sudo chown -R teleport:teleport /var/lib/teleport/
```

### 6.4 Teleport Service Management

```bash
# Start and enable Teleport as a systemd service
sudo systemctl enable teleport
sudo systemctl start teleport
```

## 7. Security Enhancements

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 7.1 ⚠️ | Configure Fail2Ban | 15m | |
| 7.2 | Install AIDE intrusion detection | 15m | |
| 7.3 | Configure log rotation for landing zone | 10m | |
| 7.4 | Set up file cleanup | 10m | |

### 7.1 Fail2Ban Configuration

```bash
# Configure fail2ban for SSH
sudo nano /etc/fail2ban/jail.local
```

Add the following:

```
[sshd]
enabled = true
port = 2223,2222
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
```

```bash
# Restart fail2ban
sudo systemctl restart fail2ban
```

### 7.2 AIDE Intrusion Detection

```bash
# Install AIDE
sudo apt install -y aide

# Initialize AIDE database
sudo aideinit

# Move the generated database to the proper location
sudo mv /var/lib/aide/aide.db.new /var/lib/aide/aide.db

# Set up daily checks
sudo nano /etc/cron.daily/aide-check
```

Add:

```bash
#!/bin/bash
/usr/bin/aide.wrapper --check | mail -s "AIDE report for $(hostname)" root
```

```bash
sudo chmod +x /etc/cron.daily/aide-check
```

### 7.3 & 7.4 Log Rotation and File Cleanup

```bash
# Create cleanup script
sudo nano /etc/cron.daily/landingzone-cleanup
```

Add:

```bash
#!/bin/bash

# Remove files older than 7 days from landing zone
find /opt/LANDINGZONE -type f -not -name ".*" -mtime +7 -delete

# Rotate log file if it gets too large
if [ $(stat -c%s "/opt/LANDINGZONE/.log") -gt 10485760 ]; then
    mv /opt/LANDINGZONE/.log /opt/LANDINGZONE/.log.old
    touch /opt/LANDINGZONE/.log
    chown filetransfer:filetransfer /opt/LANDINGZONE/.log
    chmod 644 /opt/LANDINGZONE/.log
fi
```

```bash
sudo chmod +x /etc/cron.daily/landingzone-cleanup
```

## 8. Monitoring and Alerting

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 8.1 | Configure SSH logging | 10m | |
| 8.2 | Install Netdata monitoring | 15m | |
| 8.3 | Configure email alerts | 10m | |
| 8.4 | Set up container monitoring | 15m | |

### 8.1 SSH Logging Configuration

```bash
# Create log directory
sudo mkdir -p /var/log/ssh-landingzone
sudo chown syslog:adm /var/log/ssh-landingzone

# Configure SSH logging
sudo nano /etc/ssh/sshd_config
```

Add:

```
# Enhanced logging for filetransfer user
Match User filetransfer
    LogLevel VERBOSE
```

```bash
# Configure rsyslog for separate SSH logs
sudo nano /etc/rsyslog.d/10-ssh-landingzone.conf
```

Add:

```
:programname, isequal, "sshd" and :msg, contains, "filetransfer" /var/log/ssh-landingzone/access.log
& stop
```

```bash
# Restart rsyslog
sudo systemctl restart rsyslog
```

### 8.2 & 8.3 Netdata Monitoring

```bash
# Install Netdata
bash <(curl -Ss https://my-netdata.io/kickstart.sh)

# Configure email alerts
sudo nano /etc/netdata/health_alarm_notify.conf
# Set EMAIL_SENDER and DEFAULT_RECIPIENT_EMAIL
```

### 8.4 Container Monitoring

```bash
# Create monitoring script for Docker containers
sudo nano /opt/scripts/monitor_containers.sh
```

Add this content:

```bash
#!/bin/bash

# Check container status
for container in ubuntu-ssh windows-ssh admin-sftp; do
  status=$(docker inspect --format='{{.State.Status}}' $container 2>/dev/null)
  
  if [ "$?" -ne 0 ] || [ "$status" != "running" ]; then
    echo "$(date): WARNING - $container is not running (status: $status)" >> /var/log/container-monitor.log
    # Alert administrators
    mail -s "Container $container is down!" root
    
    # Try to restart the container
    docker start $container
  else
    echo "$(date): Container $container is running normally" >> /var/log/container-monitor.log
  fi
done
```

```bash
# Make script executable
sudo chmod +x /opt/scripts/monitor_containers.sh

# Add to crontab to run every 5 minutes
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/scripts/monitor_containers.sh") | crontab -
```

## 9. Backup Strategy

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 9.1 | Install restic backup tool | 10m | |
| 9.2 | Initialize backup repository | 5m | |
| 9.3 | Create backup script | 15m | |
| 9.4 | Schedule regular backups | 5m | |

```bash
# Install restic backup tool
sudo apt install -y restic

# Initialize restic repository
sudo mkdir -p /backup/ssh-server
sudo restic -r /backup/ssh-server init

# Create backup script
sudo nano /usr/local/bin/backup-ssh-server.sh
```

Add:

```bash
#!/bin/bash
# Backup container images
docker save ubuntu-ssh | gzip > /tmp/ubuntu-ssh.tar.gz
docker save windows-ssh | gzip > /tmp/windows-ssh.tar.gz
docker save admin-sftp | gzip > /tmp/admin-sftp.tar.gz

# Backup Docker Compose config
cp /opt/docker/docker-compose.yml /tmp/

# Backup configuration and containers with restic
restic -r /backup/ssh-server backup \
  /etc/ssh \
  /etc/teleport \
  /var/lib/teleport \
  /opt/LANDINGZONE/.log* \
  /opt/docker \
  /tmp/ubuntu-ssh.tar.gz \
  /tmp/windows-ssh.tar.gz \
  /tmp/admin-sftp.tar.gz \
  /tmp/docker-compose.yml

# Clean up
rm /tmp/ubuntu-ssh.tar.gz /tmp/windows-ssh.tar.gz /tmp/admin-sftp.tar.gz /tmp/docker-compose.yml
```

```bash
sudo chmod +x /usr/local/bin/backup-ssh-server.sh

# Set up cron job for regular backups
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/backup-ssh-server.sh") | crontab -
```

## 10. Performance Tuning

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 10.1 | Install performance monitoring tools | 10m | |
| 10.2 | Configure TCP optimization | 10m | |
| 10.3 | Set up unattended upgrades | 15m | |
| 10.4 | Optimize Docker performance | 15m | |

```bash
# Install sysstat for performance monitoring
sudo apt install -y sysstat

# Enable sysstat collection
sudo sed -i 's/ENABLED="false"/ENABLED="true"/' /etc/default/sysstat
sudo systemctl restart sysstat

# Set up TCP tuning
sudo nano /etc/sysctl.conf
```

Add:

```
# Optimize TCP for high-performance server
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_intvl = 10
net.ipv4.tcp_keepalive_probes = 9
```

```bash
# Apply sysctl changes
sudo sysctl -p

# Configure unattended upgrades
sudo apt install -y unattended-upgrades apt-listchanges

# Enable automatic updates
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure update settings
sudo nano /etc/apt/apt.conf.d/50unattended-upgrades
```

### 10.4 Docker Performance Optimization

```bash
# Create Docker daemon configuration
sudo nano /etc/docker/daemon.json
```

Add:

```json
{
  "storage-driver": "overlay2",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
```

```bash
# Restart Docker
sudo systemctl restart docker
```

## 11. Administrative Network Configuration

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 11.1 | Create administrative user | 10m | |
| 11.2 | Configure admin SSH access | 15m | |
| 11.3 | Set up administrative file upload script | 20m | |
| 11.4 | Configure admin access logging | 10m | |
| 11.5 | Implement administrative network security | 15m | |

### 11.1 Create Administrative User

```bash
# Create dedicated admin user
sudo useradd -m -s /bin/bash adminuser
sudo usermod -aG docker adminuser

# Create admin SSH directory
sudo mkdir -p /home/adminuser/.ssh
sudo touch /home/adminuser/.ssh/authorized_keys

# Add admin public key to authorized_keys
# Replace ADMIN_PUBLIC_KEY with your admin's public key
echo "ADMIN_PUBLIC_KEY" | sudo tee /home/adminuser/.ssh/authorized_keys

# Set proper permissions
sudo chmod 700 /home/adminuser/.ssh
sudo chmod 600 /home/adminuser/.ssh/authorized_keys
sudo chown -R adminuser:adminuser /home/adminuser/.ssh

# Allow admin user to access LANDINGZONE
sudo setfacl -R -m u:adminuser:rwx /opt/LANDINGZONE
sudo usermod -aG docker adminuser
```

### 11.2 Configure Admin SSH Access

```bash
# Create SSH key for admin container access
ssh-keygen -t ed25519 -f ~/.ssh/admin_key -C "admin@server"

# Update the ADMIN_SSH_KEY in the Docker Compose file
sudo nano /opt/docker/docker-compose.yml
# Replace 'ADMIN_SSH_KEY' with the public key content

# Restart the admin container to apply changes
docker restart admin-sftp
```

### 11.3 Set Up Administrative File Upload Script

```bash
# Create script for easy file uploads by administrators
sudo nano /opt/scripts/admin-upload.sh
```

Add this content:

```bash
#!/bin/bash

# Administrative File Upload Script for LANDINGZONE
# Usage: ./admin-upload.sh [file/directory] [destination]

# Configuration
SSH_KEY="$HOME/.ssh/admin_key"
REMOTE_HOST="YOUR_SERVER_IP"  # Replace with your server IP
REMOTE_USER="admin-user"
REMOTE_PORT=2222
DEFAULT_REMOTE_PATH="/LANDINGZONE"

# Check if at least one source is provided
if [ $# -lt 1 ]; then
  echo "Usage: $0 [file/directory] [destination]"
  echo "Example: $0 /path/to/local/file.txt"
  echo "Example: $0 /path/to/local/directory /LANDINGZONE/subdirectory"
  exit 1
fi

# Source file or directory
SOURCE="$1"

# Destination path (default to root LANDINGZONE if not specified)
if [ $# -ge 2 ]; then
  DESTINATION="$2"
else
  DESTINATION="$DEFAULT_REMOTE_PATH"
fi

# Check if source exists
if [ ! -e "$SOURCE" ]; then
  echo "Error: Source file or directory does not exist: $SOURCE"
  exit 1
fi

# Upload file(s)
if [ -d "$SOURCE" ]; then
  # For directories, use recursive copy
  echo "Uploading directory: $SOURCE to $REMOTE_USER@$REMOTE_HOST:$DESTINATION"
  scp -i "$SSH_KEY" -P "$REMOTE_PORT" -r "$SOURCE" "$REMOTE_USER@$REMOTE_HOST:$DESTINATION"
else
  # For single files
  echo "Uploading file: $SOURCE to $REMOTE_USER@$REMOTE_HOST:$DESTINATION"
  scp -i "$SSH_KEY" -P "$REMOTE_PORT" "$SOURCE" "$REMOTE_USER@$REMOTE_HOST:$DESTINATION"
fi

# Check if upload was successful
if [ $? -eq 0 ]; then
  echo "Upload completed successfully!"
  
  # List uploaded files in remote directory
  echo "Contents of $DESTINATION:"
  ssh -i "$SSH_KEY" -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "ls -la $DESTINATION"
else
  echo "Error: Upload failed"
  exit 1
fi
```

```bash
# Make script executable
sudo chmod +x /opt/scripts/admin-upload.sh

# Create symlink for convenience
sudo ln -s /opt/scripts/admin-upload.sh /usr/local/bin/admin-upload
```

### 11.4 Configure Admin Access Logging

```bash
# Create admin access log directory
sudo mkdir -p /var/log/landingzone
sudo touch /var/log/landingzone/admin-access.log
sudo chown -R adminuser:adminuser /var/log/landingzone

# Configure admin access logging
sudo nano /etc/pam.d/sshd
```

Add at the end:

```
# Admin user audit logging
if [ "$PAM_TYPE" = "open_session" ] && [ "$PAM_USER" = "adminuser" -o "$PAM_USER" = "admin-user" ]; then
    echo "$(date): Admin login from $PAM_RHOST" >> /var/log/landingzone/admin-access.log
fi
```

```bash
# Create log rotation for admin access logs
sudo nano /etc/logrotate.d/admin-access
```

Add:

```
/var/log/landingzone/admin-access.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 adminuser adminuser
}
```

### 11.5 Implement Administrative Network Security

```bash
# Update firewall rules to allow admin network access only from authorized IPs
# Replace ADMIN_IP_1, ADMIN_IP_2, etc. with your actual admin IP addresses
sudo ufw allow from ADMIN_IP_1 to any port 2222 proto tcp comment 'Admin SFTP access'
sudo ufw allow from ADMIN_IP_2 to any port 2222 proto tcp comment 'Additional admin SFTP access'

# Create script to monitor admin access attempts
sudo nano /opt/scripts/monitor_admin_access.sh
```

Add:

```bash
#!/bin/bash

# Check for unauthorized access attempts to admin ports
grep "Failed password" /var/log/auth.log | grep "port 2222" | tail -n 10 > /tmp/admin_failed.log

# Count attempts
count=$(cat /tmp/admin_failed.log | wc -l)

if [ "$count" -gt 5 ]; then
  echo "ALERT: Multiple failed admin login attempts detected!"
  cat /tmp/admin_failed.log
  # Send email alert
  mail -s "ALERT: Admin access attempts on $(hostname)" root < /tmp/admin_failed.log
fi

# Clean up
rm /tmp/admin_failed.log
```

```bash
# Make script executable
sudo chmod +x /opt/scripts/monitor_admin_access.sh

# Add to crontab to run every hour
(crontab -l 2>/dev/null; echo "0 * * * * /opt/scripts/monitor_admin_access.sh") | crontab -
```

## 12. Testing

| Step | Description | Est. Time | Actual Time |
|------|-------------|-----------|-------------|
| 12.1 🧪 | Test SFTP connection to landing zone | 10m | |
| 12.2 🧪 | Verify file transfer restrictions | 10m | |
| 12.3 🧪 | Test semaphore mechanism | 15m | |
| 12.4 🧪 | Verify SSH hardening | 10m | |
| 12.5 🧪 | Test Teleport access | 15m | |
| 12.6 📝 | Document test results | 15m | |
| 12.7 🧪 | Test SSH access to Docker containers | 15m | |
| 12.8 🧪 | Verify LANDINGZONE shared access | 15m | |
| 12.9 🧪 | Test administrative network | 15m | |
| 12.10 🧪 | Verify Windows container functionality | 20m | |

### 12.1 & 12.2 Test SFTP Connection & Restrictions

On the external client:

```bash
# Test SFTP connection
sftp -i ~/.ssh/filetransfer_key filetransfer@your-server-ip

# Within SFTP:
ls          # Should only show LANDINGZONE
cd LANDINGZONE
mkdir test   # Should work
cd /         # Should fail - confined to chroot
exit
```

### 12.3 Test Semaphore Mechanism

On the external client, create a test script:

```bash
nano ~/test_transfer.sh
```

Add:

```bash
#!/bin/bash

# Configuration
SSH_KEY="$HOME/.ssh/filetransfer_key"
REMOTE_HOST="your-server-ip"
REMOTE_USER="filetransfer"
REMOTE_PATH="/LANDINGZONE"

# Create a test file
echo "Test file" > /tmp/test_file.txt

# Transfer the file
sftp -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" <<EOF
cd $REMOTE_PATH
put /tmp/test_file.txt
EOF

# Check for semaphore (should appear within 10 seconds)
sleep 15
sftp -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" <<EOF
cd $REMOTE_PATH
ls -la
EOF
```

```bash
chmod +x ~/test_transfer.sh
./test_transfer.sh
```

### 12.4 Test SSH Hardening

```bash
# Test SSH access with default settings (should fail)
ssh root@your-server-ip 

# Test with new port (should work)
ssh -p 2223 your-username@your-server-ip

# Test firewall restrictions
# From an unauthorized IP (should fail)
ssh -p 2223 your-username@your-server-ip
```

### 12.5 Test Teleport Access

```bash
# Create a Teleport user (on the server)
sudo tctl users add teleport-admin --roles=editor,access

# Access the Web UI from a browser:
# https://your-domain.com:3080

# Install Teleport client locally
brew install teleport  # On macOS
# OR
sudo apt install teleport  # On Ubuntu

# Login with the teleport client
tsh login --proxy=your-domain.com:3080 --user=teleport-admin

# List available nodes
tsh ls

# Connect to the server
tsh ssh your-username@your-server-name
```

### 12.7 Test SSH Access to Docker Containers

```bash
# Test SSH access to Ubuntu container
ssh -p 2201 ubuntu-user@your-server-ip

# Test SSH access to Windows container
ssh -p 2202 windows-user@your-server-ip
```

### 12.8 Verify LANDINGZONE Shared Access

On the Ubuntu container:

```bash
# Create a test file in the LANDINGZONE
echo "Test from Ubuntu container" > /LANDINGZONE/ubuntu-test.txt
```

On the Windows container:

```bash
# Verify the file exists and create another
ls -la /LANDINGZONE/ubuntu-test.txt
echo "Test from Windows container" > /LANDINGZONE/windows-test.txt
```

On the host server:

```bash
# Verify both files exist in the host's LANDINGZONE
ls -la /opt/LANDINGZONE/
cat /opt/LANDINGZONE/ubuntu-test.txt
cat /opt/LANDINGZONE/windows-test.txt
```

### 12.9 Test Administrative Network

```bash
# Test administrative access
ssh -p 2222 -i ~/.ssh/admin_key admin-user@your-server-ip

# Test file upload using admin-upload script
./admin-upload.sh /path/to/test/file.txt

# Verify permissions after upload
ls -la /opt/LANDINGZONE/file.txt

# Run permission sync script and verify permissions are maintained
sudo /opt/scripts/sync_permissions.sh
ls -la /opt/LANDINGZONE/file.txt
```

### 12.10 Verify Windows Container Functionality

```bash
# Connect to Windows container
ssh -p 2202 windows-user@your-server-ip

# Verify Windows-specific functionality
powershell -Command "Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion, OsHardwareAbstractionLayer"

# Test file operations in Windows environment
powershell -Command "New-Item -Path 'C:\LANDINGZONE\windows\test.txt' -ItemType File -Value 'Test content from Windows'"

# Verify visibility from host
ls -la /opt/LANDINGZONE/windows/test.txt
cat /opt/LANDINGZONE/windows/test.txt
```

### 12.6 Document Test Results

```bash
# Create document with test results
nano ~/test_results.md
```

## Appendix: Administrative File Upload Client

For the administrative client that will upload files to the landing zone, create this script:

```bash
#!/bin/bash

# Configuration
SSH_KEY="$HOME/.ssh/admin_key"
REMOTE_HOST="your-server-ip"
REMOTE_USER="admin-user" 
REMOTE_PORT=2222
LOCAL_FILES_PATH="$HOME/files_to_upload"
REMOTE_PATH="/LANDINGZONE"

# Check if directory exists
if [ ! -d "$LOCAL_FILES_PATH" ]; then
  echo "Error: Local files directory does not exist: $LOCAL_FILES_PATH"
  exit 1
fi

# Count files to upload
file_count=$(find "$LOCAL_FILES_PATH" -type f | wc -l)
if [ "$file_count" -eq 0 ]; then
  echo "No files found in $LOCAL_FILES_PATH to upload."
  exit 0
fi

# Upload files to the landing zone
echo "Found $file_count files to upload."
echo "Uploading files to the landing zone..."

# Create temporary directory list
find "$LOCAL_FILES_PATH" -type d -mindepth 1 | sed "s|$LOCAL_FILES_PATH/||" > /tmp/dir_list.txt

# Create directories first (if any)
if [ -s /tmp/dir_list.txt ]; then
  echo "Creating remote directories..."
  while read dir; do
    ssh -i "$SSH_KEY" -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "mkdir -p $REMOTE_PATH/$dir"
  done < /tmp/dir_list.txt
fi

# Upload all files to the landing zone
echo "Uploading files..."
scp -i "$SSH_KEY" -P "$REMOTE_PORT" -r "$LOCAL_FILES_PATH"/* "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/"

# Check if upload was successful
if [ $? -eq 0 ]; then
  echo "Files uploaded successfully to $REMOTE_HOST:$REMOTE_PATH/"
  
  # Get remote file list
  echo "Files now available in the landing zone:"
  ssh -i "$SSH_KEY" -p "$REMOTE_PORT" "$REMOTE_USER@$REMOTE_HOST" "find $REMOTE_PATH -type f | sort"
  
  # Log the upload
  echo "$(date): Uploaded $file_count files to $REMOTE_HOST:$REMOTE_PATH/" >> ~/admin_uploads.log
else
  echo "Error: File upload failed!"
  exit 1
fi

# Clean up
rm -f /tmp/dir_list.txt
```

Make this script executable:

```bash
chmod +x ~/admin-upload-client.sh
```

## Appendix: Windows Container Customization

To further customize the Windows container for specific workloads:

```bash
# Create script to customize Windows container
sudo nano /opt/scripts/customize_windows.sh
```

Add:

```bash
#!/bin/bash

# This script adds additional Windows software and configurations to the Windows container

# Connect to Windows container
docker exec -it windows-ssh powershell -Command "
  # Install additional Windows features
  Add-WindowsFeature Web-Server;
  
  # Create Windows environment variables
  [Environment]::SetEnvironmentVariable('LANDINGZONE_PATH', 'C:\\LANDINGZONE', 'Machine');
  
  # Install Windows-specific tools
  Invoke-WebRequest -Uri 'https://example.com/windows-tool.msi' -OutFile 'C:\\windows-tool.msi';
  Start-Process -FilePath 'msiexec.exe' -ArgumentList '/i C:\\windows-tool.msi /quiet' -Wait;
  
  # Configure Windows environment
  New-Item -Path 'C:\\LANDINGZONE\\windows\\config' -ItemType Directory -Force;
  Set-Content -Path 'C:\\LANDINGZONE\\windows\\config\\settings.ini' -Value '[Settings]\nEnabled=True\nPath=C:\\LANDINGZONE\\windows';
  
  # Report success
  Write-Host 'Windows container customization completed successfully.'
"
```

```bash
# Make script executable
sudo chmod +x /opt/scripts/customize_windows.sh
```

## Appendix: Troubleshooting Guide

### Common Issues and Resolutions

1. **Docker containers can't access LANDINGZONE**
   - Check permissions: `ls -la /opt/LANDINGZONE`
   - Ensure Docker group has access: `groups filetransfer`
   - Verify mount in containers: `docker exec ubuntu-ssh ls -la /LANDINGZONE`
   - Solution: Run `chmod 775 /opt/LANDINGZONE && chown filetransfer:docker /opt/LANDINGZONE`

2. **SSH connection to containers fails**
   - Check container status: `docker ps`
   - Verify port forwarding: `netstat -tulpn | grep 220`
   - Check container logs: `docker logs ubuntu-ssh`
   - Solution: Restart container or check SSH configuration inside container

3. **Semaphore not created after file transfer**
   - Check monitor service: `systemctl status landingzone-monitor`
   - Verify script permissions: `ls -la /opt/scripts/monitor_landingzone.sh`
   - Check script logs: `cat /opt/LANDINGZONE/.log`
   - Solution: Restart service or check for script errors

4. **Access denied when transferring files**
   - Verify user permissions: `id filetransfer`
   - Check SSH key setup: `cat /home/filetransfer/.ssh/authorized_keys`
   - Review SSH server logs: `tail /var/log/auth.log`
   - Solution: Fix permissions or SSH configuration

5. **Windows container not functioning properly**
   - Check Windows container status: `docker logs windows-ssh`
   - Verify Windows container can access files: `docker exec windows-ssh powershell -Command "Get-ChildItem -Path C:\LANDINGZONE"`
   - Test Windows container network: `docker exec windows-ssh powershell -Command "Test-NetConnection -ComputerName 8.8.8.8 -Port 80"`
   - Solution: Rebuild Windows container with proper configuration

6. **Administrative access issues**
   - Check admin container status: `docker ps | grep admin-sftp`
   - Verify admin SSH configuration: `docker exec admin-sftp cat /etc/ssh/sshd_config`
   - Test admin network: `docker network inspect admin-network`
   - Solution: Restart admin container or fix SSH configuration

### Security Incident Response

In case of detected security incidents:

1. **Unauthorized access attempt**
   - Check logs: `tail -f /var/log/auth.log`
   - Review failed login attempts: `grep "Failed password" /var/log/auth.log`
   - Check banned IPs: `fail2ban-client status sshd`
   - Action: Update firewall rules, rotate SSH keys

2. **File integrity violation**
   - Review AIDE reports: `cat /var/mail/root`
   - Check recent file changes: `find /opt/LANDINGZONE -type f -mtime -1`
   - Action: Restore from backup, investigate source of compromise

3. **Container compromise**
   - Stop affected container: `docker stop [container-name]`
   - Save container for forensics: `docker commit [container-id] forensic-image`
   - Review container logs: `docker logs [container-name]`
   - Action: Rebuild container from scratch, update image
