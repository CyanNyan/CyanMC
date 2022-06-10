#!/bin/bash

# Minecraft Server Launcher v1.1
# For Minecraft 1.17.1+ Paper/Fabric, Velocity 3.1.0+, GeyserMC

# set -xe

if [ -f "config.env" ]; then
  echo "** Load config from config.env"
  cat config.env
  source "config.env"
fi

# > Example configs for different server types

# SERVER=velocity
# VERSION=3.1.0

# SERVER=paper
# VERSION=1.17.1
# AUTHLIB_INJECTOR=ely.by

# SERVER=geyser
# JVM_MEM="-Xms128M -Xmx128M"

# SERVER=fabric
# VERSION=1.18-rc4

JAVA="${JAVA:-java}"
JVM_MEM="${JVM_MEM:--Xms3G -Xmx3G}"
SERVER_JVM_PARAMS="-XX:+UseG1GC -XX:G1HeapRegionSize=4M -XX:+UnlockExperimentalVMOptions -XX:+ParallelRefProcEnabled -XX:+AlwaysPreTouch -XX:MaxInlineLevel=15"
AIKARS_JVM_PARAMS="-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 -Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true"

CACHE_DIR="cache"
MCRCON_ROOT="mcrcon"
FABRIC_DIR="fabric-$VERSION"
RCON_CONFIG="server.properties"

AUTHLIB_INJECTOR_VERSION=1.1.45  # https://github.com/yushijinhun/authlib-injector/releases
FABRIC_INSTALLER_VERSION=0.11.0  # https://maven.fabricmc.net/net/fabricmc/fabric-installer/
HMCL_VERSION=3.5.3.221  # https://github.com/huanghongxun/HMCL/releases

AUTHLIB_INJECTOR_JAR="authlib-injector-$AUTHLIB_INJECTOR_VERSION.jar"
FABRIC_INSTALLER_JAR="fabric-installer-$FABRIC_INSTALLER_VERSION.jar"

MCRCON_REPOSITORY="https://github.com/Tiiffi/mcrcon.git"

if [ -n "$AUTHLIB_INJECTOR" ]; then
  JVM_PARAMS="$JVM_PARAMS -javaagent:$AUTHLIB_INJECTOR_JAR=$AUTHLIB_INJECTOR"
fi

if [ -z "$HOME" ]; then
  JVM_PARAMS="$JVM_PARAMS -Duser.home=."
fi

case "$SERVER" in
    "paper")
        SERVER_JAR="$SERVER-$VERSION.jar"
        JVM_PARAMS=${JVM_PARAMS:-$AIKARS_JVM_PARAMS}
        JAR_PARAMS="$JAR_PARAMS --nogui"
        ;;
    "fabric")
        SERVER_JAR="$FABRIC_DIR/fabric-server-launch.jar"
        JVM_PARAMS=${JVM_PARAMS:-$AIKARS_JVM_PARAMS}
        JVM_PARAMS="$JVM_PARAMS -Dfabric.gameJarPath=$FABRIC_DIR/server.jar"
        JAR_PARAMS="$JAR_PARAMS --nogui"
        ;;
    "velocity")
        SERVER_JAR="velocity.jar"
        JVM_PARAMS=${JVM_PARAMS:-$SERVER_JVM_PARAMS}
        RCON_CONFIG="plugins/velocityrcon/rcon.toml"
        ;;
    "geyser")
        JVM_PARAMS=${JVM_PARAMS:-$SERVER_JVM_PARAMS}
        SERVER_JAR="geyser.jar"
        JAR_PARAMS="$JAR_PARAMS --nogui"
        ;;
    "server")
        SERVER_JAR="server.jar"
        JVM_PARAMS=${JVM_PARAMS:-$SERVER_JVM_PARAMS}
        ;;
    "hmcl")
        VERSION="${VERSION:-$HMCL_VERSION}"
        SERVER_JAR="HMCL-$VERSION.jar"
        ;;
    *)
        echo "Unrecognized server type: $SERVER"
        exit 127
esac

_curl() {
    if [ -n "$2" ]; then
        mkdir -p "$CACHE_DIR"
        curl -fsSLo "$CACHE_DIR/$2.tmp" "${API_PATH}$1"
        mv "$CACHE_DIR/$2.tmp" "$2"
    else
        curl -fsS "${API_PATH}$1"
    fi
}

_paper_check_update() {
    echo "Checking for paper/velocity updates..."

    API_PATH="https://papermc.io/api/v2/projects/$SERVER"

    # Check version group
    if [ -n "$VERSION_GROUP" ]; then
        echo "Check for version group $VERSION_GROUP..."
        VERSION="$(_curl "/version_group/$VERSION_GROUP/builds" | jq -r '.builds[-1].version')"
        SERVER_JAR="$SERVER-$VERSION.jar"
        echo "Latest version number: $VERSION"
    fi

    # Check paper version
    BUILD="$(_curl "/versions/$VERSION" | jq -r '.builds[-1]')"
    if [ -z "$BUILD" ]; then
        echo "!! Paper version check failed."
        return
    fi

    DOWNLOAD="$(_curl "/versions/$VERSION/builds/$BUILD" | jq -r '.downloads.application.name')"

    echo "Latest version: $BUILD"

    if [ ! -f "$DOWNLOAD" ]; then
        echo "Downloading $DOWNLOAD..."
        _curl "/versions/$VERSION/builds/$BUILD/downloads/$DOWNLOAD" "$DOWNLOAD" || return
    fi

    ln -sf "$DOWNLOAD" "$SERVER_JAR"
}

_jenkins_check_update() {
    echo "Checking for Geyser updates..."

    # Check geyser version
    BUILD="$(_curl "/api/json" | jq -r '.builds[0].number')"
    if [ -z "$BUILD" ]; then
        echo "!! Geyser version check failed."
        return
    fi

    if [ -n "$1" ]; then
      RELATIVE_PATH="$(_curl "/$BUILD/api/json" | jq -r ".artifacts[] | select( .fileName == \"$1\" ).relativePath")"
    else
      RELATIVE_PATH="$(_curl "/$BUILD/api/json" | jq -r '.artifacts[0].relativePath')"
    fi

    DOWNLOAD="geyser-$BUILD.jar"
    echo "Latest version: $BUILD"
    echo "Jenkins artifact path: $RELATIVE_PATH"

    if [ ! -f "$DOWNLOAD" ]; then
        echo "Downloading $DOWNLOAD"
        _curl "/$BUILD/artifact/$RELATIVE_PATH" "$DOWNLOAD"
    fi

    ln -sf "$DOWNLOAD" "$SERVER_JAR"
}

_fabric_check_update() {
    echo "Checking for fabric installer $FABRIC_INSTALLER_VERSION..."

    API_PATH="https://maven.fabricmc.net/net/fabricmc/fabric-installer"

    if [ ! -f "$FABRIC_INSTALLER_JAR" ]; then
        echo "Downloading $FABRIC_INSTALLER_JAR"
        _curl "/$FABRIC_INSTALLER_VERSION/$FABRIC_INSTALLER_JAR" "$FABRIC_INSTALLER_JAR"
    fi

    mkdir -p "$FABRIC_DIR"

    if [ ! -f "$SERVER_JAR" ]; then
        echo "Install fabric server..."
        "$JAVA" -jar "$FABRIC_INSTALLER_JAR" server -dir "$FABRIC_DIR" -mcversion "$VERSION" -downloadMinecraft
    fi
}

_authlib_injector_check_update() {
    if [ ! -f "$AUTHLIB_INJECTOR_JAR" ]; then
        echo "Downloading $AUTHLIB_INJECTOR_JAR..."
        curl -fsSLo "$AUTHLIB_INJECTOR_JAR" "https://github.com/yushijinhun/authlib-injector/releases/download/v$AUTHLIB_INJECTOR_VERSION/$AUTHLIB_INJECTOR_JAR"
    fi
}

_hmcl_check_update() {
    if [ ! -f "$SERVER_JAR" ]; then
        echo "Downloading $SERVER_JAR..."
        curl -fsSLo "$SERVER_JAR" "https://github.com/huanghongxun/HMCL/releases/download/v$VERSION/HMCL-$VERSION.jar"
    fi
}

_check_update() {
    case "$SERVER" in
    "velocity" | "paper")
        _paper_check_update
        ;;
    "geyser")
        API_PATH="https://ci.opencollab.dev/job/GeyserMC/job/Geyser/job/master"
        _jenkins_check_update "Geyser.jar"
        ;;
    "fabric")
        _fabric_check_update
        ;;
    "hmcl")
        _hmcl_check_update
        ;;
    esac

    if [ -n "$AUTHLIB_INJECTOR" ]; then
        _authlib_injector_check_update
    fi
}

_check_mcrcon() {
    # Check and install mcrcon command
    if command -v mcrcon &> /dev/null; then
        MCRCON_CMD="mcrcon"
        return
    fi

    MCRCON_CMD="$MCRCON_ROOT/mcrcon"
    if [ ! -x "$MCRCON_CMD" ]; then
        echo "mcrcon is not installed, trying to install ..."

        git clone "$MCRCON_REPOSITORY" "$MCRCON_ROOT"
        make -C "$MCRCON_ROOT"
    fi
}

_console() {
    if [ ! -f "$RCON_CONFIG" ]; then
        echo "rcon is not configured in $RCON_CONFIG!"
        return 1
    elif [[ "$RCON_CONFIG" == *.properties ]]; then
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
        return 1
    fi

    _check_mcrcon
    echo "mcrcon: $MCRCON_CMD"

    "$MCRCON_CMD" -H "127.0.0.1" -P "$RCON_PORT" -p "$RCON_PASS" "$@"
}

_systemd_stop() {
    SERVER_PID="$1"
    if [ -n "$SERVER_PID" ]; then
        echo "Terminating server, PID=$SERVER_PID..."

        # Try to use rcon first, otherwise send SIGINT
        _console stop || kill -SIGTERM "$SERVER_PID"

        # Wait for process to exit
        tail --pid="$SERVER_PID" -f /dev/null
    else
        echo '$MAINPID is empty, skipping.'
    fi
}

_scheduled_restart() {
    RESTART_SEC="$1"

    echo "Minecraft is scheduled to restart in $RESTART_SEC seconds!"

    _console "broadcast Server restarting in $RESTART_SEC seconds!!"
    _console "broadcast Server restarting in $RESTART_SEC seconds!!"
    sleep "$(( RESTART_SEC - 30 ))"

    echo "Minecraft is scheduled to restart in 30 seconds!"
    _console "broadcast Server restarting in 30 seconds!!!"
    sleep 25

    for i in {5..1}; do
        _console "broadcast Server restarting in $i..."
        sleep 1
    done

    _console stop
}

_run_server() {
    if ! _check_update; then
        echo "Failed to check update for $SERVER"
    fi

    # Start server
    echo "Starting server $SERVER_JAR..."
    echo "JVM memory option: $JVM_MEM"
    echo "JVM params: $JVM_PARAMS"
    echo "JAR params: $JAR_PARAMS" "$@"

    # If script is called by systemd, let it fork
    if [ -n "$INVOCATION_ID" ]; then
      "$JAVA" $JVM_MEM $JVM_PARAMS -jar "$SERVER_JAR" $JAR_PARAMS "$@" &
    else
      exec "$JAVA" $JVM_MEM $JVM_PARAMS -jar "$SERVER_JAR" $JAR_PARAMS "$@"
    fi
}

main() {
    case "$1" in
        "console" | "con")
            shift
            _console "$@"
            ;;
        "eula" | "eula.txt")
            echo "eula=true" > "eula.txt"
            ;;
        "systemd_stop")
            shift
            _systemd_stop "$@"
            ;;
        "scheduled_restart")
            shift
            _scheduled_restart "$@"
            ;;
        *)
            _run_server
            ;;
    esac
}

main "$@"
