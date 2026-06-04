#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="${ROOT}/test-output"
rm -rf "$OUT"
mkdir -p "$OUT"

pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

printf '[1/11] required file validation\n'
for f in amd64.Dockerfile arm64.Dockerfile ppc64le.Dockerfile s390x.Dockerfile deploy-vllm-openshift.sh IMAGE_MATRIX.md README.md .env.example; do
  [[ -f "$ROOT/$f" ]] || fail "missing $f"
done
pass 'all required files exist with exact architecture Dockerfile names'

printf '\n[2/11] bash syntax validation\n'
bash -n "$ROOT/deploy-vllm-openshift.sh"
pass 'deploy script syntax is valid'

printf '\n[3/11] Dockerfile anti-regression validation\n'
for f in amd64.Dockerfile arm64.Dockerfile ppc64le.Dockerfile s390x.Dockerfile; do
  grep -q '^FROM ${BASE_IMAGE}' "$ROOT/$f" || fail "$f does not use FROM \\${BASE_IMAGE}"
  grep -q '^ARG BASE_IMAGE=' "$ROOT/$f" || fail "$f is missing ARG BASE_IMAGE"
done
! grep -R 'pip install.*vllm\[cpu\]' "$ROOT/s390x.Dockerfile" >/dev/null || fail 's390x.Dockerfile contains stale pip install vllm[cpu] path'
! grep -R 'ai/gpt-oss-vllm' "$ROOT"/*.Dockerfile >/dev/null || fail 'a Dockerfile contains invalid Docker Model Runner artifact image'
pass 'Dockerfiles use architecture base args and avoid stale s390x build path'

run_dry() {
  local model="$1" arch="$2" work="$3"
  DRY_RUN=1 MODEL_ID="$model" ARCH="$arch" WORK_DIR="$work" "$ROOT/deploy-vllm-openshift.sh" >"$work.log" 2>&1
}

printf '\n[4/11] dry-run amd64 generation\n'
run_dry 'ibm-granite/granite-3.2-2b-instruct' amd64 "$OUT/amd64"
grep -q 'Selected Dockerfile: amd64.Dockerfile' "$OUT/amd64/context/BUILD_SELECTION.txt" || fail 'amd64 selected Dockerfile mismatch'
grep -q 'dockerfilePath: amd64.Dockerfile' "$OUT/amd64/manifests/01-build.yaml" || fail 'amd64 BuildConfig dockerfilePath mismatch'
grep -q 'docker.io/vllm/vllm-openai-cpu:v0.22.0-x86_64' "$OUT/amd64/context/BUILD_SELECTION.txt" || fail 'amd64 base image mismatch'
pass 'amd64 dry-run generated expected Dockerfile and base image'

printf '\n[5/11] dry-run arm64 generation\n'
run_dry 'ibm-granite/granite-3.2-2b-instruct' arm64 "$OUT/arm64"
grep -q 'Selected Dockerfile: arm64.Dockerfile' "$OUT/arm64/context/BUILD_SELECTION.txt" || fail 'arm64 selected Dockerfile mismatch'
grep -q 'dockerfilePath: arm64.Dockerfile' "$OUT/arm64/manifests/01-build.yaml" || fail 'arm64 BuildConfig dockerfilePath mismatch'
grep -q 'docker.io/vllm/vllm-openai-cpu:v0.22.0-arm64' "$OUT/arm64/context/BUILD_SELECTION.txt" || fail 'arm64 base image mismatch'
pass 'arm64 dry-run generated expected Dockerfile and base image'

printf '\n[6/11] dry-run ppc64le generation\n'
run_dry 'RedHatAI/Meta-Llama-3.1-8B-quantized.w8a8' ppc64le "$OUT/ppc64le"
grep -q 'Selected Dockerfile: ppc64le.Dockerfile' "$OUT/ppc64le/context/BUILD_SELECTION.txt" || fail 'ppc64le selected Dockerfile mismatch'
grep -q 'dockerfilePath: ppc64le.Dockerfile' "$OUT/ppc64le/manifests/01-build.yaml" || fail 'ppc64le BuildConfig dockerfilePath mismatch'
grep -q 'registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0' "$OUT/ppc64le/context/BUILD_SELECTION.txt" || fail 'ppc64le base image mismatch'
pass 'ppc64le dry-run generated expected Dockerfile and base image'

printf '\n[7/11] dry-run s390x GPT-OSS generation\n'
run_dry 'unsloth/gpt-oss-20b' s390x "$OUT/s390x"
grep -q 'Selected Dockerfile: s390x.Dockerfile' "$OUT/s390x/context/BUILD_SELECTION.txt" || fail 's390x selected Dockerfile mismatch'
grep -q 'dockerfilePath: s390x.Dockerfile' "$OUT/s390x/manifests/01-build.yaml" || fail 's390x BuildConfig dockerfilePath mismatch'
grep -q 'registry.redhat.io/rhaiis/vllm-spyre-rhel9:3.3.0' "$OUT/s390x/context/BUILD_SELECTION.txt" || fail 's390x base image mismatch'
! grep -R 'ai/gpt-oss-vllm' "$OUT/s390x" >/dev/null || fail 's390x GPT-OSS dry-run selected invalid Docker Model Runner artifact image'
pass 's390x GPT-OSS dry-run uses s390x.Dockerfile and Red Hat architecture image'

printf '\n[8/11] option-5 style custom model path through environment\n'
run_dry 'Qwen/Qwen3-1.7B' arm64 "$OUT/custom-arm64"
grep -q 'Model ID: Qwen/Qwen3-1.7B' "$OUT/custom-arm64/context/BUILD_SELECTION.txt" || fail 'custom model not preserved'
grep -q 'Selected Dockerfile: arm64.Dockerfile' "$OUT/custom-arm64/context/BUILD_SELECTION.txt" || fail 'custom model arch Dockerfile mismatch'
pass 'custom model ID path works in dry-run'

printf '\n[9/11] invalid Docker Model Runner artifact override is rejected\n'
if DRY_RUN=1 MODEL_ID='unsloth/gpt-oss-20b' ARCH=s390x BASE_IMAGE_OVERRIDE='ai/gpt-oss-vllm' WORK_DIR="$OUT/bad" "$ROOT/deploy-vllm-openshift.sh" >"$OUT/bad.log" 2>&1; then
  fail 'BASE_IMAGE_OVERRIDE=ai/gpt-oss-vllm should have failed'
fi
grep -q 'Docker Model Runner model artifact' "$OUT/bad.log" || fail 'bad override error message missing'
pass 'invalid ai/gpt-oss-vllm override fails before OpenShift build generation'

printf '\n[10/11] quit path exits cleanly\n'
if printf 'q\n' | DRY_RUN=1 "$ROOT/deploy-vllm-openshift.sh" >"$OUT/quit.log" 2>&1; then
  pass 'q selection exits with code 0'
else
  fail 'q selection did not exit 0'
fi

printf '\n[11/11] generated manifest resource checks\n'
for arch in amd64 arm64 ppc64le s390x custom-arm64; do
  grep -q '^kind: BuildConfig' "$OUT/$arch/manifests/01-build.yaml" || fail "$arch missing BuildConfig"
  grep -q '^kind: Deployment' "$OUT/$arch/manifests/02-runtime.yaml" || fail "$arch missing Deployment"
  grep -q '^kind: Service' "$OUT/$arch/manifests/02-runtime.yaml" || fail "$arch missing Service"
  grep -q '^kind: Route' "$OUT/$arch/manifests/02-runtime.yaml" || fail "$arch missing Route"
  grep -q 'image-registry.openshift-image-registry.svc:5000' "$OUT/$arch/manifests/02-runtime.yaml" || fail "$arch runtime image is not internal OpenShift image registry"
done
pass 'generated OpenShift manifests include required resources'

printf '\nALL LOCAL TESTS PASSED\n'
