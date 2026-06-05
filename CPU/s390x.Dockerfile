# s390x / IBM Z OpenShift vLLM wrapper.
# Default uses Red Hat AI Inference Server Spyre image instead of upstream source-build, avoiding the long fragile PyArrow/torchvision source-build path.
ARG BASE_IMAGE=registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0
FROM ${BASE_IMAGE}

ARG TARGETARCH=s390x
USER 0
ENV VLLM_TARGET_DEVICE=cpu \
    HF_HOME=/models/huggingface \
    TRANSFORMERS_CACHE=/models/huggingface \
    HF_HUB_CACHE=/models/huggingface/hub \
    HOME=/models/home \
    XDG_CACHE_HOME=/models/cache \
    VLLM_CACHE_ROOT=/models/cache/vllm \
    VLLM_CONFIG_ROOT=/models/config/vllm \
    TORCH_HOME=/models/cache/torch \
    NUMBA_CACHE_DIR=/models/cache/numba \
    VLLM_PORT=8000 \
    PYTHONUNBUFFERED=1

RUN set -eux; \
    mkdir -p /models/huggingface /models/huggingface/hub /models/home /models/cache /models/cache/vllm /models/cache/vllm/modelinfos /models/cache/torch /models/cache/numba /models/config/vllm /tmp/vllm; \
    chgrp -R 0 /models /tmp/vllm || true; \
    chmod -R g=u /models /tmp/vllm || true; \
    python -c "import importlib.util, sys; sys.exit('The selected BASE_IMAGE does not contain vLLM. Set BASE_IMAGE_S390X or BASE_IMAGE_OVERRIDE to a vLLM-capable image.') if importlib.util.find_spec('vllm') is None else None"

EXPOSE 8000
USER 1001
ENTRYPOINT ["python", "-m", "vllm.entrypoints.openai.api_server"]
