#!/usr/bin/env bash
set -Eeuo pipefail

#.................................................................................
# @Author:  Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
# @Purpose: VLLM on Red Hat OpenShift CPU deployment
# @Use: Deploy vLLM on Red Hat OpenShift with CPU support, using a selection of compatible models and architectures. This script guides users through selecting a model, choosing the appropriate OpenShift architecture, and deploying vLLM with the selected configuration.
# @File: sdlc.sh (Version Control and Software Development Lifecycle Script)
# @Copyright: All Rights Reserved (c) 2026
# @Credit: Dr. Jeffrey Chijioke-Uche - Copyright 2026 & Licensed
# @CodeID: CPU-633679964-VLLM-OPENSHIFT-SDLC
#...............................................................................

#Add Changes to Version Control:
git add -A

#Commit Changes with a Descriptive Message:
git commit -m "Updated vLLM OpenShift deployment solution."

#Push Changes to Remote Repository:
git push origin main

# Exit 0:
exit 0