#!/usr/bin/env bash
# Author: Jrohy (modified)
# Description: Simplified Kubernetes installation script using only Google sources (v1.33+)

set -euo pipefail

# Ensure script is run with Bash
if [ -z "${BASH_VERSION:-}" ]; then
    echo "Error: Please run this script with bash."
    exit 1
fi

# Redirect all output (stdout and stderr) to both console and log file
LOG_FILE="/var/log/k8s-install.log"
mkdir -p "$(dirname "$LOG_FILE")"
exec > >(tee -i "$LOG_FILE")
exec 2>&1

# Enable shell debugging to trace execution
set -x

echo "Starting Kubernetes installation script..."
echo "Debug: Logging to $LOG_FILE"

####### Color codes #######
red="31m"
green="32m"
yellow="33m"
blue="36m"

color_echo() {
    echo -e "\033[$1${@:2}\033[0m"
}

run_command() {
    echo
    echo -e "\033[32m$1\033[0m"
    bash -c "$1"
}

set_hostname() {
    local hostname=$1
    if [[ $hostname =~ '_' ]]; then
        color_echo $yellow "hostname can't contain '_' character, converting to '-'..."
        hostname=${hostname//_/-}
    fi
    echo "Setting hostname to: $(color_echo $blue $hostname)"
    echo "127.0.0.1 $hostname" >> /etc/hosts
    run_command "hostnamectl --static set-hostname $hostname"
}

####### Parse parameters #######
k8s_version="1.33.2"
is_master=0
network=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --hostname)
            set_hostname "$2"
            shift
            ;;
        -v|--version)
            k8s_version="${2#v}"
            echo "Preparing to install Kubernetes version: $(color_echo $green $k8s_version)"
            shift
            ;;
        --flannel)
            network="flannel"
            is_master=1
            echo "Using Flannel network, marking as master node"
            ;;
        --calico)
            network="calico"
            is_master=1
            echo "Using Calico network, marking as master node"
            ;;
        -h|--help)
            cat << EOF
Usage: $0 [options]

Options:
  --hostname [name]    Set the node hostname
  -v, --version [ver]  Install specific Kubernetes version (e.g. 1.33.0)
  --flannel            Use Flannel CNI and initialize as master
  --calico             Use Calico CNI and initialize as master
  -h, --help           Display this help message
EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            ;;  
    esac
    shift
done

####### System checks #######
check_sys() {
    color_echo $yellow "Debug: Running system checks..."
    [ $(id -u) -ne 0 ] && { color_echo $red "Error: run as root"; exit 1; }
    if [[ $(nproc) -eq 1 && $is_master -eq 1 ]]; then
        color_echo $red "Master node requires at least 2 CPU cores"; exit 1
    fi
    if [[ -f /etc/redhat-release ]]; then
        if grep -q Fedora /etc/redhat-release; then
            os='Fedora'; pkg_mgr='dnf'
        else
            os='CentOS'; pkg_mgr='yum'
        fi
    elif grep -q Debian /etc/issue; then
        os='Debian'; pkg_mgr='apt-get'
    elif grep -q Ubuntu /etc/issue; then
        os='Ubuntu'; pkg_mgr='apt-get'
    else
        color_echo $red "Unsupported OS"; exit 1
    fi
    [[ "$(cat /etc/hostname)" =~ '_' ]] && set_hostname "$(cat /etc/hostname)"
    color_echo $green "Debug: System checks passed. OS=$os, pkg_mgr=$pkg_mgr"
}

####### Install dependencies #######
install_deps() {
    color_echo $yellow "Debug: Installing dependencies..."
    if [[ $pkg_mgr == "apt-get" ]]; then
        run_command "${pkg_mgr} update"
        run_command "${pkg_mgr} install -y apt-transport-https ca-certificates curl gpg containerd"
    else
        run_command "${pkg_mgr} install -y bash-completion curl containerd"
    fi
    color_echo $green "Debug: Dependencies installed"
}

####### Containerd setup #######
setup_containerd() {
    color_echo $yellow "Debug: Setting up Containerd..."
    mkdir -p /etc/containerd
    containerd config default > /etc/containerd/config.toml
    sed -i 's/\(SystemdCgroup = \)false/\1true/' /etc/containerd/config.toml
    systemctl enable --now containerd
    color_echo $green "Debug: Containerd setup complete"
}

####### Kernel & Firewall #######
prepare_sysctl() {
    color_echo $yellow "Debug: Applying kernel & firewall settings..."
    if [[ $os =~ ^(CentOS|Fedora)$ ]]; then
        systemctl disable --now firewalld || true
        cat <<EOF > /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
        sysctl --system
    fi
    if [ -f /etc/selinux/config ]; then
        sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
        setenforce 0 || true
    fi
    swapoff -a
    sed -i '/ swap / s/^/#/' /etc/fstab
    color_echo $green "Debug: Kernel & firewall settings applied"
}

####### Install Kubernetes (v1.33) #######
install_k8s() {
    color_echo $yellow "Debug: Installing Kubernetes v${k8s_version}..."
    if [[ $pkg_mgr == "apt-get" ]]; then
        run_command "mkdir -p -m 755 /etc/apt/keyrings"
        run_command "curl -fsSL https://pkgs.k8s.io/core:/stable:/v${k8s_version%.*}/deb/Release.key | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg"
        echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${k8s_version%.*}/deb/ /" | tee /etc/apt/sources.list.d/kubernetes.list
        run_command "${pkg_mgr} update"
        run_command "${pkg_mgr} install -y kubelet=${k8s_version}-* kubeadm=${k8s_version}-* kubectl=${k8s_version}-*"
        run_command "apt-mark hold kubelet kubeadm kubectl"
    else
        cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes Repo
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64/
gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
EOF
        run_command "${pkg_mgr} install -y kubelet-$k8s_version kubeadm-$k8s_version kubectl-$k8s_version"
        systemctl enable --now kubelet
    fi
    grep -qxF "source <(kubectl completion bash)" ~/.bashrc || echo "source <(kubectl completion bash)" >> ~/.bashrc
    grep -qxF "source <(kubeadm completion bash)" ~/.bashrc || echo "source <(kubeadm completion bash)" >> ~/.bashrc
    color_echo $green "Debug: Kubernetes installation complete"
}

####### Pull images via Containerd #######
pull_images() {
    color_echo $yellow "Debug: Pulling images from registry.k8s.io via containerd"
    images=( $(kubeadm config images list) )
    for img in "${images[@]}"; do
        run_command "ctr -n k8s.io i pull $img"
    done
    color_echo $green "Debug: Image pull complete"
}

####### Init/Join cluster #######
run_k8s() {
    color_echo $yellow "Debug: Preparing cluster init/join..."
    if [[ $is_master -eq 1 ]]; then
        init_cmd="kubeadm init --kubernetes-version=${k8s_version}"
        [[ $network == "flannel" ]] && init_cmd+=" --pod-network-cidr=10.244.0.0/16"
        [[ $network == "calico" ]]  && init_cmd+=" --pod-network-cidr=192.168.0.0/16"
        run_command "$init_cmd"
        run_command "mkdir -p \$HOME/.kube && cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config && chown \$(id -u):\$(id -g) \$HOME/.kube/config"
        if [[ $network == "flannel" ]]; then
            run_command "kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml"
        else
            run_command "kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml"
        fi
        color_echo $green "Debug: Cluster initialized"
    else
        color_echo $yellow "Worker node: run 'kubeadm join' from master to join cluster"
    fi
}

main() {
    echo "Debug: Entering main()"
    check_sys
    install_deps
    prepare_sysctl
    setup_containerd
    install_k8s
    pull_images
    run_k8s
    echo "Debug: Script completed successfully"
}

# Invoke main with all passed arguments
main "$@"
