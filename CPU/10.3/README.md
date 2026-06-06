# CPU-633679964-VLLM-OPENSHIFT / v10.3

Production OpenShift deployment bundle for CPU-backed vLLM model serving.

```text
Code ID: CPU-633679964-VLLM-OPENSHIFT
Version: 10.3
Primary script: deploy-vllm-openshift.sh
```

## What changed from v10.2

v10.3 is a conservative hardening release. It keeps the approved v10.x production behavior and adds only the research-derived non-root entrypoint and Dockerfile guard checks.

Kept from production/v10.2:

- Service name remains `${APP_NAME}`.
- Route name remains `${APP_NAME}`.
- Deployment name remains `${APP_NAME}`.
- Service links remain enabled.
- No `api-*` Service rewrite.
- No service-discovery ConfigMap rewrite.
- The Secret object remains `${APP_NAME}-secrets`.
- The API key Secret data key remains `${APP_NAME}-vllm-api-key`.
- `amd64` and `arm64` keep upstream vLLM CPU base images.
- `ppc64le` and `s390x` keep the Red Hat Spyre base image default.

Added in v10.3:

- `entrypoints/vllm-nonroot-entrypoint.sh`, derived from the research Docker bundle.
- Dockerfiles copy and use the non-root entrypoint.
- Dockerfiles create OpenShift-friendly writable cache/home paths.
- Dockerfiles mark `/etc/passwd` group-writable when possible, allowing arbitrary OpenShift UIDs to get a synthetic passwd entry.
- `validate_dockerfile_syntax_guards()` catches trailing whitespace after Dockerfile line-continuation backslashes before an OpenShift build starts.
- Build context now includes the `entrypoints/` directory.

## Bundle layout

```text
vllm-production-v10.3/
├── deploy-vllm-openshift.sh
├── amd64.Dockerfile
├── arm64.Dockerfile
├── ppc64le.Dockerfile
├── s390x.Dockerfile
├── entrypoints/
│   ├── vllm-nonroot-entrypoint.sh
│   └── test_vllm_nonroot_entrypoint.sh
├── test-local.sh
├── README.md
├── TEST_PROOF.md
└── V10.2_TO_V10.3.diff
```

## Required `.env`

Place `.env` one directory above the bundle directory, or set `ENV_FILE` explicitly.

```bash
OCP_URL=https://api.your-cluster.example.com:6443
OCP_TOKEN=sha256~your-token

# Required only when using registry.redhat.io base images and the namespace does
# not already have rh-registry-pull linked to builder/default/deployer.
RH_REGISTRY_USERNAME=your-redhat-registry-user
RH_REGISTRY_PASSWORD=your-redhat-registry-password
```

Optional shared vLLM API key:

```bash
VLLM_API_KEY='your-approved-api-key'
```

If omitted, the script generates a key for each deployment.

## Deploy

```bash
chmod +x deploy-vllm-openshift.sh
./deploy-vllm-openshift.sh
```

For non-interactive dry-run testing:

```bash
DRY_RUN=1 \
MODEL_ID='ibm-granite/granite-3.2-2b-instruct' \
ARCH=amd64 \
VLLM_API_KEY='unit-test-key' \
./deploy-vllm-openshift.sh
```

## Retrieve the API key

For IBM Granite on amd64:

```bash
NAMESPACE='ibm-granite2b'
APP_NAME='vllm-ibm-granite2b-amd64'
SECRET="${APP_NAME}-secrets"
SECRET_KEY="${APP_NAME}-vllm-api-key"

API_KEY="$(oc -n "$NAMESPACE" get secret "$SECRET" \
  -o "go-template={{ index .data \"${SECRET_KEY}\" }}" | base64 -d)"
```

## Test the endpoint

```bash
BASE_URL="https://$(oc -n "$NAMESPACE" get route "$APP_NAME" -o jsonpath='{.spec.host}')/v1"

curl -sS "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"granite-3.2-2b-instruct","messages":[{"role":"user","content":"Say hello from IBM Granite."}],"max_tokens":80}' \
  | jq -r '.choices[0].message.content'
```

## Local validation

```bash
./test-local.sh
```

See `TEST_PROOF.md` for the validation output captured during bundle creation.
