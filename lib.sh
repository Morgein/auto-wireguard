#!/bin/env bash

#This script is a lib for the main script and the lib contains all of functions which are needed for the main script
set -euo pipefail


# -------- logging --------
log() { echo "[*] $*"; }
ok()  { echo "[OK] $*";  }
die() { echo "[!] $*" >&2; exit 1; }



checking_root() {
	if [[ $EUID -ne 0  ]]; then 
		die "Please run the script as root"
	fi
}

checking_pm() {
	log "Detecting packet manager"
	local pms=("apt" "dnf" "yum" "pacman" "zypper" "apk" "emerge")
	for pm in "${pms[@]}"; do
		if command -v "$pm" >/dev/null 2>&1; then
			PKG_MGR="$pm"
			ok "Detected packet manager: $pm" 
			return 0
		fi
	done
	die "Unupported packet manager"	
}


install_wireguard(){
	log "Installing wireguard"
	case $PKG_MGR in
		apt)
			apt update -y && apt upgrade -y
			DEBIAN_FRONTEND=noninteractive apt install -y wireguard iproute2 qrencode || die "Failed to install packets" 
			ok "Wireguard has been install successfuly" ;;
		dnf)
			dnf update -y
			dnf install -y wireguard-tools qrencode iproute2 || die "Failed to install packets"
			ok "Wireguard has been installed succesfuly" 
			;;
		yum)
			yum update -y
			yum install -y epel-release || die "Failed to install packets"
			yum install -y wireguard-tools qrencode iproute2 || die "Failed to install packets"
			ok "Wireguard has been installed succesfuly" 
			;;
		pacman)
			pacman -Syu --noconfirm
			pacman -S --noconfirm wireguard-tools qrencode iproute2 || die "Failed to install packets"
			ok "Wireguard has been installed succesfuly" 
			;;
		zypper)
			zypper refresh
			zypper update -y
			zypper install -y wireguard-tools qrencode iproute2 || die "Failed to install packets"
			ok "Wireguard has been installed succesfuly" 
			;;
		apk)
			apk update
			apk add wireguard-tools qrencode iproute2 || die "Failed to install packets"
			ok "Wireguard has been installed succesfuly" 
			;;
		emerge)
			emerge --sync
			emerge --update --deep --with-bdeps=y @world
			emerge net-vpn/wireguard-tools app-misc/qrencode net-misc/iproute2 || die "Failed to install packets"
			ok "Wireguard has been installed succesfuly" 
			;;
		*) die "Packet manager $pm is not supported" 
		;;
	esac
	ok "Wireguard has been installed successfuly" 
}

generate_keys(){
	local CONFIG_DIR="/etc/wireguard"
	local SHARE_DIR="/etc/wireguard/share"
	local client_name="${1-}"
	local client_dir="$SHARE_DIR/$client_name"
	
	mkdir -p "$SHARE_DIR" || die "Failed to create directory $SHARE_DIR"

	if [[ ! -f "$CONFIG_DIR/server_private.key" || ! -f "$SHARE_DIR/server_public.key" ]]; then
		log "Generating keys for server"
		wg genkey | tee $CONFIG_DIR/server_private.key | wg pubkey > $SHARE_DIR/server_public.key || die "Failed to generate server keys"
		chmod 600 "$CONFIG_DIR/server_private"
	else
		log "Keys for server already exist, skipping..."
	fi

	if [[ -n "$client_name" ]]; then
		log "Generating keys for $client_name"
		mkdir -p "$client_dir" || die "Failed to create directory $client_dir"
		chmod 700 "$client_dir"
		

		if [[ -f "$client_dir/client_private.key" || -f "$client_dir/client_public.key" ]]; then
			die "Keys for client $client_name already exist, please choose another name or delete the existing keys"
		fi


		wg genkey | tee $client_dir/client_private.key | wg pubkey > $client_dir/client_public.key || die "Failed to generate keys"
		chmod 600 "$client_dir/client_private.key"
		client_pubkey=$(< $client_dir/client_public.key)
		client_privkey=$(< $client_dir/client_private.key)
		ok "Keys have been generated successfuly"
	fi
}


setup_server(){
	log "Setting up wireguard server"
	local WG_PORT=51820
	local CONFIG_DIR="/etc/wireguard"
	local SHARE_DIR="$CONFIG_DIR/share"
	local METADATA_FILE="$SHARE_DIR/server_metadata.conf"
	mkdir -p $SHARE_DIR || die "Failed to create directory $SHARE_DIR"

	log "Creating config"
	generate_keys


	read -p "Please enter the range ip addresses(by default 10.8.0.0)" RANGE_IP
	RANGE_IP=${RANGE_IP:-10.8.0.0}


	read -p "Please enter the Server's IP address(by default 10.8.0.1):" SERVER_VPN_IP
	SERVER_VPN_IP=${SERVER_VPN_IP:-10.8.0.1}

	read -p "Please enter the VPN subnet (by default /24)" VPN_SUBNET
	VPN_SUBNET=${VPN_SUBNET:-24}

	read -p "Please enter the interface that will be used by wireguard(default is eth0):" INTERFACE
	INTERFACE=${INTERFACE:-eth0}

	read -p "Please enter the VPN port(default is 51820):" VPN_PORT
	VPN_PORT=${VPN_PORT:-$WG_PORT}
		
	read -p "Please enter the DNS ip address(by default 1.1.1.1)" DNS_IP
	DNS_IP=${DNS_IP:-1.1.1.1}
	
	local server_privkey
    server_privkey=$(< "$CONFIG_DIR/server_private.key")

	log "Generating config file /etc/wireguard/wg0.conf"
sudo bash -c "cat > $CONFIG_DIR/wg0.conf" <<EOF
[Interface]
    PrivateKey = $server_privkey
    Address = $SERVER_VPN_IP/$VPN_SUBNET
    ListenPort = $VPN_PORT
    SaveConfig = true
	PostUp = iptables -t nat -A POSTROUTING -s $RANGE_IP -o $INTERFACE -j MASQUERADE
	PostDown = iptables -t nat -D POSTROUTING -s $RANGE_IP -o $INTERFACE -j MASQUERADE
EOF

	ok "Config file has been generated successfuly"

	log "Saving server metadata for clients"

	cat > $METADATA_FILE <<EOF
SERVER_IP=$SERVER_VPN_IP
SERVER_PORT=$VPN_PORT
DNS_IP=$DNS_IP
SERVER_MASK=$VPN_SUBNET
EOF

	ok "Server metadata save to $METADATA_FILE"

echo "Do you want to turn on IP forwarding? (yes/no)"
select yn in "yes" "no"; do
    case $yn in
        yes ) 
            sysctl -w net.ipv4.ip_forward=1 || die "Failed to enable IP forwarding"
			grep -q "net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
            ok "IP forwarding has been enabled"
            break ;;
        no ) 
            echo "Skipping enabling IP forwarding"
            break ;;
        * ) 
            echo "Please choose 1 or 2."
            ;;
    esac
done


	log "Starting and enabling Wireguard service"
	sudo systemctl enable wg-quick@wg0 || die "Failed to enable wg-quick@wg0"
	sudo systemctl start wg-quick@wg0 || die "Failed to start wg-quick@wg0"
	ok "wg-quick@wg0 has been started successfuly"

}


add_client() {
	local CONFIG_DIR="/etc/wireguard"
	local SHARE_DIR="$CONFIG_DIR/share"
	local METADATA_FILE="$SHARE_DIR/server_metadata.conf"


	if [[ ! -f "$METADATA_FILE" ]]; then
		die "Server metadata file not found, please make sure that the server is set up correctly"
	fi


	source "$METADATA_FILE"

	read -p "Please enter name for the new client: " CLIENT_NAME
	local CLIENT_DIR="$SHARE_DIR/$CLIENT_NAME"
	

	if [[ -d "$CLIENT_DIR" ]]; then
		die "Client '$CLIENT_NAME' already exist, please choose another name or delete the existing directory"
	fi


	read -p "Please enter the VPN ip address for the client: " CLIENT_IP

	generate_keys "$CLIENT_NAME"

	local CLIENT_PRIVKEY=$(< "$CLIENT_DIR/client_private.key")
	local CLIENT_PUBKEY=$(< "$CLIENT_DIR/client_public.key")
	local SERVER_PUBKEY=$(< "$SHARE_DIR/server_public.key")


	cat > "$CLIENT_DIR/client.conf" <<EOF
[Interface]
Address = $CLIENT_IP/$SERVER_MASK
PrivateKey = $CLIENT_PRIVKEY
DNS = $DNS_IP

[Peer]
PublicKey = $SERVER_PUBKEY
Endpoint = $SERVER_IP:$SERVER_PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

	ok "Client config created at $CLIENT_DIR/client.conf"

	if grep -q "$CLIENT_PUBKEY" "$CONFIG_DIR/wg0.conf"; then
		log "Client $CLIENT_NAME already exists in server config, skipping..."
	else
		log "Adding client to server config"
				echo "
[Peer]
PublicKey = $CLIENT_PUBKEY
AllowedIPs = $CLIENT_IP/32
" >> "$CONFIG_DIR/wg0.conf"
		ok "Client '$CLIENT_NAME' added to wg0.conf"
	fi

	wg addconf wg0 <(wg-quick strip wg0)

	ok "WireGuard configuration reloaded"


	read -p "Enter the IP address or hostname client: " CLIENT_HOST
	read -p "Enter the username on the client (e.g, user): " CLIENT_USER

	echo "Where should the client config be saved?"
	echo "1) ~/wireguard/ (default) — recommended for desktop/laptop/mobile users"
	echo "2) /etc/wireguard/ — required for system-level WireGuard clients"
	read -p "Select destination path [1]: " dest_choice

case "$dest_choice" in
	2) CLIENT_DEST_PATH="/etc/wireguard/" ;;
	*) CLIENT_DEST_PATH="~/wireguard/" ;;
esac

	if ! command -v scp &>/dev/null; then
		die "scp is not installed. Please install openssh-client."
	fi

	log "Installing wireguard-tools and iptables on client $CLIENT_USER@$CLIENT_HOST"
	log "You may be prompted for the user's password on the client machine."
	
	ssh -t "$CLIENT_USER@$CLIENT_HOST" 'set -e
if command -v apt >/dev/null 2>&1; then
  sudo apt update && sudo apt install -y wireguard-tools iptables
elif command -v dnf >/dev/null 2>&1; then
  sudo dnf install -y wireguard-tools iptables
elif command -v yum >/dev/null 2>&1; then
  sudo yum install -y wireguard-tools iptables
elif command -v pacman >/dev/null 2>&1; then
  sudo pacman -S --noconfirm wireguard-tools iptables
elif command -v zypper >/dev/null 2>&1; then
  sudo zypper install -y wireguard-tools iptables
elif command -v apk >/dev/null 2>&1; then
  sudo apk add wireguard-tools iptables
else
  echo "Unknown package manager on client" >&2; exit 1
fi' || die "Failed to install wireguard-tools and iptables on client"




	log "Creating destination directory on client $CLIENT_USER@$CLIENT_HOST:$CLIENT_DEST_PATH"
	ssh -t "$CLIENT_USER@$CLIENT_HOST" "mkdir -p $CLIENT_DEST_PATH && chmod 700 $CLIENT_DEST_PATH" || die "Failed to create directory on client"

	log "Transferring client config to $CLIENT_USER@$CLIENT_HOST:$CLIENT_DEST_PATH"
	scp "$CLIENT_DIR/client.conf" "$CLIENT_USER@$CLIENT_HOST:$CLIENT_DEST_PATH" || die "Failed to transfer client config"
	ok "Client config transferred successfully to $CLIENT_USER@$CLIENT_HOST:$CLIENT_DEST_PATH"
}


remove_wireguard_server() {
	local CONFIG_DIR="/etc/wireguard"
	local IFACE
	read -p "Enter the WireGuard interface to remove (default is wg0): " IFACE
	IFACE=${IFACE:-wg0}

	log "Stopping WireGuard interface on server: $IFACE"

	wg-quick down "$IFACE" || die "Failed to bring down interface $IFACE"



	if command -v systemctl >/dev/null 2>&1; then
		log "Disabling WireGuard service"
		systemctl stop "wg-quick@$IFACE" || die "Failed to stop wg-quick@$IFACE"
		systemctl disable "wg-quick@$IFACE" || die "Failed to disable wg-quick@$IFACE"
	fi	

	
	if [[ -f "$CONFIG_DIR/${IFACE}.conf" ]]; then
        # Nothing to do: PostDown should have handled it
        :
    else
        # Try to detect a MASQUERADE rule referencing 10.0/10.8… ranges and delete by number
        if command -v iptables >/dev/null 2>&1; then
            log "Attempting to clean NAT MASQUERADE rules (best-effort)"
            # List with numbers and delete all MASQUERADE rules referencing wg/cidr
            while read -r num rest; do
                [[ -z "$num" ]] && break
                iptables -t nat -D POSTROUTING "$num" || true
            done < <(iptables -t nat -L POSTROUTING --line-numbers -n | awk '/MASQUERADE/ {print $1}' | tac)
        fi
    fi

	echo "Disable IPv4 forwarding (set net.ipv4.ip_forward=0)?"
    select yn in "yes" "no"; do
        case "$yn" in
            yes)
                sysctl -w net.ipv4.ip_forward=0 || true
                # remove exact line if present
                sed -i '/^net\.ipv4\.ip_forward=1$/d' /etc/sysctl.conf || true
                ok "IPv4 forwarding disabled"
                break ;;
            no) break ;;
        esac
    done


	log "Removing WireGuard configs and keys from $CONFIG_DIR"
    rm -rf "$CONFIG_DIR" || die "Failed to remove $CONFIG_DIR"
    ok "Configs removed"

	echo "Uninstall WireGuard packages from server?"
    select yn in "yes" "no"; do
        case "$yn" in
            yes)
                checking_pm || true
                case "${PKG_MGR:-unknown}" in
                    apt)    apt remove -y --purge wireguard wireguard-tools || true ;;
                    dnf)    dnf remove -y wireguard-tools wireguard || true ;;
                    yum)    yum remove -y wireguard-tools wireguard || true ;;
                    zypper) zypper -n remove wireguard-tools wireguard || true ;;
                    apk)    apk del wireguard-tools || true ;;
                    pacman) pacman -Rns --noconfirm wireguard-tools wireguard 2>/dev/null || pacman -Rns --noconfirm wireguard-tools || true ;;
                    *)      log "Unknown package manager; skip uninstall" ;;
                esac
                ok "Packages removal attempted"
                break ;;
            no) break ;;
        esac
    done

    ok "Server cleanup completed"

}

