#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="deploy-vllm-openshift.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

log() { printf '[%s] %s\n' "$SCRIPT_NAME" "$*"; }
warn() { printf '[%s] WARNING: %s\n' "$SCRIPT_NAME" "$*" >&2; }
fail() { printf '[%s] ERROR: %s\n' "$SCRIPT_NAME" "$*" >&2; exit 1; }

set -a                    
source "${SCRIPT_DIR}/../.env"
set +a

load_env() {
  local env_file="${ENV_FILE:-${SCRIPT_DIR}/../.env}"
  if [[ -f "$env_file" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$env_file"
    set +a
  fi
}

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's#[^a-z0-9]+#-#g; s#^-+##; s#-+$##; s#--+#-#g'
}

short_hash() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print substr($1,1,8)}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print substr($1,1,8)}'
  fi
}

yaml_dq() {
  local s="${1:-}"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '"%s"' "$s"
}


redhat_registry_login() {
  if [[ -n "${RH_REGISTRY_USERNAME:-${PUBLIC_REDHAT_REGISTRY_USER}}" && -n "${RH_REGISTRY_PASSWORD:-${PUBLIC_REDHAT_REGISTRY_PASSWORD}}" ]]; then
    export RH_REGISTRY_USERNAME="${RH_REGISTRY_USERNAME:-${PUBLIC_REDHAT_REGISTRY_USER}}"
    export RH_REGISTRY_PASSWORD="${RH_REGISTRY_PASSWORD:-${PUBLIC_REDHAT_REGISTRY_PASSWORD}}"
    docker login registry.redhat.io -u "${RH_REGISTRY_USERNAME}" -p "${RH_REGISTRY_PASSWORD}"
  fi
}

print_model_menu() {
  cat <<'MENU'
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| #  | Example model ID                                              | Type               | CPU guidance                |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| 1  | ibm-granite/granite-3.2-2b-instruct                           | Text               | Good small CPU smoke test   |
| 2  | unsloth/gpt-oss-20b                                           | Text               | GPT-OSS CPU-supported model |
| 3  | RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8                     | Text quantized     | Practical CPU quantized     |
| 4  | RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w8a8         | Text quantized     | Very large CPU deployment   |
| 5  | <Any supported model id>                                      | <any>              | <any guidance>              |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| q  |                                                  QUIT                                                            |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
MENU
}

print_arch_menu() {
  cat <<'MENU'
Select Red Hat OpenShift architecture:
+-------------------------------------------------------+
[1]      amd64       |      x86_64 / Intel 64 / AMD64   |
[2]      arm64       |      aarch64 / AArch64           |
[3]      ppc64le     |      IBM Power (little-endian)   |
[4]      s390x       |      IBM Z                       |
+-------------------------------------------------------+
MENU
}

select_model() {
  local choice
  print_model_menu
  printf 'Enter model option [1-5 or q]: '
  read -r choice
  case "$choice" in
    q|Q)
      log "User selected quit. Exiting."
      exit 0
      ;;
    1) MODEL_ID="ibm-granite/granite-3.2-2b-instruct" ;;
    2) MODEL_ID="unsloth/gpt-oss-20b" ;;
    3) MODEL_ID="RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8" ;;
    4) MODEL_ID="RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w8a8" ;;
    5)
      printf 'You selection option-5, please enter the model ID: '
      read -r MODEL_ID
      [[ -n "${MODEL_ID:-}" ]] || fail "model ID cannot be empty."
      ;;
    *) fail "invalid model option: $choice" ;;
  esac
}


vllm_models() {
  local model_name="${1:-${MODEL_ID:-}}"
  local model_key=""

  VLLM_MODEL_ID="unset"
  export VLLM_MODEL_ID

  if [[ -z "${model_name}" ]]; then
    echo "[ERROR] Model name is required. Pass it as an argument or set MODEL_ID." >&2
    return 1
  fi

  model_key="$(printf '%s' "${model_name}" | tr '[:upper:]' '[:lower:]')"

  case "${model_key}" in
    "unsloth/gpt-oss-20b")
      VLLM_MODEL_ID="gpt-oss-20b"
      ;;

    "meta-llama/llama-3.1-8b-instruct")
      VLLM_MODEL_ID="llama31-8bi"
      ;;

    "meta-llama/llama-3.2-1b")
      VLLM_MODEL_ID="llama32-1b"
      ;;

    "meta-llama/llama-3.2-3b-instruct")
      VLLM_MODEL_ID="llama32-3bi"
      ;;

    "meta-llama/llama-3.3-70b-instruct")
      VLLM_MODEL_ID="llama33-70bi"
      ;;

    "redhatai/meta-llama-3.1-8b-quantized.w8a8")
      VLLM_MODEL_ID="rh-llama318q"
      ;;

    "redhatai/meta-llama-3.1-8b-instruct-quantized.w8a8")
      VLLM_MODEL_ID="rh-llama318i"
      ;;

    "redhatai/llama-3.2-1b-instruct-quantized.w8a8")
      VLLM_MODEL_ID="rh-llama321q"
      ;;

    "redhatai/llama-3.2-3b-instruct-quantized.w8a8")
      VLLM_MODEL_ID="rh-llama323q"
      ;;

    "redhatai/deepseek-r1-distill-llama-70b-quantized.w8a8")
      VLLM_MODEL_ID="rh-dseek-r1-llama-70q"
      ;;

    "hugging-quants/meta-llama-3.1-8b-instruct-awq-int4")
      VLLM_MODEL_ID="hq-llama318a"
      ;;

    "amead10/llama-3.2-1b-instruct-awq")
      VLLM_MODEL_ID="am-llama321a"
      ;;

    "amead10/llama-3.2-3b-instruct-awq")
      VLLM_MODEL_ID="am-llama323a"
      ;;

    "thebloke/tinyllama-1.1b-chat-v1.0-awq")
      VLLM_MODEL_ID="tinylama-awq"
      ;;

    "thebloke/tinyllama-1.1b-chat-v1.0-gptq")
      VLLM_MODEL_ID="tinylama-gptq"
      ;;

    "ibm-granite/granite-3.2-2b-instruct")
      VLLM_MODEL_ID="ibm-granite2b"
      ;;

    "qwen/qwen3-1.7b")
      VLLM_MODEL_ID="qwen3-17b"
      ;;

    "qwen/qwen3-4b")
      VLLM_MODEL_ID="qwen3-4b"
      ;;

    "qwen/qwen3-8b")
      VLLM_MODEL_ID="qwen3-8b"
      ;;

    "qwen/qwen3-14b")
      VLLM_MODEL_ID="qwen3-14b"
      ;;

    "qwen/qwen3-14b-awq")
      VLLM_MODEL_ID="qwen314awq"
      ;;

    "qwen/qwen3-30b-a3b")
      VLLM_MODEL_ID="qwen330a3b"
      ;;

    "qwen/qwen-32b-awq")
      VLLM_MODEL_ID="qwen32-awq"
      ;;

    "qwen/qwen1.5-0.5b-chat-gptq-int4")
      VLLM_MODEL_ID="qwen15gptq"
      ;;

    "redhatai/qwq-32b-quantized.w8a8")
      VLLM_MODEL_ID="rh-qwq32q"
      ;;

    "zai-org/glm-4-9b-hf")
      VLLM_MODEL_ID="glm4-9b"
      ;;

    "google/gemma-7b")
      VLLM_MODEL_ID="gemma7b"
      ;;

    "microsoft/phi-4-reasoning")
      VLLM_MODEL_ID="phi4reas"
      ;;

    "thebloke/mistral-7b-instruct-v0.2-awq")
      VLLM_MODEL_ID="mist7bawq"
      ;;

    "meta-llama/llama-4-scout-17b-16e-instruct")
      VLLM_MODEL_ID="llama4-scout"
      ;;

    "google/gemma-3-4b-it")
      VLLM_MODEL_ID="gemma34b"
      ;;

    "google/gemma-3-12b-it")
      VLLM_MODEL_ID="gemma312b"
      ;;

    "google/gemma-4-e4b-it")
      VLLM_MODEL_ID="gemma4e4b"
      ;;

    "google/gemma-4-e2b-it")
      VLLM_MODEL_ID="gemma4e2b"
      ;;

    "google/gemma-4-26b-a4b-it")
      VLLM_MODEL_ID="gem426a4b"
      ;;

    "microsoft/phi-4-multimodal-instruct")
      VLLM_MODEL_ID="phi4multi"
      ;;

    "qwen/qwen2.5-vl-7b-instruct")
      VLLM_MODEL_ID="qwen25vl7"
      ;;

    "openai/whisper-large-v3")
      VLLM_MODEL_ID="openai-whisperv3"
      ;;

    *)
      VLLM_MODEL_ID="unset"
      export VLLM_MODEL_ID
      echo "[ERROR] Unsupported vLLM CPU model: ${model_name}" >&2
      return 1
      ;;
  esac

  # Production normalization:
  # 1. lowercase
  # 2. replace every period character with "-"
  # 3. replace non-DNS-safe characters with "-"
  # 4. collapse duplicate "-"
  # 5. trim leading/trailing "-"
  # 6. enforce max length of 14 characters
  VLLM_MODEL_ID="$(
    printf '%s' "${VLLM_MODEL_ID}" \
      | tr '[:upper:]' '[:lower:]' \
      | tr '.' '-' \
      | sed -E 's/[^a-z0-9-]+/-/g' \
      | sed -E 's/-+/-/g' \
      | sed -E 's/^-+//; s/-+$//'
  )"

  if (( ${#VLLM_MODEL_ID} > 14 )); then
    VLLM_MODEL_ID="${VLLM_MODEL_ID:0:14}"
    VLLM_MODEL_ID="$(printf '%s' "${VLLM_MODEL_ID}" | sed -E 's/-+$//')"
  fi

  export VLLM_MODEL_ID
  return 0
}


set_architecture_defaults() {
  case "$1" in
    amd64)
      ARCH="amd64"
      ARCH_LABEL="x86_64 / Intel 64 / AMD64"
      NODE_ARCH="amd64"
      DOCKERFILE_NAME="amd64.Dockerfile"
      BASE_IMAGE="${BASE_IMAGE_AMD64:-docker.io/vllm/vllm-openai-cpu:v0.22.0-x86_64}"
      ;;
    arm64)
      ARCH="arm64"
      ARCH_LABEL="aarch64 / AArch64"
      NODE_ARCH="arm64"
      DOCKERFILE_NAME="arm64.Dockerfile"
      BASE_IMAGE="${BASE_IMAGE_ARM64:-docker.io/vllm/vllm-openai-cpu:v0.22.0-arm64}"
      ;;
    ppc64le)
      ARCH="ppc64le"
      ARCH_LABEL="IBM Power little-endian"
      NODE_ARCH="ppc64le"
      DOCKERFILE_NAME="ppc64le.Dockerfile"
      BASE_IMAGE="${BASE_IMAGE_PPC64LE:-registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0}"
      ;;
    s390x)
      ARCH="s390x"
      ARCH_LABEL="IBM Z"
      NODE_ARCH="s390x"
      DOCKERFILE_NAME="s390x.Dockerfile"
      BASE_IMAGE="${BASE_IMAGE_S390X:-registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0}"
      ;;
    *) fail "unsupported architecture: $1" ;;
  esac

  if [[ -n "${BASE_IMAGE_OVERRIDE:-}" ]]; then
    BASE_IMAGE="$BASE_IMAGE_OVERRIDE"
  fi
}

select_architecture() {
  local choice
  print_arch_menu
  printf 'Enter architecture option [1-4]: '
  read -r choice
  case "$choice" in
    1) set_architecture_defaults amd64 ;;
    2) set_architecture_defaults arm64 ;;
    3) set_architecture_defaults ppc64le ;;
    4) set_architecture_defaults s390x ;;
    *) fail "invalid architecture option: $choice" ;;
  esac
}

reject_docker_model_artifact_images() {
  local image="$1"
  case "$image" in
    ai/gpt-oss-vllm|ai/gpt-oss-vllm:*|docker.io/ai/gpt-oss-vllm|docker.io/ai/gpt-oss-vllm:*)
      fail "${image} is a Docker Model Runner model artifact, not a valid OpenShift Dockerfile FROM image. Use an architecture-specific vLLM runtime image instead."
      ;;
  esac
}

verify_required_files() {
  local file
  for file in amd64.Dockerfile arm64.Dockerfile ppc64le.Dockerfile s390x.Dockerfile; do
    [[ -f "${SCRIPT_DIR}/${file}" ]] || fail "required Dockerfile is missing: ${file}"
  done
  [[ -f "${SCRIPT_DIR}/${DOCKERFILE_NAME}" ]] || fail "selected Dockerfile missing: ${DOCKERFILE_NAME}"
}

maybe_verify_image_arch() {
  [[ "${VERIFY_IMAGE_ARCH:-0}" == "1" ]] || return 0
  if ! command -v skopeo >/dev/null 2>&1; then
    warn "VERIFY_IMAGE_ARCH=1 requested, but skopeo is not installed; skipping image-architecture check."
    return 0
  fi
  log "Verifying base image architecture with skopeo: ${BASE_IMAGE} (${ARCH})"
  skopeo inspect --override-os linux --override-arch "$ARCH" "docker://${BASE_IMAGE}" >/dev/null \
    || fail "base image ${BASE_IMAGE} is not inspectable for linux/${ARCH}."
}

dns_label_truncate() {
  local value="${1:-}"
  local max_len="${2:-63}"
  local hash_input="${3:-${value}}"
  local label hash keep

  label="$(slugify "$value")"
  [[ -n "$label" ]] || label="x"

  if (( max_len < 1 )); then
    fail "invalid DNS label max length: ${max_len}"
  fi

  if (( ${#label} <= max_len )); then
    printf '%s' "$label"
    return 0
  fi

  if (( max_len <= 9 )); then
    label="${label:0:${max_len}}"
    label="$(printf '%s' "$label" | sed -E 's#-+$##')"
    [[ -n "$label" ]] || label="x"
    printf '%s' "$label"
    return 0
  fi

  hash="$(short_hash "$hash_input")"
  keep=$(( max_len - 9 ))
  label="${label:0:${keep}}-${hash}"
  label="$(printf '%s' "$label" | sed -E 's#-+$##')"
  [[ -n "$label" ]] || label="x"
  printf '%s' "$label"
}

route_trimmer() {
  # Normalize the deployment/route base name so OpenShift-generated objects stay short:
  #   default Route host first label: <route-name>-<namespace> <= 63 chars
  #   generated Pod name:            <deployment-name>-<generated-suffix> remains compact
  # The namespace is security-driven and is expected to come from VLLM_MODEL_ID.
  local model_id="${1:-${MODEL_ID:-}}"
  local namespace="${2:-${NAMESPACE:-}}"
  local arch="${3:-${ARCH:-}}"
  local ns_label model_label desired_app max_app route_budget pod_budget original_app host_first host_rest trimmed_first

  ns_label="$(dns_label_truncate "$namespace" "${NAMESPACE_MAX_LEN:-14}" "$model_id-$namespace")"
  model_label="${VLLM_MODEL_ID:-}"
  if [[ -z "$model_label" || "$model_label" == "unset" ]]; then
    model_label="$model_id"
  fi
  model_label="$(dns_label_truncate "$model_label" "${MODEL_ROUTE_TOKEN_MAX:-24}" "$model_id")"

  NAMESPACE="$ns_label"
  export NAMESPACE

  desired_app="vllm-${model_label}-${arch}"

  # OpenShift default route hosts are commonly rendered as
  # <route-name>-<namespace>.<apps-domain>. Keep that first DNS label <= 63.
  route_budget=$(( 63 - ${#NAMESPACE} - 1 ))
  if (( route_budget < 12 )); then
    fail "namespace ${NAMESPACE} is too long to produce a valid OpenShift Route host label."
  fi

  # Keep the Deployment name intentionally shorter than the Kubernetes DNS-label limit,
  # because generated pod names append controller/random suffixes.
  pod_budget="${POD_APP_NAME_MAX:-40}"
  max_app=63
  (( route_budget < max_app )) && max_app=$route_budget
  (( pod_budget < max_app )) && max_app=$pod_budget

  original_app="${APP_NAME:-$desired_app}"
  APP_NAME="$(dns_label_truncate "$original_app" "$max_app" "$model_id-$namespace-$arch")"
  export APP_NAME

  # If a custom ROUTE_HOST is supplied, protect it from the same first-label failure.
  if [[ -n "${ROUTE_HOST:-}" ]]; then
    host_first="${ROUTE_HOST%%.*}"
    if [[ "$ROUTE_HOST" == *.* ]]; then
      host_rest=".${ROUTE_HOST#*.}"
    else
      host_rest=""
    fi
    trimmed_first="$(dns_label_truncate "$host_first" 63 "$model_id-$namespace-$arch-route-host")"
    ROUTE_HOST="${trimmed_first}${host_rest}"
    export ROUTE_HOST
  fi

  ROUTE_HOST_LABEL="${APP_NAME}-${NAMESPACE}"
  if (( ${#ROUTE_HOST_LABEL} > 63 )); then
    fail "internal route_trimmer error: ${ROUTE_HOST_LABEL} is longer than 63 characters."
  fi
  export ROUTE_HOST_LABEL
}

prepare_names() {
  [[ -n "${VLLM_MODEL_ID:-}" && "${VLLM_MODEL_ID}" != "unset" ]] || vllm_models "$MODEL_ID"
  NAMESPACE="${NAMESPACE:-${VLLM_MODEL_ID}}"
  route_trimmer "$MODEL_ID" "$NAMESPACE" "$ARCH"
  SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-$(basename "$MODEL_ID")}" 
  [[ -n "$SERVED_MODEL_NAME" ]] || SERVED_MODEL_NAME="model"
}

write_build_context() {
  rm -rf "$BUILD_DIR"
  mkdir -p "$BUILD_DIR"
  cp "${SCRIPT_DIR}/amd64.Dockerfile" "$BUILD_DIR/"
  cp "${SCRIPT_DIR}/arm64.Dockerfile" "$BUILD_DIR/"
  cp "${SCRIPT_DIR}/ppc64le.Dockerfile" "$BUILD_DIR/"
  cp "${SCRIPT_DIR}/s390x.Dockerfile" "$BUILD_DIR/"
  cat > "${BUILD_DIR}/BUILD_SELECTION.txt" <<EOF_SUMMARY
Model ID: ${MODEL_ID}
Served model name: ${SERVED_MODEL_NAME}
Architecture: ${ARCH} (${ARCH_LABEL})
Node selector: kubernetes.io/arch=${NODE_ARCH}
Selected Dockerfile: ${DOCKERFILE_NAME}
Selected base image: ${BASE_IMAGE}
Generated by: ${SCRIPT_NAME}
EOF_SUMMARY
}

write_manifests() {
  rm -rf "$MANIFEST_DIR"
  mkdir -p "$MANIFEST_DIR"

  local model_q served_q base_q api_key_q hf_token_q dtype_q max_model_len_q kv_cache_q extra_args_q shm_q
  model_q="$(yaml_dq "$MODEL_ID")"
  served_q="$(yaml_dq "$SERVED_MODEL_NAME")"
  base_q="$(yaml_dq "$BASE_IMAGE")"
  api_key_q="$(yaml_dq "${VLLM_API_KEY}")"
  hf_token_q="$(yaml_dq "${HF_TOKEN:-}")"
  dtype_q="$(yaml_dq "${DTYPE}")"
  max_model_len_q="$(yaml_dq "${MAX_MODEL_LEN}")"
  kv_cache_q="$(yaml_dq "${VLLM_CPU_KVCACHE_SPACE}")"
  extra_args_q="$(yaml_dq "${EXTRA_VLLM_ARGS:-}")"
  shm_q="$(yaml_dq "${SHM_SIZE}")"

  cat > "${MANIFEST_DIR}/01-build.yaml" <<EOF_BUILD
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
---
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: vllm-cpu
    app.kubernetes.io/part-of: vllm-openshift
spec:
  runPolicy: Serial
  source:
    type: Binary
    binary: {}
  strategy:
    type: Docker
    dockerStrategy:
      dockerfilePath: ${DOCKERFILE_NAME}
      buildArgs:
        - name: BASE_IMAGE
          value: ${base_q}
  output:
    to:
      kind: ImageStreamTag
      name: ${APP_NAME}:latest
EOF_BUILD

  if [[ "$BASE_IMAGE" == registry.redhat.io/* ]]; then
    cat >> "${MANIFEST_DIR}/01-build.yaml" <<'EOF_PULL'
      
EOF_PULL
    # Insert pullSecret under dockerStrategy by rebuilding with awk to avoid YAML indentation mistakes.
    awk '
      { print }
      /dockerfilePath:/ && !done { print "      pullSecret:"; print "        name: rh-registry-pull"; done=1 }
    ' "${MANIFEST_DIR}/01-build.yaml" > "${MANIFEST_DIR}/01-build.yaml.tmp"
    mv "${MANIFEST_DIR}/01-build.yaml.tmp" "${MANIFEST_DIR}/01-build.yaml"
  fi

  cat > "${MANIFEST_DIR}/02-runtime.yaml" <<EOF_RUNTIME
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: ${APP_NAME}-model-cache
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
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
  labels:
    app.kubernetes.io/name: ${APP_NAME}
type: Opaque
stringData:
  vllm-api-key: ${api_key_q}
  hf-token: ${hf_token_q}
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
    app.kubernetes.io/component: vllm-openai-api
spec:
  replicas: ${REPLICAS}
  selector:
    matchLabels:
      app.kubernetes.io/name: ${APP_NAME}
  template:
    metadata:
      labels:
        app.kubernetes.io/name: ${APP_NAME}
        app.kubernetes.io/component: vllm-openai-api
    spec:
      nodeSelector:
        kubernetes.io/arch: ${NODE_ARCH}
      terminationGracePeriodSeconds: 120
      containers:
        - name: vllm
          image: image-registry.openshift-image-registry.svc:5000/${NAMESPACE}/${APP_NAME}:latest
          imagePullPolicy: Always
          command:
            - /bin/sh
            - -c
          args:
            - |
              set -eu
              exec python3 -m vllm.entrypoints.openai.api_server \
                --model "\${MODEL_ID}" \
                --served-model-name "\${SERVED_MODEL_NAME}" \
                --host 0.0.0.0 \
                --port "\${VLLM_PORT}" \
                --dtype "\${DTYPE}" \
                --max-model-len "\${MAX_MODEL_LEN}" \
                --api-key "\${VLLM_API_KEY}" \
                \${EXTRA_VLLM_ARGS}
          ports:
            - name: http
              containerPort: ${VLLM_PORT}
              protocol: TCP
          env:
            - name: MODEL_ID
              value: ${model_q}
            - name: SERVED_MODEL_NAME
              value: ${served_q}
            - name: VLLM_PORT
              value: "${VLLM_PORT}"
            - name: DTYPE
              value: ${dtype_q}
            - name: MAX_MODEL_LEN
              value: ${max_model_len_q}
            - name: EXTRA_VLLM_ARGS
              value: ${extra_args_q}
            - name: VLLM_TARGET_DEVICE
              value: "cpu"
            - name: VLLM_CPU_KVCACHE_SPACE
              value: ${kv_cache_q}
            - name: HF_HOME
              value: /models/huggingface
            - name: TRANSFORMERS_CACHE
              value: /models/huggingface
            - name: VLLM_API_KEY
              valueFrom:
                secretKeyRef:
                  name: ${APP_NAME}-secrets
                  key: vllm-api-key
            - name: HF_TOKEN
              valueFrom:
                secretKeyRef:
                  name: ${APP_NAME}-secrets
                  key: hf-token
          resources:
            requests:
              cpu: ${CPU_REQUEST}
              memory: ${MEMORY_REQUEST}
            limits:
              cpu: ${CPU_LIMIT}
              memory: ${MEMORY_LIMIT}
          volumeMounts:
            - name: model-cache
              mountPath: /models
            - name: shm
              mountPath: /dev/shm
          readinessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: ${READINESS_INITIAL_DELAY_SECONDS}
            periodSeconds: 10
            timeoutSeconds: 5
            failureThreshold: 60
          livenessProbe:
            httpGet:
              path: /health
              port: http
            initialDelaySeconds: ${LIVENESS_INITIAL_DELAY_SECONDS}
            periodSeconds: 30
            timeoutSeconds: 10
            failureThreshold: 10
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop:
                - ALL
      volumes:
        - name: model-cache
          persistentVolumeClaim:
            claimName: ${APP_NAME}-model-cache
        - name: shm
          emptyDir:
            medium: Memory
            sizeLimit: ${shm_q}
---
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
spec:
  selector:
    app.kubernetes.io/name: ${APP_NAME}
  ports:
    - name: http
      port: 8000
      targetPort: http
      protocol: TCP
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: ${APP_NAME}
spec:
  to:
    kind: Service
    name: ${APP_NAME}
  port:
    targetPort: http
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
EOF_RUNTIME

  if [[ -n "${ROUTE_HOST:-}" ]]; then
    awk -v host="${ROUTE_HOST}" '
      $0 == "kind: Route" { in_route=1 }
      { print }
      in_route && /^spec:/ && !done { print "  host: " host; done=1; in_route=0 }
    ' "${MANIFEST_DIR}/02-runtime.yaml" > "${MANIFEST_DIR}/02-runtime.yaml.tmp"
    mv "${MANIFEST_DIR}/02-runtime.yaml.tmp" "${MANIFEST_DIR}/02-runtime.yaml"
  fi
}

create_redhat_pull_secret_if_needed() {
  [[ "$BASE_IMAGE" == registry.redhat.io/* ]] || return 0
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    return 0
  fi

  if oc -n "$NAMESPACE" get secret rh-registry-pull >/dev/null 2>&1; then
    log "Using existing rh-registry-pull secret in namespace ${NAMESPACE}."
  else
    [[ -n "${RH_REGISTRY_USERNAME:-}" ]] || fail "BASE_IMAGE is from registry.redhat.io, but rh-registry-pull does not exist and RH_REGISTRY_USERNAME is not set in .env."
    [[ -n "${RH_REGISTRY_PASSWORD:-}" ]] || fail "BASE_IMAGE is from registry.redhat.io, but rh-registry-pull does not exist and RH_REGISTRY_PASSWORD is not set in .env."

    oc -n "$NAMESPACE" create secret docker-registry rh-registry-pull \
      --docker-server=registry.redhat.io \
      --docker-username="$RH_REGISTRY_USERNAME" \
      --docker-password="$RH_REGISTRY_PASSWORD" \
      --docker-email="${RH_REGISTRY_EMAIL:-unused@example.com}" \
      --dry-run=client -o yaml | oc apply -f -
  fi

  oc -n "$NAMESPACE" secrets link builder rh-registry-pull --for=pull || true
  oc -n "$NAMESPACE" secrets link default rh-registry-pull --for=pull || true
  oc -n "$NAMESPACE" secrets link deployer rh-registry-pull --for=pull || true
}

oc_login_and_project() {
  [[ -n "${OCP_URL:-}" ]] || fail "OCP_URL must be set in .env."
  [[ -n "${OCP_TOKEN:-}" ]] || fail "OCP_TOKEN must be set in .env."
  command -v oc >/dev/null 2>&1 || fail "oc CLI is required for live deployment."

  local tls_args=()
  if [[ "${OCP_INSECURE_SKIP_TLS_VERIFY:-false}" == "true" || "${OCP_INSECURE_SKIP_TLS_VERIFY:-false}" == "1" ]]; then
    tls_args+=(--insecure-skip-tls-verify=true)
  fi

  oc login "$OCP_URL" --token="$OCP_TOKEN" "${tls_args[@]}"
  if oc get project "$NAMESPACE" >/dev/null 2>&1; then
    oc project "$NAMESPACE"
  else
    oc new-project "$NAMESPACE"
  fi
}

apply_and_build() {
  oc apply -f "${MANIFEST_DIR}/01-build.yaml"
  log "Starting OpenShift binary build from ${BUILD_DIR} using ${DOCKERFILE_NAME}."
  oc start-build "$APP_NAME" -n "$NAMESPACE" --from-dir="$BUILD_DIR" --follow --wait
  oc apply -f "${MANIFEST_DIR}/02-runtime.yaml"
  oc -n "$NAMESPACE" rollout status "deployment/${APP_NAME}" --timeout="${ROLLOUT_TIMEOUT}"

  local route_host
  route_host="$(oc -n "$NAMESPACE" get route "$APP_NAME" -o jsonpath='{.spec.host}')"
  printf '\nDeployment complete.\n'
  printf 'OpenAI-compatible base URL: https://%s/v1\n' "$route_host"
  printf 'Model name for requests: %s\n' "$SERVED_MODEL_NAME"
  printf 'API key secret: %s-secrets / key vllm-api-key\n' "$APP_NAME"
}

main() {
  load_env
  redhat_registry_login

  # Runtime defaults. Override in .env when needed.
  REPLICAS="${REPLICAS:-1}"
  VLLM_PORT="${VLLM_PORT:-8000}"
  DTYPE="${DTYPE:-auto}"
  MAX_MODEL_LEN="${MAX_MODEL_LEN:-4096}"
  VLLM_CPU_KVCACHE_SPACE="${VLLM_CPU_KVCACHE_SPACE:-8}"
  CPU_REQUEST="${CPU_REQUEST:-4}"
  CPU_LIMIT="${CPU_LIMIT:-8}"
  MEMORY_REQUEST="${MEMORY_REQUEST:-16Gi}"
  MEMORY_LIMIT="${MEMORY_LIMIT:-64Gi}"
  PVC_SIZE="${PVC_SIZE:-200Gi}"
  SHM_SIZE="${SHM_SIZE:-8Gi}"
  READINESS_INITIAL_DELAY_SECONDS="${READINESS_INITIAL_DELAY_SECONDS:-120}"
  LIVENESS_INITIAL_DELAY_SECONDS="${LIVENESS_INITIAL_DELAY_SECONDS:-240}"
  ROLLOUT_TIMEOUT="${ROLLOUT_TIMEOUT:-45m}"
  VLLM_API_KEY="${VLLM_API_KEY:-$(short_hash "${RANDOM:-0}-$(date +%s 2>/dev/null || true)")-$(short_hash "vllm")}"
  EXTRA_VLLM_ARGS="${EXTRA_VLLM_ARGS:-}"

  set_namespace() {
    NAMESPACE="${VLLM_MODEL_ID}"
    export NAMESPACE
  }

  if [[ -z "${MODEL_ID:-}" ]]; then
    select_model
  fi
  vllm_models "$MODEL_ID"
  set_namespace

  if [[ -n "${ARCH:-}" ]]; then
    set_architecture_defaults "$ARCH"
  else
    select_architecture
  fi

  reject_docker_model_artifact_images "$BASE_IMAGE"
  verify_required_files
  maybe_verify_image_arch
  prepare_names

  WORK_DIR="${WORK_DIR:-${SCRIPT_DIR}/.build-${APP_NAME}}"
  BUILD_DIR="${WORK_DIR}/context"
  MANIFEST_DIR="${WORK_DIR}/manifests"
  mkdir -p "$WORK_DIR"
  write_build_context
  write_manifests

  log "Selected model: ${MODEL_ID}"
  log "Selected architecture: ${ARCH} (${ARCH_LABEL})"
  log "Selected Dockerfile: ${DOCKERFILE_NAME}"
  log "Selected base image: ${BASE_IMAGE}"
  log "Normalized namespace: ${NAMESPACE}"
  log "Normalized app/route/deployment name: ${APP_NAME}"
  log "OpenShift default route first label: ${ROUTE_HOST_LABEL} (${#ROUTE_HOST_LABEL}/63)"
  log "Build context: ${BUILD_DIR}"
  log "Manifests: ${MANIFEST_DIR}"

  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    log "DRY_RUN=1 set; not logging into OpenShift and not starting a build."
    exit 0
  fi

  oc_login_and_project
  create_redhat_pull_secret_if_needed
  apply_and_build
}

main "$@"
