# shellcheck shell=bash
# 公共工具：日志、错误、路径、锁。无网络、不执行仓库内旧脚本。
# 下列变量供其他 lib 模块使用：
# shellcheck disable=SC2034

safer_sbx_die() {
  printf '错误: %s\n' "$*" >&2
  exit 1
}

safer_sbx_info() {
  printf '%s\n' "$*"
}

safer_sbx_warn() {
  printf '警告: %s\n' "$*" >&2
}

safer_sbx_require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || safer_sbx_die "缺少必要命令: $c"
  done
}

safer_sbx_init_paths() {
  # SAFER_SBX_PREFIX：测试用根前缀；生产为空
  SAFER_SBX_PREFIX="${SAFER_SBX_PREFIX:-}"
  SAFER_SBX_LIB_DIR="${SAFER_SBX_PREFIX}/usr/local/lib/safer-sbx"
  SAFER_SBX_BIN="${SAFER_SBX_LIB_DIR}/bin/sing-box"
  SAFER_SBX_ETC="${SAFER_SBX_PREFIX}/etc/safer-sbx"
  SAFER_SBX_VAR="${SAFER_SBX_PREFIX}/var/lib/safer-sbx"
  SAFER_SBX_UNIT_DIR="${SAFER_SBX_PREFIX}/etc/systemd/system"
  SAFER_SBX_UNIT="${SAFER_SBX_UNIT_DIR}/safer-sbx.service"
  SAFER_SBX_OPERATOR_ENV="${SAFER_SBX_ETC}/operator.env"
  SAFER_SBX_CONFIG="${SAFER_SBX_ETC}/config.json"
  SAFER_SBX_MANIFEST="${SAFER_SBX_VAR}/MANIFEST"
  SAFER_SBX_MANAGED="${SAFER_SBX_VAR}/MANAGED"
  SAFER_SBX_CREDS="${SAFER_SBX_VAR}/credentials.json"
  SAFER_SBX_CLIENT="${SAFER_SBX_VAR}/client.json"
  SAFER_SBX_LOCK="${SAFER_SBX_VAR}/safer-sbx.lock"
  SAFER_SBX_USER="${SAFER_SBX_USER:-safer-sbx}"
  SAFER_SBX_GROUP="${SAFER_SBX_GROUP:-safer-sbx}"
}

safer_sbx_toolkit_root() {
  # 本工具包根目录（含 pinning/、templates/）
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  printf '%s\n' "$here"
}

safer_sbx_load_pinning() {
  local pin
  pin="$(safer_sbx_toolkit_root)/pinning/sing-box.env"
  [[ -f "$pin" ]] || safer_sbx_die "缺少钉死文件: $pin"
  set -a
  # shellcheck disable=SC1090,SC1091
  source "$pin"
  set +a
  [[ -n "${SING_BOX_VERSION:-}" && -n "${SING_BOX_SHA256_AMD64:-}" && -n "${SING_BOX_SHA256_ARM64:-}" ]] \
    || safer_sbx_die "钉死文件字段不完整"
}

safer_sbx_confirm() {
  local prompt="$1"
  local answer
  if [[ "${SAFER_SBX_ASSUME_YES:-}" == "1" ]]; then
    return 0
  fi
  printf '%s\n请输入 YES 继续: ' "$prompt" >&2
  read -r answer
  [[ "$answer" == "YES" ]] || safer_sbx_die "已取消"
}

safer_sbx_with_lock() {
  local lockdir
  lockdir="$(dirname "$SAFER_SBX_LOCK")"
  mkdir -p "$lockdir"
  exec 9>"$SAFER_SBX_LOCK"
  if ! flock -n 9; then
    safer_sbx_die "无法获取锁 $SAFER_SBX_LOCK（另一操作正在进行）"
  fi
  "$@"
}

safer_sbx_is_root() {
  [[ "$(id -u)" -eq 0 ]]
}

safer_sbx_require_root_for_write() {
  if [[ -n "${SAFER_SBX_PREFIX:-}" ]]; then
    return 0
  fi
  safer_sbx_is_root || safer_sbx_die "写操作需要 root（或设置 SAFER_SBX_PREFIX 做沙箱测试）"
}
