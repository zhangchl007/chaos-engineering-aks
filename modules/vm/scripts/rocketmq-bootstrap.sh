#!/usr/bin/env bash
# Ubuntu 22.04 amd64 private workshop runtime only; never runs Chaos actions.
# Requires outbound HTTPS to Apache and signed Ubuntu apt repositories.
# Usage: sudo bash rocketmq-bootstrap.sh [IMDS-assigned-NIC-IPv4]
set -Eeuo pipefail
umask 027

readonly ROCKETMQ_VERSION=5.5.1
# Verified 2026-11-22 against the official release and binary SHA512:
# https://rocketmq.apache.org/release-notes/2026/08/20/5.5.1/
# https://downloads.apache.org/rocketmq/5.5.1/rocketmq-all-5.5.1-bin-release.zip.sha512
readonly ROCKETMQ_SHA512=21555d9bd79792ac89f246566f19f58e300784c59b96289fd0c74db14787861081fb60ebb95cf541bf20a3e508bf3b70feb9596ea3ba6dc5dc88fa6081f00577
readonly ROCKETMQ_URL="https://downloads.apache.org/rocketmq/${ROCKETMQ_VERSION}/rocketmq-all-${ROCKETMQ_VERSION}-bin-release.zip"
# A filesystem prefix permits isolated command-mocked tests; unset in deployment.
readonly ROOT="${ROCKETMQ_ROOT:-}"
readonly INSTALL="${ROOT}/opt/rocketmq-${ROCKETMQ_VERSION}"
readonly CACHE="${ROOT}/var/cache/rocketmq"
readonly ARCHIVE="${CACHE}/rocketmq-${ROCKETMQ_VERSION}.zip"
readonly CONFIG="${ROOT}/etc/rocketmq"
readonly STATE="${ROOT}/var/lib/rocketmq"
readonly UNITS="${ROOT}/etc/systemd/system"
readonly JAVA="${ROOT}/usr/lib/jvm/java-17-openjdk-amd64/bin/java"
STAGING=""
PRIVATE_IP=""

fail() { printf 'RocketMQ bootstrap ERROR: %s\n' "$*" >&2; exit 1; }

cleanup() {
  if [[ -n "$STAGING" ]]; then rm -rf -- "$STAGING"; fi
}

verify_archive() {
  printf '%s  %s\n' "$ROCKETMQ_SHA512" "$1" | sha512sum --check --status
}

check_host() {
  [[ $# -le 1 ]] || fail "Expected at most one private IPv4 argument."
  [[ $(id -u) == 0 ]] || fail "Run as root on the target VM."
  [[ "$ROOT" != *[[:space:]]* && "$ROOT" != *..* ]] || fail "Unsafe filesystem prefix."
  # shellcheck disable=SC1091
  source "${ROOT}/etc/os-release"
  [[ "$ID" == ubuntu && "$VERSION_ID" == 22.04 && $(uname -m) == x86_64 ]] ||
    fail "Only Ubuntu 22.04 amd64 is supported."
  local memory
  memory=$(awk '/^MemTotal:/ {print $2}' "${ROOT}/proc/meminfo")
  [[ "$memory" =~ ^[0-9]+$ && "$memory" -ge 7000000 ]] ||
    fail "At least 7 GB RAM is required (use Standard_D2s_v3 or larger)."
}

install_packages() {
  local package missing=false
  for package in openjdk-17-jre-headless ca-certificates curl unzip util-linux iproute2; do
    if [[ $(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true) != "install ok installed" ]]; then
      missing=true
    fi
  done
  if "$missing"; then
    # Never add third-party apt sources or disable signature verification.
    timeout --kill-after=15s 600s env DEBIAN_FRONTEND=noninteractive apt-get \
      -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
      -o APT::Get::AllowUnauthenticated=false update
    timeout --kill-after=15s 600s env DEBIAN_FRONTEND=noninteractive apt-get \
      -o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 \
      -o APT::Get::AllowUnauthenticated=false -y --no-install-recommends install \
      openjdk-17-jre-headless ca-certificates curl unzip util-linux iproute2
  fi
  [[ -x "$JAVA" ]] || fail "Ubuntu OpenJDK 17 JRE is missing."
}

resolve_ip() {
  # IMDS assignment, not RFC1918 membership, defines the Azure private address.
  # Always consult IMDS: a caller argument cannot bypass the NIC assignment.
  PRIVATE_IP=$(curl --fail --silent --show-error --noproxy '*' \
    --connect-timeout 3 --max-time 10 --retry 2 --retry-delay 1 --retry-max-time 30 \
    -H 'Metadata: true' \
    'http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2021-02-01&format=text')
  [[ "$PRIVATE_IP" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || fail "Invalid IPv4."
  local a b c d octet
  IFS=. read -r a b c d <<< "$PRIVATE_IP"
  for octet in "$a" "$b" "$c" "$d"; do
    [[ "$octet" == 0 || "$octet" != 0* ]] || fail "IPv4 must not contain leading zeros."
    (( 10#$octet <= 255 )) || fail "Invalid IPv4 octet."
  done
  [[ -z "${1:-}" || "$1" == "$PRIVATE_IP" ]] ||
    fail "Caller IPv4 does not match the Azure IMDS assigned NIC private IPv4."
  ip -4 -o address show | awk '{split($4,a,"/"); print a[1]}' |
    grep -Fxq "$PRIVATE_IP" || fail "Private IPv4 is not assigned to this VM."
}

install_runtime() {
  install -d -m 0755 "${ROOT}/opt"
  install -d -m 0700 "$CACHE"
  if [[ -d "$INSTALL" ]]; then
    [[ -f "$ARCHIVE" ]] && verify_archive "$ARCHIVE" ||
      fail "Existing installation has no checksum-verified archive; refusing replacement."
    [[ -f "$CACHE/install.sha256" ]] &&
      sha256sum --check --status "$CACHE/install.sha256" ||
      fail "Existing runtime integrity failed; refusing to overwrite a possibly running broker."
    printf 'RocketMQ: verified existing %s installation.\n' "$ROCKETMQ_VERSION"
    return
  fi
  STAGING="${CACHE}/staging-${BASHPID}"
  mkdir -m 0700 "$STAGING"
  if [[ -f "$ARCHIVE" ]]; then
    verify_archive "$ARCHIVE" || fail "Cached archive SHA512 mismatch."
  else
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' \
      --tlsv1.2 --connect-timeout 10 --max-time 180 --retry 3 --retry-delay 2 \
      --retry-max-time 600 --output "$STAGING/download.zip" "$ROCKETMQ_URL"
    verify_archive "$STAGING/download.zip" || fail "Downloaded archive SHA512 mismatch."
    install -m 0600 "$STAGING/download.zip" "$ARCHIVE"
  fi
  # Extraction is only reached after verification of the pinned Apache binary.
  unzip -q "$ARCHIVE" -d "$STAGING/unpacked"
  local extracted="${STAGING}/unpacked/rocketmq-all-${ROCKETMQ_VERSION}-bin-release"
  [[ -f "$extracted/lib/rocketmq-broker-${ROCKETMQ_VERSION}.jar" &&
     -f "$extracted/lib/rocketmq-namesrv-${ROCKETMQ_VERSION}.jar" &&
     -f "$extracted/conf/rmq.broker.logback.xml" &&
     -f "$extracted/conf/rmq.namesrv.logback.xml" ]] || fail "Unexpected Apache binary layout."
  chown -R root:root "$extracted"
  chmod -R u+rwX,go+rX,go-w "$extracted"
  mv "$extracted" "$INSTALL"
  find "$INSTALL" -type f -print0 | sort -z | xargs -0 sha256sum > "$CACHE/install.sha256"
  chmod 0600 "$CACHE/install.sha256"
  cleanup
  STAGING=""
}

create_account() {
  if ! getent passwd rocketmq >/dev/null; then
    useradd --system --user-group --home-dir "$STATE" --no-create-home \
      --shell /usr/sbin/nologin rocketmq
  fi
  local name password uid gid gecos home shell
  IFS=: read -r name password uid gid gecos home shell < <(getent passwd rocketmq)
  [[ "$uid" =~ ^[0-9]+$ && "$uid" -gt 0 && "$home" == "$STATE" &&
     "$shell" == /usr/sbin/nologin ]] || fail "Existing rocketmq account is unsafe or incompatible."
  [[ $(getent group rocketmq | cut -d: -f3) == "$gid" && "$gid" -gt 0 ]] ||
    fail "rocketmq must have a dedicated non-root primary group."
  install -d -m 0750 -o rocketmq -g rocketmq "$STATE" "$STATE/store" \
    "$STATE/namesrv" "$STATE/logs" "$STATE/tmp"
  install -d -m 0750 -o root -g rocketmq "$CONFIG"
}

write_configuration() {
  cat > "$CONFIG/nameserver.properties" <<EOF
bindAddress=$PRIVATE_IP
listenPort=9876
kvConfigPath=$STATE/namesrv/kvConfig.json
enableControllerInNamesrv=false
EOF
  cat > "$CONFIG/broker.properties" <<EOF
brokerClusterName=WorkshopCluster
brokerName=workshop-broker
brokerId=0
brokerRole=ASYNC_MASTER
namesrvAddr=$PRIVATE_IP:9876
bindAddress=$PRIVATE_IP
brokerIP1=$PRIVATE_IP
brokerIP2=$PRIVATE_IP
listenPort=10911
haListenPort=10912
storePathRootDir=$STATE/store
storePathCommitLog=$STATE/store/commitlog
flushDiskType=SYNC_FLUSH
transientStorePoolEnable=false
mappedFileSizeCommitLog=134217728
autoCreateTopicEnable=false
autoCreateSubscriptionGroup=false
defaultTopicQueueNums=2
EOF
  chown root:rocketmq "$CONFIG/"*.properties
  chmod 0640 "$CONFIG/"*.properties
  install -d -m 0755 "$UNITS"
  local component class heap direct logconfig extra
  for component in nameserver broker; do
    if [[ "$component" == nameserver ]]; then
      class=org.apache.rocketmq.namesrv.NamesrvStartup
      heap='-Xms128m -Xmx256m'
      direct=128m
      logconfig=rmq.namesrv.logback.xml
      extra=""
    else
      class=org.apache.rocketmq.broker.BrokerStartup
      heap='-Xms512m -Xmx1024m'
      direct=512m
      logconfig=rmq.broker.logback.xml
      extra=$'Requires=rocketmq-nameserver.service\nAfter=rocketmq-nameserver.service'
    fi
    # Direct foreground Java avoids the upstream 4/8 GB defaults and lets
    # systemd own exactly one JVM per unit, including graceful SIGTERM shutdown.
    cat > "$UNITS/rocketmq-${component}.service" <<EOF
[Unit]
Description=Apache RocketMQ ${component} (private workshop)
Wants=network-online.target
After=network-online.target
$extra
StartLimitIntervalSec=120
StartLimitBurst=5

[Service]
Type=simple
User=rocketmq
Group=rocketmq
WorkingDirectory=$STATE
Environment=HOME=$STATE
Environment=ROCKETMQ_HOME=$INSTALL
Environment=TMPDIR=$STATE/tmp
ExecStart=$JAVA -server $heap -XX:MaxDirectMemorySize=$direct -XX:MaxMetaspaceSize=256m -XX:+UseG1GC -XX:-UsePerfData --add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.nio=ALL-UNNAMED --add-opens=java.base/sun.nio.ch=ALL-UNNAMED -Duser.home=$STATE -Djava.io.tmpdir=$STATE/tmp -Drmq.logback.configurationFile=$INSTALL/conf/$logconfig -cp $INSTALL/conf:$INSTALL/lib/* $class -c $CONFIG/${component}.properties
Restart=on-failure
RestartSec=5
TimeoutStartSec=60
TimeoutStopSec=90
KillSignal=SIGTERM
KillMode=control-group
LimitNOFILE=65536
UMask=0027
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateDevices=true
ReadWritePaths=$STATE
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
CapabilityBoundingSet=

[Install]
WantedBy=multi-user.target
EOF
    chmod 0644 "$UNITS/rocketmq-${component}.service"
  done
}

admin() {
  timeout --kill-after=2s 10s runuser -u rocketmq -- "$JAVA" \
    -Xms32m -Xmx128m -XX:MaxDirectMemorySize=64m -XX:-UsePerfData \
    -Duser.home="$STATE" -Djava.io.tmpdir="$STATE/tmp" \
    -Drocketmq.home.dir="$INSTALL" -cp "$INSTALL/conf:$INSTALL/lib/*" \
    org.apache.rocketmq.tools.command.MQAdminStartup "$@"
}

converge_services() {
  local desired previous="" component active output
  desired=$(sha256sum "$CONFIG/"*.properties "$UNITS/rocketmq-"*.service)
  if [[ -f "$CACHE/services.sha256" ]]; then previous=$(cat "$CACHE/services.sha256"); fi
  if [[ "$desired" != "$previous" ]]; then systemctl daemon-reload; fi
  systemctl enable rocketmq-nameserver.service rocketmq-broker.service
  for component in nameserver broker; do
    active=false
    if systemctl is-active --quiet "rocketmq-${component}.service"; then active=true; fi
    if "$active"; then
      if [[ "$desired" != "$previous" ]]; then
        systemctl restart "rocketmq-${component}.service"
      fi
    else
      systemctl start "rocketmq-${component}.service"
    fi
  done
  # A listening port or systemd's "active" alone is not application readiness.
  local attempt
  for ((attempt=1; attempt<=24; attempt++)); do
    if systemctl is-active --quiet rocketmq-nameserver.service &&
       systemctl is-active --quiet rocketmq-broker.service &&
       admin brokerStatus -n "$PRIVATE_IP:9876" -b "$PRIVATE_IP:10911" > "$CACHE/broker-health.log" 2>&1 &&
       grep -q 'brokerVersion' "$CACHE/broker-health.log"; then
      if output=$(admin clusterList -n "$PRIVATE_IP:9876" 2>&1) &&
         awk -v address="$PRIVATE_IP:10911" \
           '$1=="WorkshopCluster" && $2=="workshop-broker" && $3=="0" && $4==address {found=1} END {exit !found}' <<< "$output"; then
        printf '%s\n' "$desired" > "$CACHE/services.sha256"
        printf 'RocketMQ %s: nameserver and standalone broker are ready.\n' "$ROCKETMQ_VERSION"
        return
      fi
    fi
    sleep 5
  done
  fail "Application readiness timed out; inspect journalctl -u rocketmq-nameserver -u rocketmq-broker and the private broker-health.log."
}

main() {
  trap cleanup EXIT
  trap 'printf "RocketMQ bootstrap failed at line %s (exit %s).\n" "$LINENO" "$?" >&2' ERR
  check_host "$@"
  install -d -m 0755 "${ROOT}/run/lock"
  exec 9>"${ROOT}/run/lock/rocketmq-bootstrap.lock"
  flock -w 600 9 || fail "Another bootstrap holds the runtime lock."
  install_packages
  resolve_ip "$@"
  install_runtime
  create_account
  write_configuration
  converge_services
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
