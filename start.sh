#!/bin/bash

# Minecraft Server Launcher v1.1
# For Minecraft 1.17

# set -xe

if [ -f "config.env" ]; then
  echo "** Load config from config.env"
  cat config.env
  source "config.env"
fi

# SERVER=velocity
# VERSION=1.1.8

# SERVER=server

# SERVER=geyser
# VERSION=741

# === Change Options ===
SERVER="${SERVER:-paper}"
VERSION="${VERSION:-1.17}"
JVM_MEM="${JVM_MEM:--Xms3G -Xmx3G}"
JVM_PARAMS="${JVM_PARAMS:--XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true}"
# AUTHLIB_INJECTOR=ely.by
AUTHLIB_INJECTOR_VERSION=1.1.38
# ===   End Options   ===

CACHE_DIR="cache"
SERVER_JAR="$SERVER-$VERSION.jar"
AUTHLIB_INJECTOR_JAR="authlib-injector-$AUTHLIB_INJECTOR_VERSION.jar"
RCON_CONFIG="server.properties"
MCRCON_ROOT="mcrcon"

if [ -n "$AUTHLIB_INJECTOR" ]; then
  JVM_PARAMS="$JVM_PARAMS -javaagent:$AUTHLIB_INJECTOR_JAR=$AUTHLIB_INJECTOR"
fi

case "$SERVER" in
    "velocity")
        API_PATH="https://versions.velocitypowered.com/download"
        RCON_CONFIG="plugins/velocityrcon/rcon.toml"
        ;;
    "paper")
        API_PATH="https://papermc.io/api/v2/projects/paper"
        JAR_PARAMS="$JAR_PARAMS --nogui"
        ;;
    "geyser")
        API_PATH="https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master/$VERSION/artifact/bootstrap/standalone/target"
        ;;
    "server")
        SERVER_JAR="server.jar"
        ;;
    *)
        echo "Unrecognized server type: $SERVER"
        exit 1
esac

_curl() {
    if [ -n "$2" ]; then
        mkdir -p "$CACHE_DIR"
        curl -fsSLo "$CACHE_DIR/$2.tmp" "${API_PATH}/$1"
        mv "$CACHE_DIR/$2.tmp" "$2"
    else
        curl -fsS "${API_PATH}/$1"
    fi
}

_paper_check_update() {
    echo "Checking for paper updates..."

    # Check paper version
    BUILD="$(_curl "/versions/$VERSION" | jq -r '.builds[-1]')"
    DOWNLOAD="$(_curl "/versions/$VERSION/builds/$BUILD" | jq -r '.downloads.application.name')"

    echo "Latest version: $DOWNLOAD"

    if [ ! -f "$DOWNLOAD" ]; then
        echo "Downloading $DOWNLOAD..."
        _curl "/versions/$VERSION/builds/$BUILD/downloads/$DOWNLOAD" "$DOWNLOAD" || return
    fi

    ln -sf "$DOWNLOAD" "$SERVER_JAR"
}

_velocity_check_update() {
    echo "Checking for velocity jar..."

    if [ ! -f "$SERVER_JAR" ]; then
        echo "Downloading $SERVER_JAR"
        _curl "/$VERSION.jar" "$SERVER_JAR"
    fi
}

_geyser_check_update() {
    echo "Checking for Geyser jar..."
    if [ ! -f "$SERVER_JAR" ]; then
        echo "Downloading $SERVER_JAR"
        _curl "/Geyser.jar" "$SERVER_JAR"
    fi
}

_check_update() {
    case "$SERVER" in
    "velocity")
        _velocity_check_update
        ;;
    "paper")
        _paper_check_update
        ;;
    "geyser")
        _geyser_check_update
        ;;
    esac
    
    if [ -n "$AUTHLIB_INJECTOR" ]; then
      if [ ! -f "$AUTHLIB_INJECTOR_JAR" ]; then
        echo "Downloading $AUTHLIB_INJECTOR_JAR..."
        curl -fsSLO "https://github.com/yushijinhun/authlib-injector/releases/download/v$AUTHLIB_INJECTOR_VERSION/$AUTHLIB_INJECTOR_JAR"
      fi
    fi
}

_check_mcrcon() {
    # Check and install mcrcon command
    if command -v mcrcon &> /dev/null; then
        return
    fi

    if [ -x "$MCRCON_ROOT/mcrcon" ]; then
        return
    fi

    echo "mcrcon is not installed, trying to install ..."

    git clone https://github.com/Tiiffi/mcrcon.git "$MCRCON_ROOT"
    make -C "$MCRCON_ROOT"
}

_console() {
    if [[ "$RCON_CONFIG" == *.properties ]]; then
        # server.properties config
        RCON_ENABLED="$(sed -nE 's/enable-rcon=(.+)/\1/gp' $RCON_CONFIG)"
        RCON_PORT="$(sed -nE 's/rcon.port=(.+)/\1/gp' $RCON_CONFIG)"
        RCON_PASS="$(sed -nE 's/rcon.password=(.+)/\1/gp' $RCON_CONFIG)"
    elif [[ "$RCON_CONFIG" == *.toml ]]; then
        # VelocityRcon config
        RCON_ENABLED="true"
        RCON_PORT="$(sed -nE 's/rcon-port = "(.+?)"/\1/gp' $RCON_CONFIG)"
        RCON_PASS="$(sed -nE 's/rcon-password = "(.+?)"/\1/gp' $RCON_CONFIG)"
    fi

    if [ "$RCON_ENABLED" != "true" ]; then
        echo "rcon is not enabled in $RCON_CONFIG!"
        exit 1
    fi

    _check_mcrcon

    MCRCON="mcrcon"
    if [ -x "$MCRCON_ROOT/mcrcon" ]; then
        MCRCON="$MCRCON_ROOT/mcrcon"
    fi

    echo "mcrcon: $MCRCON"

    "$MCRCON" -H "127.0.0.1" -P "$RCON_PORT" -p "$RCON_PASS" "$@"
}

main() {
    case "$1" in
        "console" | "con")
            shift
            _console "$@"
            exit
            ;;
        "eula")
            echo "eula=true" > "eula.txt"
            exit
            ;;
    esac

    if ! _check_update; then
        echo "Failed to check update for $SERVER"
    fi

    # Start server
    echo "Starting server $SERVER_JAR..."
    echo "JVM memory option: $JVM_MEM"
    echo "JVM params: $JVM_PARAMS"
    echo "JAR params: $JAR_PARAMS" "$@"

    java $JVM_MEM $JVM_PARAMS -jar "$SERVER_JAR" $JAR_PARAMS "$@"
}

main "$@"
