#!/bin/env bash
set -euo pipefail

LIB_FILE="./lib.sh"

if [[ ! -f "$LIB_FILE" ]]; then
    echo "[!] lib.sh not found!"
    exit 1
fi

source "$LIB_FILE"


main_menu() {
    echo ""
    echo "================ Wireguard Management Menu ================"
    echo "1) Install Wireguard"
    echo "2) Setup Wireguard Server"
    echo "3) Add New Client (over SSH)"
    echo "4) Exit"
    read -p "Choose an option [1-4]: " choice

    case "$choice" in
        1) 
            checking_root
            checking_pm
            install_wireguard
            ;;
        2)
            checking_root
            setup_server
            ;;
        3) 
            checking_root
            add_client
            ;;
        4)
            echo "Exiting..."
            exit 0
            ;;
        *)
            echo "[!] Invalid option. Please choose a number between 1 and 4."
            ;;
    esac

    main_menu
}


main_menu

