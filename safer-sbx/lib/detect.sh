# shellcheck shell=bash

safer_sbx_map_arch() {
  local m
  m="$(uname -m)"
  case "$m" in
    x86_64|amd64) printf 'amd64\n' ;;
    aarch64|arm64) printf 'arm64\n' ;;
    *) safer_sbx_die "不支持的 CPU 架构: $m（仅支持 amd64/arm64）" ;;
  esac
}

safer_sbx_detect_os() {
  local id like pretty
  [[ -r /etc/os-release ]] || safer_sbx_die "无法读取 /etc/os-release"
  # shellcheck disable=SC1091
  . /etc/os-release
  id="${ID:-}"
  like="${ID_LIKE:-}"
  pretty="${PRETTY_NAME:-unknown}"
  case "$id" in
    debian|ubuntu) ;;
    *)
      case " $like " in
        *" debian "*|*" ubuntu "*) ;;
        *) safer_sbx_die "不支持的系统: $pretty（仅明确支持 Debian/Ubuntu）" ;;
      esac
      ;;
  esac
  if [[ -z "${SAFER_SBX_PREFIX:-}" ]]; then
    command -v systemctl >/dev/null 2>&1 || safer_sbx_die "未找到 systemctl（需要 systemd）"
    [[ "$(ps -p 1 -o comm= 2>/dev/null || true)" == "systemd" ]] \
      || safer_sbx_die "PID1 不是 systemd，已拒绝继续"
  fi
  SAFER_SBX_OS_PRETTY="$pretty"
  SAFER_SBX_ARCH="$(safer_sbx_map_arch)"
}

safer_sbx_asset_for_arch() {
  local arch="$1"
  case "$arch" in
    amd64)
      SAFER_SBX_ASSET="$SING_BOX_ASSET_AMD64"
      SAFER_SBX_SHA256="$SING_BOX_SHA256_AMD64"
      ;;
    arm64)
      SAFER_SBX_ASSET="$SING_BOX_ASSET_ARM64"
      SAFER_SBX_SHA256="$SING_BOX_SHA256_ARM64"
      ;;
    *) safer_sbx_die "内部错误: 未知 arch $arch" ;;
  esac
  SAFER_SBX_URL="${SING_BOX_DOWNLOAD_BASE}/${SAFER_SBX_ASSET}"
}

safer_sbx_unrelated_singbox_present() {
  # 默认拒绝接管/覆盖无关 sing-box 安装
  local hits=0
  if [[ -z "${SAFER_SBX_PREFIX:-}" ]]; then
    if systemctl cat sing-box.service >/dev/null 2>&1; then
      hits=1
    fi
    if [[ -e /etc/systemd/system/sing-box.service || -e /lib/systemd/system/sing-box.service ]]; then
      hits=1
    fi
  else
    if [[ -e "${SAFER_SBX_PREFIX}/etc/systemd/system/sing-box.service" ]]; then
      hits=1
    fi
  fi
  # 非本工具管理的 /usr/local/bin/sing-box
  if [[ -e /usr/local/bin/sing-box && ! -e "${SAFER_SBX_MANAGED:-/nonexistent}" ]]; then
    if [[ -z "${SAFER_SBX_PREFIX:-}" ]]; then
      hits=1
    fi
  fi
  [[ "$hits" -eq 1 ]]
}

safer_sbx_preflight_plan() {
  safer_sbx_detect_os
  safer_sbx_load_pinning
  safer_sbx_asset_for_arch "$SAFER_SBX_ARCH"
  safer_sbx_info "=== safer-sbx 预检计划（只读，尚未写入）==="
  safer_sbx_info "系统: ${SAFER_SBX_OS_PRETTY}"
  safer_sbx_info "架构: ${SAFER_SBX_ARCH}"
  safer_sbx_info "钉死版本: sing-box ${SING_BOX_VERSION} (${SING_BOX_TAG})"
  safer_sbx_info "下载: ${SAFER_SBX_URL}"
  safer_sbx_info "期望 SHA-256: ${SAFER_SBX_SHA256}"
  safer_sbx_info "将写入（若确认安装）:"
  safer_sbx_info "  - ${SAFER_SBX_BIN}"
  safer_sbx_info "  - ${SAFER_SBX_ETC}/ (operator.env, config.json)"
  safer_sbx_info "  - ${SAFER_SBX_VAR}/ (MANAGED, MANIFEST, credentials, client)"
  safer_sbx_info "  - ${SAFER_SBX_UNIT}"
  safer_sbx_info "不会: 改 DNS/sysctl/SSH、清空防火墙、apt upgrade、cron、订阅 HTTP、Argo/WARP/面板"
  safer_sbx_info "不会: 自动跟踪 upstream main；更新仅使用本工具包内钉死版本"
  if safer_sbx_unrelated_singbox_present; then
    safer_sbx_warn "检测到可能无关的 sing-box 服务/二进制；默认安装将拒绝继续"
    return 2
  fi
  if [[ -e "$SAFER_SBX_MANAGED" ]]; then
    safer_sbx_info "已存在本工具管理的安装标记: $SAFER_SBX_MANAGED"
  fi
  return 0
}
