#!/bin/bash

# Landing Zone Testing Script
# This script tests all components of the Secure Landing Zone implementation

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to print section header
print_header() {
    echo -e "\n${YELLOW}======================================================${NC}"
    echo -e "${YELLOW}$1${NC}"
    echo -e "${YELLOW}======================================================${NC}"
}

# Function to print test result
print_result() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}[PASS]${NC} $2"
    else
        echo -e "${RED}[FAIL]${NC} $2"
    fi
}

# Start testing
print_header "SECURE LANDING ZONE - TESTING SCRIPT"
echo "This script will test all components of the Secure Landing Zone implementation"

# 1. Check if required directories exist
print_header "Testing Directory Structure"

test -d /opt/LANDINGZONE
print_result $? "LANDINGZONE directory exists"

test -d /opt/LANDINGZONE/windows
print_result $? "Windows subdirectory exists"

test -d /opt/scripts
print_result $? "Scripts directory exists"

test -d /opt/docker
print_result $? "Docker directory exists"

# 2. Check if required files exist
print_header "Testing Configuration Files"

test -f /opt/docker/docker-compose.yml
print_result $? "Docker compose configuration exists"

test -f /opt/scripts/sync_permissions.sh
print_result $? "Permission sync script exists"

test -f /opt/scripts/admin-upload.sh
print_result $? "Admin upload script exists"

# 3. Check if users exist
print_header "Testing User Configuration"

id filetransfer &>/dev/null
print_result $? "Filetransfer user exists"

id adminuser &>/dev/null
print_result $? "Admin user exists"

# 4. Check SSH configuration
print_header "Testing SSH Configuration"

grep -q "Match User filetransfer" /etc/ssh/sshd_config
print_result $? "SSH config contains filetransfer configuration"

systemctl is-active --quiet sshd
print_result $? "SSH service is running"

# 5. Check Docker containers
print_header "Testing Docker Containers"

docker ps | grep -q "ubuntu-ssh"
print_result $? "Ubuntu container is running"

docker ps | grep -q "windows-ssh"
print_result $? "Windows container is running"

docker ps | grep -q "admin-sftp"
print_result $? "Admin container is running"

# 6. Test network connectivity to containers
print_header "Testing Container Network Connectivity"

# Check if netcat is installed
if ! command -v nc &> /dev/null; then
    echo "Installing netcat for network tests..."
    sudo apt-get update && sudo apt-get install -y netcat
fi

nc -z -w 1 localhost 2201
print_result $? "Ubuntu container SSH port (2201) is accessible"

nc -z -w 1 localhost 2202
print_result $? "Windows container SSH port (2202) is accessible"

nc -z -w 1 localhost 2222
print_result $? "Admin container SSH port (2222) is accessible"

# 7. Test permissions
print_header "Testing Permissions"

touch /opt/LANDINGZONE/test_file.txt
print_result $? "Can create files in LANDINGZONE"

sudo -u filetransfer touch /opt/LANDINGZONE/test_filetransfer.txt
print_result $? "Filetransfer user can create files in LANDINGZONE"

sudo -u adminuser touch /opt/LANDINGZONE/test_admin.txt
print_result $? "Admin user can create files in LANDINGZONE"

# 8. Test permission sync script
print_header "Testing Permission Synchronization"

sudo /opt/scripts/sync_permissions.sh
print_result $? "Permission sync script executes successfully"

# Check file permissions after sync
ls -la /opt/LANDINGZONE/test_file.txt | grep -q "rw-rw-r--"
print_result $? "File permissions are correctly set by sync script"

# Check directory permissions after sync
ls -lad /opt/LANDINGZONE/windows | grep -q "rwxrwxr-x"
print_result $? "Directory permissions are correctly set by sync script"

# 9. Test firewall configuration
print_header "Testing Firewall Configuration"

sudo ufw status | grep -q "22/tcp.*ALLOW.*YOUR_AUTHORIZED_IP"
print_result $? "External SFTP port is restricted to authorized IP"

sudo ufw status | grep -q "2222/tcp.*ALLOW.*ADMIN_IP"
print_result $? "Admin SFTP port is restricted to admin IPs"

sudo ufw status | grep -q "2201/tcp.*ALLOW"
print_result $? "Ubuntu container port is allowed"

sudo ufw status | grep -q "2202/tcp.*ALLOW"
print_result $? "Windows container port is allowed"

# 10. Test container file access
print_header "Testing Container File Access"

echo "test content" > /opt/LANDINGZONE/container_test.txt
docker exec ubuntu-ssh ls -la /LANDINGZONE/container_test.txt &>/dev/null
print_result $? "Ubuntu container can access files in LANDINGZONE"

docker exec admin-sftp ls -la /LANDINGZONE/container_test.txt &>/dev/null
print_result $? "Admin container can access files in LANDINGZONE"

# Cleanup test files
print_header "Cleaning Up Test Files"

rm -f /opt/LANDINGZONE/test_file.txt
rm -f /opt/LANDINGZONE/test_filetransfer.txt
rm -f /opt/LANDINGZONE/test_admin.txt
rm -f /opt/LANDINGZONE/container_test.txt

echo -e "\n${GREEN}Testing completed!${NC}"
echo "Please review any failed tests and make necessary adjustments."
echo "For complete external user testing, follow the procedures in the documentation."
