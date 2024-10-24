#!/bin/bash

MASTER_HOSTNAME="k8s-master"

get_master_ip() {
    while true; do
        read -p "Please enter the public IP address of the master server: " MASTER_IP
        
        # Basic IP address format validation
        if [[ $MASTER_IP =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            # Validate each octet is between 0-255
            valid=true
            IFS='.' read -ra ADDR <<< "$MASTER_IP"
            for i in "${ADDR[@]}"; do
                if [ $i -lt 0 ] || [ $i -gt 255 ]; then
                    valid=false
                    break
                fi
            done
            
            if [ "$valid" = true ]; then
                export MASTER_IP
                break
            fi
        fi
        
        echo "Invalid IP address format. Please try again."
    done
}

setup_hosts() {
    sudo hostnamectl set-hostname $MASTER_HOSTNAME
    local new_entry="$MASTER_IP   $MASTER_HOSTNAME"
    echo "$new_entry" | cat - /etc/hosts > /tmp/hosts.new
    sudo mv /tmp/hosts.new /etc/hosts
}

disable_swap() {
    sudo swapoff -a
    sudo sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab
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
    sudo apt install gnupg
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

    kubectl get pods -n kube-system
    kubectl get nodes
}

install_helm() {
    curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
}

initial_k8s_setup() {
    kubectl taint nodes $MASTER_HOSTNAME node-role.kubernetes.io/control-plane:NoSchedule-
    kubectl label nodes $MASTER_HOSTNAME ingress-ready=true
}

get_master_ip
setup_hosts
disable_swap
install_containerd
install_kubernetes
init_k8s_master
setup_calico
install_helm
initial_k8s_setup
