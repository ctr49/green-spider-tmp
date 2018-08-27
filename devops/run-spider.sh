#!/bin/bash

# Creates a server, installs Docker, runs the spider job, tears down the server.
#
# This will take several hours. For a complete, clean run it is required to leave the
# terminal running the script open. Otherwise the server won't be deleted properly
# which will result in extra cost.
#
# When stopping the script at any point (Ctrl+C), please make sure that the server
# gets deleted afterwards.
#
# Requirements:
#
# - curl
# - jq (https://stedolan.github.io/jq/)
# - ssh
# - SSH key referenced in the server details ("ssh_keys")
# - Service account with write permission for Storage and Datastore in 
#   secrets/datastore-writer.json


API_TOKEN_SECRET="secrets/hetzner-api-token.sh"

test -f $API_TOKEN_SECRET || { echo >&2 "File $API_TOKEN_SECRET does not exist."; exit 1; }

source $API_TOKEN_SECRET

echo "Creating server 'spider'"

# server_type 'cx11' is the smallest, cheapest category.
# location 'nbg1' is Nürnberg/Nuremberg, Germany.
# image 'debian-9' is a plain Debian stretch.
# ssh_keys ['Marian'] adds Marian's public key to the server and can be extended.
# user_data: Ensures that we can detect when the cloud-init setup is done.
#
CREATE_RESPONSE=$(curl -s -X POST https://api.hetzner.cloud/v1/servers \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  -d '{
    "name": "spider",
    "server_type": "cx11",
    "location": "nbg1",
    "start_after_create": true,
    "image": "debian-9",
    "ssh_keys": [
      "Marian"
    ],
    "user_data": "#cloud-config\nruncmd:\n  - touch /cloud-init-done\n"
  }')

# Get ID:
SERVER_ID=$(echo $CREATE_RESPONSE | jq -r .server.id)

# Get IP:
SERVER_IP=$(echo $CREATE_RESPONSE | jq -r .server.public_net.ipv4.ip)

echo "Created server with ID $SERVER_ID and IP $SERVER_IP"
echo -n "Waiting for the server to be reachable via SSH "

sleep 30

STATUS="255"
while [ "$STATUS" != "0" ]; do
  echo -n "."
  sleep 5
  ssh -o StrictHostKeyChecking=no -q root@$SERVER_IP ls /cloud-init-done &> /dev/null
  STATUS=$?
done

echo ""

echo "Executing remote commands..."

ssh -o StrictHostKeyChecking=no -q root@$SERVER_IP << EOF
  DEBIAN_FRONTEND=noninteractive
  
  echo ""
  echo "Update package sources"
  apt-get update -q

  echo ""
  echo "Install dependencies"
  apt-get install -y curl apt-transport-https gnupg2 software-properties-common

  echo ""
  echo "Add docker repo key"
  curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -

  echo ""
  echo "Add repo"
  add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian stretch stable"

  echo ""
  echo "Update package sources again"
  apt-get update -q

  echo ""
  echo "Install docker"
  apt-get install -y docker-ce

  mkdir /root/secrets
EOF

echo "Done with remote setup."

# Copy service account secret to server
echo "Copying secret to /root/secrets/datastore-writer.json"
scp -o StrictHostKeyChecking=no -q secrets/datastore-writer.json root@$SERVER_IP:/root/secrets/datastore-writer.json

# Run docker job
echo "Starting Docker Job"
ssh -o StrictHostKeyChecking=no -q root@$SERVER_IP docker run -t \
	-v /root/secrets:/secrets \
	quay.io/netzbegruenung/green-spider \
  spider spider.py \
	--credentials-path /secrets/datastore-writer.json \
	jobs
ssh -o StrictHostKeyChecking=no -q root@$SERVER_IP docker run -t \
	-v /root/secrets:/secrets \
	quay.io/netzbegruenung/green-spider \
  spider spider.py \
	--credentials-path /secrets/datastore-writer.json \
	spider

# Delete the box
echo "Deleting server $SERVER_ID"
curl -s -X DELETE -H "Content-Type: application/json" \
  -H "Authorization: Bearer $API_TOKEN" \
  https://api.hetzner.cloud/v1/servers/$SERVER_ID
