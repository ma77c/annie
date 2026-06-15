#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG="${KUBECONFIG:-${HOME}/.kube/annie-k3s.yaml}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -f "${KUBECONFIG}" ]; then
  echo "Error: Kubeconfig not found at ${KUBECONFIG}"
  echo "Run ./k3s/setup-k3s.sh first."
  exit 1
fi

echo "==> Verifying cluster connectivity..."
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo "Error: Cannot connect to cluster. Check that K3s is running on the remote machine."
  exit 1
fi

echo "==> Applying namespace..."
kubectl apply -f "${SCRIPT_DIR}/manifests/namespace.yaml"

echo "==> Applying manifests..."
kubectl apply -f "${SCRIPT_DIR}/manifests/"

echo "==> Waiting for Ollama deployment to be ready..."
kubectl -n annie rollout status deployment/ollama --timeout=120s

NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')

echo ""
echo "Done! Ollama is running."
echo ""
echo "Access from any machine on your LAN:"
echo "  http://${NODE_IP}:31434"
echo ""
echo "Pull a model:"
echo "  curl http://${NODE_IP}:31434/api/pull -d '{\"name\":\"qwen2.5-coder:7b\"}'"
