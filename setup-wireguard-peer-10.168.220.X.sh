#!/bin/bash

# ==============================================================================
# - This script is used to configure servacatba and other peers for remote
#   access. It assumes a wireguard server (gateway) hosted on a virtual server
#   with a public IP address.
# - The wireguard PrivateKey needs to be available, either as a file called
#   "privatekey" in the current directory, or as text to be typed/pasted during
#   script execution.
# ==============================================================================


# ------------------------------------------------------------------------------
# Ensure elevated privileges.
# ------------------------------------------------------------------------------
if [[ $(id -u) != 0 ]]; then
    sudo $0 $@
    exit $?
fi

if [[ ! $1 =~ ^[0-9]{1,3}$ ]]; then
    echo "Need to pass last IP octet; e.g. \"4\" for servacatba (10.16.1.4)."
    if [[ -n $1 ]]; then
        echo "\"$1\" was passed."
    fi
    exit 1
else
    ID="$1"
fi

# Set global variables.
PUBLIC_IP4="165.22.82.201"
IP4="10.168.220.${ID}"
IP6_108="fded:f4ce:74ba:f54b::"
IP6="${IP6_108}${ID}"
SN4='32'    # IPv4 subnet
SN6='128'   # IPv6 subnet
CLIENT_IFACE='wgmarti0'
LISTEN_PORT="21168"


echo "This script will install and configure this system as a wireguard peer, $IP4,
connecting to the wireguard gateway at $PUBLIC_IP4."
read -p "Hit [Enter] to continue or Ctrl+C to cancel..."


# ------------------------------------------------------------------------------
# Ensure needed packages are installed.
# ------------------------------------------------------------------------------
installs=()
# wireguard
if [[ ! $(which wg) ]]; then
    installs+=(wireguard)
fi

# Install packages.
if [[ ${installs[@]} ]]; then
    apt-get update
    apt-get --yes install ${installs[@]}
    ret=$?
    if [[ $ret != 0 ]]; then
        echo "Failed to install the wireguard package. Please fix and try again."
        exit 1
    fi
fi

# ------------------------------------------------------------------------------
# Set the privatekey and generate the publickey.
# ------------------------------------------------------------------------------
wg_dir='/etc/wireguard'
privatekey_file="${wg_dir}/privatekey"
privatekey=''
if [[ -e $privatekey_file ]]; then
    privatekey=$(cat "$privatekey_file")
elif [[ -e ./privatekey ]]; then
    privatekey=$(cat ./privatekey)
else
    read -p "Please enter/paste this system's \"privatekey\" for wireguard: " privatekey
fi
if [[ ! $privatekey ]]; then
    echo "The \"privatekey\" for wireguard was not entered. Try again."
    exit 1
fi
mkdir -p "$wg_dir"

# Create key files.
publickey_file="${wg_dir}/publickey"
echo "$privatekey" | tee "$privatekey_file" | wg pubkey > "$publickey_file"

# ------------------------------------------------------------------------------
# Set the wireguard config.
# ------------------------------------------------------------------------------
# # wgmarti0.conf of peer
# [Interface]
# Address = 10.168.220.X/32, fded:f4ce:74ba:f54b::X/128
# PrivateKey = <PrivateKey>
#
# [Peer]
# # DO-VPS
# PublicKey = v+wQwcIwZKAgNC6P8SDLuHP6Fxm7DeIVZFPl8cSVbWU=
# EndPoint = 165.22.82.201:21168
# AllowedIPs = 10.168.220.0/24, fded:f4ce:74ba:f54b::/64
# PersistentKeepalive = 25


# Interface
client_ipv4="${IP4}/${SN4}"
client_ipv6="${IP6}/${SN6}"
client_port="$LISTEN_PORT"
cat > "${wg_dir}/${CLIENT_IFACE}.conf" << MULTILINE
[Interface]
Address = ${client_ipv4}, ${client_ipv6}
PrivateKey = $privatekey

MULTILINE

# Peer
cat >> "${wg_dir}/${CLIENT_IFACE}.conf" << MULTILINE
[Peer]
# DO-VPS
PublicKey = v+wQwcIwZKAgNC6P8SDLuHP6Fxm7DeIVZFPl8cSVbWU=
EndPoint = ${PUBLIC_IP4}:${client_port}
AllowedIPs = 10.168.220.0/24, fded:f4ce:74ba:f54b::/64
PersistentKeepalive = 25

MULTILINE

# ------------------------------------------------------------------------------
# Start and confirm the service.
# ------------------------------------------------------------------------------
svc_name="wg-quick@${CLIENT_IFACE}.service"
systemctl enable --now "$svc_name"

# Confirm wireguard configuration.
echo "Confirming the wireguard configuration..."
# ping -c3 "$serv_ipv4_priv" >/dev/null 2>&1
iface_status=$(ip -br a | grep "$CLIENT_IFACE")
# ping_ret=$?
if [[ -z $iface_status ]]; then
    echo "Error: The wireguard service $svc_name did not start properly."
    exit 1
else
    echo "The wireguard service has started properly."
fi
