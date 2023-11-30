#!/usr/bin/env bash

# To debug this script, run it with: bash -x ./update.sh
LATEST_URL='https://github.com/google/cadvisor/releases/latest'
REGEX_TO_EXTRACT_TAG='(?<=^https://github.com/google/cadvisor/releases/tag/).*$'
GCR_IO_MANIFEST_BASE_URL='https://gcr.io/v2/cadvisor/cadvisor/manifests'

# Github has a 'latest' release which redirects to the associated tag
TAG=$(curl -sIo /dev/null $LATEST_URL -w '%header{location}' | grep -Po "$REGEX_TO_EXTRACT_TAG")

# Check TAG
if [ -z "$TAG" ]; then 
    echo "Something went wrong, the tag is empty - did they change the tag format?"
    exit 1
fi

echo "Latest release tag from github is $TAG"
NEW_LATEST_IMAGE="gcr.io/cadvisor/cadvisor:$TAG"
GCR_IO_TAG_URL="$GCR_IO_MANIFEST_BASE_URL/$TAG"

# Load .env file
set -o allexport # automatically export all variables
source .env
set +o allexport # turn off auto-export

# Check if the image is already the latest
if [ "$CADVISOR_LATEST_IMAGE" = "$NEW_LATEST_IMAGE" ]; then
    echo "Current Image is already the latest - no need to update."
    exit 0
fi
echo "Current image is not up to date, continuing..."
echo "New image: $NEW_LATEST_IMAGE"
echo "Old image: $CADVISOR_LATEST_IMAGE" # the old LATEST

# Ensure the image exists in the gcr.io registry
if curl --output /dev/null --silent --head --fail "$GCR_IO_TAG_URL"; then # negation with !
    echo "Image exists in gcr.io registry, continuing..."
else
    echo "Image does not exist in gcr.io registry, aborting..."
    exit 1
fi

# Prompt the user if they want to update the running container now so the new image is used
read -p "Do you want to update now? [Y/n] " -n 1 -r
echo # move to a new line

if [[ $REPLY =~ ^[Yy]$ ]] || [ -z "$REPLY" ]; then
    echo "Updating running container"
    SED_COMMAND="s|CADVISOR_LATEST_IMAGE=.*|CADVISOR_LATEST_IMAGE=$NEW_LATEST_IMAGE|g"
    
    # check if user is root (so we can update the .env file)
    if [ $(id -u) = 0 ]; then
        echo "Updating .env file"
        sed -i "$SED_COMMAND" .env

        echo "Pulling new image and restarting container"
        docker-compose pull && docker-compose up -d
    else # fallback to sudo
        echo "Updating .env file"
        sudo sed -i "$SED_COMMAND" .env
        sudo docker-compose pull && sudo docker-compose up -d 
    fi
else
    echo "User aborted, did not change/update anything."
fi
