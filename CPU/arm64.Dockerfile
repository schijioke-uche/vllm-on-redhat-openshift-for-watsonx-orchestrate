# arm64.Dockerfile
# OpenShift binary-build wrapper for vLLM CPU on aarch64 / AArch64.
# The official vLLM CPU image publishes arm64/v8 tags.
ARG BASE_IMAGE=docker.io/vllm/vllm-openai-cpu:v0.22.0-arm64
FROM ${BASE_IMAGE}

USER 0
ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VLLM_TARGET_DEVICE=cpu \
    HF_HOME=/models/huggingface \
    TRANSFORMERS_CACHE=/models/huggingface \
    VLLM_PORT=8000

RUN mkdir -p /models/huggingface /opt/app-root/src && \
    chgrp -R 0 /models /opt/app-root/src || true && \
    chmod -R g=u /models /opt/app-root/src || true

EXPOSE 8000
USER 1001
ENTRYPOINT ["python3", "-m", "vllm.entrypoints.openai.api_server"]
