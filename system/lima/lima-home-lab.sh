#!/bin/bash
# Run as your normal macOS user, not with sudo.
set -euo pipefail

# =============================================================================
# EDITABLE SETTINGS. Environment variables override these defaults; CLI wins.
# Empty settings are detected automatically or prompted for, as noted below.
# Runtime measurements and derived paths are calculated after argument parsing.
# =============================================================================
VM_HOSTNAME="${VM_HOSTNAME:-cary-home-lab-m2-max}" # Also the Lima instance name.
VM_IP="${VM_IP:-}"                             # Required IPv4; prompt if empty.
SUBNET_PREFIX="${SUBNET_PREFIX:-24}"             # /24 = 255.255.255.0.
LAN_IFACE="${LAN_IFACE:-}"                       # Prefer connected Ethernet; prompt otherwise.
LAN_GATEWAY="${LAN_GATEWAY:-}"                   # Detect from selected interface; prompt.
LAN_DNS="${LAN_DNS:-}"                           # Default to gateway; prompt.

UBUNTU_VERSION="${UBUNTU_VERSION:-26.04}"         # Maintained LTS cloud-image series.
VM_USER="${VM_USER:-ubuntu}"
GITHUB_USER="${GITHUB_USER:-carysyd}"
VM_TYPE="${VM_TYPE:-vz}"
VM_ARCH="${VM_ARCH:-aarch64}"

HOST_RAM_RESERVE_GIB="${HOST_RAM_RESERVE_GIB:-8}"
HOST_DISK_RESERVE_GIB="${HOST_DISK_RESERVE_GIB:-200}"
MIN_VM_RAM_GIB="${MIN_VM_RAM_GIB:-2}"
MIN_VM_DISK_GIB="${MIN_VM_DISK_GIB:-20}"
CPUS="${CPUS:-}"                                # Empty = all detected cores.
RAM_GIB="${RAM_GIB:-}"                          # Empty = physical RAM - reserve.
DISK_GIB="${DISK_GIB:-}"                        # Empty = free disk - reserve.

AUTOSTART="${AUTOSTART:-true}"
AUTOSTART_CONDITION="${AUTOSTART_CONDITION:-boot}" # boot or login; boot uses sudo.
AUTOSTART_KEEP_ALIVE="${AUTOSTART_KEEP_ALIVE:-true}"

BREW_PREFIX="${BREW_PREFIX:-/opt/homebrew}"
BREW_INSTALL_URL="${BREW_INSTALL_URL:-https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh}"
SOCKET_VMNET_PREFIX="${SOCKET_VMNET_PREFIX:-/opt/socket_vmnet}"
SOCKET_VMNET_VERSION="${SOCKET_VMNET_VERSION:-latest}" # Or a release tag, e.g. vX.Y.Z.
IMAGE_BASE="${IMAGE_BASE:-https://cloud-images.ubuntu.com/releases/$UBUNTU_VERSION/release}"
# =============================================================================

usage() {
  cat <<'HELP'
Usage: lima-home-lab.sh [--hostname NAME] [--ip IPV4] [--interface enN] [--help]

  --hostname NAME  Ubuntu hostname and Lima instance name.
  --ip IPV4       Static LAN IPv4 address, without a /prefix.
  --interface enN Mac interface to bridge, e.g. the USB Ethernet dongle's en7.
  -h, --help      Show help without installing or changing anything.

Example:
  bash lima-home-lab.sh --hostname cary-home-lab-m2-max --ip 192.168.1.50

Other settings are editable at the top or supplied as environment variables.
The subnet prefix is configured separately using SUBNET_PREFIX (default 24).
This script creates a new VM; it does not modify an existing VM.
HELP
}

die() { echo "Error: $*" >&2; exit 1; }

while (( $# )); do
  case "$1" in
    --hostname|--ip|--interface)
      (( $# >= 2 )) && [[ -n $2 && $2 != --* ]] || die "$1 requires a value."
      case "$1" in
        --hostname) VM_HOSTNAME=$2 ;;
        --ip) VM_IP=$2 ;;
        --interface) LAN_IFACE=$2 ;;
      esac
      shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "Unknown argument: $1. Use --help." ;;
  esac
done

# Derived settings: follow --hostname, so each VM has matching host-side paths.
NAME=$VM_HOSTNAME
export LIMA_HOME="$HOME/.lima-$NAME"
NETWORK_RUN_DIR="/private/var/run/lima-$NAME"
SUDOERS_FILE="/private/etc/sudoers.d/lima-$NAME"
CONFIG_FILE="$LIMA_HOME/$NAME.yaml"
IMAGE="ubuntu-$UBUNTU_VERSION-server-cloudimg-arm64.img"

[[ $(uname -m) == arm64 ]] || { echo 'Run this on your Apple Silicon Mac.' >&2; exit 1; }
[[ $EUID != 0 ]] || { echo 'Run as your normal user.' >&2; exit 1; }
[[ ${#NAME} -le 55 && $NAME =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?$ ]] || die 'Hostname must be 1-55 lowercase letters, digits, or internal dashes.'
[[ $VM_USER =~ ^[a-z_][a-z0-9_-]*$ ]] || die 'Invalid Ubuntu username.'
[[ $GITHUB_USER =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || die 'Invalid GitHub username.'
[[ $UBUNTU_VERSION =~ ^[0-9]{2}\.[0-9]{2}$ ]] || die 'Ubuntu version must be a series such as 26.04.'
[[ $VM_TYPE == vz && $VM_ARCH == aarch64 ]] || die 'This Apple Silicon script supports VM_TYPE=vz and VM_ARCH=aarch64.'
[[ $AUTOSTART == true || $AUTOSTART == false ]] || die 'AUTOSTART must be true or false.'
[[ $AUTOSTART_CONDITION == boot || $AUTOSTART_CONDITION == login ]] || die 'AUTOSTART_CONDITION must be boot or login.'
[[ $AUTOSTART_KEEP_ALIVE == true || $AUTOSTART_KEEP_ALIVE == false ]] || die 'AUTOSTART_KEEP_ALIVE must be true or false.'
for INTEGER_SETTING in "$HOST_RAM_RESERVE_GIB" "$HOST_DISK_RESERVE_GIB" "$MIN_VM_RAM_GIB" "$MIN_VM_DISK_GIB" "$SUBNET_PREFIX"; do
  [[ $INTEGER_SETTING =~ ^(0|[1-9][0-9]*)$ ]] || die 'Reserve, minimum, and prefix settings must be nonnegative decimal integers.'
done
(( SUBNET_PREFIX >= 1 && SUBNET_PREFIX <= 30 && MIN_VM_RAM_GIB >= 1 && MIN_VM_DISK_GIB >= 1 )) || die 'Invalid subnet prefix or minimum VM size.'
CPUS=${CPUS:-$(sysctl -n hw.logicalcpu)}

# Budget from installed physical memory, not the momentary free-memory counter.
TOTAL_RAM_BYTES=$(sysctl -n hw.memsize)
MAX_RAM_GIB=$(( TOTAL_RAM_BYTES / 1073741824 - HOST_RAM_RESERVE_GIB ))
(( MAX_RAM_GIB >= MIN_VM_RAM_GIB )) || die "Insufficient RAM after reserving $HOST_RAM_RESERVE_GIB GiB for macOS."
RAM_GIB=${RAM_GIB:-$MAX_RAM_GIB}
[[ $RAM_GIB =~ ^[0-9]+$ && $CPUS =~ ^[0-9]+$ ]] || { echo 'RAM_GIB and CPUS must be positive integers.' >&2; exit 1; }
(( RAM_GIB >= MIN_VM_RAM_GIB && RAM_GIB <= MAX_RAM_GIB && CPUS >= 1 )) || {
  echo "RAM_GIB must be between $MIN_VM_RAM_GIB and $MAX_RAM_GIB; CPUS must be positive." >&2
  exit 1
}

# Prefer a physically connected Ethernet port independently of macOS route order.
# USB dongles may be named "USB ... LAN" rather than "Ethernet".
HARDWARE_PORTS=$(networksetup -listallhardwareports)
DEFAULT_IFACE=$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}' || true)
if [[ -z ${LAN_IFACE:-} ]]; then
  ETHERNET_IFACES=()
  while IFS= read -r CANDIDATE_IFACE; do
    if ifconfig "$CANDIDATE_IFACE" 2>/dev/null | awk '
      /status: active/ {active=1} END {exit !active}'; then
      ETHERNET_IFACES+=("$CANDIDATE_IFACE")
    fi
  done < <(printf '%s\n' "$HARDWARE_PORTS" | awk '
    /^Hardware Port:/ {port=tolower($0)}
    /^Device:/ && port ~ /ethernet|lan|gigabit/ && port !~ /wi-fi|airport|bluetooth|bridge/ {print $2}')
  if (( ${#ETHERNET_IFACES[@]} == 1 )); then
    LAN_IFACE=${ETHERNET_IFACES[0]}
    printf 'Using connected Ethernet interface: %s\n' "$LAN_IFACE"
  else
    printf '%s\n' "$HARDWARE_PORTS"
    if (( ${#ETHERNET_IFACES[@]} > 1 )); then
      printf 'Multiple connected Ethernet interfaces: %s\n' "${ETHERNET_IFACES[*]}"
      read -r -p 'Choose the Ethernet interface to bridge (enN): ' LAN_IFACE
    else
      printf 'No connected Ethernet interface detected. Connect the dongle and cable,\n'
      printf 'or explicitly select Wi-Fi if that is your intended bridge.\n'
      read -r -p "Mac bridge interface [${DEFAULT_IFACE:-en0}]: " LAN_IFACE
      LAN_IFACE=${LAN_IFACE:-${DEFAULT_IFACE:-en0}}
    fi
  fi
fi
[[ $LAN_IFACE =~ ^en[0-9]+$ ]] || die 'Expected an enN network interface.'
ifconfig "$LAN_IFACE" >/dev/null
printf 'Bridge pinned to %s (saved for subsequent boots).\n' "$LAN_IFACE"
ifconfig "$LAN_IFACE" | awk '/media:|status:/ {print}'

# Use the selected interface's DHCP router or scoped route, not Wi-Fi's gateway.
DEFAULT_GATEWAY=$(ipconfig getoption "$LAN_IFACE" router 2>/dev/null || true)
if [[ -z $DEFAULT_GATEWAY ]]; then
  DEFAULT_GATEWAY=$(route -n get -ifscope "$LAN_IFACE" default 2>/dev/null | awk '/gateway:/ {print $2}' || true)
fi
if [[ -z $VM_IP ]]; then
  read -r -p 'Unused VM IPv4 (example 192.168.1.50): ' VM_IP
fi
if [[ -z ${LAN_GATEWAY:-} ]]; then
  read -r -p "LAN gateway [$DEFAULT_GATEWAY]: " LAN_GATEWAY
  LAN_GATEWAY=${LAN_GATEWAY:-$DEFAULT_GATEWAY}
fi
if [[ -z ${LAN_DNS:-} ]]; then
  read -r -p "IPv4 DNS server [$LAN_GATEWAY]: " LAN_DNS
  LAN_DNS=${LAN_DNS:-$LAN_GATEWAY}
fi
valid_ipv4() {
  [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  printf '%s\n' "$1" | awk -F. '{for (i=1;i<=4;i++) if ($i>255 || (length($i)>1 && substr($i,1,1)=="0")) exit 1}'
}
valid_ipv4 "$VM_IP" && valid_ipv4 "$LAN_GATEWAY" && valid_ipv4 "$LAN_DNS" || die 'VM_IP, LAN_GATEWAY, and LAN_DNS must be valid IPv4 addresses.'
VM_CIDR="$VM_IP/$SUBNET_PREFIX"
if [[ -e "$LIMA_HOME" ]]; then
  echo "$LIMA_HOME already exists. Inspect it before attempting a fresh setup." >&2
  exit 1
fi
TASK_TMP=$(mktemp -d)
trap 'rm -rf "$TASK_TMP"' EXIT

# Find an existing Apple Silicon installation even if shellenv is not configured.
if [[ -x $BREW_PREFIX/bin/brew ]]; then
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
elif ! command -v brew >/dev/null 2>&1; then
  echo 'Installing Homebrew using its official installer...'
  curl -fsSL "$BREW_INSTALL_URL" \
    -o "$TASK_TMP/install-homebrew.sh"
  /bin/bash "$TASK_TMP/install-homebrew.sh"
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
fi
brew install lima jq
if [[ $AUTOSTART == true ]]; then
  if ! limactl autostart enable --help >/dev/null 2>&1; then
    brew upgrade lima
  fi
  limactl autostart enable --help >/dev/null 2>&1 || die 'Automatic startup requires Lima 2.2 or newer.'
fi

# Install the networking helper into the root-owned location Lima requires.
# This follows the official socket_vmnet binary installation procedure.
if [[ ! -x $SOCKET_VMNET_PREFIX/bin/socket_vmnet ]]; then
  VERSION=$SOCKET_VMNET_VERSION
  if [[ $VERSION == latest ]]; then
    VERSION=$(curl -fsSL https://api.github.com/repos/lima-vm/socket_vmnet/releases/latest | jq -er .tag_name)
  fi
  ARCHIVE="socket_vmnet-${VERSION#v}-arm64.tar.gz"
  curl -fL "https://github.com/lima-vm/socket_vmnet/releases/download/$VERSION/$ARCHIVE" -o "$TASK_TMP/$ARCHIVE"
  # Official archives install into /opt/socket_vmnet. A custom prefix must
  # already contain a root-owned installation.
  [[ $SOCKET_VMNET_PREFIX == /opt/socket_vmnet ]] || die 'Install socket_vmnet in your custom prefix first.'
  sudo tar -xzf "$TASK_TMP/$ARCHIVE" -C / opt/socket_vmnet
fi

# Measure genuinely free space on the filesystem that will hold LIMA_HOME.
# Do this after dependency installation. Do not count APFS purgeable space.
# The guest disk is sparse: this is its capacity ceiling, not preallocation.
# This budget is a setup-time target, not a filesystem-enforced host reservation;
# host writes, image caches, snapshots, and VM metadata also consume disk space.
FREE_DISK_KIB=$(df -Pk "$HOME" | awk 'END {print $4}')
[[ $FREE_DISK_KIB =~ ^[0-9]+$ ]] || { echo 'Unable to determine free disk space.' >&2; exit 1; }
MAX_DISK_GIB=$(( FREE_DISK_KIB / 1048576 - HOST_DISK_RESERVE_GIB ))
(( MAX_DISK_GIB >= MIN_VM_DISK_GIB )) || {
  echo "Need at least $((HOST_DISK_RESERVE_GIB + MIN_VM_DISK_GIB)) GiB free: $HOST_DISK_RESERVE_GIB GiB for macOS plus $MIN_VM_DISK_GIB GiB for Ubuntu." >&2
  exit 1
}
DISK_GIB=${DISK_GIB:-$MAX_DISK_GIB}
[[ $DISK_GIB =~ ^[0-9]+$ ]] || { echo 'DISK_GIB must be a positive integer.' >&2; exit 1; }
(( DISK_GIB >= MIN_VM_DISK_GIB && DISK_GIB <= MAX_DISK_GIB )) || {
  echo "DISK_GIB must be between $MIN_VM_DISK_GIB and $MAX_DISK_GIB to retain the host budget." >&2
  exit 1
}
printf '\nVM resources: %s CPUs, %s GiB RAM, %s GiB sparse disk capacity.\n' "$CPUS" "$RAM_GIB" "$DISK_GIB"
printf 'Host budget: %s GiB RAM and %s GiB of currently free disk space.\n\n' "$HOST_RAM_RESERVE_GIB" "$HOST_DISK_RESERVE_GIB"

mkdir -p "$LIMA_HOME/_config"
cat > "$LIMA_HOME/_config/networks.yaml" <<EOF
paths:
  socketVMNet: "$SOCKET_VMNET_PREFIX/bin/socket_vmnet"
  varRun: "$NETWORK_RUN_DIR"
  sudoers: "$SUDOERS_FILE"
group: admin
networks:
  lan:
    mode: bridged
    interface: $LAN_IFACE
EOF

limactl sudoers > "$TASK_TMP/lima-sudoers"
cat "$TASK_TMP/lima-sudoers"
/usr/sbin/visudo -cf "$TASK_TMP/lima-sudoers"
sudo install -o root -g wheel -m 0444 "$TASK_TMP/lima-sudoers" "$SUDOERS_FILE"

curl -fsSL "$IMAGE_BASE/SHA256SUMS" > "$TASK_TMP/SHA256SUMS"
IMAGE_SHA=$(awk -v file="$IMAGE" '$2 == file || $2 == "*" file {print $1}' "$TASK_TMP/SHA256SUMS")
[[ $IMAGE_SHA =~ ^[0-9a-f]{64}$ ]] || { echo 'Unable to find image checksum.' >&2; exit 1; }

cat > "$CONFIG_FILE" <<EOF
vmType: $VM_TYPE
arch: $VM_ARCH
cpus: $CPUS
memory: "${RAM_GIB}GiB"
disk: "${DISK_GIB}GiB"
images:
  - location: "$IMAGE_BASE/$IMAGE"
    arch: $VM_ARCH
    digest: "sha256:$IMAGE_SHA"
user:
  name: $VM_USER
  home: /home/$VM_USER
mounts: []
containerd:
  system: false
  user: false
networks:
  - lima: lan
    interface: lima0
    metric: 50
hostResolver:
  enabled: false
dns:
  - $LAN_DNS
provision:
  - mode: system
    script: |
      #!/bin/bash
      set -eu
      # Lima normally prefixes the instance hostname with "lima-".
      hostnamectl set-hostname '$NAME'
      printf 'preserve_hostname: true\n' > /etc/cloud/cloud.cfg.d/99-preserve-hostname.cfg
      sed -i 's/lima-$NAME/$NAME/g' /etc/hosts
      if ! command -v ssh-import-id >/dev/null 2>&1; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y ssh-import-id
      fi
      # Override DHCP on the bridge NIC while preserving Lima's management NIC.
      install -d -m 0755 /etc/netplan
      umask 077
      cat > /etc/netplan/90-static-lan.yaml <<'NETPLAN'
      network:
        version: 2
        ethernets:
          lima0:
            dhcp4: false
            dhcp6: false
            accept-ra: false
            addresses: [$VM_CIDR]
            routes:
              - to: default
                via: $LAN_GATEWAY
                metric: 50
            nameservers:
              addresses: [$LAN_DNS]
      NETPLAN
      netplan generate
      netplan apply
  - mode: user
    script: |
      #!/bin/bash
      set -eu
      umask 077
      mkdir -p "\$HOME/.ssh"
      if [ ! -f "\$HOME/.ssh/.github-$GITHUB_USER-imported" ]; then
        ssh-import-id gh:$GITHUB_USER
        touch "\$HOME/.ssh/.github-$GITHUB_USER-imported"
      fi
      chmod 700 "\$HOME/.ssh"
      chmod 600 "\$HOME/.ssh/authorized_keys"
EOF

limactl start --name="$NAME" --tty=false "$CONFIG_FILE"

limactl shell "$NAME" -- sh -c '. /etc/os-release; printf "%s\n" "$PRETTY_NAME"; whoami; hostname; uname -m; nproc; free -h; ip -4 address show lima0; ip -4 route'

if [[ $AUTOSTART == true ]]; then
  # Lima generates a launchd service that preserves this LIMA_HOME and runs
  # as this macOS user. With condition=boot, no GUI login is required.
  if [[ $AUTOSTART_CONDITION == boot ]]; then
    # Hand the running VM over to the system service, avoiding two host agents.
    limactl stop "$NAME"
  fi
  limactl autostart enable --condition="$AUTOSTART_CONDITION" \
    --keep-alive="$AUTOSTART_KEEP_ALIVE" "$NAME"
  printf 'Automatic startup enabled: %s.\n' "$AUTOSTART_CONDITION"
  if [[ $AUTOSTART_CONDITION == boot ]]; then
    fdesetup status || true
    printf 'If FileVault requires disk unlock after reboot, the VM starts after that unlock.\n'
    printf 'The VM is now starting under launchd; allow time for SSH to become ready.\n'
  fi
fi

printf '\nLAN SSH: ssh %s@%s\n' "$VM_USER" "$VM_IP"
printf 'For future Lima commands, first run:\nexport LIMA_HOME="$HOME/.lima-%s"\n' "$NAME"
printf 'Then: limactl shell %s\n' "$NAME"
