variable "continuous_deployment_script" {
  description = "Script for continuous deployment"
  type        = string
  default     = <<-SCRIPTFILE
#!/bin/bash

# Check for required arguments
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <docker_args> <image> <port> <release_tag> <instance_name> <blue_green_deployment>"
    exit 1
fi

DOCKER_ARGS=$1
IMAGE=$2
EXTERNAL_PORT=$3
RELEASE_TAG=$4
INSTANCE_NAME=$5
BLUE_GREEN_DEPLOYMENT=$6

# Log file for updates
LOG_FILE="/var/log/sweep-deployment-updates.log"
TAGS_URL="https://sweep-release.s3.amazonaws.com/tags.txt"

echo "$(date): Starting update process" >> $LOG_FILE

# Fetch the latest release tags
if ! TAGS=$(curl -s $TAGS_URL); then
  echo "$(date): Failed to fetch tags from $TAGS_URL" >> $LOG_FILE
  exit 1
fi

# Extract the latest release tag
LATEST_RELEASE=$(echo "$TAGS" | grep "$RELEASE_TAG=" | cut -d= -f2)
if [ -z "$LATEST_RELEASE" ]; then
  echo "$(date): Failed to extract latest release tag" >> $LOG_FILE
  exit 1
fi

echo "$(date): Starting update process with image=$IMAGE, release_tag=$RELEASE_TAG, instance_name=$INSTANCE_NAME" >> $LOG_FILE

# Check if we already have this version pulled
if docker image list | grep $LATEST_RELEASE &>/dev/null; then
    echo "$(date): Image version $LATEST_RELEASE already pulled, exiting" >> $LOG_FILE
    # This means we are done
    exit 0
else
    echo "$(date): Pulling new version $LATEST_RELEASE" >> $LOG_FILE
    # Pull the specific version image
    docker pull $IMAGE:$LATEST_RELEASE
fi

# Start a new container with the latest image on the new port
TIMESTAMP=$(date +%Y%m%d%H%M%S)
IMAGE_AND_RELEASE="$IMAGE:$LATEST_RELEASE"

blue_green_deployment() {
  # Find next available port to deploy to
  PORT=$((EXTERNAL_PORT+1))
  is_port_used() {
    # Simply check if ss returns any output for the port
    if ss -tuln | grep ":$1 " > /dev/null; then
        return 0 # Port is in use (success)
    else
        return 1 # Port is free (failure)
    fi
  }

  while is_port_used $PORT; do
      ((PORT++))
  done

  echo "$(date): Found open port: $PORT" >> $LOG_FILE

  docker run --name $INSTANCE_NAME-$TIMESTAMP $DOCKER_ARGS -p $PORT:$EXTERNAL_PORT $IMAGE_AND_RELEASE

  # Wait until webhook is available before rerouting traffic to it
  echo "$(date): Waiting for server to start..." >> $LOG_FILE
  while true; do
      curl --output /dev/null --silent --head --fail http://localhost:$PORT
      result=$?
      if [[ $result -eq 0 || $result -eq 22 ]]; then
          echo "$(date): Received a good response!" >> $LOG_FILE
          break
      else
          echo "$(date): Waiting for server to start..." >> $LOG_FILE
          sleep 5
      fi
  done

  # Reroute traffic to new docker container
  sudo iptables -t nat -L PREROUTING --line-numbers | grep 'REDIRECT' | tail -n1 | awk '{print $1}' | xargs -I {} sudo iptables -t nat -D PREROUTING {}

  # redirect external 8080 to internal docker container
  sudo iptables -t nat -A PREROUTING -p tcp --dport $EXTERNAL_PORT -j REDIRECT --to-port $PORT

  # redirect internal 8080 to internal docker container
  sudo iptables -t nat -L OUTPUT --line-numbers | grep 'REDIRECT' | tail -n1 | awk '{print $1}' | xargs -I {} sudo iptables -t nat -D OUTPUT {}
  sudo iptables -t nat -A OUTPUT -p tcp -o lo --dport $EXTERNAL_PORT -j REDIRECT --to-port $PORT

  containers_to_remove=$(docker ps -q --filter "name=$INSTANCE_NAME" | awk 'NR>1')

  if [ ! -z "$containers_to_remove" ]; then
      (
          sleep 1200
          echo "$containers_to_remove" | while read -r container; do
              if [ ! -z "$container" ]; then
                  docker kill "$container"
                  # Wait for container to be fully terminated
                  while [ -n "$(docker ps -q --filter "id=$container")" ]; do
                      echo "$(date): Waiting for container $container to terminate..." >> $LOG_FILE
                      sleep 1
                  done
              fi
          done
      ) &
      echo "Scheduled removal of old containers after 20 minutes"
  else
      echo "$(date): No old containers to remove" >> $LOG_FILE
  fi

  echo "$(date): Update completed successfully" >> $LOG_FILE
}

direct_redeployment() {
  echo "$(date): Running direct redeployment" >> $LOG_FILE

  # Kill the last instance
  containers_to_remove=$(docker ps -q --filter "name=$INSTANCE_NAME")

  echo "$containers_to_remove" | while read -r container; do
    if [ ! -z "$container" ]; then
      docker kill "$container"
      # Wait for container to be fully terminated
      while [ -n "$(docker ps -q --filter "id=$container")" ]; do
          echo "$(date): Waiting for container $container to terminate..." >> $LOG_FILE
          sleep 1
      done
    fi
  done

  # Deploy the latest version, all instances currently use 80 if not backend
  docker run --name $INSTANCE_NAME-$TIMESTAMP $DOCKER_ARGS -p 80:$EXTERNAL_PORT $IMAGE_AND_RELEASE

  echo "$(date): Direct redeployment completed" >> $LOG_FILE
}

if [ "$BLUE_GREEN_DEPLOYMENT" = "true" ]; then
  blue_green_deployment
else
  direct_redeployment
fi

echo "$(date): Running aggressive Docker cleanup" >> $LOG_FILE
docker system prune -af >> $LOG_FILE 2>&1
  SCRIPTFILE
}

output "continuous_deployment_script" {
  value = var.continuous_deployment_script
}