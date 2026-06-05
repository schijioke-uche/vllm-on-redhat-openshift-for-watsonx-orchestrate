# Test proof - vLLM OpenShift Production Recovery v8

Local validation performed in a fresh workspace.

## Checks executed

- `bash -n deploy-vllm-openshift.sh`
- `DRY_RUN=1` with model option `2` and architecture `1` (`unsloth/gpt-oss-20b` on `amd64`)
- `DRY_RUN=1` with model option `1` and architecture `4` (`ibm-granite/granite-3.2-2b-instruct` on `s390x`)
- Confirmed `amd64` default base image is restored to `docker.io/vllm/vllm-openai-cpu:v0.22.0-x86_64`
- Confirmed no `enableServiceLinks: false`
- Confirmed no `api-*` Service rename and no service ConfigMap
- Confirmed no `convert_weight_packed` build-time hard-fail guard
- Confirmed no `registry.redhat.io/rhaiis/vllm-cpu-rhel9` amd64 default
- Confirmed generated Route label length is below 63 characters
- Confirmed generated Service name remains the app name, preserving production service-link behavior
- Confirmed writable runtime cache environment variables and directory creation are present
- Confirmed `redhat_registry_login` does not fail when legacy public registry variables are unset

## Result

All local syntax, dry-run, manifest, anti-regression, and packaging checks passed.


