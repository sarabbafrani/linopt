# ⚙️ LinOpt: Linux Server Performance Optimizer

`linopt.sh` is a one-click, interactive optimization tool for Linux servers focused on:
- Network stack tuning
- NGINX server performance
- Kernel-level system tweaks
- File descriptor limits
- And more…

This tool is ideal for sysadmins, developers, and server enthusiasts who want **maximum performance and minimal hassle**.

---

## ✨ Features

- ✅ Auto-check system settings vs optimized values
- 🧠 Advanced sysctl kernel network tuning
- 🚀 NGINX optimization (keepalive, gzip, buffers)
- 🔧 File descriptor + systemd limits
- 🧬 Automatic XanMod Kernel installation
- 🔍 System verification and backup before changes
- 📦 Fully portable with one-line installer

---

## 📥 Installation

Run the script on any supported Linux system (Ubuntu/Debian):

```bash
bash <(curl -s https://raw.githubusercontent.com/sarabbafrani/linopt/main/linopt.sh)

