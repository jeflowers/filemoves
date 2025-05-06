#!/bin/bash

# Set default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (port 22) only from specific IP for external users
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
sudo ufw enable

# Display firewall status to verify
sudo ufw status verbose
