# vLLM CPU model deployment on Red Hat OpenShift

This bundle deploys a selected vLLM CPU-supported model as an OpenAI-compatible `/v1` API endpoint on Red Hat OpenShift.

The Dockerfiles are deliberately named exactly as follows:

```text
amd64.Dockerfile
arm64.Dockerfile
ppc64le.Dockerfile
s390x.Dockerfile
```

The deploy script selects one of those files based on the architecture menu.

## Files

```text
vllm-bundle-update-v7-fresh/
├── amd64.Dockerfile
├── arm64.Dockerfile
├── ppc64le.Dockerfile
├── s390x.Dockerfile
├── deploy-vllm-openshift.sh
├── test-local.sh
├── IMAGE_MATRIX.md
├── README.md
├── TEST_PROOF.md
└── .env.example
```

## Why this fixes the earlier s390x failure

Earlier attempts failed because the s390x build path tried to install or source-build vLLM during the OpenShift image build. One log showed `pip install "vllm[cpu]"` failing because `torch==2.11.0` was unavailable for s390x. Another long s390x source-build path spent time compiling PyArrow, TorchVision, and related native components.

This version does **not** run `pip install "vllm[cpu]"` in `s390x.Dockerfile`. Instead, it uses an architecture-appropriate base image:

```text
registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0
```

for both `s390x` and `ppc64le` by default.

## Important GPT-OSS image correction

Do not use this as a Dockerfile base image:

```text
ai/gpt-oss-vllm
```

That Docker Hub reference is a Docker Model Runner model artifact, not a normal Docker/OCI runtime base image that OpenShift Buildah can use in `FROM`. The script rejects it if supplied as `BASE_IMAGE_OVERRIDE`.

For `unsloth/gpt-oss-20b`, the script selects the architecture runtime image and passes the model ID to vLLM at runtime.

## Usage

```bash
unzip vllm-bundle-update-v7-fresh.zip
cd vllm-bundle-update-v7-fresh
cp .env.example .env
vi .env
chmod +x deploy-vllm-openshift.sh
./deploy-vllm-openshift.sh
```

The script asks for a model:

```text
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| #  | Example model ID                                              | Type               | CPU guidance                |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| 1  | ibm-granite/granite-3.2-2b-instruct                           | Text               | Good small CPU smoke test   |
| 2  | unsloth/gpt-oss-20b                                            | Text               | GPT-OSS CPU-supported model |
| 3  | RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8                       | Text quantized     | Practical CPU quantized     |
| 4  | RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w8a8            | Text quantized     | Very large CPU deployment   |
| 5  | <Any supported model id>                                        | <any>              | <any guidance>              |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
| q  |                               QUIT                                                            |
+----+---------------------------------------------------------------+--------------------+-----------------------------+
```

If you select `5`, it asks:

```text
You selection option-5, please enter the model ID:
```

If you select `q`, the script exits with code `0`.

The script then asks for an architecture:

```text
Select Red Hat OpenShift architecture:
+-------------------------------------------------------+
[1]      amd64       |      x86_64 / Intel 64 / AMD64   |
[2]      arm64       |      aarch64 / AArch64           |
[3]      ppc64le     |      IBM Power (little-endian)   |
[4]      s390x       |      IBM Z                       |
+-------------------------------------------------------+
```

## Dry-run testing

```bash
DRY_RUN=1 MODEL_ID=unsloth/gpt-oss-20b ARCH=s390x ./deploy-vllm-openshift.sh
```

This generates a build context and manifests without logging into OpenShift.

## Live deployment output

After a successful deployment, the remote API base URL is:

```text
https://<openshift-route-host>/v1
```

Get the generated API key:

```bash
oc -n <namespace> get secret <app-name>-secrets -o jsonpath='{.data.vllm-api-key}' | base64 -d
```

Example request:

```bash
curl -k "https://<openshift-route-host>/v1/chat/completions" \
  -H "Authorization: Bearer <api-key>" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gpt-oss-20b",
    "messages": [{"role":"user","content":"Say hello from OpenShift."}],
    "max_tokens": 64
  }'
```
