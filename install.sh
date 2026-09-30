#!/usr/bin/env sh
# shellcheck shell=sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
##@Version           :  202605121722-git
# @@Author           :  Jason Hempstead
# @@Contact          :  jason@casjaysdev.pro
# @@License          :  LICENSE.md
# @@ReadME           :  install.sh --help
# @@Copyright        :  Copyright: (c) 2026 Jason Hempstead, Casjays Developments
# @@Created          :  Tuesday, May 12, 2026 17:22 EDT
# @@File             :  install.sh
# @@Description      :
# @@Changelog        :  New script
# @@TODO             :  Better documentation
# @@Other            :
# @@Resource         :
# @@Terminal App     :  no
# @@sudo/root        :  no
# @@Template         :  shell/sh
# - - - - - - - - - - - - - - - - - - - - - - - - -
# shellcheck disable=SC1001,SC1003,SC2001,SC2003,SC2016,SC2031,SC2090,SC2115,SC2120,SC2155,SC2199,SC2229,SC2317,SC2329
# - - - - - - - - - - - - - - - - - - - - - - - - -
APPNAME="${0##*/}"
VERSION="202605121722-git"
RUN_USER="${USER}"
SET_UID="$(id -u)"
SCRIPT_SRC_DIR="${0%/*}"
INSTALL_SH_CWD="${PWD}"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# colorization
if [ -n "${NO_COLOR+x}" ] || [ "${SHOW_RAW}" = "true" ]; then
  __printf_color() { printf '%s\n' "$1"; }
else
  __printf_color() { if [ -t 1 ]; then printf '%b%s%b\n' "${2:-$PRINTF_SET_RESET}" "$1" "$PRINTF_SET_RESET"; else printf '%s\n' "$1"; fi; }
fi
# - - - - - - - - - - - - - - - - - - - - - - - - -
# check for command
__cmd_exists() { command -v "$1" >/dev/null 2>&1; }
__function_exists() { case "$(type "$1" 2>/dev/null)" in *function*) return 0 ;; *) return 1 ;; esac; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# custom functions
__git_clone() { git clone "$1" "$2" -q; }
__git_local() { git -C "$CODEXMGR_LOCAL_REPO" "$@"; }
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Define variables
PRINTF_SET_BLACK='\033[1;30m'
PRINTF_SET_RED='\033[0;31m'
PRINTF_SET_GREEN='\033[0;32m'
PRINTF_SET_YELLOW='\033[1;33m'
PRINTF_SET_BLUE='\033[1;34m'
PRINTF_SET_PURPLE='\033[0;35m'
PRINTF_SET_CYAN='\033[0;36m'
PRINTF_SET_WHITE='\033[1;37m'
PRINTF_SET_RESET='\033[0m'
INSTALL_SH_EXIT_STATUS=0
CODEXMGR_LOCAL_REPO="$HOME/.local/dotfiles/codexmgr/config"
CODEXMGR_CONFIG_REPO="https://github.com/codexmgr/config"
# - - - - - - - - - - - - - - - - - - - - - - - - -
# Main application
if ! __cmd_exists git; then
  __printf_color "git is not installed" "$PRINTF_SET_RED" >&2
  exit 1
fi
if ! __cmd_exists codex; then
  __printf_color "Codex CLI is not installed; install it before running this script" "$PRINTF_SET_RED" >&2
  exit 1
fi
if [ -d "$CODEXMGR_LOCAL_REPO/.git" ]; then
  __printf_color "Updating the Codex config repo in $CODEXMGR_LOCAL_REPO" "$PRINTF_SET_CYAN"
  __git_local pull --ff-only -q
  INSTALL_SH_EXIT_STATUS=$?
else
  if [ -e "$CODEXMGR_LOCAL_REPO" ]; then
    __printf_color "Refusing to replace $CODEXMGR_LOCAL_REPO because it is not a git checkout" "$PRINTF_SET_RED" >&2
    exit 1
  fi
  mkdir -p "${CODEXMGR_LOCAL_REPO%/*}"
  __printf_color "Cloning $CODEXMGR_CONFIG_REPO to $CODEXMGR_LOCAL_REPO" "$PRINTF_SET_CYAN"
  __git_clone "$CODEXMGR_CONFIG_REPO" "$CODEXMGR_LOCAL_REPO"
  INSTALL_SH_EXIT_STATUS=$?
fi
if [ "$INSTALL_SH_EXIT_STATUS" = 0 ]; then
  mkdir -p "$HOME/.codex" || exit 1
  if cp -R "$CODEXMGR_LOCAL_REPO/home/." "$HOME/.codex/"; then
    find "$HOME/.codex/hooks" -type f -name '*.sh' -exec chmod 755 {} \; 2>/dev/null || true
    __printf_color "The Codex config files have been installed in $HOME/.codex" "$PRINTF_SET_GREEN"
    __printf_color "Review and trust the installed hooks with /hooks in Codex" "$PRINTF_SET_YELLOW"
  else
    INSTALL_SH_EXIT_STATUS=$?
    __printf_color "Failed to copy Codex config files (exit: $INSTALL_SH_EXIT_STATUS)" "$PRINTF_SET_RED" >&2
  fi
fi

# - - - - - - - - - - - - - - - - - - - - - - - - -
# End application
# - - - - - - - - - - - - - - - - - - - - - - - - -
# lets exit with code
# - - - - - - - - - - - - - - - - - - - - - - - - -
exit $INSTALL_SH_EXIT_STATUS
# - - - - - - - - - - - - - - - - - - - - - - - - -
# ex: ts=2 sw=2 et filetype=sh
