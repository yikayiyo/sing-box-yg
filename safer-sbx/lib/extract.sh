# shellcheck shell=bash

safer_sbx_tar_list_safe() {
  local archive="$1"
  local entry
  safer_sbx_require_cmd tar
  while IFS= read -r entry; do
    [[ -n "$entry" ]] || continue
    case "$entry" in
      /*)
        safer_sbx_die "归档含绝对路径，已拒绝: $entry"
        ;;
    esac
    # 拒绝任何 .. 路径段
    if [[ "$entry" == ".." || "$entry" == */.. || "$entry" == */../* || "$entry" == ../* ]]; then
      safer_sbx_die "归档含路径穿越，已拒绝: $entry"
    fi
  done < <(tar -tzf "$archive")
}

safer_sbx_extract_singbox_binary() {
  local archive="$1"
  local dest_dir="$2"
  local extract_dir bin_found
  safer_sbx_tar_list_safe "$archive"
  extract_dir="$(dirname "$archive")/extract"
  mkdir -p "$extract_dir"
  chmod 700 "$extract_dir"
  # 不解压到系统路径；先到临时目录
  tar -xzf "$archive" -C "$extract_dir"
  bin_found="$(find "$extract_dir" -type f -name sing-box | head -n 1 || true)"
  [[ -n "$bin_found" ]] || safer_sbx_die "归档中未找到 sing-box 二进制"
  # 再确认二进制路径相对 extract_dir 无穿越
  case "$bin_found" in
    "$extract_dir"/*) ;;
    *) safer_sbx_die "提取路径异常: $bin_found" ;;
  esac
  if command -v file >/dev/null 2>&1; then
    file "$bin_found" | grep -qi 'ELF' || safer_sbx_die "提取物不是 ELF: $bin_found"
  fi
  # 架构粗检
  case "$SAFER_SBX_ARCH" in
    amd64)
      if command -v file >/dev/null 2>&1; then
        file "$bin_found" | grep -Eqi 'x86-64|x86_64|amd64' || safer_sbx_die "ELF 架构与 amd64 不匹配"
      fi
      ;;
    arm64)
      if command -v file >/dev/null 2>&1; then
        file "$bin_found" | grep -Eqi 'aarch64|ARM aarch64|arm64' || safer_sbx_die "ELF 架构与 arm64 不匹配"
      fi
      ;;
  esac
  mkdir -p "$dest_dir"
  install -m 0755 "$bin_found" "${dest_dir}/sing-box"
  # 调用前再做版本探测（已校验后的二进制）
  "${dest_dir}/sing-box" version >/dev/null 2>&1 \
    || safer_sbx_die "校验后的 sing-box 无法执行 version（已中止）"
  printf '%s\n' "${dest_dir}/sing-box"
}
