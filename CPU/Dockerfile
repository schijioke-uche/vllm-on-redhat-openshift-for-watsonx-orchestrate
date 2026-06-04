# vLLM CPU OpenShift image
# Builds a CPU-targeted vLLM OpenAI-compatible API server image.
# Default base image is Red Hat UBI 9 Python 3.11.
# Override BASE_IMAGE during oc new-build if your enterprise requires a mirrored image.

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
