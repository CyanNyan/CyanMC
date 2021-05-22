#!/bin/bash
# Minecraft Server Launcher v1.0

# set -xe


# SERVER=velocity
# VERSION=1.1.5

# === Change Options ===
SERVER="${SERVER:-paper}"
VERSION="${VERSION:-1.16.5}"
JVM_MEM="${JVM_MEM:--Xms3G -Xmx6G}"
JVM_PARAMS="${JVM_PARAMS:--XX:+UseG1GC -XX:G1HeapRegionSize=4M -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled -XX:+AlwaysPreTouch -XX:MaxInlineLevel=15}"
# ===  End Options   ===


CACHE_DIR="cache"
SERVER_JAR="$SERVER-$VERSION.jar"
RCON_CONFIG="server.properties"
MCRCON_ROOT="mcrcon"


case "$SERVER" in
    "velocity")
        API_PATH="https://versions.velocitypowered.com/download"
        RCON_CONFIG="plugins/velocityrcon/rcon.toml"
        ;;
    "paper")
        API_PATH="https://papermc.io/api/v2/projects/paper"
        JAR_PARAMS="$JAR_PARAMS --nogui"
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
    BUILD="$(_curl /versions/$VERSION | jq -r '.builds[-1]')"
    DOWNLOAD="$(_curl /versions/$VERSION/builds/$BUILD | jq -r '.downloads.application.name')"

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

_check_update() {
    case "$SERVER" in
    "velocity")
        _velocity_check_update
        ;;
    "paper")
        _paper_check_update
        ;;
    esac
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

    "$MCRCON" -H "127.0.0.1" -P "$RCON_PORT" -p "$RCON_PASS" $@
}

main() {
    case "$1" in
        "console" | "con")
            shift
            _console $@
            exit
            ;;
        "eula")
            if [ ! -f "eula.txt" ]; then
                echo "eula=true" > "eula.txt"
            fi
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
    echo "JAR params: $JAR_PARAMS $@"

    java $JVM_MEM $JVM_PARAMS -jar "$SERVER_JAR" $JAR_PARAMS $@
}

main $@
