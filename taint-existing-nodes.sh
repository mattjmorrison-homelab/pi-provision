#!/usr/bin/env bash
# k3s only applies --node-taint (set in join-node.sh) when a node registers
# for the first time — it's a no-op on already-joined nodes. This retaints
# every non-control-plane node already in the cluster. Safe to rerun.
set -euo pipefail

NODE_TAINT="${NODE_TAINT:-dedicated=pi:NoSchedule}"
export KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

for node in $(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath='{.items[*].metadata.name}'); do
  echo "Tainting $node with $NODE_TAINT..."
  kubectl taint nodes "$node" "$NODE_TAINT" --overwrite
done
