# amd64.Dockerfile
# OpenShift binary-build wrapper for vLLM CPU on x86_64 / Intel 64 / AMD64.
# The default base image is architecture-specific and can be overridden by
# the deployment script with the BASE_IMAGE build argument.
ARG BASE_IMAGE=docker.io/vllm/vllm-openai-cpu:v0.22.0-x86_64
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
