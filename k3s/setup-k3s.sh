#!/usr/bin/env bash
set -euo pipefail

KUBECONFIG_PATH="${HOME}/.kube/annie-k3s.yaml"

if [ -z "${1:-}" ]; then
  echo "Usage: $0 user@<remote-ip> [--gpu]"
  echo "Example: $0 ma77c@192.168.1.50"
  echo "         $0 ma77c@192.168.1.50 --gpu"
  exit 1
fi

REMOTE_HOST="$1"
REMOTE_IP="${REMOTE_HOST##*@}"
ENABLE_GPU="${2:-}"

echo "==> Installing K3s on ${REMOTE_HOST}..."
ssh "${REMOTE_HOST}" "curl -sfL https://get.k3s.io | sh -"

echo "==> Creating model storage directory..."
ssh "${REMOTE_HOST}" "sudo mkdir -p /var/lib/annie/ollama"

echo "==> Waiting for K3s node to become Ready..."
TIMEOUT=120
ELAPSED=0
while true; do
  STATUS=$(ssh "${REMOTE_HOST}" "sudo k3s kubectl get nodes --no-headers 2>/dev/null | awk '{print \$2}'" || true)
  if [ "${STATUS}" = "Ready" ]; then
    echo "    Node is Ready."
    break
  fi
  if [ "${ELAPSED}" -ge "${TIMEOUT}" ]; then
    echo "Error: Timed out waiting for node to become Ready."
    exit 1
  fi
  sleep 5
  ELAPSED=$((ELAPSED + 5))
done

echo "==> Copying kubeconfig to ${KUBECONFIG_PATH}..."
mkdir -p "$(dirname "${KUBECONFIG_PATH}")"
ssh "${REMOTE_HOST}" "sudo cat /etc/rancher/k3s/k3s.yaml" > "${KUBECONFIG_PATH}"
sed -i "s/127.0.0.1/${REMOTE_IP}/g" "${KUBECONFIG_PATH}"
chmod 600 "${KUBECONFIG_PATH}"

if [ "${ENABLE_GPU}" = "--gpu" ]; then
  echo ""
  echo "==> Setting up GPU support..."

  HAS_GPU=$(ssh "${REMOTE_HOST}" "lspci | grep -ci nvidia" || true)
  if [ "${HAS_GPU}" -eq 0 ]; then
    echo "Warning: No NVIDIA GPU detected on ${REMOTE_IP}. Skipping GPU setup."
  else
    echo "    NVIDIA GPU detected."

    DRIVER_VERSION=$(ssh "${REMOTE_HOST}" "nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null || echo 0")
    DRIVER_MAJOR="${DRIVER_VERSION%%.*}"
    if [ "${DRIVER_MAJOR}" -lt 570 ]; then
      echo "    Driver ${DRIVER_VERSION} is too old (need 570+). Installing nvidia-driver-570..."
      ssh "${REMOTE_HOST}" "sudo apt-get update -qq && sudo apt-get install -y -qq nvidia-driver-570"
      echo "    Driver installed. A reboot is required."
      echo "    Rebooting ${REMOTE_IP}..."
      ssh "${REMOTE_HOST}" "sudo reboot" || true
      echo "    Waiting for ${REMOTE_IP} to come back..."
      sleep 10
      ELAPSED=0
      while ! ssh -o ConnectTimeout=3 -o BatchMode=yes "${REMOTE_HOST}" "echo up" &>/dev/null; do
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [ "${ELAPSED}" -ge 180 ]; then
          echo "Error: Timed out waiting for reboot."
          exit 1
        fi
      done
      echo "    ${REMOTE_IP} is back."
      echo "    Waiting for K3s to become Ready after reboot..."
      ELAPSED=0
      while true; do
        STATUS=$(KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' || true)
        if [ "${STATUS}" = "Ready" ]; then
          break
        fi
        sleep 5
        ELAPSED=$((ELAPSED + 5))
        if [ "${ELAPSED}" -ge 120 ]; then
          echo "Error: K3s not ready after reboot."
          exit 1
        fi
      done
    fi

    echo "    Installing nvidia-container-toolkit..."
    ssh "${REMOTE_HOST}" 'curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg 2>/dev/null; curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | sed "s#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g" | sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list > /dev/null; sudo apt-get update -qq && sudo apt-get install -y -qq nvidia-container-toolkit'

    echo "    Configuring NVIDIA container runtime for K3s..."
    ssh "${REMOTE_HOST}" "sudo nvidia-ctk runtime configure --runtime=containerd"
    ssh "${REMOTE_HOST}" "sudo nvidia-ctk cdi generate --output=/etc/cdi/nvidia.yaml"

    echo "    Setting NVIDIA as default containerd runtime..."
    ssh "${REMOTE_HOST}" 'sudo mkdir -p /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d && echo -e "version = 3\n\n[plugins.\"io.containerd.cri.v1.runtime\".containerd]\n  default_runtime_name = \"nvidia\"" | sudo tee /var/lib/rancher/k3s/agent/etc/containerd/config-v3.toml.d/nvidia.toml > /dev/null'

    echo "    Restarting K3s..."
    ssh "${REMOTE_HOST}" "sudo systemctl restart k3s"
    ELAPSED=0
    while true; do
      STATUS=$(KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}' || true)
      if [ "${STATUS}" = "Ready" ]; then
        break
      fi
      sleep 5
      ELAPSED=$((ELAPSED + 5))
      if [ "${ELAPSED}" -ge 120 ]; then
        echo "Error: K3s not ready after runtime config."
        exit 1
      fi
    done

    echo "    Deploying NVIDIA device plugin..."
    KUBECONFIG="${KUBECONFIG_PATH}" kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.17.1/deployments/static/nvidia-device-plugin.yml

    echo "    Waiting for device plugin to be ready..."
    ELAPSED=0
    while ! KUBECONFIG="${KUBECONFIG_PATH}" kubectl -n kube-system get pods -l name=nvidia-device-plugin-ds --no-headers 2>/dev/null | grep -q Running; do
      sleep 5
      ELAPSED=$((ELAPSED + 5))
      if [ "${ELAPSED}" -ge 120 ]; then
        echo "Warning: Device plugin not ready yet. It may still be pulling the image."
        break
      fi
    done

    GPU_COUNT=$(KUBECONFIG="${KUBECONFIG_PATH}" kubectl describe node "$(KUBECONFIG="${KUBECONFIG_PATH}" kubectl get nodes -o jsonpath='{.items[0].metadata.name}')" | grep "nvidia.com/gpu" | head -1 | awk '{print $2}' || echo "0")
    echo "    GPU(s) available: ${GPU_COUNT}"
    echo "    GPU setup complete."
  fi
fi

echo ""
echo "Done! K3s is running on ${REMOTE_IP}."
echo ""
echo "Test with:"
echo "  KUBECONFIG=${KUBECONFIG_PATH} kubectl get nodes"
echo ""
echo "Next step:"
echo "  ./k3s/deploy.sh"
