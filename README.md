## VLLM Deployment on Red Hat OpenShift for watsonx Orchestrate

Deploying CPU- and GPU-based vLLM on enterprise Red Hat OpenShift provides IBM customers with a flexible, production-grade inference layer for serving large language models inside their own controlled infrastructure. GPU-backed vLLM deployments are well suited for high-throughput, low-latency generative AI workloads where accelerators such as NVIDIA GPUs are available, while CPU-based deployments provide a practical option for environments where GPUs are constrained, unavailable, or reserved for higher-priority workloads. On OpenShift, vLLM can be containerized and deployed as a scalable service with Kubernetes-native controls for scheduling, resource quotas, node affinity, health probes, autoscaling, secrets management, persistent model storage, and network policies. This allows enterprise teams to expose a standardized OpenAI-compatible inference endpoint while retaining control over model selection, infrastructure placement, security boundaries, and operational governance.

When IBM watsonx Orchestrate runs on IBM Software Hub in an enterprise Cloud Pak for Data environment, the OpenShift-hosted vLLM service can be integrated as an external or internal model endpoint that agents, tools, and orchestration flows invoke during execution. This creates a strong separation of responsibilities: watsonx Orchestrate manages agentic reasoning, skills, tools, workflow coordination, and enterprise automation, while vLLM provides the underlying model-serving runtime. A GPU-backed endpoint can support complex agentic workloads that require faster token generation and greater concurrency, whereas a CPU-backed endpoint can support lighter workloads, development environments, fallback paths, or cost-sensitive use cases. Because the inference service is deployed inside the same enterprise OpenShift ecosystem, organizations can reduce dependency on public model endpoints, maintain lower-latency communication between Orchestrate and the model runtime, and apply the same enterprise controls used across IBM Software Hub for authentication, observability, certificate management, and workload isolation.

This architecture is especially valuable for enterprises that need hybrid performance, resilience, and governance. CPU and GPU vLLM endpoints can be operated together so that watsonx Orchestrate routes workloads according to model size, latency requirements, accelerator availability, cost, or business priority. For example, high-value production agents can target GPU-backed inference, while lower-priority or batch-oriented tasks use CPU-based models; health checks and routing logic can also provide fallback behavior if a preferred endpoint becomes unavailable. Running vLLM on Red Hat OpenShift further supports reproducible deployments, controlled upgrades, air-gapped or restricted-network operation, and integration with private registries and enterprise model repositories. The result is a scalable and governed AI serving layer that complements IBM watsonx Orchestrate on IBM Software Hub, giving customers greater control over model execution while preserving the automation, security, and lifecycle-management capabilities expected from an enterprise CPD platform.

#### Prerequisites
- A Red Hat OpenShift cluster with appropriate permissions to create resources.
- OpenShift CLI (oc) installed and configured to access your cluster.
- Docker or Podman installed for building container images.
- Access to the VLLM source code or container image.    

#### Options:
- GPU based Models
- CPU based Models

GPU based models require NVIDIA GPU and NVIDIA Container Toolkit installed on the OpenShift cluster. GPU based models can provide significantly better performance for large language models compared to CPU based models. It is recommended to use GPU based models for optimal performance when running VLLM on OpenShift.

CPU based models ensure that the model supports CPU execution, which can be beneficial for environments without GPU resources. However, CPU based models may have slower performance compared to GPU based models, especially for larger language models. It is recommended to use CPU based models only if GPU resources are not available or if the model is specifically designed for CPU execution.

## Deployment

[Deployment on OpenShift](https://github.com/schijioke-uche/vllm-on-redhat-openshift-for-watsonx-orchestrate/blob/main/deploy/README.md)

# vLLM CPU-Supported Model Reference

> Production-ready model and CPU backend reference for repository integration.

## Overview

This README summarizes the CPU-supported vLLM model reference extracted from the supplied document. It contains **38 validated model entries** across text, multimodal, and speech-capable model types, plus CPU backend requirements for x86, ARM, Apple Silicon, and IBM Z / S390X platforms. The common validated CPU target is **Intel Xeon 5th/6th Gen**, with **AVX-512F recommended** and **AVX2 considered limited** for x86 CPU deployments.

## Quick Summary

| Item | Value |
|---|---|
| Validated model entries | 38 |
| Text models | 29 |
| Multimodal / speech models | 9 |
| Primary validated CPU | Intel Xeon 5th/6th Gen |
| Recommended x86 ISA | AVX-512F |
| Limited x86 fallback | AVX2 |

## Validated CPU Models

| Model | Type | Architecture | Corresponding CPU | CPU flags / ISA |
|---|---|---|---|---|
| `unsloth/gpt-oss-20b` | Text | `GptOssForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `meta-llama/Llama-3.1-8B-Instruct` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `meta-llama/Llama-3.2-1B` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `meta-llama/Llama-3.2-3B-Instruct` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `meta-llama/Llama-3.3-70B-Instruct` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `RedHatAI/Meta-Llama-3.1-8B-Instruct-quantized.w8a8` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `RedHatAI/Llama-3.2-1B-Instruct-quantized.w8a8` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `RedHatAI/Llama-3.2-3B-Instruct-quantized.w8a8` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `RedHatAI/DeepSeek-R1-Distill-Llama-70B-quantized.w8a8` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `hugging-quants/Meta-Llama-3.1-8B-Instruct-AWQ-INT4` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `AMead10/Llama-3.2-1B-Instruct-AWQ` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `AMead10/Llama-3.2-3B-Instruct-AWQ` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `TheBloke/TinyLlama-1.1B-Chat-v1.0-AWQ` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `TheBloke/TinyLlama-1.1B-Chat-v1.0-GPTQ` | Text | `LlamaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `ibm-granite/granite-3.2-2b-instruct` | Text | `GraniteForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen3-1.7B` | Text | `Qwen3ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen3-4B` | Text | `Qwen3ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen3-8B` | Text | `Qwen3ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen3-14B` | Text | `Qwen3ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen3-14B-AWQ` | Text | `Qwen3ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen3-30B-A3B` | Text | `Qwen3MoeForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/QwQ-32B-AWQ` | Text | `Qwen2ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen1.5-0.5B-Chat-GPTQ-Int4` | Text | `Qwen2ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `RedHatAI/QwQ-32B-quantized.w8a8` | Text | `Qwen2ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `zai-org/glm-4-9b-hf` | Text | `GLMForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `google/gemma-7b` | Text | `GemmaForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `microsoft/Phi-4-reasoning` | Text | `Phi3ForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `TheBloke/Mistral-7B-Instruct-v0.2-AWQ` | Text | `MistralForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `meta-llama/Llama-4-Scout-17B-16E-Instruct` | Multimodal | `Llama4ForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `google/gemma-3-4b-it` | Multimodal | `Gemma3ForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `google/gemma-3-12b-it` | Multimodal | `Gemma3ForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `google/gemma-4-E4B-it` | Multimodal | `Gemma4ForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `google/gemma-4-E2B-it` | Multimodal | `Gemma4ForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `google/gemma-4-26B-A4B-it` | Multimodal | `Gemma4ForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `microsoft/Phi-4-multimodal-instruct` | Multimodal | `Phi4MMForCausalLM` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `Qwen/Qwen2.5-VL-7B-Instruct` | Multimodal | `Qwen2VLForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |
| `openai/whisper-large-v3` | Multimodal / speech | `WhisperForConditionalGeneration` | Intel Xeon 5th/6th Gen | avx512f recommended; avx2 limited |

## Other vLLM CPU Backend Requirements

| CPU Backend | OS | Required / Supported CPU Flags or ISA | Notes |
|---|---|---|---|
| Intel/AMD x86 | Linux | avx512f recommended; avx2 limited | FP32, FP16, BF16 |
| ARM AArch64 | Linux | NEON required | FP32, FP16, BF16 |
| Apple Silicon CPU | macOS Sonoma or later | Apple Silicon; no generic avx flags | Experimental; FP32, FP16 |
| IBM Z / S390X | Linux | VXE required; Z14 or newer | Experimental; FP32, BF16, FP16 |

## Repository Integration Notes

- Prefer **Intel Xeon 5th/6th Gen with AVX-512F** for x86 CPU deployments.
- Treat **AVX2-only systems** as limited-capability targets; validate throughput and memory pressure before production use.
- Treat Apple Silicon and IBM Z / S390X support as experimental where noted by the source document.
- Do not assume models absent from the table are validated for CPU deployment without a separate compatibility test.

## Author and Contact
Dr. Jeffrey Chijioke, PhD
IBM Computer Scientist & IBM Quantum Ambassadors

