#!/usr/bin/env bash
# safer-sbx：独立的最小安全安装器（sing-box + VLESS Reality）
# 不调用、不改写仓库内 sb.sh / serv00* 等既有脚本。
set -euo pipefail

SAFER_SBX_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/common.sh"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/detect.sh"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/download.sh"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/extract.sh"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/config.sh"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/systemd.sh"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/install.sh"
# shellcheck disable=SC1091
source "${SAFER_SBX_SELF_DIR}/lib/uninstall.sh"

safer_sbx_usage() {
  cat <<'EOF'
用法: safer-sbx.sh <命令>

命令:
  preflight   只读预检：系统/架构/钉死版本/计划写入路径
  install     安装（需确认 YES；下载钉死官方包并校验）
  update      更新到本工具包钉死版本（不跟踪 upstream main）
  uninstall   仅删除托管文件（需确认；缺省状态幂等）
  status      显示托管状态（不打印密钥）
  version     显示工具与钉死版本
  help        本帮助

环境变量:
  SAFER_SBX_PREFIX        沙箱根前缀（测试用，避免写真实系统）
  SAFER_SBX_ASSUME_YES=1  跳过 YES 确认（仅自动化测试）
  SAFER_SBX_ALLOW_UNRELATED=1  在存在无关 sing-box 时仍安装本工具（仍不接管旧服务）
  SAFER_SBX_FORCE_REINSTALL=1  强制覆盖本工具已有安装

本工具不是“完全安全”。请阅读 TRUST-MODEL.md。
EOF
}

safer_sbx_cmd_status() {
  safer_sbx_init_paths
  if [[ -f "$SAFER_SBX_MANAGED" ]]; then
    safer_sbx_info "托管状态: 已安装"
    # 不输出可能含敏感信息的文件内容以外的元数据
    grep -E '^(managed_by|sing_box_version|installed_at_utc|arch)=' "$SAFER_SBX_MANAGED" || true
    safer_sbx_info "二进制: $SAFER_SBX_BIN"
    safer_sbx_info "配置: $SAFER_SBX_CONFIG"
    safer_sbx_info "客户端配置路径（含密钥，勿外传）: $SAFER_SBX_CLIENT"
    if [[ -z "${SAFER_SBX_PREFIX:-}" ]] && command -v systemctl >/dev/null; then
      systemctl is-active safer-sbx.service 2>/dev/null || true
    fi
  else
    safer_sbx_info "托管状态: 未安装"
  fi
}

safer_sbx_cmd_version() {
  safer_sbx_load_pinning
  safer_sbx_info "safer-sbx toolkit"
  safer_sbx_info "pinned sing-box: ${SING_BOX_VERSION} (${SING_BOX_TAG})"
  safer_sbx_info "pin source: ${SING_BOX_RELEASE_API}"
  safer_sbx_info "pinned at: ${SING_BOX_PINNED_AT}"
}

main() {
  local cmd="${1:-help}"
  safer_sbx_init_paths
  case "$cmd" in
    preflight) safer_sbx_preflight_plan || true ;;
    install) safer_sbx_cmd_install ;;
    update) safer_sbx_cmd_update ;;
    uninstall) safer_sbx_cmd_uninstall ;;
    status) safer_sbx_cmd_status ;;
    version) safer_sbx_cmd_version ;;
    help|-h|--help) safer_sbx_usage ;;
    *) safer_sbx_usage; safer_sbx_die "未知命令: $cmd" ;;
  esac
}

main "$@"
