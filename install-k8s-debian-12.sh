#!/bin/bash

MASTER_HOSTNAME="k8s-master"
MASTER_IP="95.174.93.15"

setup_hosts() {
    sudo hostnamectl set-hostname $MASTER_HOSTNAME
    echo "$MASTER_IP   $MASTER_HOSTNAME" | sudo tee -a /etc/hosts
}

disable_swap() {
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
}

install_ufw() {
    if ! command -v ufw &> /dev/null
    then
        sudo apt update
        sudo apt install -y ufw
    fi
}

setup_firewall() {
    install_ufw
    sudo ufw allow 6443/tcp
    sudo ufw allow 2379/tcp
    sudo ufw allow 2380/tcp
    sudo ufw allow 10250/tcp
    sudo ufw allow 10251/tcp
    sudo ufw allow 10252/tcp
    sudo ufw allow 10255/tcp
    sudo ufw reload
}

install_containerd() {
    sudo apt update
    sudo apt install -y containerd
    sudo modprobe overlay
    sudo modprobe br_netfilter

    cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

    cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-k8s.conf
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    sudo sysctl --system
    containerd config default | sudo tee /etc/containerd/config.toml >/dev/null 2>&1
    sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo systemctl enable containerd
}

install_kubernetes() {
    sudo apt update
    sudo apt install -y apt-transport-https ca-certificates curl
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
    echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

    sudo apt update
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
}

init_k8s_master() {
    cat <<EOF | sudo tee kubelet.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: "1.30.0"
controlPlaneEndpoint: "$MASTER_HOSTNAME"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
EOF

    sudo kubeadm init --config kubelet.yaml

    mkdir -p $HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
    sudo chown $(id -u):$(id -g) $HOME/.kube/config

    kubectl get nodes
    kubectl cluster-info
}

setup_calico() {
    kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/calico.yaml

    sudo ufw allow 179/tcp
    sudo ufw allow 4789/udp
    sudo ufw allow 51820/udp
    sudo ufw allow 51821/udp
    sudo ufw reload

    kubectl get pods -n kube-system
    kubectl get nodes
}

setup_hosts
disable_swap
setup_firewall
install_containerd
install_kubernetes
init_k8s_master
setup_calico