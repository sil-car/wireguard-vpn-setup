#!/bin/bash

# ==============================================================================
# - This script is used to configure DO-VPS for remote access, specifically
#   to configure the wiregard server (gateway) hosted on a cloud server with a
#   public IP address.
# - The wireguard PrivateKey needs to be available, either as a file called
#   "privatekey" in the current directory, or as text to be typed/pasted during
#   script execution.
# ==============================================================================


# ------------------------------------------------------------------------------
# Ensure elevated privileges.
# ------------------------------------------------------------------------------
if [[ $(id -u) != 0 ]]; then
    sudo "${0}"
    exit $?
fi

# Set global variables
ID='1'
IP4="10.168.220.${ID}"
IP4_108="fded:f4ce:74ba:f54b::"
IP6="${IP6_108}${ID}"
SN4='24'
SN6='64'
CLIENT_IFACE='wgmarti0'
CLIENT_PORT='21168'


echo "This script will install and configure this system as a wireguard gateway, $IP4."
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
# # wgmarti0.conf of DO-VPS
# [Interface]
# Address = 10.168.220.1/24,fded:f4ce:74ba:f54b::1/64
# PrivateKey = <PrivateKey>
# ListenPort = 21168
#
# [Peer]
# # Nate-XPS
# PublicKey = AO2i+0Dn61wOeOB0TcsgVbuH7nv4sdVe8OXiKa50Oy8=
# AllowedIPs = 10.16.1.2/32,fded:f4ce:74ba:f54b::2/128
#
# [Peer]
# # marti-printer
# PublicKey = aw0dGjMjJ44uQpAGEM0x9zf5FW3X+lrPFugrPHAn4k8=
# AllowedIPs = 10.168.220.4/32,fded:f4ce:74ba:f54b::4/128
#


# Interface
client_ipv4="${IP4}/${SN4}"
client_ipv6="${IP6}/${SN6}"
cat > "${wg_dir}/${CLIENT_IFACE}.conf" << MULTILINE
[Interface]
Address = ${client_ipv4}, ${client_ipv6}
PrivateKey = $privatekey
ListenPort = $CLIENT_PORT

MULTILINE

# Peers
peers=(
    "# Nate-XPS|AO2i+0Dn61wOeOB0TcsgVbuH7nv4sdVe8OXiKa50Oy8=|10.168.220.2/32, ${IP6_108}::2/128"
    "# marti-printer|aw0dGjMjJ44uQpAGEM0x9zf5FW3X+lrPFugrPHAn4k8=|10.168.220.3/32, ${IP6_108}::3/128"
    "# moto6e|ELEKPlmiabwd+u9o8x9rh9KGDVlTzfxzB5HFWmBTOBg=|10.16.1.31/32, ${IP6_108}::31/128"
)
for p in "${peers[@]}"; do
    name=$(echo $p | cut -d'|' -f1)
    address=$(echo $p | cut -d'|' -f3)
    publickey=$(echo $p | cut -d'|' -f2)

cat >> "${wg_dir}/${CLIENT_IFACE}.conf" << MULTILINE
[Peer]
$name
AllowedIPs = $address
PublicKey = $publickey

MULTILINE
done

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

# Enable IP forwarding.
ip4='net.ipv4.ip_forward'
ip6='net.ipv6.conf.all.forwarding'
ips=( $ip4 $ip6 )
sysctl_file='/etc/sysctl.conf'
for t in ${ips[@]}; do
    if [[ $(grep "$t" "$sysctl_file" | cut -d= -f2) != '1' ]]; then
        # Replace line with "#" or with "=0"/"=1" with the full line.
        sed -i -r s'/^#?'$t'=[01]$/'$t'=1/' /etc/sysctl.conf
    fi
done
