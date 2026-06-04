# s390x.Dockerfile
# OpenShift binary-build wrapper for IBM Z.
# This intentionally avoids installing or source-building vLLM during
# the OpenShift build. The uploaded failure logs show that path is fragile on s390x.
# Red Hat AI Inference Server publishes vllm-spyre-rhel9 for s390x.
# Override BASE_IMAGE in .env if your organization has a different supported s390x image.
ARG BASE_IMAGE=registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0
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
