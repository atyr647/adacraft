#!/bin/sh
# The oracle lab (docs/ORACLE.md): the official 26.3 server, run beside
# AdaCraft so its bytes can be recorded. Lab only: nothing in src/ runs it.
#
#   tools/oracle-lab.sh start    fetch (once, hashes checked against pin/26.3.toml),
#                                set up a fresh world, start it on 127.0.0.1:25599
#   tools/oracle-lab.sh fresh    stop, wipe the world (new players), start again
#   tools/oracle-lab.sh stop
#   tools/oracle-lab.sh status
#
# Everything lives in lab/oracle/ (not committed). Needs curl and python3;
# Java 25 is fetched into the lab when the machine has none.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAB="$ROOT/lab/oracle"
PORT="${ORACLE_PORT:-25599}"
PIN="$ROOT/pin/26.3.toml"
pin() { sed -n "s/^$1 = \"\(.*\)\"/\1/p" "$PIN"; }

java_bin() {
  for j in "$LAB"/jdk/*/bin/java "$(command -v java 2>/dev/null || true)"; do
    [ -x "$j" ] || continue
    v=$("$j" -version 2>&1 | sed -n 's/.*version "\([0-9]*\).*/\1/p' | head -1)
    [ "${v:-0}" -ge 25 ] && { echo "$j"; return; }
  done
  echo "fetching Java 25 into the lab" >&2
  mkdir -p "$LAB/jdk"
  curl -fsSL -o "$LAB/jdk.tgz" \
    "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse"
  tar -xzf "$LAB/jdk.tgz" -C "$LAB/jdk" && rm -f "$LAB/jdk.tgz"
  ls "$LAB"/jdk/*/bin/java | head -1
}

fetch_jar() {
  [ -f "$LAB/server.jar" ] && return
  mkdir -p "$LAB"
  url=$(curl -fsSL https://piston-meta.mojang.com/mc/game/version_manifest_v2.json \
    | python3 -c 'import json,sys; v=[x for x in json.load(sys.stdin)["versions"] if x["id"]=="26.3"][0]; print(v["url"])' \
    | xargs curl -fsSL \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["downloads"]["server"]["url"])')
  curl -fsSL -o "$LAB/server.jar.part" "$url"
  got=$(sha256sum "$LAB/server.jar.part" | cut -d' ' -f1)
  if [ "$got" != "$(pin server_jar_sha256)" ]; then
    rm -f "$LAB/server.jar.part"
    echo "server jar hash $got is not the pinned one: refusing it" >&2; exit 1
  fi
  mv "$LAB/server.jar.part" "$LAB/server.jar"
}

# The settings every capture assumes (docs/ORACLE.md): offline, no
# white-list (26.3 turns it on by default), no compression, a flat world,
# seed 777, the same motd as AdaCraft's status.
configure() {
  mkdir -p "$LAB/srv"
  echo "eula=true" > "$LAB/srv/eula.txt"
  cat > "$LAB/srv/server.properties" <<EOF
online-mode=false
white-list=false
enforce-whitelist=false
network-compression-threshold=-1
server-ip=127.0.0.1
server-port=$PORT
level-seed=777
level-type=minecraft\:flat
generate-structures=false
spawn-monsters=false
spawn-animals=false
view-distance=2
simulation-distance=2
motd=AdaCraft
EOF
}

pid_of() {
  # By the java process's own command line: never a pattern that could
  # match the shell running this script.
  for p in $(pgrep -x java 2>/dev/null || true); do
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "$LAB/server.jar" && echo "$p"
  done
}

stop() {
  for p in $(pid_of); do kill "$p"; done
  i=0; while [ -n "$(pid_of)" ] && [ $i -lt 60 ]; do sleep 0.5; i=$((i + 1)); done
}

start() {
  [ -n "$(pid_of)" ] && { echo "already running on 127.0.0.1:$PORT"; return; }
  fetch_jar
  J=$(java_bin)
  configure
  : > "$LAB/server.log"
  (cd "$LAB/srv" && nohup "$J" -Xmx2G -jar "$LAB/server.jar" nogui > "$LAB/server.log" 2>&1 &)
  i=0
  until grep -q "Done (" "$LAB/server.log" 2>/dev/null; do
    i=$((i + 1))
    if [ $i -gt 600 ] || grep -q "Exception" "$LAB/server.log"; then
      echo "the oracle didn't start:" >&2; tail -20 "$LAB/server.log" >&2; exit 1
    fi
    sleep 0.5
  done
  echo "oracle up on 127.0.0.1:$PORT (log: lab/oracle/server.log)"
}

case "${1:-status}" in
  start) start ;;
  fresh) stop; rm -rf "$LAB/srv/world"; start ;;
  stop) stop; echo "stopped" ;;
  status) [ -n "$(pid_of)" ] && echo "running on 127.0.0.1:$PORT" || echo "not running" ;;
  *) echo "usage: $0 start|fresh|stop|status" >&2; exit 2 ;;
esac
