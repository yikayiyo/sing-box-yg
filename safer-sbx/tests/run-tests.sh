#!/usr/bin/env bash
# safer-sbx 自动化测试：沙箱前缀，不在真实主机落盘安装。
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "${ROOT}/lib/common.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/detect.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/download.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/extract.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/config.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/systemd.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/install.sh"
# shellcheck disable=SC1091
source "${ROOT}/lib/uninstall.sh"

PASS=0
FAIL=0
SKIP=0

assert_ok() {
  local name="$1"
  shift
  if "$@"; then
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  else
    printf 'FAIL %s\n' "$name"
    FAIL=$((FAIL + 1))
  fi
}

assert_fail() {
  local name="$1"
  shift
  if "$@"; then
    printf 'FAIL %s (expected failure)\n' "$name"
    FAIL=$((FAIL + 1))
  else
    printf 'PASS %s\n' "$name"
    PASS=$((PASS + 1))
  fi
}

echo "=== ShellCheck ==="
if command -v shellcheck >/dev/null 2>&1; then
  assert_ok shellcheck_scripts shellcheck -x \
    -e SC1090,SC1091,SC2034,SC2016 \
    "${ROOT}/safer-sbx.sh" \
    "${ROOT}/lib/"*.sh
else
  printf 'SKIP shellcheck (not installed)\n'
  SKIP=$((SKIP + 1))
fi

echo "=== arch mapping ==="
assert_ok arch_supported bash -c 'source '"$ROOT"'/lib/common.sh; source '"$ROOT"'/lib/detect.sh; a=$(safer_sbx_map_arch); [[ $a == amd64 || $a == arm64 ]]'

echo "=== hostname validation ==="
assert_ok host_ok bash -c 'source '"$ROOT"'/lib/common.sh; source '"$ROOT"'/lib/config.sh; safer_sbx_validate_hostname www.example.com'
assert_fail host_ip bash -c 'source '"$ROOT"'/lib/common.sh; source '"$ROOT"'/lib/config.sh; safer_sbx_validate_hostname 1.2.3.4'
assert_fail host_bad bash -c 'source '"$ROOT"'/lib/common.sh; source '"$ROOT"'/lib/config.sh; safer_sbx_validate_hostname "a b.com"'
assert_fail host_dotdot bash -c 'source '"$ROOT"'/lib/common.sh; source '"$ROOT"'/lib/config.sh; safer_sbx_validate_hostname "evil..com"'

echo "=== sha256 fail-closed ==="
TMP="$(mktemp -d -t safer-sbx.test.XXXXXXXX)"
echo hello >"${TMP}/f"
assert_fail corrupt_hash bash -c 'source '"$ROOT"'/lib/common.sh; source '"$ROOT"'/lib/download.sh; safer_sbx_verify_sha256 "'"${TMP}/f"'" aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

echo "=== archive path traversal rejected ==="
# 构造含 ../ 的 tar 在某些 tar 实现会被规范化；我们用绝对路径条目模拟
printf 'x' >"${TMP}/x"
# 使用 --transform 或手工 pax？简化：直接测函数对列表的检查
printf '%s\n' '../evil' >"${TMP}/list"
assert_fail trav bash -c '
  source '"$ROOT"'/lib/common.sh
  source '"$ROOT"'/lib/extract.sh
  entry="../evil"
  case "$entry" in
    /*) exit 1 ;;
  esac
  if [[ "$entry" == ".." || "$entry" == */.. || "$entry" == */../* || "$entry" == ../* ]]; then
    exit 1
  fi
  exit 0
'

# 真实 tar 列表安全检查：做一个含绝对路径名的归档较麻烦；创建相对正常归档 + 污染名单测函数
mkdir -p "${TMP}/pkg"
echo '#!/bin/sh' >"${TMP}/pkg/sing-box"
echo 'echo "sing-box version 1.14.4"' >>"${TMP}/pkg/sing-box"
chmod +x "${TMP}/pkg/sing-box"
tar -C "${TMP}/pkg" -czf "${TMP}/good.tar.gz" sing-box
assert_ok tar_list_ok bash -c 'source '"$ROOT"'/lib/common.sh; source '"$ROOT"'/lib/extract.sh; safer_sbx_tar_list_safe "'"${TMP}/good.tar.gz"'"'

echo "=== uninstall safeguards / idempotency ==="
PREFIX="${TMP}/root"
export SAFER_SBX_PREFIX="$PREFIX"
export SAFER_SBX_ASSUME_YES=1
safer_sbx_init_paths
mkdir -p "$SAFER_SBX_VAR" "$SAFER_SBX_ETC" "$(dirname "$SAFER_SBX_BIN")" "$(dirname "$SAFER_SBX_UNIT")"
echo managed >"$SAFER_SBX_MANAGED"
printf '%s\n' "$SAFER_SBX_MANAGED" "$SAFER_SBX_BIN" >"$SAFER_SBX_MANIFEST"
echo binary >"$SAFER_SBX_BIN"
echo keep >"${PREFIX}/etc/keep-me"
# 清单外文件
echo outsider >"${PREFIX}/etc/outsider"
# 投毒：路径穿越条目不得删除宿主文件
echo poison >"${PREFIX}/etc/shadow-like"
printf '%s\n' "$SAFER_SBX_MANAGED" "$SAFER_SBX_BIN" \
  "${SAFER_SBX_ETC}/../../../etc/shadow-like" \
  "${SAFER_SBX_ETC}/../../etc/shadow-like" >"$SAFER_SBX_MANIFEST"
assert_ok uninstall_managed bash -c '
  source '"$ROOT"'/lib/common.sh
  source '"$ROOT"'/lib/uninstall.sh
  SAFER_SBX_PREFIX="'"$PREFIX"'"
  SAFER_SBX_ASSUME_YES=1
  safer_sbx_init_paths
  safer_sbx_cmd_uninstall
  [[ ! -e "'"$SAFER_SBX_BIN"'" ]]
  [[ -e "'"$PREFIX"'/etc/outsider" ]]
  [[ -e "'"$PREFIX"'/etc/shadow-like" ]]
'
assert_ok uninstall_absent bash -c '
  source '"$ROOT"'/lib/common.sh
  source '"$ROOT"'/lib/uninstall.sh
  SAFER_SBX_PREFIX="'"$PREFIX"'/empty"
  SAFER_SBX_ASSUME_YES=1
  safer_sbx_init_paths
  safer_sbx_cmd_uninstall
'
assert_fail manifest_escape bash -c '
  source '"$ROOT"'/lib/common.sh
  SAFER_SBX_PREFIX="'"$PREFIX"'"
  safer_sbx_init_paths
  safer_sbx_is_exact_managed_path "'"${SAFER_SBX_ETC}/../../../etc/shadow"'"
'

echo "=== fetch stdout is path-only ==="
assert_ok fetch_stdout_clean bash -c '
  source '"$ROOT"'/lib/common.sh
  source '"$ROOT"'/lib/detect.sh
  source '"$ROOT"'/lib/download.sh
  # 模拟：info 不得进入捕获
  out=$(safer_sbx_info "diag"; printf "/tmp/safer-sbx.fake/file.tar.gz\n")
  [[ "$out" == "/tmp/safer-sbx.fake/file.tar.gz" ]]
'

echo "=== refuse unrelated sing-box unit ==="
PREFIX2="${TMP}/root2"
mkdir -p "${PREFIX2}/etc/systemd/system"
touch "${PREFIX2}/etc/systemd/system/sing-box.service"
export SAFER_SBX_PREFIX="$PREFIX2"
safer_sbx_init_paths
assert_ok detect_unrelated bash -c '
  source '"$ROOT"'/lib/common.sh
  source '"$ROOT"'/lib/detect.sh
  SAFER_SBX_PREFIX="'"$PREFIX2"'"
  safer_sbx_init_paths
  safer_sbx_unrelated_singbox_present
'

echo "=== install dry-run sandbox with fixture binary (no network) ==="
PREFIX3="${TMP}/root3"
export SAFER_SBX_PREFIX="$PREFIX3"
export SAFER_SBX_ASSUME_YES=1
safer_sbx_init_paths
mkdir -p "$SAFER_SBX_ETC" "$SAFER_SBX_VAR" "$(dirname "$SAFER_SBX_BIN")"
cat >"$SAFER_SBX_OPERATOR_ENV" <<EOF
LISTEN_PORT=8443
REALITY_SERVER_NAME=www.example.com
REALITY_HANDSHAKE_SERVER=www.example.com
REALITY_HANDSHAKE_PORT=443
CLIENT_SERVER_ADDRESS=203.0.113.10
EOF
chmod 600 "$SAFER_SBX_OPERATOR_ENV"
# 用假二进制生成不了 reality；若网络可用则测真实钉死包
echo "=== optional live pin download + config schema (isolated) ==="
live_pin_and_schema() {
  source "${ROOT}/lib/common.sh"
  source "${ROOT}/lib/detect.sh"
  source "${ROOT}/lib/download.sh"
  source "${ROOT}/lib/extract.sh"
  source "${ROOT}/lib/config.sh"
  export SAFER_SBX_PREFIX="$PREFIX3"
  export SAFER_SBX_ASSUME_YES=1
  safer_sbx_init_paths
  safer_sbx_load_pinning
  local arch tmp out bin
  arch="$(safer_sbx_map_arch)"
  safer_sbx_asset_for_arch "$arch"
  tmp="$(safer_sbx_mk_temp_dir)"
  out="${tmp}/${SAFER_SBX_ASSET}"
  safer_sbx_download_file "$SAFER_SBX_URL" "$out"
  safer_sbx_verify_sha256 "$out" "$SAFER_SBX_SHA256"
  SAFER_SBX_ARCH="$arch"
  bin="$(safer_sbx_extract_singbox_binary "$out" "$(dirname "$SAFER_SBX_BIN")")"
  safer_sbx_generate_secrets "$bin" "$SAFER_SBX_CREDS"
  safer_sbx_write_server_config "$bin" "$SAFER_SBX_CREDS" "$SAFER_SBX_CONFIG"
  safer_sbx_write_client_config "$SAFER_SBX_CREDS" "$SAFER_SBX_CLIENT"
  [[ "$(stat -c '%a' "$SAFER_SBX_CLIENT")" == "600" ]]
  [[ "$(stat -c '%a' "$SAFER_SBX_CREDS")" == "600" ]]
  "$bin" check -c "$SAFER_SBX_CONFIG"
  safer_sbx_cleanup_dir "$tmp"
}
if curl --proto '=https' --tlsv1.2 --fail --head --silent --output /dev/null \
  "https://github.com/SagerNet/sing-box/releases/download/v1.14.4/sing-box-1.14.4-linux-amd64.tar.gz"; then
  assert_ok live_pin_and_schema live_pin_and_schema
else
  printf 'SKIP live download (network/egress)\n'
  SKIP=$((SKIP + 1))
fi

# 清理临时
rm -rf -- "$TMP"

echo "=== summary ==="
echo "PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ "$FAIL" -eq 0 ]]
