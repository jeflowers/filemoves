# Improved Secure Landing Zone Implementation

This implementation provides a lightweight but secure framework for:
1. Allowing SFTP connections over port 22 from a specified IP address
2. Maintaining the NAT configuration for containers
3. Creating a secure transfer environment with minimal components
4. Using a proper Windows container (fixed)
5. Adding an administrative network for managing the LANDINGZONE

## 1. Initial Setup

First, let's set up the basic system:

```bash
# Update the system
sudo apt update && sudo apt upgrade -y

# Install essential packages
sudo apt install -y ufw fail2ban openssh-server docker.io docker-compose acl
```

## 2. Configure Landing Zone

Let's create the landing zone directory and user:

```bash
# Create dedicated user for file transfers
sudo useradd -m -s /bin/bash filetransfer

# Create dedicated admin user
sudo useradd -m -s /bin/bash adminuser
sudo usermod -aG docker adminuser

# Create landing zone directory
sudo mkdir -p /opt/LANDINGZONE
sudo mkdir -p /opt/LANDINGZONE/windows

# Set proper permissions
sudo chown filetransfer:docker /opt/LANDINGZONE
sudo chmod 770 /opt/LANDINGZONE

# Allow admin user to access LANDINGZONE
sudo setfacl -R -m u:adminuser:rwx /opt/LANDINGZONE
```

## 3. SSH Configuration

Configure SSH for secure access:

```bash
# Create SSH directory for the filetransfer user
sudo mkdir -p /home/filetransfer/.ssh
sudo touch /home/filetransfer/.ssh/authorized_keys

# Add your public key to authorized_keys
# Replace YOUR_PUBLIC_KEY with your actual public key
echo "YOUR_PUBLIC_KEY" | sudo tee /home/filetransfer/.ssh/authorized_keys

# Set proper permissions
sudo chmod 700 /home/filetransfer/.ssh
sudo chmod 600 /home/filetransfer/.ssh/authorized_keys
sudo chown -R filetransfer:filetransfer /home/filetransfer/.ssh

# Configure SSH for adminuser
sudo mkdir -p /home/adminuser/.ssh
sudo touch /home/adminuser/.ssh/authorized_keys

# Add admin public key to authorized_keys
# Replace ADMIN_PUBLIC_KEY with your actual admin public key
echo "ADMIN_PUBLIC_KEY" | sudo tee /home/adminuser/.ssh/authorized_keys

# Set proper permissions
sudo chmod 700 /home/adminuser/.ssh
sudo chmod 600 /home/adminuser/.ssh/authorized_keys
sudo chown -R adminuser:adminuser /home/adminuser/.ssh

# Configure SFTP chroot for filetransfer user
sudo nano /etc/ssh/sshd_config
```

Add the following to the end of sshd_config:

```
# Restrict filetransfer user to LANDINGZONE
Match User filetransfer
    ChrootDirectory /opt
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
```

```bash
# Restart SSH service
sudo systemctl restart sshd
```

## 4. Firewall Configuration

Set up the firewall to allow connections from specified IPs:

```bash
# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (port 22) only from specific IP for regular users
# Replace YOUR_AUTHORIZED_IP with your actual IP address
sudo ufw allow from YOUR_AUTHORIZED_IP to any port 22 proto tcp comment 'Regular SFTP access'

# Allow SSH container ports
sudo ufw allow 2201/tcp comment 'Ubuntu container SSH via NAT'
sudo ufw allow 2202/tcp comment 'Windows container SSH via NAT'

# Allow admin SFTP access on port 2222 only from admin IPs
# Replace ADMIN_IP_1, ADMIN_IP_2 with actual admin IP addresses
sudo ufw allow from ADMIN_IP_1 to any port 2222 proto tcp comment 'Admin SFTP access'
sudo ufw allow from ADMIN_IP_2 to any port 2222 proto tcp comment 'Additional admin access'

# Enable firewall
sudo ufw enable
```

## 5. Configure Docker Networks and Container Setup

Create the required networks and docker-compose.yml file:

```bash
# Create Docker networks
docker network create --driver bridge landing_zone_network
docker network create --driver bridge admin_network

# Create docker-compose directory
sudo mkdir -p /opt/docker
sudo nano /opt/docker/docker-compose.yml
```

Add the following content:

```yaml
version: '3'

networks:
  landing_zone_network:
    external: true
  admin_network:
    external: true

services:
  ubuntu-container:
    image: ubuntu:22.04
    container_name: ubuntu-ssh
    restart: always
    volumes:
      - /opt/LANDINGZONE:/LANDINGZONE:rw
    ports:
      - "2201:22"
    networks:
      - landing_zone_network
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
    ports:
      - "2202:22"
    networks:
      - landing_zone_network
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
      - admin_network
      - landing_zone_network
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

## 6. File Permissions Synchronization

Set up enhanced file permissions sync to ensure consistent access:

```bash
# Create script to synchronize file permissions
sudo mkdir -p /opt/scripts
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

# Run every 5 minutes via cron
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/scripts/sync_permissions.sh") | crontab -
```

## 7. Administrative File Upload Script

Create a script to help administrators easily upload files to the LANDINGZONE:

```bash
# Create admin upload script
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

## 8. Start Docker Containers

```bash
# Start Docker containers
cd /opt/docker
sudo docker-compose up -d

# Run initial permission sync
sudo /opt/scripts/sync_permissions.sh
```

## 9. Testing - External User File Retrieval

For the external user to retrieve files from the LANDINGZONE, they need to:

1. Generate an SSH key pair (if they don't already have one):
```bash
# On the external user's machine
ssh-keygen -t ed25519 -f ~/.ssh/landingzone_key -C "external_user@example.com"
```

2. Provide their public key to be added to the server:
```bash
# On external user's machine - display public key to send to server admin
cat ~/.ssh/landingzone_key.pub
```

The server admin should add this key to the authorized_keys file:
```bash
# On the server
echo "EXTERNAL_USER_PUBLIC_KEY" | sudo tee -a /home/filetransfer/.ssh/authorized_keys
```

3. Test connection from the external user's machine:
```bash
# Test SFTP connection
sftp -i ~/.ssh/landingzone_key filetransfer@SERVER_IP
```

4. Retrieve files from the LANDINGZONE:
```bash
# Within SFTP session
cd LANDINGZONE
ls               # List files available to retrieve
get filename     # Download a specific file
get -r directory # Download a directory recursively
exit
```

Alternatively, the external user can use scp to download files directly:
```bash
# Download a specific file
scp -i ~/.ssh/landingzone_key filetransfer@SERVER_IP:/LANDINGZONE/filename local_destination

# Download an entire directory
scp -i ~/.ssh/landingzone_key -r filetransfer@SERVER_IP:/LANDINGZONE/directory local_destination
```

For automated retrieval, the external user can create a script like this:
```bash
#!/bin/bash

# Configuration
SSH_KEY="$HOME/.ssh/landingzone_key"
REMOTE_HOST="SERVER_IP"
REMOTE_USER="filetransfer"
REMOTE_PATH="/LANDINGZONE"
LOCAL_PATH="$HOME/downloaded_files"

# Create local directory if it doesn't exist
mkdir -p "$LOCAL_PATH"

# Download all files from the landing zone
scp -i "$SSH_KEY" -r "$REMOTE_USER@$REMOTE_HOST:$REMOTE_PATH/*" "$LOCAL_PATH/"

echo "Files retrieved successfully to $LOCAL_PATH"
```

## 10. Testing - Administrative File Upload

For administrators to upload files to the LANDINGZONE:

1. Generate an SSH key pair for admin access:
```bash
# On the admin's machine
ssh-keygen -t ed25519 -f ~/.ssh/admin_key -C "admin@example.com"
```

2. Provide the admin public key to be added to the server:
```bash
# On admin's machine - display public key to send to server admin
cat ~/.ssh/admin_key.pub
```

The server admin should add this key to both the admin-user in the container and the adminuser on the host:
```bash
# On the server - for admin container
docker exec -it admin-sftp bash -c "echo 'ADMIN_PUBLIC_KEY' > /home/admin-user/.ssh/authorized_keys"

# On the server - for host admin user
echo "ADMIN_PUBLIC_KEY" | sudo tee /home/adminuser/.ssh/authorized_keys
```

3. Test admin connection:
```bash
# Test SFTP connection to admin container
sftp -i ~/.ssh/admin_key -P 2222 admin-user@SERVER_IP
```

4. Upload files to the LANDINGZONE:
```bash
# Using the admin-upload script
./admin-upload.sh /path/to/local/file.txt
./admin-upload.sh /path/to/local/directory

# Or directly via SFTP
sftp -i ~/.ssh/admin_key -P 2222 admin-user@SERVER_IP
```

## 11. Backout Plan

In case the implementation needs to be rolled back, follow these steps:

```bash
# 1. Stop Docker containers
cd /opt/docker
sudo docker-compose down

# 2. Remove Docker containers and directories
sudo docker rm -f ubuntu-ssh windows-ssh admin-sftp
sudo docker network rm landing_zone_network admin_network
sudo rm -rf /opt/docker

# 3. Restore SSH configuration
sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config  # If a backup was made
# OR manually remove the "Match User filetransfer" section
sudo systemctl restart sshd

# 4. Remove the landing zone and scripts
sudo rm -rf /opt/LANDINGZONE
sudo rm -rf /opt/scripts
sudo rm -f /usr/local/bin/admin-upload

# 5. Remove the users
sudo userdel -r filetransfer
sudo userdel -r adminuser

# 6. Reset firewall rules
sudo ufw reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh  # or your original SSH port
sudo ufw enable

# 7. Clean up crontab entries
crontab -l | grep -v "sync_permissions.sh" | crontab -
```

Before implementing the full solution, create backups:

```bash
# Create a backup of SSH config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

# Document current firewall rules
sudo ufw status verbose > ~/ufw_rules_backup.txt

# Backup crontab entries
crontab -l > ~/crontab_backup.txt
```

This improved implementation provides:
1. Secure SFTP access to the landing zone (port 22) from a specified IP only
2. A proper Windows Server Core container instead of Ubuntu+Wine
3. Administrative network for secure file uploads to the LANDINGZONE
4. Enhanced permission management for both external users and administrators
5. NAT configuration for containers
6. Core security measures
7. Simple procedures for both external users to retrieve files and administrators to upload files
8. A complete backout plan for reverting changes

These components form a secure implementation that addresses the requirements for both Windows compatibility and administrative access.
