#!/bin/bash

function cleanup() {
    local work_dir=$1
    local rebuild=$2
    local format=$3

    echo "work dir: $work_dir, rebuild: $rebuild, format: $format"
    pushd $work_dir

    echo "-> flutter clean"
    flutter clean

    echo "-> flutter pub upgrade"
    flutter pub upgrade

    if [  "$format" = true ]; then
        echo "-> dart format ."
        dart format --fix .    
    fi

    cleanup_podfile "$(pwd)/ios"
    cleanup_podfile "$(pwd)/macos"

    if [  "$rebuild" = true ]; then
        echo "-> flutter pub run build_runner build --delete-conflicting-outputs"
        flutter pub run build_runner build --delete-conflicting-outputs
    fi

    popd
}

function cleanup_podfile() {
    local dir=$1
    local file="$dir/Podfile.lock"
    
    if [ -f "$file" ]; then
        echo "cleaup pods:"
        pushd $dir
        
        echo "-> rm $file"
        rm $file
        echo "-> pod install --repo-update"
        pod install --repo-update 
        
        popd
    fi
}

# clenup ags: 1 dir, 2 rebuild, 3 format
cleanup "../localization" false false
cleanup "../models" true true
cleanup "../utils" false true
cleanup "../http_client" true true
cleanup "../storage" false true
cleanup "../business" true true
cleanup "../ui" true true
cleanup "../storybook" false true
cleanup "../app" false true
