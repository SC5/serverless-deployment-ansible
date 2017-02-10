#!/usr/bin/env bash

docker run -v $(pwd):/src -w /src serverless-deployment /bin/bash -c "\
export SERVICE_VERSION=$SERVICE_VERSION && \
ansible-playbook -vvvv --inventory-file inventories/development/inventory site.yml"

[[ $? -eq 0 ]] || { echo "Build failed!" ; exit 1; }