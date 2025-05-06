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
