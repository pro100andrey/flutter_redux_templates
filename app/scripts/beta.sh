#!/bin/bash

# how to use: ./scripts/beta.sh prod "qa, customers"

# dev, prod, stage
build_env=$1
firebase_groups=$2

echo "Building env: $build_env groups: $firebase_groups"

pushd ios
bundle install
pod repo update
bundle exec fastlane beta env:$build_env groups:"$firebase_groups"
popd

pushd android
bundle install
bundle exec fastlane beta env:$build_env groups:"$firebase_groups"
popd
