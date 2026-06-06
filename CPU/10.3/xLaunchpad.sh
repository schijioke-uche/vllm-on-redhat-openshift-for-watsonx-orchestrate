#!/usr/bin/env bash
set -Eeuo pipefail

#.................................................................................
# @Author:  Dr. Jeffrey Chijioke-Uche, IBM Computer Scientist
# @Purpose: VLLM on Red Hat OpenShift CPU deployment
# @Use: Deploy vLLM on Red Hat OpenShift with CPU support, using a selection of compatible models and architectures. This script guides users through selecting a model, choosing the appropriate OpenShift architecture, and deploying vLLM with the selected configuration.
# @File: xLaunchpad.sh (CPU only supported)
# @Copyright: All Rights Reserved (c) 2026
# @Credit: Dr. Jeffrey Chijioke-Uche - Copyright 2026 & Licensed
# @CodeID: CPU-633679964-VLLM-OPENSHIFT-xLaunchpad
#...............................................................................

# @Code ID: CPU-633679964-VLLM-OPENSHIFT-xLaunchpad
# @Launchpad Version: 10.4.2

SCRIPT_NAME="xLaunchpad.sh"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
DEPLOY_SCRIPT="${XLAUNCHPAD_DEPLOY_SCRIPT:-${SCRIPT_DIR}/deploy-vllm-openshift.sh}"

if [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_CYAN=$'\033[36m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'
else
  C_RESET=''
  C_BOLD=''
  C_DIM=''
  C_CYAN=''
  C_GREEN=''
  C_YELLOW=''
  C_RED=''
fi

screen_lines() { tput lines 2>/dev/null || printf '24'; }
screen_cols() { tput cols 2>/dev/null || printf '80'; }

# Clear both the visible screen and scrollback/history above the prompt.
# CSI 3J clears scrollback in xterm-compatible terminals; CSI 2J clears
# the visible screen; CSI H moves the cursor to the top-left corner.
clear_terminal_history() {
  printf '\033[3J\033[2J\033[H'
}

clear_screen() {
  clear_terminal_history
}

center_colored_line() {
  local plain="$1"
  local colored="$2"
  local cols pad
  cols="$(screen_cols)"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  pad=$(( (cols - ${#plain}) / 2 ))
  (( pad < 0 )) && pad=0
  printf '%*s%s\n' "$pad" '' "$colored"
}

center_prompt() {
  local plain="$1"
  local colored="$2"
  local cols pad
  cols="$(screen_cols)"
  [[ "$cols" =~ ^[0-9]+$ ]] || cols=80
  pad=$(( (cols - ${#plain}) / 2 ))
  (( pad < 0 )) && pad=0
  printf '%*s%s' "$pad" '' "$colored"
}

vertical_center_pad() {
  local content_lines="${1:-7}"
  local lines top i
  lines="$(screen_lines)"
  [[ "$lines" =~ ^[0-9]+$ ]] || lines=24
  top=$(( (lines - content_lines) / 2 ))
  (( top < 1 )) && top=1
  for ((i=0; i<top; i++)); do printf '\n'; done
}

main_menu() {
  clear_terminal_history
  vertical_center_pad 7
  center_colored_line '+--------------------------------------------------------------+' "${C_CYAN}${C_BOLD}+--------------------------------------------------------------+${C_RESET}"
  center_colored_line '| Enter 1 to Deploy VLLM on OpenShift or 0 to Quit |' "${C_CYAN}${C_BOLD}|${C_RESET} ${C_GREEN}${C_BOLD}Enter 1 to Deploy VLLM on OpenShift or 0 to Quit${C_RESET} ${C_CYAN}${C_BOLD}|${C_RESET}"
  center_colored_line '+--------------------------------------------------------------+' "${C_CYAN}${C_BOLD}+--------------------------------------------------------------+${C_RESET}"
  printf '\n'
  center_prompt 'Selection: ' "${C_YELLOW}Selection:${C_RESET} "
}

wait_for_menu() {
  printf '\n'
  center_colored_line 'Press Enter to Return to Main Menu:' "${C_YELLOW}${C_BOLD}Press Enter to Return to Main Menu:${C_RESET}"
  center_colored_line '----------------------------------------' "${C_DIM}----------------------------------------${C_RESET}"
  read -r _
  clear_terminal_history
}

post_run_screen() {
  local status="${1:-0}"
  clear_terminal_history
  vertical_center_pad 6
  if (( status == 0 )); then
    center_colored_line "[${SCRIPT_NAME}] Deployment workflow completed." "${C_GREEN}${C_BOLD}[${SCRIPT_NAME}] Deployment workflow completed.${C_RESET}"
  else
    center_colored_line "[${SCRIPT_NAME}] Deployment workflow exited with status ${status}." "${C_RED}${C_BOLD}[${SCRIPT_NAME}] Deployment workflow exited with status ${status}.${C_RESET}"
  fi
  wait_for_menu
}

run_deploy() {
  if [[ ! -f "$DEPLOY_SCRIPT" ]]; then
    clear_terminal_history
    vertical_center_pad 6
    center_colored_line "[${SCRIPT_NAME}] ERROR: deploy script not found: ${DEPLOY_SCRIPT}" "${C_RED}${C_BOLD}[${SCRIPT_NAME}] ERROR: deploy script not found: ${DEPLOY_SCRIPT}${C_RESET}"
    wait_for_menu
    return 1
  fi

  # Source deploy-vllm-openshift.sh in a subshell so deploy-script exit paths do not terminate Launchpad.
  clear_terminal_history
  (
    # shellcheck disable=SC1090
    source "$DEPLOY_SCRIPT"
  )
  local status=$?

  post_run_screen "$status"
  return "$status"
}

quit_launchpad() {
  clear_terminal_history
  vertical_center_pad 3
  center_colored_line 'Goodbye.' "${C_GREEN}${C_BOLD}Goodbye.${C_RESET}"
  printf '\n'
}

main() {
  local choice
  while true; do
    main_menu
    read -r choice
    case "$choice" in
      1)
        run_deploy || true
        ;;
      0)
        quit_launchpad
        exit 0
        ;;
      *)
        printf '\n%sInvalid option. Enter 1 to Deploy VLLM on OpenShift or 0 to Quit.%s\n' "$C_RED" "$C_RESET"
        sleep 1
        ;;
    esac
  done
}

main "$@"
