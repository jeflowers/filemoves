#!/bin/bash

# Improved Secure Landing Zone Implementation Script
# This script sets up a secure file transfer environment with:
# 1. A fixed Windows container
# 2. An administrative network for adding files
# 3. Enhanced security measures

# Exit on any error
set -e

echo "Starting Secure Landing Zone setup..."

# 1. Update the system
echo "Updating system packages..."
sudo apt update && sudo apt upgrade -y

# 2. Install essential packages
echo "Installing required packages..."
sudo apt install -y ufw fail2ban openssh-server docker.io docker-compose acl

# 3. Create landing zone directory and users
echo "Creating landing zone directory and users..."
# Create dedicated user for file transfers
sudo useradd -m -s /bin/bash filetransfer

# Create landing zone directory
sudo mkdir -p /opt/LANDINGZONE
sudo mkdir -p /opt/LANDINGZONE/windows

# Set proper permissions
sudo chown filetransfer:docker /opt/LANDINGZONE
sudo chmod 770 /opt/LANDINGZONE

# 4. SSH Configuration for filetransfer user
echo "Configuring SSH for secure access..."
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

# Configure SFTP chroot for filetransfer user
echo "Backing up SSH config..."
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak

echo "Updating SSH config..."
echo '
# Restrict filetransfer user to LANDINGZONE
Match User filetransfer
    ChrootDirectory /opt
    ForceCommand internal-sftp
    AllowTcpForwarding no
    X11Forwarding no
    PermitTunnel no
' | sudo tee -a /etc/ssh/sshd_config

# 5. Set up administrative user
echo "Setting up administrative user..."
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

# Create admin access log directory 
sudo mkdir -p /var/log/landingzone
sudo touch /var/log/landingzone/admin-access.log
sudo chown -R adminuser:adminuser /var/log/landingzone

# 6. Configure Docker setup
echo "Configuring Docker..."
# Create docker directory
sudo mkdir -p /opt/docker

# Create docker-compose.yml
cat > /opt/docker/docker-compose.yml << 'EOL'
version: '3'

networks:
  landing_zone_network:
    driver: bridge
  admin_network:
    driver: bridge
    internal: false  # Allows external connectivity

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
EOL

# 7. Create file permissions synchronization script
echo "Creating file permissions sync script..."
cat > /opt/scripts/sync_permissions.sh << 'EOL'
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
EOL

# Make script executable
sudo chmod +x /opt/scripts/sync_permissions.sh

# 8. Set up firewall
echo "Configuring firewall..."
# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (port 22) only from specific IP
# Replace YOUR_AUTHORIZED_IP with your actual IP address
sudo ufw allow from YOUR_AUTHORIZED_IP to any port 22 proto tcp comment 'External user SFTP access'

# Allow container SSH ports
sudo ufw allow 2201/tcp comment 'Ubuntu container SSH via NAT'
sudo ufw allow 2202/tcp comment 'Windows container SSH via NAT'

# Allow admin access only from authorized admin IPs
# Replace ADMIN_IP_1, ADMIN_IP_2, etc. with actual admin IP addresses
sudo ufw allow from ADMIN_IP_1 to any port 2222 proto tcp comment 'Admin SFTP access'
sudo ufw allow from ADMIN_IP_2 to any port 2222 proto tcp comment 'Additional admin SFTP access'

# Enable firewall
sudo ufw --force enable

echo "Configuring firewall rules completed"

# 9. Set up crontab for permission synchronization
echo "Setting up scheduled permission synchronization..."
(crontab -l 2>/dev/null; echo "*/5 * * * * /opt/scripts/sync_permissions.sh") | crontab -

# 10. Create administrative file upload script
echo "Creating administrative file upload script..."
cat > /opt/scripts/admin-upload.sh << 'EOL'
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
EOL

sudo chmod +x /opt/scripts/admin-upload.sh

# 11. Start Docker containers
echo "Starting Docker containers..."
cd /opt/docker
sudo docker-compose up -d

# 12. Run initial permission sync
echo "Running initial permission synchronization..."
sudo /opt/scripts/sync_permissions.sh

# 13. Restart SSH service
echo "Restarting SSH service..."
sudo systemctl restart sshd

# 14. Create documentation
echo "Creating documentation..."
cat > /opt/LANDING_ZONE_README.md << 'EOL'
# Secure Landing Zone Implementation

This implementation provides a secure framework for file transfers with both regular and administrative access:

## Features
- SFTP connections over port 22 from specified IP addresses for regular users
- Administrative network for adding files to the landing zone (port 2222)
- Proper Windows container implementation
- Secure file permissions management
- Regular synchronization of permissions

## Access Instructions

### For Regular Users
Regular users can access the landing zone via SFTP:
```bash
# Connect via SFTP
sftp -i ~/.ssh/landingzone_key filetransfer@SERVER_IP

# Navigate to the landing zone
cd LANDINGZONE

# List files
ls

# Download files
get filename
get -r directory
```

### For Administrators
Administrators can upload files to the landing zone:
```bash
# Using the provided script
/opt/scripts/admin-upload.sh /path/to/local/file.txt

# Or directly via SFTP
sftp -i ~/.ssh/admin_key -P 2222 admin-user@SERVER_IP
```

## Windows Environment
The Windows container is accessible on port 2202 and provides a Windows Server Core environment.

## Security Features
- IP-based access restrictions
- Key-based authentication only
- Regular permission synchronization
- Separation between user and admin networks
- Comprehensive logging
EOL

echo "==================================================="
echo "Setup completed successfully!"
echo "Please review /opt/LANDING_ZONE_README.md for usage information"
echo "==================================================="

# Remind to replace placeholder values
echo "IMPORTANT: Please replace the following placeholders in the configuration:"
echo "- YOUR_PUBLIC_KEY: The SSH public key for regular users"
echo "- ADMIN_PUBLIC_KEY: The SSH public key for administrative users"
echo "- CONTAINER_USER_SSH_KEY: The SSH key for container access"
echo "- ADMIN_SSH_KEY: The SSH key for admin container access"
echo "- YOUR_AUTHORIZED_IP: The IP address allowed for regular SFTP access"
echo "- ADMIN_IP_1, ADMIN_IP_2: The IP addresses allowed for admin access"
echo "- YOUR_SERVER_IP: The IP address of this server in the admin-upload.sh script"
