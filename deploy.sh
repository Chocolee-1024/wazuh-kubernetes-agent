#!/bin/bash
# =============================================================
# Wazuh on Kubernetes 部署腳本
# 執行前先 clone：
# git clone https://github.com/Chocolee-1024/wazuh-kubernetes-agent.git
# cd wazuh-kubernetes-agent
# bash deploy.sh
# =============================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
section() { echo -e "\n${GREEN}========== $1 ==========${NC}"; }

MASTER_NODE="ubuntu"

# =============================================================
section "環境確認"
# =============================================================

kubectl get nodes || error "kubectl 無法連線"

# 沒有 local-path 就自動安裝
if kubectl get storageclass | grep -q "local-path"; then
  info "local-path StorageClass 已存在 ✓"
else
  warn "找不到 local-path，自動安裝中..."
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
  kubectl wait --for=condition=Ready pod \
    -l app=local-path-provisioner \
    -n local-path-storage \
    --timeout=120s
  info "local-path 安裝完成 ✓"
fi

# =============================================================
section "清除舊部署"
# =============================================================

if kubectl get namespace wazuh &>/dev/null; then
  warn "發現舊的 wazuh namespace，清除中..."
  kubectl delete namespace wazuh --wait=true
  info "清除完成 ✓"
fi

# =============================================================
section "產生 TLS 憑證"
# =============================================================

cd wazuh

bash certs/indexer_cluster/generate_certs.sh
bash certs/dashboard_http/generate_certs.sh

info "憑證產生完成 ✓"

# =============================================================
section "幫 Master Node 打標籤"
# =============================================================

kubectl label node "$MASTER_NODE" role=master --overwrite
info "節點 $MASTER_NODE 標記 role=master ✓"

# =============================================================
section "部署 Wazuh 核心元件"
# =============================================================

kubectl apply -k .

info "等待所有 Pod 啟動（最多 15 分鐘）..."

for label in "app=wazuh-indexer" "app=wazuh-manager" "app=wazuh-dashboard"; do
  kubectl wait --for=condition=Ready pod -l "$label" \
    -n wazuh --timeout=900s || warn "$label 尚未 Ready"
done

echo ""
info "部署完成！Pod 狀態："
kubectl get pods -n wazuh -o wide

echo ""
MASTER_IP=$(kubectl get node "$MASTER_NODE" \
  -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}')
DASH_PORT=$(kubectl get svc dashboard -n wazuh \
  -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "N/A")

echo "=================================================="
echo "  Dashboard : https://${MASTER_IP}:${DASH_PORT}"
echo "  帳號      : admin"
echo "  密碼      : SecretPassword"
echo "=================================================="
