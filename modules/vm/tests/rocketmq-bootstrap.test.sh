#!/usr/bin/env bash
# Self-contained offline tests: all external/system-mutating commands are mocked.
set -Eeuo pipefail
cd "$(dirname "$0")/../../.."
readonly TEST_DIR="$PWD/modules/vm/tests/.bootstrap-test-${BASHPID}"
mkdir -m 0700 "$TEST_DIR"
trap 'rm -rf -- "$TEST_DIR"' EXIT
readonly SCRIPT="$PWD/modules/vm/scripts/rocketmq-bootstrap.sh"
export TEST_DIR

assert_contains() { grep -Fq -- "$2" "$1" || { echo "FAIL: expected $2 in $1" >&2; exit 1; }; }
assert_absent() { if grep -Fq -- "$2" "$1"; then echo "FAIL: unexpected $2 in $1" >&2; exit 1; fi; }

# Shell functions are exported so no stub packages or system binaries are installed.
id() { printf '0\n'; }
uname() { printf 'x86_64\n'; }
dpkg-query() { [[ "${MOCK_PACKAGES_MISSING:-false}" == false ]] && printf 'install ok installed'; }
apt-get() { printf 'apt %s\n' "$*" >> "$TEST_DIR/calls"; }
flock() { :; }
chown() { :; }
useradd() { printf 'useradd\n' >> "$TEST_DIR/calls"; touch "$TEST_DIR/account"; }
getent() {
  [[ -f "$TEST_DIR/account" ]] || return 2
  case "$1" in
    passwd) printf 'rocketmq:x:997:997::%s/var/lib/rocketmq:/usr/sbin/nologin\n' "$ROCKETMQ_ROOT" ;;
    group) printf 'rocketmq:x:997:\n' ;;
  esac
}
install() {
  local args=()
  while (($#)); do
    case "$1" in
      -o|-g) shift 2 ;;
      *) args+=("$1"); shift ;;
    esac
  done
  command install "${args[@]}"
}
curl() {
  local output=""
  while (($#)); do
    if [[ "$1" == --output ]]; then output="$2"; shift 2; else shift; fi
  done
  if [[ -n "$output" ]]; then
    printf 'curl download\n' >> "$TEST_DIR/calls"
    printf 'mock official archive\n' > "$output"
  else
    printf 'curl imds\n' >> "$TEST_DIR/calls"
    printf '%s' "${MOCK_IMDS_IP:-10.42.0.8}"
  fi
}
sha512sum() {
  cat >/dev/null
  [[ "${MOCK_CHECKSUM:-valid}" == valid ]]
}
unzip() {
  printf 'unzip\n' >> "$TEST_DIR/calls"
  local destination=""
  while (($#)); do
    if [[ "$1" == -d ]]; then destination="$2"; shift 2; else shift; fi
  done
  local tree="$destination/rocketmq-all-5.5.1-bin-release"
  mkdir -p "$tree/lib" "$tree/conf"
  printf 'broker\n' > "$tree/lib/rocketmq-broker-5.5.1.jar"
  printf 'namesrv\n' > "$tree/lib/rocketmq-namesrv-5.5.1.jar"
  printf 'log config\n' > "$tree/conf/rmq.broker.logback.xml"
  printf 'log config\n' > "$tree/conf/rmq.namesrv.logback.xml"
}
ip() { printf '2: eth0 inet %s/24 scope global eth0\n' "${MOCK_NIC_IP:-10.42.0.8}"; }
systemctl() {
  printf 'systemctl %s\n' "$*" >> "$TEST_DIR/calls"
  case "$1" in
    is-active) [[ -f "$TEST_DIR/$3.active" ]] ;;
    start|restart) touch "$TEST_DIR/$2.active" ;;
    enable|daemon-reload) : ;;
    *) echo "Unexpected systemctl command" >&2; return 1 ;;
  esac
}
timeout() {
  # Never execute a real installer, systemctl, user switch, or JVM.
  while [[ "$1" == --* ]]; do shift; done
  shift
  if [[ "$1" == runuser ]]; then
    printf 'admin\n' >> "$TEST_DIR/calls"
    if [[ "${MOCK_HEALTH:-ready}" != ready ]]; then return 1; fi
    if [[ " $* " == *" brokerStatus "* ]]; then
      printf 'brokerVersion : 551\n'
    else
      printf 'WorkshopCluster workshop-broker 0 %s:10911 V5_5_1\n' "${MOCK_IMDS_IP:-10.42.0.8}"
    fi
  elif [[ "$1" == env ]]; then
    shift 2
    [[ "$1" == apt-get ]] || return 1
    apt-get "${@:2}"
  else
    echo "Refusing unmocked timeout command: $1" >&2
    return 1
  fi
}
sleep() { :; }
export -f id uname dpkg-query apt-get flock chown useradd getent install curl \
  sha512sum unzip ip systemctl timeout sleep

setup_root() {
  export ROCKETMQ_ROOT="$TEST_DIR/root"
  mkdir -p "$ROCKETMQ_ROOT/etc" "$ROCKETMQ_ROOT/proc" \
    "$ROCKETMQ_ROOT/usr/lib/jvm/java-17-openjdk-amd64/bin"
  printf 'ID=ubuntu\nVERSION_ID=22.04\n' > "$ROCKETMQ_ROOT/etc/os-release"
  printf 'MemTotal: 8000000 kB\n' > "$ROCKETMQ_ROOT/proc/meminfo"
  # The JVM is never executed; the bootstrap only checks its executable bit.
  touch "$ROCKETMQ_ROOT/usr/lib/jvm/java-17-openjdk-amd64/bin/java"
  chmod 0755 "$ROCKETMQ_ROOT/usr/lib/jvm/java-17-openjdk-amd64/bin/java"
  : > "$TEST_DIR/calls"
}

setup_root
export MOCK_CHECKSUM=invalid
if bash "$SCRIPT" 10.42.0.8 > "$TEST_DIR/rejected.log" 2>&1; then
  echo 'FAIL: invalid SHA512 accepted' >&2; exit 1
fi
assert_contains "$TEST_DIR/rejected.log" 'Downloaded archive SHA512 mismatch'
assert_absent "$TEST_DIR/calls" unzip
assert_absent "$TEST_DIR/calls" systemctl
[[ ! -d "$ROCKETMQ_ROOT/opt/rocketmq-5.5.1" ]]
echo 'PASS: checksum rejection happens before extraction/services'

export MOCK_CHECKSUM=valid MOCK_PACKAGES_MISSING=true
bash "$SCRIPT" > "$TEST_DIR/first.log" 2>&1
assert_contains "$TEST_DIR/calls" 'apt '
assert_contains "$TEST_DIR/calls" unzip
assert_contains "$TEST_DIR/calls" 'systemctl start rocketmq-nameserver.service'
assert_contains "$TEST_DIR/calls" 'systemctl start rocketmq-broker.service'
assert_contains "$ROCKETMQ_ROOT/etc/rocketmq/broker.properties" 'flushDiskType=SYNC_FLUSH'
assert_contains "$TEST_DIR/first.log" 'are ready'
echo 'PASS: signed-package path, IMDS, installation and protocol health are mocked'

printf 'persisted test message\n' > "$ROCKETMQ_ROOT/var/lib/rocketmq/store/retained"
: > "$TEST_DIR/calls"
export MOCK_PACKAGES_MISSING=false
bash "$SCRIPT" 10.42.0.8 > "$TEST_DIR/repeat.log" 2>&1
assert_contains "$TEST_DIR/repeat.log" 'verified existing'
assert_contains "$TEST_DIR/calls" 'curl imds'
assert_absent "$TEST_DIR/calls" 'curl download'
assert_absent "$TEST_DIR/calls" unzip
assert_absent "$TEST_DIR/calls" 'apt '
assert_absent "$TEST_DIR/calls" useradd
assert_absent "$TEST_DIR/calls" 'systemctl start '
assert_absent "$TEST_DIR/calls" 'systemctl restart '
assert_contains "$ROCKETMQ_ROOT/var/lib/rocketmq/store/retained" 'persisted test message'
echo 'PASS: repeat run verifies integrity and preserves data without duplicate JVMs'

printf 'bindAddress=wrong\n' > "$ROCKETMQ_ROOT/etc/rocketmq/broker.properties"
: > "$TEST_DIR/calls"
bash "$SCRIPT" 10.42.0.8 > "$TEST_DIR/converge.log" 2>&1
assert_contains "$ROCKETMQ_ROOT/etc/rocketmq/broker.properties" 'bindAddress=10.42.0.8'
assert_absent "$TEST_DIR/calls" 'systemctl restart '
echo 'PASS: drift is restored to the previously applied service configuration'

rm "$ROCKETMQ_ROOT/var/cache/rocketmq/services.sha256"
: > "$TEST_DIR/calls"
bash "$SCRIPT" 10.42.0.8 > "$TEST_DIR/retry.log" 2>&1
assert_contains "$TEST_DIR/calls" 'systemctl restart rocketmq-nameserver.service'
assert_contains "$TEST_DIR/calls" 'systemctl restart rocketmq-broker.service'
assert_absent "$TEST_DIR/calls" 'systemctl start '
echo 'PASS: incomplete service convergence is retried through systemd, not duplicate processes'

export MOCK_HEALTH=failed
: > "$TEST_DIR/calls"
if bash "$SCRIPT" 10.42.0.8 > "$TEST_DIR/unready.log" 2>&1; then
  echo 'FAIL: failed protocol health accepted' >&2; exit 1
fi
assert_contains "$TEST_DIR/unready.log" 'Application readiness timed out'
[[ $(grep -c '^admin$' "$TEST_DIR/calls") == 24 ]]
echo 'PASS: active services with failed protocol health time out boundedly'
export MOCK_HEALTH=ready

export MOCK_IMDS_IP=172.15.0.8 MOCK_NIC_IP=172.15.0.8
bash "$SCRIPT" > "$TEST_DIR/non-rfc1918.log" 2>&1
assert_contains "$TEST_DIR/non-rfc1918.log" 'are ready'
assert_contains "$ROCKETMQ_ROOT/etc/rocketmq/nameserver.properties" 'bindAddress=172.15.0.8'
assert_contains "$ROCKETMQ_ROOT/etc/rocketmq/broker.properties" 'bindAddress=172.15.0.8'
assert_contains "$ROCKETMQ_ROOT/etc/rocketmq/broker.properties" 'brokerIP1=172.15.0.8'
: > "$TEST_DIR/calls"
bash "$SCRIPT" 172.15.0.8 > "$TEST_DIR/non-rfc1918-repeat.log" 2>&1
assert_contains "$TEST_DIR/calls" 'curl imds'
assert_absent "$TEST_DIR/calls" 'systemctl restart '
assert_absent "$TEST_DIR/calls" 'systemctl start '
echo 'PASS: non-RFC1918 IMDS NIC private IP binds correctly, including a matching caller'
unset MOCK_IMDS_IP MOCK_NIC_IP

printf 'modified runtime\n' >> "$ROCKETMQ_ROOT/opt/rocketmq-5.5.1/lib/rocketmq-broker-5.5.1.jar"
: > "$TEST_DIR/calls"
if bash "$SCRIPT" 10.42.0.8 > "$TEST_DIR/tamper.log" 2>&1; then
  echo 'FAIL: modified installation accepted' >&2; exit 1
fi
assert_contains "$TEST_DIR/tamper.log" 'Existing runtime integrity failed'
assert_absent "$TEST_DIR/calls" unzip
assert_absent "$TEST_DIR/calls" systemctl
echo 'PASS: modified runtime is not silently trusted or replaced'

# Even another locally assigned address must not bypass the IMDS assignment.
export MOCK_NIC_IP=203.0.113.8
if bash "$SCRIPT" 203.0.113.8 > "$TEST_DIR/public.log" 2>&1; then
  echo 'FAIL: public IPv4 accepted' >&2; exit 1
fi
assert_contains "$TEST_DIR/public.log" 'Caller IPv4 does not match the Azure IMDS assigned NIC private IPv4'
echo 'PASS: arbitrary caller binding rejected even if present locally but absent from IMDS'
