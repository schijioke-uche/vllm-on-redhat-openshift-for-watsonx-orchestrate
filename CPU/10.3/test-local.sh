#!/usr/bin/env bash
set -Eeuo pipefail

#.................................................................................
# @Author:  Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
# @Purpose: VLLM on Red Hat OpenShift CPU deployment
# @Use: Deploy vLLM on Red Hat OpenShift with CPU support, using a selection of compatible models and architectures. This script guides users through selecting a model, choosing the appropriate OpenShift architecture, and deploying vLLM with the selected configuration.
# @File: test-local.sh (CPU only supported)
# @Copyright: All Rights Reserved (c) 2026
# @Credit: Dr. Jeffrey Chijioke-Uche - Copyright 2026 & Licensed
# @CodeID: CPU-633679964-VLLM-OPENSHIFT-test-local
#...............................................................................

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
cd "$ROOT"

fail() { echo "FAIL: $*" >&2; exit 1; }
pass() { echo "PASS: $*"; }

assert_file() { [[ -f "$1" ]] || fail "missing file: $1"; }
assert_grep() { grep -qE "$1" "$2" || fail "expected pattern '$1' in $2"; }
assert_not_grep() { ! grep -qE "$1" "$2" || fail "unexpected pattern '$1' in $2"; }

rm -rf .build-vllm-* test-output
mkdir -p test-output

echo "[1/10] required files"
for f in deploy-vllm-openshift.sh amd64.Dockerfile arm64.Dockerfile ppc64le.Dockerfile s390x.Dockerfile entrypoints/vllm-nonroot-entrypoint.sh entrypoints/test_vllm_nonroot_entrypoint.sh; do
  assert_file "$f"
done
pass "required files exist"

echo "[2/10] code identity and bash syntax"
assert_grep '^# @Code ID: CPU-633679964-VLLM-OPENSHIFT$' deploy-vllm-openshift.sh
assert_grep '^# @Version: 10\.3$' deploy-vllm-openshift.sh
bash -n deploy-vllm-openshift.sh
sh -n entrypoints/vllm-nonroot-entrypoint.sh
bash -n entrypoints/test_vllm_nonroot_entrypoint.sh
pass "identity and shell syntax valid"

echo "[3/10] non-root entrypoint unit test"
chmod +x entrypoints/*.sh
if [[ "$(id -u)" == "0" ]] && command -v runuser >/dev/null 2>&1 && id nobody >/dev/null 2>&1; then
  runuser -u nobody -- entrypoints/test_vllm_nonroot_entrypoint.sh > test-output/entrypoint-test.out
else
  entrypoints/test_vllm_nonroot_entrypoint.sh > test-output/entrypoint-test.out
fi
assert_grep 'ALL CASES PASSED' test-output/entrypoint-test.out
pass "entrypoint behavior test passed"

echo "[4/10] Dockerfile hardening checks"
for f in amd64.Dockerfile arm64.Dockerfile ppc64le.Dockerfile s390x.Dockerfile; do
  assert_grep 'COPY entrypoints/vllm-nonroot-entrypoint\.sh /usr/local/bin/vllm-nonroot-entrypoint\.sh' "$f"
  assert_grep 'ENTRYPOINT \["/usr/local/bin/vllm-nonroot-entrypoint\.sh"\]' "$f"
  assert_grep 'chmod g\+rw /etc/passwd \|\| true' "$f"
  if grep -nE '\\[[:space:]]+$' "$f" > test-output/${f}.trailing 2>/dev/null; then
    cat test-output/${f}.trailing >&2
    fail "$f has trailing whitespace after Dockerfile line-continuation backslash"
  fi
done
pass "Dockerfiles install entrypoint and pass syntax guard checks"

echo "[5/10] dry-run IBM Granite amd64"
DRY_RUN=1 MODEL_ID='ibm-granite/granite-3.2-2b-instruct' ARCH=amd64 VLLM_API_KEY='unit-test-key' ./deploy-vllm-openshift.sh > test-output/dryrun-granite-amd64.out
assert_grep 'API key secret key: vllm-ibm-granite2b-amd64-vllm-api-key' test-output/dryrun-granite-amd64.out
assert_file '.build-vllm-ibm-granite2b-amd64/manifests/02-runtime.yaml'
assert_file '.build-vllm-ibm-granite2b-amd64/context/entrypoints/vllm-nonroot-entrypoint.sh'
pass "Granite amd64 dry-run generated expected files"

echo "[6/10] dry-run GPT-OSS amd64"
DRY_RUN=1 MODEL_ID='unsloth/gpt-oss-20b' ARCH=amd64 VLLM_API_KEY='unit-test-key' ./deploy-vllm-openshift.sh > test-output/dryrun-gptoss-amd64.out
assert_grep 'Selected base image: docker\.io/vllm/vllm-openai-cpu:v0\.22\.0-x86_64' test-output/dryrun-gptoss-amd64.out
assert_grep 'API key secret key: vllm-gpt-oss-20b-amd64-vllm-api-key' test-output/dryrun-gptoss-amd64.out
pass "GPT-OSS amd64 dry-run preserved production base image and secret key naming"

echo "[7/10] dry-run IBM Granite s390x"
DRY_RUN=1 MODEL_ID='ibm-granite/granite-3.2-2b-instruct' ARCH=s390x VLLM_API_KEY='unit-test-key' ./deploy-vllm-openshift.sh > test-output/dryrun-granite-s390x.out
assert_grep 'Selected base image: registry\.redhat\.io/rhaiis/vllm-spyre-rhel9:3\.3\.0' test-output/dryrun-granite-s390x.out
assert_grep 'OpenShift default route first label: vllm-ibm-granite2b-s390x-ibm-granite2b \(38/63\)' test-output/dryrun-granite-s390x.out
pass "Granite s390x dry-run preserved production Spyre image and trimmed names"

echo "[8/10] generated manifest semantic checks"
python3 - <<'PY'
from pathlib import Path
import yaml, re, sys
paths=list(Path('.').glob('.build-vllm-*/manifests/*.yaml'))
if not paths:
    raise SystemExit('no generated manifest YAML files found')
for path in paths:
    docs=list(yaml.safe_load_all(path.read_text()))
    if not docs:
        raise SystemExit(f'{path} has no YAML docs')

runtime=Path('.build-vllm-ibm-granite2b-amd64/manifests/02-runtime.yaml').read_text()
checks=[
    'vllm-ibm-granite2b-amd64-vllm-api-key: "unit-test-key"',
    'key: vllm-ibm-granite2b-amd64-vllm-api-key',
    'exec /usr/local/bin/vllm-nonroot-entrypoint.sh',
    'name: vllm-ibm-granite2b-amd64',
    'kind: Service',
]
for c in checks:
    if c not in runtime:
        raise SystemExit(f'missing runtime check: {c}')
for forbidden in ['enableServiceLinks: false', 'api-gpt-oss', 'kind: ConfigMap']:
    if forbidden in runtime:
        raise SystemExit(f'forbidden production regression found: {forbidden}')
print('YAML semantic checks passed')
PY
pass "generated manifests parse and preserve production service model"

echo "[9/10] Dockerfile line-continuation guard regression"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp -R deploy-vllm-openshift.sh amd64.Dockerfile arm64.Dockerfile ppc64le.Dockerfile s390x.Dockerfile entrypoints "$TMP/"
printf '\\ \n' >> "$TMP/amd64.Dockerfile"
if (cd "$TMP" && DRY_RUN=1 MODEL_ID='ibm-granite/granite-3.2-2b-instruct' ARCH=amd64 VLLM_API_KEY='unit-test-key' ./deploy-vllm-openshift.sh) > test-output/guard-negative.out 2>&1; then
  cat test-output/guard-negative.out >&2
  fail "Dockerfile trailing-backslash guard did not fail"
fi
assert_grep 'trailing whitespace after a Dockerfile line-continuation backslash' test-output/guard-negative.out
pass "Dockerfile guard catches trailing whitespace after continuation backslash"

echo "[10/10] rejected stale experimental changes stay absent"
assert_not_grep 'enableServiceLinks: false' deploy-vllm-openshift.sh
assert_not_grep 'api-gpt-oss' deploy-vllm-openshift.sh
assert_not_grep 'registry\.redhat\.io/rhaiis/vllm-cpu-rhel9:3\.3\.0' deploy-vllm-openshift.sh
assert_not_grep 'convert_weight_packed' deploy-vllm-openshift.sh
pass "stale experimental regressions are absent"

echo
sha256sum deploy-vllm-openshift.sh *.Dockerfile entrypoints/*.sh > test-output/artifact-sha256.txt
cat test-output/artifact-sha256.txt

echo
printf 'ALL LOCAL TESTS PASSED\n'
