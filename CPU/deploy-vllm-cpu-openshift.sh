#!/usr/bin/env bash
set -Eeuo pipefail

#................................................................................
# Initializer:  ID 6781
#...............................................................................
export SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
set -a                    
source "${SCRIPT_DIR}/../.env"
set +a

# OC_LOGIN_CMD as array
"${OC_LOGIN_CMD[@]}"


APP_NAME="${APP_NAME:-vllm-cpu}"
NAMESPACE="${NAMESPACE:-vllm-cpu}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
SERVICE_PORT="${SERVICE_PORT:-8000}"
PVC_SIZE="${PVC_SIZE:-40Gi}"
CPU_REQUEST="${CPU_REQUEST:-4}"
CPU_LIMIT="${CPU_LIMIT:-8}"
MEMORY_REQUEST="${MEMORY_REQUEST:-16Gi}"
MEMORY_LIMIT="${MEMORY_LIMIT:-32Gi}"
SHM_SIZE_LIMIT="${SHM_SIZE_LIMIT:-8Gi}"
REPLICAS="${REPLICAS:-1}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
VLLM_DTYPE="${VLLM_DTYPE:-bfloat16}"
VLLM_CPU_KVCACHE_SPACE="${VLLM_CPU_KVCACHE_SPACE:-16}"
VLLM_CPU_OMP_THREADS_BIND="${VLLM_CPU_OMP_THREADS_BIND:-0-7}"
ROUTE_HOST="${ROUTE_HOST:-}"
HF_TOKEN="${HF_TOKEN:-}"
API_KEY="${API_KEY:-}"
DRY_RUN="${DRY_RUN:-0}"
WORKDIR="${WORKDIR:-./vllm-cpu-ocp-build}"
BASE_IMAGE="${BASE_IMAGE:-registry.access.redhat.com/ubi9/python-311:latest}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

print_header() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

load_env() {
  if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
  fi
  : "${OCP_URL:?Missing OCP_URL. Add it to .env or export it.}"
  : "${OCP_TOKEN:?Missing OCP_TOKEN. Add it to .env or export it.}"
}

model_examples() {
  cat <<'TABLE'
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| #  | Example model ID                                              | Type               | CPU guidance                |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| 1  | ibm-granite/granite-3.2-2b-instruct                           | Text               | Good small CPU smoke test   |
| 2  | unsloth/gpt-oss-20b                                            | Text               | GPT-OSS CPU-supported model |
| 3  | RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8                       | Text quantized     | Practical CPU quantized     |
| 4  | RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w8a8            | Text quantized     | Very large CPU deployment   |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
TABLE
}

prompt_inputs() {
  print_header "Select vLLM CPU model"
  model_examples
  read -r -p "Enter your vLLM CPU-supported model ID: " MODEL_ID
  if [[ -z "${MODEL_ID}" ]]; then
    echo "ERROR: model ID cannot be empty." >&2
    exit 1
  fi

  print_header "Select Red Hat OpenShift architecture"
  echo "1) x86 / amd64"
  echo "2) s390x / IBM Z"
  read -r -p "Enter 1 for x86, 2 for s390x: " ARCH_CHOICE
  case "${ARCH_CHOICE}" in
    1) OCP_ARCH="x86"; NODE_ARCH="amd64"; CPU_ISA_NOTE="avx512f recommended; avx2 limited" ;;
    2) OCP_ARCH="s390x"; NODE_ARCH="s390x"; CPU_ISA_NOTE="VXE required; IBM Z14 or newer" ;;
    *) echo "ERROR: unsupported choice: ${ARCH_CHOICE}" >&2; exit 1 ;;
  esac

  SAFE_MODEL_NAME="$(echo "${MODEL_ID}" | tr '/:._' '----' | tr -cd '[:alnum:]-' | tr '[:upper:]' '[:lower:]')"
  SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${SAFE_MODEL_NAME}}"

  if [[ -z "${API_KEY}" ]]; then
    if command -v openssl >/dev/null 2>&1; then
      API_KEY="$(openssl rand -hex 24)"
    else
      API_KEY="$(date +%s%N | sha256sum | awk '{print $1}')"
    fi
  fi
}

write_dockerfile() {
  mkdir -p "${WORKDIR}"
  if [[ -f "${SCRIPT_DIR}/Dockerfile" ]]; then
    cp "${SCRIPT_DIR}/Dockerfile" "${WORKDIR}/Dockerfile"
  else
    cat > "${WORKDIR}/Dockerfile" <<'DOCKERFILE'
ARG BASE_IMAGE=registry.access.redhat.com/ubi9/python-311:latest
FROM ${BASE_IMAGE}
USER 0
ENV PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    VLLM_TARGET_DEVICE=cpu \
    HF_HOME=/models/huggingface \
    TRANSFORMERS_CACHE=/models/huggingface \
    VLLM_PORT=8000
RUN dnf -y update && \
    dnf -y install git gcc gcc-c++ make cmake ninja-build numactl-libs libgomp && \
    dnf clean all && \
    python -m pip install --upgrade pip setuptools wheel && \
    python -m pip install --upgrade "vllm[cpu]"
RUN mkdir -p /models/huggingface && \
    chgrp -R 0 /models && \
    chmod -R g=u /models
EXPOSE 8000
USER 1001
ENTRYPOINT ["python", "-m", "vllm.entrypoints.openai.api_server"]
DOCKERFILE
  fi
}

oc_apply() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] oc $*"
  else
    oc "$@"
  fi
}

oc_apply_stdin() {
  local file="$1"
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] oc apply -f ${file}"
    sed -n '1,260p' "${file}"
  else
    oc apply -f "${file}"
  fi
}

login_and_project() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] oc login ${OCP_URL} --token=*** --insecure-skip-tls-verify=true"
    echo "[dry-run] oc new-project ${NAMESPACE} || oc project ${NAMESPACE}"
    return
  fi
  oc login "${OCP_URL}" --token="${OCP_TOKEN}" --insecure-skip-tls-verify=true
  oc new-project "${NAMESPACE}" >/dev/null 2>&1 || oc project "${NAMESPACE}"
}

build_image() {
  print_header "Create Dockerfile-based OpenShift build"
  write_dockerfile
  cat > "${WORKDIR}/.dockerignore" <<'EOFIGNORE'
.git
.env
*.log
EOFIGNORE

  oc_apply delete buildconfig "${APP_NAME}" --ignore-not-found=true -n "${NAMESPACE}"
  oc_apply delete imagestream "${APP_NAME}" --ignore-not-found=true -n "${NAMESPACE}"

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] Dockerfile copied to ${WORKDIR}/Dockerfile"
    echo "[dry-run] oc new-build --name=${APP_NAME} --binary --strategy=docker --build-arg=BASE_IMAGE=${BASE_IMAGE} --to=${APP_NAME}:${IMAGE_TAG} -n ${NAMESPACE}"
    echo "[dry-run] oc start-build ${APP_NAME} --from-dir=${WORKDIR} --follow -n ${NAMESPACE}"
  else
    oc new-build --name="${APP_NAME}" --binary --strategy=docker --build-arg="BASE_IMAGE=${BASE_IMAGE}" --to="${APP_NAME}:${IMAGE_TAG}" -n "${NAMESPACE}"
    oc start-build "${APP_NAME}" --from-dir="${WORKDIR}" --follow -n "${NAMESPACE}"
  fi
}

write_manifests() {
  local image_ref="image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/${APP_NAME}:${IMAGE_TAG}"
  local route_host_block=""
  if [[ -n "${ROUTE_HOST}" ]]; then
    route_host_block="  host: ${ROUTE_HOST}"
  fi

  cat > "${WORKDIR}/openshift-vllm-cpu.yaml" <<EOFYAML
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP_NAME}-models
  namespace: ${NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: ${PVC_SIZE}
---
apiVersion: v1
kind: Secret
metadata:
  name: ${APP_NAME}-secrets
  namespace: ${NAMESPACE}
type: Opaque
stringData:
  api-key: "${API_KEY}"
  hf-token: "${HF_TOKEN}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app: ${APP_NAME}
  strategy:
    type: Recreate
  template:
    metadata:
      labels:
        app: ${APP_NAME}
      annotations:
        cpu.openshift.io/architecture: "${OCP_ARCH}"
        cpu.openshift.io/isa-note: "${CPU_ISA_NOTE}"
    spec:
      nodeSelector:
        kubernetes.io/arch: ${NODE_ARCH}
      containers:
        - name: vllm-openai
          image: ${image_ref}
          imagePullPolicy: Always
          args:
            - --host
            - 0.0.0.0
            - --port
            - "${SERVICE_PORT}"
            - --model
            - "${MODEL_ID}"
            - --served-model-name
            - "${SERVED_MODEL_NAME}"
            - --dtype
            - "${VLLM_DTYPE}"
            - --max-model-len
            - "${MAX_MODEL_LEN}"
            - --api-key
            - "\$(API_KEY)"
          ports:
            - containerPort: ${SERVICE_PORT}
              name: http
          env:
            - name: API_KEY
              valueFrom:
                secretKeyRef:
                  name: ${APP_NAME}-secrets
                  key: api-key
            - name: HUGGING_FACE_HUB_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${APP_NAME}-secrets
                  key: hf-token
                  optional: true
            - name: HF_HOME
              value: /models/huggingface
            - name: TRANSFORMERS_CACHE
              value: /models/huggingface
            - name: VLLM_TARGET_DEVICE
              value: cpu
            - name: VLLM_CPU_KVCACHE_SPACE
              value: "${VLLM_CPU_KVCACHE_SPACE}"
            - name: VLLM_CPU_OMP_THREADS_BIND
              value: "${VLLM_CPU_OMP_THREADS_BIND}"
          resources:
            requests:
              cpu: "${CPU_REQUEST}"
              memory: ${MEMORY_REQUEST}
            limits:
              cpu: "${CPU_LIMIT}"
              memory: ${MEMORY_LIMIT}
          volumeMounts:
            - name: model-cache
              mountPath: /models
            - name: shm
              mountPath: /dev/shm
          readinessProbe:
            httpGet:
              path: /health
              port: ${SERVICE_PORT}
            initialDelaySeconds: 30
            periodSeconds: 20
            timeoutSeconds: 5
            failureThreshold: 30
          livenessProbe:
            httpGet:
              path: /health
              port: ${SERVICE_PORT}
            initialDelaySeconds: 120
            periodSeconds: 30
            timeoutSeconds: 5
            failureThreshold: 10
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: ${APP_NAME}-models
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: ${SHM_SIZE_LIMIT}
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
      port: ${SERVICE_PORT}
      targetPort: ${SERVICE_PORT}
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app: ${APP_NAME}
spec:
${route_host_block}
  to:
    kind: Service
    name: ${APP_NAME}
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOFYAML
}

deploy_manifests() {
  print_header "Apply OpenShift runtime objects"
  write_manifests
  oc_apply_stdin "${WORKDIR}/openshift-vllm-cpu.yaml"

  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] oc rollout status deployment/${APP_NAME} -n ${NAMESPACE} --timeout=30m"
  else
    oc rollout status deployment/"${APP_NAME}" -n "${NAMESPACE}" --timeout=30m
  fi
}

print_result() {
  print_header "Deployment summary"
  echo "Namespace:       ${NAMESPACE}"
  echo "Application:     ${APP_NAME}"
  echo "Model ID:        ${MODEL_ID}"
  echo "Served name:     ${SERVED_MODEL_NAME}"
  echo "Architecture:    ${OCP_ARCH} (${NODE_ARCH})"
  echo "CPU guidance:    ${CPU_ISA_NOTE}"
  echo "Service port:    ${SERVICE_PORT}"
  echo
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "[dry-run] Route URL will be available after deployment with:"
    echo "oc -n ${NAMESPACE} get route ${APP_NAME} -o jsonpath='{.spec.host}'"
  else
    local host
    host="$(oc -n "${NAMESPACE}" get route "${APP_NAME}" -o jsonpath='{.spec.host}')"
    echo "OpenAI-compatible base URL: https://${host}/v1"
    echo
    echo "Test command:"
    cat <<EOFTEST
API_KEY=\$(oc -n ${NAMESPACE} get secret ${APP_NAME}-secrets -o jsonpath='{.data.api-key}' | base64 -d)
curl -sS https://${host}/v1/chat/completions \\
  -H "Authorization: Bearer \${API_KEY}" \\
  -H "Content-Type: application/json" \\
  -d '{"model":"${SERVED_MODEL_NAME}","messages":[{"role":"user","content":"Say hello from vLLM CPU on OpenShift."}],"max_tokens":64}'
EOFTEST
  fi
}

main() {
  need_cmd bash
  if [[ "${DRY_RUN}" != "1" ]]; then
    need_cmd oc
  fi
  load_env
  prompt_inputs
  login_and_project
  build_image
  deploy_manifests
  print_result
}

main "$@"
