# Auto Wireguard

**Auto WireGuard** is a Bash-based tool for installing, configuring, and managing WireGuard VPN servers and clients.  
It provides an interactive menu to automate routine tasks like installation, server setup, client creation, and cleanup.  

---

## ✨ Features

- 🔎 **Auto-detects package manager** (`apt`, `dnf`, `yum`, `pacman`, `zypper`, `apk`, `emerge`)  
- ⚡ **One-click installation** of WireGuard and dependencies  
- 🔑 **Automatic key generation** for server and clients  
- 🖧 **Server setup wizard** with IP range, port, interface, and DNS configuration  
- 👤 **Add new clients interactively** (with SSH-based config transfer)  
- 📝 **Generates ready-to-use client config files**  
- 🔄 **Reloads WireGuard without downtime** when adding clients  
- 🔐 **Sets correct permissions** on private keys  
- 🧹 **Remove WireGuard** and clean up configs completely  

---

## 📥 Installation

Clone the repository and enter the directory:

```bash
git clone https://github.com/Morgein/auto-wireguard.git
cd wireguard-manager
```

Make scripts executable:

```bash
chmod +x main.sh lib.sh
```

Run the tool:

```bash
./main.sh
```

---

## 🖥️ Usage

When you run `main.sh`, you’ll see an interactive menu:

```
================ Wireguard Management Menu ==============
1) Install Wireguard
2) Setup Wireguard Server
3) Add New Client (over SSH)
4) Exit
```

- **1)** Install WireGuard (auto-detects your distro’s package manager).  
- **2)** Setup server (`wg0.conf` will be generated).  
- **3)** Add a new client and transfer its config via SSH.  
- **4)** Exit the menu.  

---

## 📂 Project Structure

```
.
├── main.sh   # Entry point with interactive menu
└── lib.sh    # Library with functions (install, setup, client mgmt, cleanup)
```

---

## 🧹 Removal

You can fully remove WireGuard from your system by selecting the **cleanup option** in the menu, which:  
- Stops and disables the WireGuard service  
- Removes configs and keys from `/etc/wireguard/`  
- Optionally uninstalls WireGuard packages  

---

## ⚠️ Disclaimer

This project is provided *as is* without any warranty.  
Always review scripts before running them in production.
