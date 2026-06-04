# vLLM OpenShift architecture image matrix

This bundle intentionally uses architecture-specific Dockerfiles and base images.

| Architecture | Dockerfile name | Default base image | Notes |
|---|---|---|---|
| amd64 | `amd64.Dockerfile` | `docker.io/vllm/vllm-openai-cpu:v0.22.0-x86_64` | Official vLLM CPU image for linux/amd64. |
| arm64 | `arm64.Dockerfile` | `docker.io/vllm/vllm-openai-cpu:v0.22.0-arm64` | Official vLLM CPU image for linux/arm64/v8. |
| ppc64le | `ppc64le.Dockerfile` | `registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0` | Red Hat AI Inference Server image published for IBM Power little-endian. Requires Red Hat registry access. |
| s390x | `s390x.Dockerfile` | `registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0` | Red Hat AI Inference Server image published for IBM Z. Requires Red Hat registry access. |

## Important GPT-OSS note

`ai/gpt-oss-vllm` is not used as a `FROM` image. It is a Docker Model Runner model artifact, not a normal OpenShift/Buildah base image. The deploy script rejects it if supplied through `BASE_IMAGE_OVERRIDE`.

For `unsloth/gpt-oss-20b`, the script still uses the selected architecture runtime image above and passes the Hugging Face model ID to vLLM at runtime.

## Base image overrides

Use these `.env` variables if your environment has a certified internal mirror or a different supported image:

```bash
BASE_IMAGE_AMD64=internal.registry.example.com/vllm/vllm-openai-cpu:v0.22.0-x86_64
BASE_IMAGE_ARM64=internal.registry.example.com/vllm/vllm-openai-cpu:v0.22.0-arm64
BASE_IMAGE_PPC64LE=internal.registry.example.com/rhaiis/vllm-spyre-rhel9:3.3.0
BASE_IMAGE_S390X=internal.registry.example.com/rhaiis/vllm-spyre-rhel9:3.3.0
```

`BASE_IMAGE_OVERRIDE` overrides all of the above for the selected run.
