#!/usr/bin/env bash
set -e

OWNER="netbirdio"
REPO="netbird"
REPO_URL="https://github.com/${OWNER}/${REPO}.git"

# Check if the first argument ($1) contains a valid tag
# (optionally with an -nnbN suffix used to re-release install.sh changes)
if echo "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+(-nnb[0-9]+)?$'; then
  TAG="$1"
else
  # If no argument (or empty string) was provided, exit
  echo "Expected a valid NetBird repo tag as argument. E.g. v0.41.3 or v0.41.3-nnb2"
  exit 1
fi

# Strip the letter v (and any install-script suffix) from the tag name
VERSION=${TAG%%-*}
VERSION=${VERSION#v}

# Install-script revision: bumps automatically whenever install.sh
# changes, so devices pick up installer fixes even without a new
# NetBird release (see the version check in install.sh)
INSTALL_REV="$(git rev-list --count HEAD -- install.sh)"

echo "Fetching NetBird sources for version $VERSION"
git clone -c advice.detachedHead=false --depth 1 --branch "$TAG" "$REPO_URL" src-$VERSION
echo "Compiling..."
mkdir dist
CURRENT_WD=$PWD
cd src-$VERSION/client
CGO_ENABLED=0 GOOS=linux GOARCH=riscv64 go build -ldflags "-s -w -X github.com/netbirdio/netbird/version.version=$VERSION" -o ../../dist/netbird .
cd $CURRENT_WD
file dist/netbird

cp install.sh dist/install.sh
echo "${VERSION}+nnb${INSTALL_REV}" > dist/version.txt
echo "Done"
