# v10.3 Test Proof

```text
Code ID: CPU-633679964-VLLM-OPENSHIFT
Version: 10.3
Test mode: local validation and dry-run manifest generation
Live OpenShift build: not executed from this sandbox
```

The local test harness validates script syntax, the research-derived non-root entrypoint, architecture Dockerfiles, dry-run manifest generation, dynamic API-key Secret naming, preserved production Service/Route naming, and the new Dockerfile line-continuation guard.

## Test output

```text
[1/10] required files
PASS: required files exist
[2/10] code identity and bash syntax
PASS: identity and shell syntax valid
[3/10] non-root entrypoint unit test
PASS: entrypoint behavior test passed
[4/10] Dockerfile hardening checks
PASS: Dockerfiles install entrypoint and pass syntax guard checks
[5/10] dry-run IBM Granite amd64
PASS: Granite amd64 dry-run generated expected files
[6/10] dry-run GPT-OSS amd64
PASS: GPT-OSS amd64 dry-run preserved production base image and secret key naming
[7/10] dry-run IBM Granite s390x
PASS: Granite s390x dry-run preserved production Spyre image and trimmed names
[8/10] generated manifest semantic checks
YAML semantic checks passed
PASS: generated manifests parse and preserve production service model
[9/10] Dockerfile line-continuation guard regression
PASS: Dockerfile guard catches trailing whitespace after continuation backslash
[10/10] rejected stale experimental changes stay absent
PASS: stale experimental regressions are absent

77e544fac29e0dc5268c80fa271f693ded2d089c11f805e64a45958ad3d7efb3  deploy-vllm-openshift.sh
4ad14da73e5b7e6740a3b07d36d0b7eb99d74e1620337422af728e33029763f4  amd64.Dockerfile
0055752cba5b810bf2aad498f1ba30210352012dca38bcb0c5f158aa92a9bf88  arm64.Dockerfile
a9f950808681b729fe745999f8559db1eabad43936508bc6dc2e1a7aec9808de  ppc64le.Dockerfile
3079adfe674d6fd148cc188d079209001f2f80d104d17868e367ab34758301cd  s390x.Dockerfile
8e53eeaac920ba8694f1681e0713828ba71c079de3daf8d391a7bb51114ecb2e  entrypoints/test_vllm_nonroot_entrypoint.sh
deca2abae935364df76c740d360534ea2c4aac37000a274ec942dd5a1f380692  entrypoints/vllm-nonroot-entrypoint.sh

ALL LOCAL TESTS PASSED
```

