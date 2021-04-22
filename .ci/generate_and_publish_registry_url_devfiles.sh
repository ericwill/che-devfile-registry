#!/bin/bash
#
# Copyright (c) 2021 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0


set -e

: "${VERSION:?Variable not set or empty}"
: "${GITHUB_ACTOR:?Variable not set or empty}"
: "${GITHUB_TOKEN:?Variable not set or empty}"

# Get up to date source code using release tag
mkdir /tmp/devfile-registry-gh-pages-publish/
cd /tmp/devfile-registry-gh-pages-publish/
git clone "https://github.com/eclipse-che/che-devfile-registry.git" che-devfile-registry
cd ./che-devfile-registry && git checkout "${VERSION}"

PLUGIN_REGISTRY_URL="https://eclipse-che.github.io/che-plugin-registry/${VERSION}/v3/"

# shellcheck disable=SC2207
DEVFILES=($(find ./devfiles -type f -name "devfile.yaml"))
for devfile in "${DEVFILES[@]}"
do
    LENGTH=$(yq eval '.components | length' "${devfile}")
    LAST_INDEX=$((LENGTH-1))
    for i in $(seq 0 ${LAST_INDEX})
    do
        chePlugin=$(yq eval '.components['"${i}"'].type' "${devfile}")
        hasRegistryUrl=$(yq eval '.components['"${i}"'].registryUrl' "${devfile}")
        if [ "${chePlugin}" == "chePlugin" ] && [ "${hasRegistryUrl}" == "null" ]; then
            yq eval -P '.components['"${i}"'] = .components['"${i}"'] * {"registryUrl":"'"${PLUGIN_REGISTRY_URL}"'"}' -i "${devfile}"
        fi
    done
done

git config --global user.email "che-bot@eclipse.org"
git config --global user.name "CHE Bot"

# Make temporary directory and copy out devfiles and images
mkdir -p /tmp/content/"${VERSION}"
./build.sh --tag gh-pages-generated
podman rm -f devfileRegistry
podman create --name devfileRegistry quay.io/eclipse/che-devfile-registry:gh-pages-generated
podman cp devfileRegistry:/var/www/html/devfiles/ /tmp/content/"${VERSION}"
podman cp devfileRegistry:/var/www/html/images/ /tmp/content/"${VERSION}"
podman cp devfileRegistry:/var/www/html/README.md /tmp/content/"${VERSION}"

# Clone GitHub pages
rm -rf ./gh-pages && mkdir gh-pages
cd ./gh-pages
rm -rf ./che-devfile-registry
git clone -b gh-pages "https://github.com/eclipse-che/che-devfile-registry.git" che-devfile-registry
cd ./che-devfile-registry
[ -d "${VERSION}" ] && git rm -r "${VERSION}"

# Copy generated devfiles and commit + push
cp -rf /tmp/content/"${VERSION}" ./
git add ./"${VERSION}"
git commit -m "Publish devfile registry $VERSION - $(date)" -s
git push "https://${GITHUB_ACTOR}:${GITHUB_TOKEN}@github.com/eclipse-che/che-devfile-registry.git" gh-pages
