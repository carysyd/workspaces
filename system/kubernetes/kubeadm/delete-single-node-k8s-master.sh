#!/usr/bin/env bash

LOCAL_SERVER_NODE=cary-ubuntu-server

kubectl drain $LOCAL_SERVER_NODE --delete-local-data --force --ignore-daemonsets
kubectl delete node $LOCAL_SERVER_NODE

kubeadm reset
