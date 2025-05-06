# Secure Landing Zone Implementation

This implementation provides a secure file transfer environment with a restricted landing zone for regulated data exchange. It features proper Windows compatibility and administrative access for managing the environment.

## Features

- **Secure SFTP Access**: IP-restricted SFTP connections over port 22
- **Proper Windows Container**: Genuine Windows Server Core environment
- **Administrative Network**: Separate network for admin file management
- **Multi-Container Architecture**: Ubuntu and Windows environments
- **Robust Permission Controls**: Automated synchronization
- **Zero-Trust Security Model**: Access controls at multiple levels

## Architecture Overview

```
┌─────────────────────────────────────────┐
│               Host Server                │
│                                         │
│  ┌──────────┐    ┌──────────────────┐   │
│  │ External │    │  Administrative  │   │
│  │  Access  │    │     Access       │   │
│  │ (Port 22)│    │   (Port 2222)    │   │
│  └────┬─────┘    └─────────┬────────┘   │
│       │                    │            │
│       ▼                    ▼            │
│  ┌─────────────────────────────────────┐│
│  │            LANDINGZONE              ││
│  │  /opt/LANDINGZONE                   ││
│  └─────────────────────────────────────┘│
│       │                    │            │
│       ▼                    ▼            │
│  ┌─────────┐         ┌─────────────┐    │
│  │ Ubuntu  │         │   Windows   │    │
│  │Container│         │  Container  │    │
│  └─────────┘         └─────────────┘    │
└─────────────────────────────────────────┘
```

## Prerequisites

- Ubuntu 20.04 or newer
- Docker and Docker Compose
- Superuser (sudo) privileges

## Quick Start

1. Clone this repository:
   ```
   git clone https://github.com/your-org/secure-landingzone.git
   cd secure-landingzone
   ```

2. Run the installation script:
   ```
   sudo ./install.sh
   ```

3. Configure your IP addresses and SSH keys:
   ```
   sudo nano /opt/docker/docker-compose.yml
   # Replace CONTAINER_USER_SSH_KEY and ADMIN_SSH_KEY with your keys

   sudo nano /etc/ufw/ufw.conf
   # Update YOUR_AUTHORIZED_IP and ADMIN_IP addresses
   ```

4. Start the environment:
   ```
   cd /opt/docker
   sudo docker-compose up -d
   ```

## User Guide

### For External Users (File Retrieval)

External users can retrieve files from the LANDINGZONE via SFTP or SCP:

1. Generate an SSH key pair:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/landingzone_key -C "user@example.com"
   ```

2. Provide the public key to the server administrator:
   ```bash
   cat ~/.ssh/landingzone_key.pub
   ```

3. Connect via SFTP:
   ```bash
   sftp -i ~/.ssh/landingzone_key filetransfer@SERVER_IP
   ```

4. Download files:
   ```bash
   # Within SFTP session
   cd LANDINGZONE
   ls               # List files
   get filename     # Download a file
   get -r directory # Download a directory
   ```

5. Or use SCP directly:
   ```bash
   scp -i ~/.ssh/landingzone_key filetransfer@SERVER_IP:/LANDINGZONE/filename local_destination
   ```

### For Administrators (File Upload & Management)

Administrators can upload files and manage the LANDINGZONE:

1. Generate an admin SSH key pair:
   ```bash
   ssh-keygen -t ed25519 -f ~/.ssh/admin_key -C "admin@example.com"
   ```

2. Connect via SFTP on the admin port:
   ```bash
   sftp -i ~/.ssh/admin_key -P 2222 admin-user@SERVER_IP
   ```

3. Use the admin-upload script for convenient file uploads:
   ```bash
   # Upload a file
   admin-upload /path/to/local/file.txt

   # Upload a directory
   admin-upload /path/to/local/directory /LANDINGZONE/target
   ```

4. Monitor LANDINGZONE contents and permissions:
   ```bash
   # Check LANDINGZONE contents
   ssh -i ~/.ssh/admin_key -p 2222 admin-user@SERVER_IP "ls -la /LANDINGZONE"
   
   # Check permission status
   ssh -i ~/.ssh/admin_key -p 2222 admin-user@SERVER_IP "cat /var/log/landingzone-sync.log"
   ```

## Windows Container Usage

The Windows container provides a genuine Windows Server Core environment:

1. Connect to the Windows container:
   ```bash
   ssh -p 2202 windows-user@SERVER_IP
   ```

2. Execute Windows commands:
   ```powershell
   # Check Windows version
   Get-ComputerInfo | Select-Object WindowsProductName, WindowsVersion

   # Access LANDINGZONE files
   Get-ChildItem -Path C:\LANDINGZONE

   # Process files with Windows tools
   # (Example with PowerShell)
   Get-Content C:\LANDINGZONE\example.csv | ConvertFrom-Csv
   ```

## Security Features

- **IP Restrictions**: All access points limited to specific IP addresses
- **SFTP Chroot Jail**: External users confined to LANDINGZONE
- **Key-Based Authentication**: No password authentication allowed
- **Separate Networks**: Administrative and regular access segregated
- **Permission Synchronization**: Automatic file permission management
- **Container Isolation**: Services run in isolated containers

## Troubleshooting

### External Access Issues

1. **Unable to connect via SFTP**:
   - Check IP restrictions: `sudo ufw status`
   - Verify SSH key: `ls -la /home/filetransfer/.ssh/authorized_keys`
   - Check SSH service: `sudo systemctl status sshd`

2. **Permission denied for files**:
   - Run permission sync: `sudo /opt/scripts/sync_permissions.sh`
   - Check file ownership: `ls -la /opt/LANDINGZONE`

### Admin Access Issues

1. **Unable to connect to admin container**:
   - Verify admin container status: `docker ps | grep admin-sftp`
   - Check admin SSH keys: `docker exec admin-sftp cat /home/admin-user/.ssh/authorized_keys`
   - Confirm firewall rules: `sudo ufw status | grep 2222`

2. **Windows container not working**:
   - Check container status: `docker ps | grep windows-ssh`
   - View container logs: `docker logs windows-ssh`
   - Verify network connection: `docker network inspect landing_zone_network`

## Maintenance

### Regular Maintenance Tasks

1. Check container status:
   ```bash
   docker ps
   ```

2. Update the system:
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

3. View LANDINGZONE logs:
   ```bash
   cat /opt/LANDINGZONE/.log
   ```

4. Monitor file access:
   ```bash
   cat /var/log/ssh-landingzone/access.log
   ```

### Backup and Recovery

1. Backup important configurations:
   ```bash
   sudo cp /opt/docker/docker-compose.yml /opt/backup/
   sudo cp /etc/ssh/sshd_config /opt/backup/
   ```

2. Backup SSH keys:
   ```bash
   sudo cp -r /home/filetransfer/.ssh /opt/backup/filetransfer-ssh/
   sudo cp -r /home/adminuser/.ssh /opt/backup/adminuser-ssh/
   ```

## Reference

### Directory Structure

- `/opt/LANDINGZONE` - Main file transfer directory
- `/opt/LANDINGZONE/windows` - Windows-specific files
- `/opt/docker` - Docker configuration files
- `/opt/scripts` - Maintenance and utility scripts

### Network Ports

- `22` - External user SFTP access
- `2201` - Ubuntu container SSH
- `2202` - Windows container SSH
- `2222` - Administrative SFTP access

### Configuration Files

- `/opt/docker/docker-compose.yml` - Container setup
- `/etc/ssh/sshd_config` - SSH server configuration
- `/opt/scripts/sync_permissions.sh` - Permission synchronization

## License

Copyright © 2025 Your Organization

This implementation is proprietary and confidential.
