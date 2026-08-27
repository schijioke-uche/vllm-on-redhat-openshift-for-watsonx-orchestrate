# vLLM CPU on Red Hat OpenShift for IBM watsonx Orchestrate

## Deployment Overview

This guide provides a step-by-step procedure for deploying the CPU-based vLLM asset from the `CPU/10.3` bundle in the `vllm-on-redhat-openshift-for-watsonx-orchestrate` repository.

The deployment creates an OpenAI-compatible vLLM inference endpoint on Red Hat OpenShift that can be consumed by IBM watsonx Orchestrate running on IBM Software Hub / enterprise Cloud Pak for Data. The current CPU v10.3 bundle is a hardened release that preserves the production behavior of v10.2 while adding OpenShift-friendly non-root execution, writable cache/home paths, arbitrary UID handling, and Dockerfile syntax guards.

Repository:

`https://github.com/schijioke-uche/vllm-on-redhat-openshift-for-watsonx-orchestrate`

Deployment bundle:

`CPU/10.3`

---

## 1. What Is Included

The CPU v10.3 bundle contains the following deployment assets:

```text
CPU/10.3/
├── README.md
├── TEST_PROOF.md
├── MANIFEST.txt
├── amd64.Dockerfile
├── arm64.Dockerfile
├── ppc64le.Dockerfile
├── s390x.Dockerfile
├── deploy-vllm-openshift.sh
├── deploy.sh
├── test-local.sh
├── xLaunchpad.sh
└── entrypoints/
    ├── vllm-nonroot-entrypoint.sh
    └── test_vllm_nonroot_entrypoint.sh
```

### File responsibilities

| File | Purpose |
|---|---|
| `deploy-vllm-openshift.sh` | Primary production deployment workflow. Selects the model and architecture, validates the environment, creates build/runtime manifests, deploys the workload, and exposes the vLLM endpoint. |
| `deploy.sh` | Deployment-script copy/entry point that mirrors the primary deployment workflow. |
| `xLaunchpad.sh` | Interactive launchpad that starts the primary deployment script from a simple menu. |
| `amd64.Dockerfile` | CPU wrapper for x86_64 / AMD64 OpenShift worker nodes. |
| `arm64.Dockerfile` | CPU wrapper for ARM64 / AArch64 OpenShift worker nodes. |
| `ppc64le.Dockerfile` | CPU wrapper for IBM Power little-endian worker nodes. |
| `s390x.Dockerfile` | CPU wrapper for IBM Z / s390x worker nodes. |
| `entrypoints/vllm-nonroot-entrypoint.sh` | OpenShift-safe non-root runtime entrypoint. Handles arbitrary UIDs, writable home/cache locations, and starts `vllm serve` or the OpenAI API server module. |
| `entrypoints/test_vllm_nonroot_entrypoint.sh` | Unit tests for the non-root entrypoint behavior. |
| `test-local.sh` | Local syntax, packaging, Dockerfile, dry-run, manifest, and regression validation. |
| `TEST_PROOF.md` | Captured validation evidence for the v10.3 bundle. |
| `MANIFEST.txt` | Bundle identity and file inventory. |

---

## 2. Supported CPU Architectures

The deployment supports four OpenShift CPU architectures:

| Option | Architecture | Platform |
|---|---|---|
| `1` | `amd64` | x86_64 / Intel 64 / AMD64 |
| `2` | `arm64` | ARM64 / AArch64 |
| `3` | `ppc64le` | IBM Power little-endian |
| `4` | `s390x` | IBM Z |

The default container bases used by the v10.3 Dockerfiles are:

```text
amd64:
docker.io/vllm/vllm-openai-cpu:v0.22.0-x86_64

arm64:
docker.io/vllm/vllm-openai-cpu:v0.22.0-arm64

ppc64le:
registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0

s390x:
registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0
```

The architecture selected during deployment must match the architecture of an available OpenShift worker node.

---

## 3. Example Models

The interactive deployment menu includes the following examples:

```text
1. ibm-granite/granite-3.2-2b-instruct
2. unsloth/gpt-oss-20b
3. RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8
4. RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w8a8
5. Any other CPU-supported model ID
```

For initial validation, IBM Granite is the recommended small CPU smoke-test model:

```text
ibm-granite/granite-3.2-2b-instruct
```

Large models can require substantial CPU, memory, model-cache storage, and startup time.

---

## 4. Prerequisites

Before deploying, make sure the workstation or bastion host has:

- Git
- Bash
- Red Hat OpenShift CLI (`oc`)
- Access to the target Red Hat OpenShift cluster
- Permission to create or manage projects/namespaces, builds, deployments, services, routes, secrets, PVCs, and image streams
- Network access to the selected container registry
- Network access to the model repository used by the selected model
- Sufficient CPU and memory on an OpenShift worker node matching the selected architecture
- A compatible OpenShift StorageClass for the model-cache PVC
- Red Hat registry credentials when a `registry.redhat.io` base image must be pulled and the namespace does not already have an appropriate pull secret

Verify the CLI:

```bash
oc version
```

Verify that you are authenticated:

```bash
oc whoami
```

Check cluster worker architectures:

```bash
oc get nodes \
  -o custom-columns='NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory'
```

Check available StorageClasses:

```bash
oc get storageclass
```

---

## 5. Clone the Repository

Clone the repository:

```bash
git clone \
  https://github.com/schijioke-uche/vllm-on-redhat-openshift-for-watsonx-orchestrate.git
```

Enter the CPU v10.3 deployment directory:

```bash
cd vllm-on-redhat-openshift-for-watsonx-orchestrate/CPU/10.3
```

Confirm the expected files are present:

```bash
ls -la
ls -la entrypoints
```

---

## 6. Prepare the OpenShift Connection

Obtain the OpenShift API URL and login token from the target cluster.

Example:

```bash
oc login \
  --server="https://api.example.openshift.com:6443" \
  --token="<OPENSHIFT_TOKEN>"
```

Verify:

```bash
oc whoami
oc whoami --show-server
```

The v10.3 bundle also supports loading its OpenShift connection values from an environment file.

---

## 7. Create the `.env` File

The documented v10.3 layout expects `.env` one directory above the `10.3` bundle unless `ENV_FILE` is explicitly set.

From:

```text
CPU/10.3
```

the default environment file should therefore be:

```text
CPU/.env
```

Create it:

```bash
cd ..
touch .env
chmod 600 .env
```

Add the OpenShift connection values:

```bash
cat > .env <<'EOF'
OCP_URL=https://api.your-cluster.example.com:6443
OCP_TOKEN=sha256~your-openshift-token
EOF
```

Return to the deployment directory:

```bash
cd 10.3
```

### Red Hat registry credentials

For `ppc64le` and `s390x`, the default base image is hosted on `registry.redhat.io`.

If the namespace does not already have a valid Red Hat registry pull secret linked to its builder/default/deployer service accounts, add:

```bash
cat >> ../.env <<'EOF'
RH_REGISTRY_USERNAME=your-redhat-registry-user
RH_REGISTRY_PASSWORD=your-redhat-registry-password
EOF
```

Do not commit `.env` to Git.

---

## 8. Optional vLLM API Key

The deployment protects the vLLM endpoint with an API key.

You can provide an approved key through the environment:

```bash
export VLLM_API_KEY='your-approved-api-key'
```

or add it to the external `.env` file:

```bash
VLLM_API_KEY='your-approved-api-key'
```

If the key is omitted, the deployment workflow can generate a key for the deployment.

The resulting OpenShift Secret is named:

```text
${APP_NAME}-secrets
```

and the vLLM API key is stored under:

```text
${APP_NAME}-vllm-api-key
```

---

## 9. Optional Resource Overrides

The script performs CPU and memory scheduling checks before deployment and supports runtime resource parameters.

Examples:

```bash
export CPU_REQUEST="4"
export MEMORY_REQUEST="16Gi"
export PVC_SIZE="50Gi"
```

For a small smoke test, lower values can be used only when they are appropriate for the selected model:

```bash
export CPU_REQUEST="1"
export MEMORY_REQUEST="4Gi"
```

Production values must be sized for the actual model.

You can inspect current node capacity and usage with:

```bash
oc adm top nodes
```

The deployment script contains additional scheduling-fit logic that compares the requested CPU and memory against allocatable node resources and existing pod requests.

---

## 10. Validate the Bundle Before Deployment

Make the validation scripts executable:

```bash
chmod +x \
  deploy-vllm-openshift.sh \
  deploy.sh \
  test-local.sh \
  xLaunchpad.sh \
  entrypoints/vllm-nonroot-entrypoint.sh \
  entrypoints/test_vllm_nonroot_entrypoint.sh
```

Run Bash syntax validation:

```bash
bash -n deploy-vllm-openshift.sh
bash -n deploy.sh
bash -n test-local.sh
bash -n xLaunchpad.sh
bash -n entrypoints/vllm-nonroot-entrypoint.sh
bash -n entrypoints/test_vllm_nonroot_entrypoint.sh
```

Run the repository's local validation suite:

```bash
./test-local.sh
```

The v10.3 test suite validates:

- required bundle files
- Bash syntax
- non-root entrypoint behavior
- Dockerfile hardening
- dry-run manifest generation
- API-key Secret naming
- preserved Service and Route naming
- Dockerfile continuation-line guards
- regression protection against rejected experimental changes

---

## 11. Perform a Dry Run

Before changing the cluster, generate and validate the deployment using dry-run mode.

Example for IBM Granite on AMD64:

```bash
DRY_RUN=1 \
MODEL_ID='ibm-granite/granite-3.2-2b-instruct' \
ARCH=amd64 \
VLLM_API_KEY='unit-test-key' \
./deploy-vllm-openshift.sh
```

Inspect the generated build-selection and manifest data before running the live deployment.

The script generates OpenShift resources that include:

- ImageStream
- BuildConfig
- PersistentVolumeClaim
- Secret
- Deployment
- Service
- Route

The BuildConfig uses a binary Docker build and the architecture-specific Dockerfile selected by the deployment workflow.

---

## 12. Deploy Interactively

The simplest deployment method is:

```bash
./deploy-vllm-openshift.sh
```

The script prompts for the model and the target OpenShift CPU architecture.

### Example selection

For IBM Granite on AMD64:

```text
Model:
1 - ibm-granite/granite-3.2-2b-instruct

Architecture:
1 - amd64
```

The deployment workflow then derives DNS-safe resource names, prepares the build context, generates OpenShift manifests, creates the image build, deploys the runtime, and exposes the service through an OpenShift Route.

The deployment also prevents generated Route labels and workload names from exceeding OpenShift/Kubernetes DNS-label limits.

---

## 13. Deploy Using the Launchpad

The repository also provides an interactive launchpad.

Run:

```bash
./xLaunchpad.sh
```

The launchpad presents:

```text
1 - Deploy VLLM on OpenShift
0 - Quit
```

Selecting `1` invokes `deploy-vllm-openshift.sh`.

This is useful for demonstrations or guided deployments where operators prefer a simple menu rather than running the primary script directly.

---

## 14. Verify the OpenShift Resources

After deployment, determine the generated namespace and application name.

For IBM Granite on AMD64, the repository README uses an example similar to:

```bash
NAMESPACE='ibm-granite2b'
APP_NAME='vllm-ibm-granite2b-amd64'
```

List the resources:

```bash
oc -n "$NAMESPACE" get all
```

Check the route:

```bash
oc -n "$NAMESPACE" get route
```

Check the PVC:

```bash
oc -n "$NAMESPACE" get pvc
```

Check the Secret:

```bash
oc -n "$NAMESPACE" get secret "${APP_NAME}-secrets"
```

Check the pod:

```bash
oc -n "$NAMESPACE" get pods -o wide
```

Follow startup logs:

```bash
oc -n "$NAMESPACE" logs \
  -f deployment/"$APP_NAME"
```

Model download and initialization can take significant time depending on model size, network throughput, storage performance, available RAM, and CPU capacity.

---

## 15. Retrieve the vLLM API Key

Set the Secret names:

```bash
SECRET="${APP_NAME}-secrets"
SECRET_KEY="${APP_NAME}-vllm-api-key"
```

Retrieve the API key:

```bash
API_KEY="$(
  oc -n "$NAMESPACE" get secret "$SECRET" \
    -o "go-template={{ index .data \"${SECRET_KEY}\" }}" |
  base64 -d
)"
```

Confirm that a key was returned without printing it into shared logs:

```bash
test -n "$API_KEY" && echo "vLLM API key retrieved successfully."
```

---

## 16. Retrieve the OpenAI-Compatible Endpoint

Get the OpenShift Route:

```bash
ROUTE_HOST="$(
  oc -n "$NAMESPACE" get route "$APP_NAME" \
    -o jsonpath='{.spec.host}'
)"
```

Build the OpenAI-compatible base URL:

```bash
BASE_URL="https://${ROUTE_HOST}/v1"
```

Display only the endpoint:

```bash
echo "$BASE_URL"
```

The vLLM service listens on port `8000` internally and is exposed through the OpenShift Service and Route generated by the deployment.

---

## 17. Test the Model Endpoint

Example using the OpenAI-compatible Chat Completions API:

```bash
curl -sS "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "granite-3.2-2b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Say hello from IBM Granite running on Red Hat OpenShift."
      }
    ],
    "max_tokens": 80
  }'
```

If `jq` is installed:

```bash
curl -sS "${BASE_URL}/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "granite-3.2-2b-instruct",
    "messages": [
      {
        "role": "user",
        "content": "Return only READY."
      }
    ],
    "max_tokens": 20
  }' |
jq -r '.choices[0].message.content'
```

Expected output should contain a valid model response.

---

## 18. Verify the Models API

Test the OpenAI-compatible models endpoint:

```bash
curl -sS "${BASE_URL}/models" \
  -H "Authorization: Bearer ${API_KEY}"
```

This is a useful final connectivity test before registering the endpoint with an upstream application.

---

## 19. Connect the Endpoint to IBM watsonx Orchestrate

Once the endpoint is healthy, use the following connection information when configuring an OpenAI-compatible model connection for IBM watsonx Orchestrate or the applicable enterprise AI integration layer:

```text
Base URL:
https://<OPENSHIFT_ROUTE>/v1

API key:
<value stored in the OpenShift vLLM Secret>

Model:
<served model name>
```

For example:

```text
Base URL:
https://vllm-ibm-granite2b-amd64-ibm-granite2b.apps.example.com/v1

Model:
granite-3.2-2b-instruct
```

The exact watsonx Orchestrate configuration workflow depends on the IBM Software Hub / watsonx Orchestrate release and the model-provider integration method enabled in that environment.

Before using the model in production, validate:

1. watsonx Orchestrate can resolve the OpenShift Route.
2. The Route certificate is trusted.
3. Required network policies and firewalls permit traffic.
4. The API key is stored as a managed secret and is not hardcoded.
5. `/v1/models` succeeds.
6. `/v1/chat/completions` succeeds.
7. The served model name matches the model identifier configured in watsonx Orchestrate.
8. Timeout values account for CPU inference latency.

---

## 20. OpenShift Non-Root Security Model

CPU v10.3 adds an OpenShift-aware non-root entrypoint.

The architecture Dockerfiles:

- create writable model, cache, configuration, and home directories
- assign group `0` permissions suitable for OpenShift
- run the runtime as a non-root user
- make `/etc/passwd` group-writable when possible
- invoke `entrypoints/vllm-nonroot-entrypoint.sh`

The entrypoint supports OpenShift's arbitrary runtime UID behavior. When required and permitted, it creates a synthetic passwd entry for the runtime UID so libraries and command-line tooling can resolve the user consistently.

It starts vLLM using:

```bash
vllm serve ...
```

when the `vllm` executable is available, otherwise it falls back to:

```bash
python3 -m vllm.entrypoints.openai.api_server ...
```

This hardening is one of the primary changes between v10.2 and v10.3.

---

## 21. Architecture-Specific Notes

### AMD64

Default:

```text
docker.io/vllm/vllm-openai-cpu:v0.22.0-x86_64
```

Recommended for general CPU deployment when x86_64 worker nodes provide sufficient memory and CPU.

### ARM64

Default:

```text
docker.io/vllm/vllm-openai-cpu:v0.22.0-arm64
```

The selected worker nodes must report:

```text
kubernetes.io/arch=arm64
```

### IBM Power / PPC64LE

Default:

```text
registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0
```

Red Hat registry authentication or a namespace pull secret might be required.

### IBM Z / S390X

Default:

```text
registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0
```

The selected worker nodes must report:

```text
kubernetes.io/arch=s390x
```

Ensure that the selected model and runtime combination is supported for the IBM Z environment.

---

## 22. Red Hat Registry Pull Secret

When using a `registry.redhat.io` base image, confirm whether the namespace already contains the appropriate pull secret.

Example:

```bash
oc -n "$NAMESPACE" get secret rh-registry-pull
```

If you must create it:

```bash
oc -n "$NAMESPACE" create secret docker-registry rh-registry-pull \
  --docker-server=registry.redhat.io \
  --docker-username="$RH_REGISTRY_USERNAME" \
  --docker-password="$RH_REGISTRY_PASSWORD"
```

Link it to the builder service account:

```bash
oc -n "$NAMESPACE" secrets link builder rh-registry-pull --for=pull
```

Link it to the default runtime service account when required:

```bash
oc -n "$NAMESPACE" secrets link default rh-registry-pull --for=pull
```

Do this only when the existing cluster/namespace configuration does not already provide the required registry credentials.

---

## 23. Troubleshooting

### `ImagePullBackOff`

Check:

```bash
oc -n "$NAMESPACE" describe pod
```

Verify registry connectivity, credentials, image name, and pull secrets.

### OpenShift build fails

Check builds:

```bash
oc -n "$NAMESPACE" get builds
```

Inspect the latest build:

```bash
oc -n "$NAMESPACE" logs -f build/"$APP_NAME"
```

For Red Hat base images, confirm `rh-registry-pull`.

### PVC remains Pending

Check:

```bash
oc -n "$NAMESPACE" describe pvc "${APP_NAME}-model-cache"
oc get storageclass
```

Verify that the cluster has an appropriate default or selected StorageClass.

### Pod remains Pending

Check scheduler events:

```bash
oc -n "$NAMESPACE" describe pod
```

Check worker architecture and capacity:

```bash
oc get nodes \
  -o custom-columns='NAME:.metadata.name,ARCH:.status.nodeInfo.architecture,CPU:.status.allocatable.cpu,MEMORY:.status.allocatable.memory'
```

Check current usage:

```bash
oc adm top nodes
```

If the pod cannot fit, adjust the workload only if appropriate for the selected model, or provide a larger worker node.

### Route is unavailable

Check:

```bash
oc -n "$NAMESPACE" get route "$APP_NAME"
oc -n "$NAMESPACE" get service "$APP_NAME"
oc -n "$NAMESPACE" get endpoints "$APP_NAME"
```

### vLLM is running but the API returns authorization errors

Retrieve the current API key again from the OpenShift Secret and confirm that the request uses:

```text
Authorization: Bearer <API_KEY>
```

### Model download fails

Check pod logs:

```bash
oc -n "$NAMESPACE" logs deployment/"$APP_NAME"
```

If the model requires authentication, provide the appropriate Hugging Face token through the supported deployment environment.

---

## 24. Production Recommendations

For production use:

- Pin all container-image versions.
- Use a private enterprise registry where required by policy.
- Store OpenShift, model-repository, registry, and vLLM credentials in controlled secret stores.
- Do not commit `.env`.
- Use trusted TLS certificates.
- Apply NetworkPolicies that restrict access to the vLLM endpoint.
- Size CPU and RAM according to the selected model.
- Use persistent model-cache storage appropriate for the model size.
- Monitor pod CPU, memory, storage, startup duration, request latency, and error rate.
- Configure OpenShift quotas and limits.
- Validate the endpoint before registering it with watsonx Orchestrate.
- Maintain separate development, test, and production namespaces.
- Re-run `./test-local.sh` after modifying Dockerfiles or deployment scripts.
- Validate new models in a non-production namespace before enterprise use.
- For air-gapped environments, mirror all required base images and model artifacts to approved internal repositories before running the deployment.

---

## 25. Upgrade Guidance

The repository contains both CPU v10.2 and v10.3.

Use:

```text
CPU/10.3
```

for the current hardened bundle.

v10.3 preserves the approved production behavior of v10.2 while adding:

- `entrypoints/vllm-nonroot-entrypoint.sh`
- arbitrary OpenShift UID handling
- writable OpenShift-compatible cache and home paths
- Dockerfile continuation-line validation
- non-root entrypoint unit tests
- expanded local regression validation

Before upgrading an existing deployment:

1. Preserve the existing model ID, API endpoint information, Secret strategy, and persistent data requirements.
2. Run `./test-local.sh`.
3. Run a dry deployment using `DRY_RUN=1`.
4. Review generated manifests.
5. Deploy into a test namespace.
6. Validate `/v1/models`.
7. Validate `/v1/chat/completions`.
8. Update the production workload only after functional testing passes.

---

## 26. Quick Deployment Summary

```bash
# 1. Clone
git clone \
  https://github.com/schijioke-uche/vllm-on-redhat-openshift-for-watsonx-orchestrate.git

# 2. Enter CPU v10.3
cd vllm-on-redhat-openshift-for-watsonx-orchestrate/CPU/10.3

# 3. Make scripts executable
chmod +x \
  deploy-vllm-openshift.sh \
  deploy.sh \
  test-local.sh \
  xLaunchpad.sh \
  entrypoints/*.sh

# 4. Create CPU/.env
cd ..
cat > .env <<'EOF'
OCP_URL=https://api.your-cluster.example.com:6443
OCP_TOKEN=sha256~your-openshift-token
EOF
chmod 600 .env
cd 10.3

# 5. Validate
./test-local.sh

# 6. Optional dry run
DRY_RUN=1 \
MODEL_ID='ibm-granite/granite-3.2-2b-instruct' \
ARCH=amd64 \
VLLM_API_KEY='unit-test-key' \
./deploy-vllm-openshift.sh

# 7. Deploy
./deploy-vllm-openshift.sh

# Or use the menu-based launcher
./xLaunchpad.sh
```

---

## 27. Deployment Flow

```text
Clone repository
        |
        v
Prepare CPU/.env
        |
        v
Authenticate to OpenShift
        |
        v
Run test-local.sh
        |
        v
Select model
        |
        v
Select CPU architecture
        |
        v
Validate node CPU/RAM capacity
        |
        v
Select architecture Dockerfile
        |
        v
Generate binary OpenShift build
        |
        v
Build vLLM image
        |
        v
Create PVC + Secret
        |
        v
Deploy vLLM runtime
        |
        v
Create Service + Route
        |
        v
Retrieve API key
        |
        v
Test /v1/models
        |
        v
Test /v1/chat/completions
        |
        v
Connect endpoint to watsonx Orchestrate
```

---

## 28. Final Validation Checklist

- [ ] OpenShift login is valid.
- [ ] Correct worker architecture is available.
- [ ] Selected model is CPU compatible.
- [ ] Sufficient CPU and RAM are available.
- [ ] StorageClass is available.
- [ ] Required registry access is available.
- [ ] `./test-local.sh` passes.
- [ ] Dry-run manifests are valid.
- [ ] OpenShift build completes.
- [ ] PVC is Bound.
- [ ] vLLM pod is Running and Ready.
- [ ] Service has endpoints.
- [ ] Route is admitted.
- [ ] API key is stored securely.
- [ ] `/v1/models` returns successfully.
- [ ] `/v1/chat/completions` returns a model response.
- [ ] watsonx Orchestrate can resolve and reach the Route.
- [ ] TLS trust is configured.
- [ ] No credentials are hardcoded in Git.

---

## Author

Dr. Jeffrey Chijioke-Uche  
IBM Computer Scientist

