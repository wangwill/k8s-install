# k8s‑install.sh 🚀

A minimal, idempotent Bash installer for Kubernetes (v1.33+) on Debian, Ubuntu, CentOS, or Fedora, using only Google-hosted package sources and container images.

---

## 🌟 Features

* **Version flexibility**: Default to v1.33.2, override interactively or via flags.
* **Multi‑OS support**: Auto-detects `apt-get`, `yum`, or `dnf`.
* **Containerd first**: Installs and configures Containerd with systemd cgroup support.
* **K8s components**: Installs `kubelet`, `kubeadm`, and `kubectl` from `pkgs.k8s.io` or `packages.cloud.google.com`.
* **Pre‑pull images**: Uses `ctr` to fetch required images from `registry.k8s.io`.
* **Master & worker**: Interactive or flag-driven selection for master initialization (with flannel or calico CNI) or worker join.
* **Robust logging**: Streams verbose output to both console and `/var/log/k8s-install.log`.
* **Idempotent & safe**: Checks for root, CPU cores (master), SELinux, swap, and sysctl settings.

---

## 🚀 Quick Start

```bash
# Clone the repo
git clone https://github.com/your-org/k8s-install-script.git
cd k8s-install-script

# Make it executable
chmod +x install-k8s.sh

# Run (interactive)
sudo bash ./install-k8s.sh

# Or run non-interactive (example for master + calico):
sudo bash ./install-k8s.sh --version 1.34.0 --calico --hostname my-master
```

---

## 📋 Usage

```bash
install-k8s.sh [options]
```

| Option              | Description                                          |
| ------------------- | ---------------------------------------------------- |
| `-v, --version <v>` | Install Kubernetes version (e.g. `1.33.2`).          |
| `--flannel`         | Set up as master with Flannel CNI (non-interactive). |
| `--calico`          | Set up as master with Calico CNI (non-interactive).  |
| `--hostname <name>` | Set node hostname (underscores → hyphens).           |
| `-h, --help`        | Show this help and exit.                             |

## ⚙️ Configuration & Flow

1. **Initialization**:

   * Validate Bash shell and root privileges.
   * Redirect `stdout`/`stderr` to `/var/log/k8s-install.log`.
   * Enable shell debugging.
2. **Interactive Prompts** (if no flags):

   * Accept or override Kubernetes version.
   * Choose node role (master/worker).
   * If master, select CNI (`flannel` or `calico`).
3. **System Checks**:

   * Detect OS & package manager.
   * Verify CPU cores for master nodes.
   * Adjust hostname, disable SELinux & swap, apply sysctl.
4. **Install Dependencies**:

   * `curl`, `containerd`, `apt-transport-https` (for APT), etc.
5. **Containerd Setup**:

   * Generate `config.toml` with `SystemdCgroup=true`.
   * Enable & start `containerd`.
6. **Kubernetes Installation**:

   * Add GPG keys & apt/yum repos.
   * Install `kubelet`, `kubeadm`, `kubectl` at specified version.
   * Hold APT packages or enable services on RPM.
   * Enable bash completion.
7. **Image Pulling**:

   * Pre-pull K8s images via `ctr` under the `k8s.io` namespace.
8. **Cluster init/join**:

   * Master: run `kubeadm init`, apply CNI.
   * Worker: expect `kubeadm join` tokens from master.

## 🔧 Customization

Edit top‑of‑script variables:

```bash
auto_version="1.33.2"
LOG_FILE="/var/log/k8s-install.log"
# Color codes, debug flags, defaults
```
