#!/usr/bin/env bash

# Script to upload the release package and the installer to gitub
#
# Expectations:
# - ~/.credentials/github_api_token is a file with the github OAuth token
# - $public_mies_repo exists and its origin remote is the github repository
# - The deployment key is setup correctly for that repository in Github. See also $public_mies_repo/.git/config and ~/.ssh/config
# - The release and installer packages are in the working tree root
# - Either the main or a release branch are checked out

set -e

git --version > /dev/null
if [ $? -ne 0 ]
then
  echo "Could not find git executable"
  exit 1
fi

top_level=$(git rev-parse --show-toplevel)

if [ -z "$top_level" ]
then
  echo "This is not a git repository"
  exit 1
fi

if [ -z "$(git tag)" ]
then
  echo "Could not find any tags!"
  echo "This looks like a shallow clone."
  exit 1
fi

cd $top_level

zipfile=$(ls Release_*.zip)
installerfile=$(ls MIES-Release*.exe)

if [ ! -f $zipfile ]
then
  echo "File $zipfile does not exist"
  exit 1
elif [ ! -f $installerfile ]
then
  echo "File $installerfile does not exist"
  exit 1
fi

public_mies_repo=~/devel/public-mies-igor

if [ ! -d $public_mies_repo ]
then
  echo "The folder $public_mies_repo does not exist"
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)

case "$branch" in
  main)
    tag=latest

    cd $public_mies_repo

    git stash || true
    git fetch --all
    git tag --force ${tag} origin/main
    git push --force origin ${tag}

    cd $top_level
    ;;
  release/*)
    tag=$(git tag --list "Release_*" | tail -1)
    ;;
  *)
    echo "Unexpected branch $branch"
    exit 1
    ;;
esac

credentials=~/.credentials/github_api_token

if [ ! -f $credentials ]
then
  echo "Could not find the file $credentials with the Github OAuth token"
  exit 1
fi

./tools/upload-github-release-asset-helper.sh github_api_token=$(cat $credentials) owner=AllenInstitute repo=MIES tag=$tag filename=$zipfile filename=$installerfile
