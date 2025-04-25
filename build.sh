#!/usr/bin/env bash
set -e

OWNER="netbirdio"
REPO="netbird"
REPO_URL="https://github.com/${OWNER}/${REPO}.git"

# Check if the first argument ($1) contains a valid tag
if echo "$1" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  TAG="$1"
else
  # If no argument (or empty string) was provided, exit
  echo "Expected a valid NetBird repo tag as argument. E.g. v0.41.3"
  exit 1
fi

# Strip the letter v from the tagname
VERSION=${TAG/v/}

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
echo $VERSION > dist/version.txt
echo "Done"
