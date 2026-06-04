# vLLM CPU on Red Hat OpenShift

This solution deploys a CPU-targeted vLLM OpenAI-compatible API server on Red Hat OpenShift using a Dockerfile-based OpenShift binary build.

The deployment flow is:

1. Read OpenShift credentials from `.env`.
2. Prompt for a vLLM CPU-supported Hugging Face model ID.
3. Prompt for OpenShift CPU architecture: x86/amd64 or IBM Z/s390x.
4. Build the bundled `Dockerfile` with `oc new-build --strategy=docker --binary`.
5. Deploy a PVC, Secret, Deployment, Service, and OpenShift Route.
6. Expose the model through an OpenAI-compatible base URL:

```text
https://<openshift-route-host>/v1
```

## Files

```text
vllm-cpu-openshift-bundle/
├── Dockerfile
├── deploy-vllm-cpu-openshift.sh
├── test-local.sh
├── README.md
```

## Prerequisites

On your workstation:

- `bash`
- `oc`, the OpenShift CLI
- Access to a Red Hat OpenShift cluster
- Permission to create projects/namespaces or deploy into an existing namespace
- Access to OpenShift internal image registry/builds
- Internet or mirrored registry access during image build so `pip install "vllm[cpu]"` can resolve dependencies

On the OpenShift cluster:

- CPU worker nodes matching your architecture choice
- For x86/amd64: AVX-512 is recommended; AVX2 is limited
- For s390x: VXE is required; IBM Z14 or newer
- Storage class capable of provisioning the model-cache PVC
- Enough CPU and memory for the selected model

## Create `.env`

Create a `.env` file next to the script:

```bash
OCP_URL=https://api.your-cluster.example.com:6443
OCP_TOKEN=sha256~your-openshift-token
HF_TOKEN=hf_your_token_if_the_model_requires_it
```

Only `OCP_URL` and `OCP_TOKEN` are mandatory. `HF_TOKEN` is optional but recommended for gated Hugging Face models.

## Run the deployment

```bash
chmod +x deploy-vllm-cpu-openshift.sh
./deploy-vllm-cpu-openshift.sh
```

The script prompts for the model ID and architecture.

Example CPU-supported model IDs displayed by the script:

```text
ibm-granite/granite-3.2-2b-instruct
unsloth/gpt-oss-20b
RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8
RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w8a8
```

## Useful environment overrides

```bash
NAMESPACE=vllm-cpu \
APP_NAME=vllm-cpu \
PVC_SIZE=100Gi \
CPU_REQUEST=8 \
CPU_LIMIT=16 \
MEMORY_REQUEST=64Gi \
MEMORY_LIMIT=128Gi \
MAX_MODEL_LEN=4096 \
VLLM_CPU_KVCACHE_SPACE=32 \
ROUTE_HOST=vllm-cpu.apps.example.com \
./deploy-vllm-cpu-openshift.sh
```

For an enterprise-mirrored base image:

```bash
BASE_IMAGE=registry.example.com/ubi9/python-311:latest ./deploy-vllm-cpu-openshift.sh
```

## Query the model

After the deployment is Ready:

```bash
export NAMESPACE=vllm-cpu
export APP_NAME=vllm-cpu
export BASE_URL="https://$(oc -n "$NAMESPACE" get route "$APP_NAME" -o jsonpath='{.spec.host}')/v1"
export API_KEY="$(oc -n "$NAMESPACE" get secret "$APP_NAME-secrets" -o jsonpath='{.data.api-key}' | base64 -d)"

curl -sS "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "ibm-granite-granite-3-2-2b-instruct",
    "messages": [
      {"role": "user", "content": "Say hello from vLLM CPU on OpenShift."}
    ],
    "max_tokens": 64
  }'
```

The served model name is derived from the Hugging Face model ID by replacing `/`, `:`, `.`, and `_` with hyphens and lowercasing. You can override it:

```bash
SERVED_MODEL_NAME=my-model ./deploy-vllm-cpu-openshift.sh
```

## Local validation

Run:

```bash
chmod +x test-local.sh
./test-local.sh
```

The local test validates:

- Bash syntax
- Dockerfile required instructions
- x86 dry-run deployment generation
- x86 generated YAML parse
- s390x dry-run deployment generation
- s390x generated YAML parse
- That the bundled Dockerfile is copied into the OpenShift binary build context

## Notes

This solution performs a Dockerfile-based OpenShift build. It does not require a local Docker daemon. The actual image build happens inside OpenShift through `oc new-build --strategy=docker --binary` and `oc start-build --from-dir`.

Local tests use `DRY_RUN=1`; they verify the generated OpenShift objects and Dockerfile usage without requiring cluster credentials.


#### Author:
Dr. Jeffrey Chijioke <br>
IBM Quantum Ambassador | AI/ML Architect | Qiskit Advocate <br>
Computer Scientist