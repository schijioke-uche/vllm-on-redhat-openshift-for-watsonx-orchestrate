#!/usr/bin/env bash
set -euo pipefail

# Deploy OpenAI GPT-OSS 120B on Red Hat OpenShift using vLLM / Red Hat AI Inference Server.
# The resulting OpenAI-compatible base URL is: https://<route-host>/v1
#
# Required before running:
#   oc login ...
#   A GPU-enabled OpenShift cluster with the NVIDIA or AMD GPU Operator already installed.
#
# Common overrides:
#   NAMESPACE=gpt-oss \
#   HF_TOKEN=hf_xxx \
#   REDHAT_REGISTRY_USERNAME='...' REDHAT_REGISTRY_PASSWORD='...' \
#   ROUTE_HOST='gpt-oss-your-ocp-domain.example.com' \
#   ./deploy-gpt-oss-120b-vllm-openshift.sh

log() { printf '\n[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }
warn() { printf '\n[%s] WARNING: %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "Missing required command: $1" >&2; exit 1; }; }

require_cmd oc

if ! oc whoami >/dev/null 2>&1; then
  echo "You are not logged in to OpenShift. Run: oc login <api-server>" >&2
  exit 1
fi

NAMESPACE="${NAMESPACE:-gpt-oss}"
APP_NAME="${APP_NAME:-gpt-oss-vllm}"
MODEL_ID="${MODEL_ID:-openai/gpt-oss-120b}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-gpt-oss-120b}"

# Red Hat AI Inference Server CUDA image. Override for upstream vLLM or ROCm, for example:
#   VLLM_IMAGE=vllm/vllm-openai:v0.22.0-cu129-ubuntu2404
#   VLLM_IMAGE=registry.redhat.io/rhaiis/vllm-rocm-rhel9:3.2.2
VLLM_IMAGE="${VLLM_IMAGE:-registry.redhat.io/rhaiis/vllm-cuda-rhel9:3.2.2}"

# GPU resource name is nvidia.com/gpu for NVIDIA GPU Operator and usually amd.com/gpu for AMD GPU Operator.
GPU_RESOURCE="${GPU_RESOURCE:-nvidia.com/gpu}"
GPU_COUNT="${GPU_COUNT:-1}"
TENSOR_PARALLEL_SIZE="${TENSOR_PARALLEL_SIZE:-$GPU_COUNT}"

# Conservative GPT-OSS 120B defaults. Increase for throughput after the service is stable.
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.95}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-32768}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-1024}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-16}"
EXTRA_VLLM_ARGS="${EXTRA_VLLM_ARGS:-}"

PVC_NAME="${PVC_NAME:-${APP_NAME}-model-cache}"
PVC_SIZE="${PVC_SIZE:-300Gi}"
STORAGE_CLASS="${STORAGE_CLASS:-}"
SHM_SIZE="${SHM_SIZE:-8Gi}"

CPU_REQUEST="${CPU_REQUEST:-4}"
CPU_LIMIT="${CPU_LIMIT:-16}"
MEM_REQUEST="${MEM_REQUEST:-32Gi}"
MEM_LIMIT="${MEM_LIMIT:-128Gi}"

HF_SECRET_NAME="${HF_SECRET_NAME:-${APP_NAME}-hf}"
API_KEY_SECRET_NAME="${API_KEY_SECRET_NAME:-${APP_NAME}-api-key}"
IMAGE_PULL_SECRET_NAME="${IMAGE_PULL_SECRET_NAME:-}"
ROUTE_NAME="${ROUTE_NAME:-$APP_NAME}"
ROUTE_HOST="${ROUTE_HOST:-}"
OCP_SERVER_DOMAIN="${OCP_SERVER_DOMAIN:-}"
WAIT_FOR_READY="${WAIT_FOR_READY:-false}"
ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-90m}"

if [[ -z "$ROUTE_HOST" && -n "$OCP_SERVER_DOMAIN" ]]; then
  ROUTE_HOST="${NAMESPACE}-${OCP_SERVER_DOMAIN}"
fi

if [[ "$VLLM_IMAGE" == *":latest" || "$VLLM_IMAGE" == *":latest-"* ]]; then
  warn "VLLM_IMAGE uses a latest-style tag. Pin an immutable version for repeatable production deployments. Current value: $VLLM_IMAGE"
fi

log "Using OpenShift user: $(oc whoami)"
log "Deploying ${APP_NAME} in namespace ${NAMESPACE}"

if oc get namespace "$NAMESPACE" >/dev/null 2>&1; then
  oc project "$NAMESPACE" >/dev/null
else
  oc new-project "$NAMESPACE" >/dev/null
fi

if ! oc get nodes -o json | grep -q "\"${GPU_RESOURCE}\""; then
  warn "No node capacity named '${GPU_RESOURCE}' was found. The deployment will be created, but the pod will stay Pending until that GPU resource exists."
fi

# Create or reuse the API key secret.
if [[ -z "${VLLM_API_KEY:-}" ]]; then
  if oc -n "$NAMESPACE" get secret "$API_KEY_SECRET_NAME" >/dev/null 2>&1; then
    VLLM_API_KEY="$(oc -n "$NAMESPACE" get secret "$API_KEY_SECRET_NAME" -o jsonpath='{.data.api-key}' | base64 -d)"
    log "Reusing existing API key secret ${API_KEY_SECRET_NAME}"
  else
    if command -v openssl >/dev/null 2>&1; then
      VLLM_API_KEY="$(openssl rand -hex 32)"
    else
      VLLM_API_KEY="$(date +%s | sha256sum | awk '{print $1}')"
    fi
    log "Generated a new vLLM API key"
  fi
fi

oc -n "$NAMESPACE" create secret generic "$API_KEY_SECRET_NAME" \
  --from-literal=api-key="$VLLM_API_KEY" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null

# Hugging Face token is optional for public models but strongly recommended for reliability and gated repos.
oc -n "$NAMESPACE" create secret generic "$HF_SECRET_NAME" \
  --from-literal=HF_TOKEN="${HF_TOKEN:-}" \
  --dry-run=client -o yaml | oc apply -f - >/dev/null

# Optional Red Hat registry pull secret. You may also set IMAGE_PULL_SECRET_NAME to an existing pull secret.
if [[ -n "${IMAGE_PULL_SECRET:-}" ]]; then
  IMAGE_PULL_SECRET_NAME="$IMAGE_PULL_SECRET"
elif [[ -n "${REDHAT_REGISTRY_USERNAME:-}" && -n "${REDHAT_REGISTRY_PASSWORD:-}" ]]; then
  IMAGE_PULL_SECRET_NAME="${IMAGE_PULL_SECRET_NAME:-redhat-registry-pull}"
  oc -n "$NAMESPACE" create secret docker-registry "$IMAGE_PULL_SECRET_NAME" \
    --docker-server=registry.redhat.io \
    --docker-username="$REDHAT_REGISTRY_USERNAME" \
    --docker-password="$REDHAT_REGISTRY_PASSWORD" \
    --docker-email="${REDHAT_REGISTRY_EMAIL:-unused@example.com}" \
    --dry-run=client -o yaml | oc apply -f - >/dev/null
elif [[ "$VLLM_IMAGE" == registry.redhat.io/* ]]; then
  warn "Using registry.redhat.io image without a pull secret. If the image pull fails, rerun with REDHAT_REGISTRY_USERNAME and REDHAT_REGISTRY_PASSWORD, or set IMAGE_PULL_SECRET_NAME to an existing pull secret."
fi

STORAGE_CLASS_YAML=""
if [[ -n "$STORAGE_CLASS" ]]; then
  STORAGE_CLASS_YAML="  storageClassName: ${STORAGE_CLASS}"
fi

IMAGE_PULL_SECRETS_YAML=""
if [[ -n "$IMAGE_PULL_SECRET_NAME" ]]; then
  IMAGE_PULL_SECRETS_YAML=$(cat <<EOF_PULL
      imagePullSecrets:
        - name: ${IMAGE_PULL_SECRET_NAME}
EOF_PULL
)
fi

ROUTE_HOST_YAML=""
if [[ -n "$ROUTE_HOST" ]]; then
  ROUTE_HOST_YAML="  host: ${ROUTE_HOST}"
fi

log "Applying PVC, Deployment, Service, and Route"
cat <<EOF_APPLY | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${PVC_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_SIZE}
${STORAGE_CLASS_YAML}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
    spec:
${IMAGE_PULL_SECRETS_YAML}
      terminationGracePeriodSeconds: 120
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: ${PVC_NAME}
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: ${SHM_SIZE}
      containers:
        - name: vllm
          image: ${VLLM_IMAGE}
          imagePullPolicy: IfNotPresent
          command:
            - /bin/bash
            - -lc
          args:
            - |
              set -euo pipefail
              mkdir -p /models/huggingface /models/home /models/tmp /models/cache /models/uv-cache /models/triton-cache
              exec python -m vllm.entrypoints.openai.api_server \
                --host 0.0.0.0 \
                --port 8000 \
                --model "${MODEL_ID}" \
                --served-model-name "${SERVED_MODEL_NAME}" \
                --tensor-parallel-size "${TENSOR_PARALLEL_SIZE}" \
                --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
                --max-model-len "${MAX_MODEL_LEN}" \
                --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}" \
                --max-num-seqs "${MAX_NUM_SEQS}" \
                --download-dir /models/huggingface \
                --api-key "\${VLLM_API_KEY}" \
                \${EXTRA_VLLM_ARGS}
          env:
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${HF_SECRET_NAME}
                  key: HF_TOKEN
                  optional: true
            - name: HUGGING_FACE_HUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${HF_SECRET_NAME}
                  key: HF_TOKEN
                  optional: true
            - name: VLLM_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ${API_KEY_SECRET_NAME}
                  key: api-key
            - name: HOME
              value: /models/home
            - name: HF_HOME
              value: /models/huggingface
            - name: XDG_CACHE_HOME
              value: /models/cache
            - name: TMPDIR
              value: /models/tmp
            - name: UV_CACHE_DIR
              value: /models/uv-cache
            - name: TRITON_CACHE_DIR
              value: /models/triton-cache
            - name: VLLM_NO_USAGE_STATS
              value: "1"
            - name: EXTRA_VLLM_ARGS
              value: "${EXTRA_VLLM_ARGS}"
          ports:
            - name: http
              containerPort: 8000
              protocol: TCP
          resources:
            requests:
              cpu: "${CPU_REQUEST}"
              memory: ${MEM_REQUEST}
              ${GPU_RESOURCE}: "${GPU_COUNT}"
            limits:
              cpu: "${CPU_LIMIT}"
              memory: ${MEM_LIMIT}
              ${GPU_RESOURCE}: "${GPU_COUNT}"
          volumeMounts:
            - name: model-cache
              mountPath: /models
            - name: shm
              mountPath: /dev/shm
          startupProbe:
            httpGet:
              path: /health
              port: http
            periodSeconds: 10
            failureThreshold: 360
            timeoutSeconds: 5
          readinessProbe:
            httpGet:
              path: /health
              port: http
            periodSeconds: 10
            failureThreshold: 3
            timeoutSeconds: 5
          livenessProbe:
            httpGet:
              path: /health
              port: http
            periodSeconds: 30
            failureThreshold: 3
            timeoutSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  selector:
    app: ${APP_NAME}
  ports:
    - name: http
      protocol: TCP
      port: 8000
      targetPort: http
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${ROUTE_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
${ROUTE_HOST_YAML}
  to:
    kind: Service
    name: ${APP_NAME}
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF_APPLY

if [[ "$WAIT_FOR_READY" == "true" ]]; then
  log "Waiting for rollout; first model download can take a long time"
  oc -n "$NAMESPACE" rollout status deployment "$APP_NAME" --timeout="$ROLLOUT_TIMEOUT"
else
  log "Deployment submitted. Follow startup with: oc -n ${NAMESPACE} logs deploy/${APP_NAME} -f"
fi

ROUTE_ACTUAL_HOST="$(oc -n "$NAMESPACE" get route "$ROUTE_NAME" -o jsonpath='{.spec.host}')"
BASE_URL="https://${ROUTE_ACTUAL_HOST}/v1"

cat <<EOF_DONE

Deployment objects are in place.

OpenAI-compatible base URL:
  ${BASE_URL}

Model name to send in API requests:
  ${SERVED_MODEL_NAME}

API key secret:
  oc -n ${NAMESPACE} get secret ${API_KEY_SECRET_NAME} -o jsonpath='{.data.api-key}' | base64 -d; echo

Test after the pod is Ready:
  curl -sS ${BASE_URL}/chat/completions \\
    -H "Authorization: Bearer \$(oc -n ${NAMESPACE} get secret ${API_KEY_SECRET_NAME} -o jsonpath='{.data.api-key}' | base64 -d)" \\
    -H "Content-Type: application/json" \\
    -d '{
      "model": "${SERVED_MODEL_NAME}",
      "messages": [
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Briefly explain what deep learning is."}
      ],
      "temperature": 0.2,
      "max_tokens": 256,
      "stream": false
    }'

Useful checks:
  oc -n ${NAMESPACE} get pods,pvc,svc,route -l app=${APP_NAME}
  oc -n ${NAMESPACE} describe pod -l app=${APP_NAME}
  oc -n ${NAMESPACE} logs deploy/${APP_NAME} -f
EOF_DONE
