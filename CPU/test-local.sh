#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

cp -a "${ROOT_DIR}/." "${TMP_DIR}/"
cd "${TMP_DIR}"

cat > .env <<'EOF'
OCP_URL=https://api.test-cluster.example.com:6443
OCP_TOKEN=sha256~test-token
HF_TOKEN=hf_test_token
EOF

echo '[1/6] Bash syntax validation'
bash -n ./deploy-vllm-cpu-openshift.sh

echo '[2/6] Dockerfile required instruction validation'
python3 - <<'PY'
from pathlib import Path
s = Path('Dockerfile').read_text()
required = [
    'FROM ${BASE_IMAGE}',
    'VLLM_TARGET_DEVICE=cpu',
    'python -m pip install --upgrade "vllm[cpu]"',
    'EXPOSE 8000',
    'ENTRYPOINT ["python", "-m", "vllm.entrypoints.openai.api_server"]',
]
missing = [item for item in required if item not in s]
if missing:
    raise SystemExit(f'Missing Dockerfile entries: {missing}')
print('Dockerfile check PASS')
PY

echo '[3/6] x86 dry-run deployment generation'
printf 'ibm-granite/granite-3.2-2b-instruct\n1\n' | \
  DRY_RUN=1 NAMESPACE=test-x86 APP_NAME=vllm-cpu-test ROUTE_HOST=test-x86.apps.example.com \
  ./deploy-vllm-cpu-openshift.sh > x86.log

grep -q 'oc new-build --name=vllm-cpu-test --binary --strategy=docker' x86.log
grep -q 'Dockerfile copied to ./vllm-cpu-ocp-build/Dockerfile' x86.log
grep -q 'kubernetes.io/arch: amd64' x86.log
grep -q 'host: test-x86.apps.example.com' x86.log
cmp -s Dockerfile vllm-cpu-ocp-build/Dockerfile

echo '[4/6] x86 generated YAML parse validation'
python3 - <<'PY'
from pathlib import Path
import yaml
objs = list(yaml.safe_load_all(Path('vllm-cpu-ocp-build/openshift-vllm-cpu.yaml').read_text()))
kinds = [o.get('kind') for o in objs if o]
expected = ['PersistentVolumeClaim', 'Secret', 'Deployment', 'Service', 'Route']
if kinds != expected:
    raise SystemExit(f'Unexpected OpenShift object sequence: {kinds}')
dep = objs[2]
assert dep['spec']['template']['spec']['nodeSelector']['kubernetes.io/arch'] == 'amd64'
env = {item['name']: item for item in dep['spec']['template']['spec']['containers'][0]['env']}
assert env['VLLM_TARGET_DEVICE']['value'] == 'cpu'
print('x86 YAML check PASS')
PY

echo '[5/6] s390x dry-run deployment generation'
printf 'unsloth/gpt-oss-20b\n2\n' | \
  DRY_RUN=1 NAMESPACE=test-s390x APP_NAME=vllm-cpu-test ROUTE_HOST=test-s390x.apps.example.com \
  ./deploy-vllm-cpu-openshift.sh > s390x.log

grep -q 'kubernetes.io/arch: s390x' s390x.log
grep -q 'VXE required; IBM Z14 or newer' s390x.log
grep -q 'host: test-s390x.apps.example.com' s390x.log

echo '[6/6] s390x generated YAML parse validation'
python3 - <<'PY'
from pathlib import Path
import yaml
objs = list(yaml.safe_load_all(Path('vllm-cpu-ocp-build/openshift-vllm-cpu.yaml').read_text()))
dep = objs[2]
assert dep['spec']['template']['spec']['nodeSelector']['kubernetes.io/arch'] == 's390x'
assert dep['spec']['template']['metadata']['annotations']['cpu.openshift.io/isa-note'] == 'VXE required; IBM Z14 or newer'
print('s390x YAML check PASS')
PY

echo 'ALL LOCAL TESTS PASSED'
