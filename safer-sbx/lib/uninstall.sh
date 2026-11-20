# shellcheck shell=bash

safer_sbx_cmd_uninstall() {
  safer_sbx_require_root_for_write
  safer_sbx_init_paths
  safer_sbx_with_lock safer_sbx_cmd_uninstall_locked
}

safer_sbx_cmd_uninstall_locked() {
  local f
  if [[ ! -f "$SAFER_SBX_MANAGED" && ! -f "$SAFER_SBX_MANIFEST" ]]; then
    safer_sbx_info "未发现本工具管理痕迹，无需卸载（幂等）"
    return 0
  fi
  safer_sbx_confirm "将仅删除 MANIFEST 中列出的 safer-sbx 托管文件（不会递归扫盘）"
  if [[ -z "${SAFER_SBX_PREFIX:-}" ]]; then
    systemctl stop safer-sbx.service 2>/dev/null || true
    systemctl disable safer-sbx.service 2>/dev/null || true
  fi
  if [[ -f "$SAFER_SBX_MANIFEST" ]]; then
    local -a entries=()
    mapfile -t entries <"$SAFER_SBX_MANIFEST"
    for f in "${entries[@]}"; do
      [[ -n "$f" ]] || continue
      # 保护：只删除清单内、且路径落在托管前缀下的文件
      case "$f" in
        "${SAFER_SBX_PREFIX}/usr/local/lib/safer-sbx"/*|\
        "${SAFER_SBX_PREFIX}/etc/safer-sbx"/*|\
        "${SAFER_SBX_PREFIX}/var/lib/safer-sbx"/*|\
        "${SAFER_SBX_PREFIX}/etc/systemd/system/safer-sbx.service")
          if [[ -e "$f" || -L "$f" ]]; then
            rm -f -- "$f"
            safer_sbx_info "已删除: $f"
          fi
          ;;
        *)
          safer_sbx_warn "跳过非托管路径（保护）: $f"
          ;;
      esac
    done
  fi
  # 清理空目录（不强制）
  rmdir "${SAFER_SBX_PREFIX}/usr/local/lib/safer-sbx/bin" 2>/dev/null || true
  rmdir "${SAFER_SBX_PREFIX}/usr/local/lib/safer-sbx" 2>/dev/null || true
  rmdir "${SAFER_SBX_PREFIX}/etc/safer-sbx" 2>/dev/null || true
  rmdir "${SAFER_SBX_PREFIX}/var/lib/safer-sbx" 2>/dev/null || true
  if [[ -z "${SAFER_SBX_PREFIX:-}" ]]; then
    systemctl daemon-reload 2>/dev/null || true
  fi
  safer_sbx_info "卸载完成（仅托管文件）"
}
