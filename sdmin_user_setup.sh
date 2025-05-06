#!/bin/bash

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

# Create admin access log directory 
sudo mkdir -p /var/log/landingzone
sudo touch /var/log/landingzone/admin-access.log
sudo chown -R adminuser:adminuser /var/log/landingzone

# Set up admin access logging
echo '
# Admin user audit logging
if [ "$PAM_TYPE" = "open_session" ] && [ "$PAM_USER" = "adminuser" ]; then
    echo "$(date): Admin login from $PAM_RHOST" >> /var/log/landingzone/admin-access.log
fi
' | sudo tee -a /etc/pam.d/sshd > /dev/null

echo "Admin user setup completed successfully"
