# shellcheck shell=bash

safer_sbx_mk_temp_dir() {
  local d
  d="$(mktemp -d -t safer-sbx.XXXXXXXX)"
  chmod 700 "$d"
  printf '%s\n' "$d"
}

safer_sbx_cleanup_dir() {
  local d="${1:-}"
  [[ -n "$d" && -d "$d" ]] || return 0
  # 仅删除我们创建的临时目录名模式
  case "$d" in
    /tmp/safer-sbx.*|/tmp/tmp.*/safer-sbx.*|*/safer-sbx.*)
      rm -rf -- "$d"
      ;;
    *)
      safer_sbx_warn "拒绝删除非预期临时目录: $d"
      ;;
  esac
}

safer_sbx_download_file() {
  local url="$1"
  local out="$2"
  safer_sbx_require_cmd curl
  # 禁止 insecure；强制 HTTPS；失败即退出
  curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
    --connect-timeout 30 --max-time 600 \
    --output "$out" \
    -- "$url" || safer_sbx_die "下载失败: $url"
  [[ -s "$out" ]] || safer_sbx_die "下载结果为空: $out"
}

safer_sbx_verify_sha256() {
  local file="$1"
  local expect="$2"
  local actual
  safer_sbx_require_cmd sha256sum
  [[ ${#expect} -eq 64 ]] || safer_sbx_die "期望哈希长度异常（fail-closed）"
  actual="$(sha256sum -- "$file" | awk '{print $1}')"
  if [[ "$actual" != "$expect" ]]; then
    safer_sbx_die "SHA-256 校验失败（fail-closed）。期望=${expect} 实际=${actual}"
  fi
}

# 从钉死通道下载并校验；返回归档路径（调用方负责 cleanup 父目录）
safer_sbx_fetch_pinned_archive() {
  local tmp out
  safer_sbx_detect_os
  safer_sbx_load_pinning
  safer_sbx_asset_for_arch "$SAFER_SBX_ARCH"
  tmp="$(safer_sbx_mk_temp_dir)"
  out="${tmp}/${SAFER_SBX_ASSET}"
  safer_sbx_info "下载到受限临时目录: $tmp"
  safer_sbx_download_file "$SAFER_SBX_URL" "$out"
  safer_sbx_verify_sha256 "$out" "$SAFER_SBX_SHA256"
  safer_sbx_info "完整性校验通过（相对钉死 SHA-256；与 GitHub 发布同源，非独立签名）"
  printf '%s\n' "$out"
}
