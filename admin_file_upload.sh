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
