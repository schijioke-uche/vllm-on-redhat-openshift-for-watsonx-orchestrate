#!/usr/bin/env bash
set -Eeuo pipefail

# Deploy gpt-oss-120b on OpenShift with vLLM and expose it at /v1 via an OpenShift Route.
#
# Default namespace:
#   gpt-oss-120b
#
# Resulting endpoint:
#   https://$(oc get route vllm -n "$NAMESPACE" -o jsonpath='{.spec.host}')/v1
#
# Notes:
# - If you want an exact custom hostname, set ROUTE_HOST and ensure DNS + ingress certs are configured for it.
# - By default this uses the official vLLM OpenAI-compatible container image.
# - The model is downloaded from Hugging Face on first start into a PVC-backed cache.

# Required before running:
#   oc login ...
#   A GPU-enabled OpenShift cluster with the NVIDIA or AMD GPU Operator already installed.
#

# NAMESPACE=gpt-oss-120b \
# GPU_COUNT=1 \
# TP_SIZE=1 \
# CREATE_HF_SECRET=1 \
# HF_TOKEN='hf_xxx' \
# ./deploy-gpt-oss-120b-openshift.sh


NAMESPACE="${NAMESPACE:-gpt-oss-120b}"
APP_NAME="${APP_NAME:-vllm}"
MODEL_NAME="${MODEL_NAME:-openai/gpt-oss-120b}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-gpt-oss-120b}"
IMAGE="${IMAGE:-vllm/vllm-openai:latest}"
GPU_COUNT="${GPU_COUNT:-1}"
TP_SIZE="${TP_SIZE:-1}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.92}"
PORT="${PORT:-8000}"
CACHE_SIZE="${CACHE_SIZE:-200Gi}"
STORAGE_CLASS="${STORAGE_CLASS:-}"
ROUTE_HOST="${ROUTE_HOST:-}"
HF_SECRET_NAME="${HF_SECRET_NAME:-hf-token}"
CREATE_NAMESPACE="${CREATE_NAMESPACE:-1}"
CREATE_HF_SECRET="${CREATE_HF_SECRET:-0}"
HF_TOKEN="${HF_TOKEN:-}"
EXTRA_VLLM_ARGS="${EXTRA_VLLM_ARGS:-}"
ENABLE_API_KEY="${ENABLE_API_KEY:-0}"
VLLM_API_KEY="${VLLM_API_KEY:-}"
API_KEY_SECRET_NAME="${API_KEY_SECRET_NAME:-vllm-api-key}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] Required command not found: $1" >&2
    exit 1
  }
}

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

die() {
  printf '[ERROR] %s\n' "$*" >&2
  exit 1
}

require_oc_login() {
  oc whoami >/dev/null 2>&1 || die "oc is not logged in. Run 'oc login' first."
}

create_namespace() {
  if [[ "${CREATE_NAMESPACE}" == "1" ]]; then
    if ! oc get namespace "${NAMESPACE}" >/dev/null 2>&1; then
      log "Creating namespace ${NAMESPACE}"
      oc create namespace "${NAMESPACE}"
    else
      log "Namespace ${NAMESPACE} already exists"
    fi
  fi
}

create_hf_secret_if_requested() {
  if [[ "${CREATE_HF_SECRET}" == "1" ]]; then
    [[ -n "${HF_TOKEN}" ]] || die "CREATE_HF_SECRET=1 requires HF_TOKEN to be set."
    oc -n "${NAMESPACE}" delete secret "${HF_SECRET_NAME}" --ignore-not-found >/dev/null 2>&1 || true
    oc -n "${NAMESPACE}" create secret generic "${HF_SECRET_NAME}" \
      --from-literal=HF_TOKEN="${HF_TOKEN}" >/dev/null
    log "Created Hugging Face token secret ${HF_SECRET_NAME}"
  else
    if oc -n "${NAMESPACE}" get secret "${HF_SECRET_NAME}" >/dev/null 2>&1; then
      log "Using existing Hugging Face token secret ${HF_SECRET_NAME}"
    else
      warn "Secret ${HF_SECRET_NAME} not found. If the model requires Hub auth, create it or set CREATE_HF_SECRET=1 HF_TOKEN=..."
    fi
  fi
}

create_api_key_secret_if_requested() {
  if [[ "${ENABLE_API_KEY}" == "1" ]]; then
    [[ -n "${VLLM_API_KEY}" ]] || die "ENABLE_API_KEY=1 requires VLLM_API_KEY to be set."
    oc -n "${NAMESPACE}" delete secret "${API_KEY_SECRET_NAME}" --ignore-not-found >/dev/null 2>&1 || true
    oc -n "${NAMESPACE}" create secret generic "${API_KEY_SECRET_NAME}" \
      --from-literal=api_key="${VLLM_API_KEY}" >/dev/null
    log "Created vLLM API key secret ${API_KEY_SECRET_NAME}"
  fi
}

apply_manifests() {
  local pvc_storage_class_yaml=""
  local route_host_yaml=""
  local hf_env_yaml=""
  local api_key_env_yaml=""

  if [[ -n "${STORAGE_CLASS}" ]]; then
    pvc_storage_class_yaml="  storageClassName: ${STORAGE_CLASS}"
  fi

  if [[ -n "${ROUTE_HOST}" ]]; then
    route_host_yaml="  host: ${ROUTE_HOST}"
  fi

  if oc -n "${NAMESPACE}" get secret "${HF_SECRET_NAME}" >/dev/null 2>&1; then
    hf_env_yaml=$(cat <<EOF
        - name: HF_TOKEN
          valueFrom:
            secretKeyRef:
              name: ${HF_SECRET_NAME}
              key: HF_TOKEN
EOF
)
  fi

  if [[ "${ENABLE_API_KEY}" == "1" ]]; then
    api_key_env_yaml=$(cat <<EOF
        - name: VLLM_API_KEY
          valueFrom:
            secretKeyRef:
              name: ${API_KEY_SECRET_NAME}
              key: api_key
EOF
)
  fi

  oc -n "${NAMESPACE}" apply -f - <<EOF
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP_NAME}-hf-cache
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${CACHE_SIZE}
${pvc_storage_class_yaml}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
      containers:
        - name: vllm
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          args:
            - "--host"
            - "0.0.0.0"
            - "--port"
            - "${PORT}"
            - "--model"
            - "${MODEL_NAME}"
            - "--served-model-name"
            - "${SERVED_MODEL_NAME}"
            - "--tensor-parallel-size"
            - "${TP_SIZE}"
            - "--gpu-memory-utilization"
            - "${GPU_MEMORY_UTILIZATION}"
$(if [[ "${ENABLE_API_KEY}" == "1" ]]; then
  cat <<EOF2
            - "--api-key"
            - "\$(VLLM_API_KEY)"
EOF2
fi)
$(if [[ -n "${EXTRA_VLLM_ARGS}" ]]; then
  for arg in ${EXTRA_VLLM_ARGS}; do
    printf '            - "%s"\n' "$arg"
  done
fi)
          ports:
            - name: http
              containerPort: ${PORT}
              protocol: TCP
          env:
${hf_env_yaml:+$hf_env_yaml}
${api_key_env_yaml:+$api_key_env_yaml}
          resources:
            limits:
              nvidia.com/gpu: ${GPU_COUNT}
            requests:
              nvidia.com/gpu: ${GPU_COUNT}
          volumeMounts:
            - name: hf-cache
              mountPath: /home/vllm/.cache/huggingface
          securityContext:
            runAsNonRoot: true
            runAsGroup: 0
      volumes:
        - name: hf-cache
          persistentVolumeClaim:
            claimName: ${APP_NAME}-hf-cache
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - name: http
      port: 80
      targetPort: http
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
spec:
${route_host_yaml}
  to:
    kind: Service
    name: ${APP_NAME}
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF
}

wait_for_rollout() {
  log "Waiting for deployment rollout"
  oc -n "${NAMESPACE}" rollout status deployment/"${APP_NAME}" --timeout=30m
}

print_endpoint() {
  local host
  host="$(oc -n "${NAMESPACE}" get route "${APP_NAME}" -o jsonpath='{.spec.host}')"
  echo
  log "Deployment complete."
  log "Namespace: ${NAMESPACE}"
  log "Route: https://${host}/v1"
  log "Health check: https://${host}/health"
  log "Example curl:"
  if [[ "${ENABLE_API_KEY}" == "1" ]]; then
    printf "curl -s https://%s/v1/chat/completions -H 'Content-Type: application/json' -H 'Authorization: Bearer <YOUR_API_KEY>' -d '{\"model\":\"%s\",\"messages\":[{\"role\":\"user\",\"content\":\"Return only READY.\"}],\"temperature\":0,\"max_tokens\":3}'\n" "$host" "$SERVED_MODEL_NAME"
  else
    printf "curl -s https://%s/v1/chat/completions -H 'Content-Type: application/json' -d '{\"model\":\"%s\",\"messages\":[{\"role\":\"user\",\"content\":\"Return only READY.\"}],\"temperature\":0,\"max_tokens\":3}'\n" "$host" "$SERVED_MODEL_NAME"
  fi
}

main() {
  need oc
  require_oc_login
  create_namespace
  create_hf_secret_if_requested
  create_api_key_secret_if_requested
  apply_manifests
  wait_for_rollout
  print_endpoint
}

main "$@"
