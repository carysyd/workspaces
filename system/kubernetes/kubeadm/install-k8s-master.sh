#!/usr/bin/env bash

# Install kubeadm, kubelet and kubectl
apt-get update && apt-get install -y apt-transport-https curl
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
cat <<EOF >/etc/apt/sources.list.d/kubernetes.list
deb http://apt.kubernetes.io/ kubernetes-xenial main
EOF
apt-get update
apt-get install -y kubelet kubeadm kubectl

# kubeadm enforces swap off before initializing K8s, also permanently disable swap partition
sudo swapoff -a
sed -i 's/^.*swap.img/#&/' /etc/fstab

# Initialize master node
kubeadm init --pod-network-cidr=192.168.0.0/16

# Allow non-root user to use kubtctl
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

# Install Pod Network add-on, at the end of this line, it would print the join node commands
kubectl apply -f https://docs.projectcalico.org/v3.9/manifests/calico.yaml

# An networking step I found needed on Kubernetes Worker Nodes
# Make a backup of the resolve.conf file, then use the systemd one
mv /etc/resolv.conf /etc/resolv.conf.orig
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf