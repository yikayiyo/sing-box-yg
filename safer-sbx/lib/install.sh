# shellcheck shell=bash

safer_sbx_write_manifest() {
  umask 077
  mkdir -p "$SAFER_SBX_VAR" "$SAFER_SBX_ETC" "$(dirname "$SAFER_SBX_BIN")"
  # MANIFEST 自身放最后，便于卸载时先读完再删
  cat >"$SAFER_SBX_MANIFEST" <<EOF
${SAFER_SBX_BIN}
${SAFER_SBX_ETC}/operator.env
${SAFER_SBX_CONFIG}
${SAFER_SBX_UNIT}
${SAFER_SBX_MANAGED}
${SAFER_SBX_CREDS}
${SAFER_SBX_CLIENT}
${SAFER_SBX_LOCK}
${SAFER_SBX_MANIFEST}
EOF
  chmod 600 "$SAFER_SBX_MANIFEST"
  cat >"$SAFER_SBX_MANAGED" <<EOF
managed_by=safer-sbx
sing_box_version=${SING_BOX_VERSION}
installed_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)
arch=${SAFER_SBX_ARCH}
EOF
  chmod 600 "$SAFER_SBX_MANAGED"
}

safer_sbx_install_operator_env_if_missing() {
  local example
  example="$(safer_sbx_toolkit_root)/templates/operator.env.example"
  if [[ ! -f "$SAFER_SBX_OPERATOR_ENV" ]]; then
    [[ -f "$example" ]] || safer_sbx_die "缺少示例: $example"
    install -m 600 "$example" "$SAFER_SBX_OPERATOR_ENV"
    safer_sbx_info "已安装运营商配置模板到 $SAFER_SBX_OPERATOR_ENV"
    safer_sbx_info "请编辑其中的 REALITY_SERVER_NAME / REALITY_HANDSHAKE_* / LISTEN_PORT 后再继续。"
    safer_sbx_die "首次安装需先填写 operator.env 后重新运行: install"
  fi
}

safer_sbx_cmd_install() {
  safer_sbx_require_root_for_write
  safer_sbx_require_cmd curl tar sha256sum jq install awk find
  safer_sbx_init_paths
  safer_sbx_with_lock safer_sbx_cmd_install_locked
}

safer_sbx_cmd_install_locked() {
  local archive tmpdir binpath rc
  set +e
  safer_sbx_preflight_plan
  rc=$?
  set -e
  if [[ $rc -eq 2 && "${SAFER_SBX_ALLOW_UNRELATED:-}" != "1" ]]; then
    safer_sbx_die "检测到无关 sing-box；默认拒绝。确认环境后可设 SAFER_SBX_ALLOW_UNRELATED=1（仍不会接管旧服务）"
  fi
  if [[ -e "$SAFER_SBX_MANAGED" && "${SAFER_SBX_FORCE_REINSTALL:-}" != "1" ]]; then
    safer_sbx_die "已存在本工具安装。请用 update，或显式 SAFER_SBX_FORCE_REINSTALL=1"
  fi
  safer_sbx_confirm "将下载钉死版 sing-box ${SING_BOX_VERSION} 并写入上述路径"
  mkdir -p "$SAFER_SBX_VAR" "$SAFER_SBX_ETC" "$(dirname "$SAFER_SBX_BIN")"
  safer_sbx_install_operator_env_if_missing
  safer_sbx_load_operator_env "$SAFER_SBX_OPERATOR_ENV"

  archive="$(safer_sbx_fetch_pinned_archive)"
  tmpdir="$(dirname "$archive")"
  # shellcheck disable=SC2064
  trap "safer_sbx_cleanup_dir '$tmpdir'" EXIT

  binpath="$(safer_sbx_extract_singbox_binary "$archive" "$(dirname "$SAFER_SBX_BIN")")"
  [[ "$binpath" == "$SAFER_SBX_BIN" ]] || safer_sbx_die "二进制安装路径异常"

  if [[ ! -f "$SAFER_SBX_CREDS" ]]; then
    safer_sbx_generate_secrets "$SAFER_SBX_BIN" "$SAFER_SBX_CREDS"
  else
    safer_sbx_info "保留已有本地凭证: $SAFER_SBX_CREDS"
  fi
  safer_sbx_write_server_config "$SAFER_SBX_BIN" "$SAFER_SBX_CREDS" "$SAFER_SBX_CONFIG"
  safer_sbx_write_client_config "$SAFER_SBX_CREDS" "$SAFER_SBX_CLIENT"
  safer_sbx_ensure_user
  if [[ -z "${SAFER_SBX_PREFIX:-}" ]]; then
    chown -R "${SAFER_SBX_USER}:${SAFER_SBX_GROUP}" "$SAFER_SBX_VAR"
    chown "root:${SAFER_SBX_GROUP}" "$SAFER_SBX_ETC" "$SAFER_SBX_CONFIG" "$SAFER_SBX_OPERATOR_ENV"
    chmod 750 "$SAFER_SBX_ETC"
    chmod 640 "$SAFER_SBX_CONFIG" "$SAFER_SBX_OPERATOR_ENV"
    # 服务账户需读配置
    chmod 600 "$SAFER_SBX_CREDS" "$SAFER_SBX_CLIENT"
  fi
  safer_sbx_write_unit "$SAFER_SBX_UNIT"
  safer_sbx_write_manifest
  safer_sbx_print_firewall_hint "$LISTEN_PORT"
  safer_sbx_systemd_reload_enable
  trap - EXIT
  safer_sbx_cleanup_dir "$tmpdir"
  safer_sbx_info "安装完成（managed）。客户端配置路径: $SAFER_SBX_CLIENT"
}

safer_sbx_cmd_update() {
  safer_sbx_require_root_for_write
  safer_sbx_require_cmd curl tar sha256sum jq
  safer_sbx_init_paths
  safer_sbx_with_lock safer_sbx_cmd_update_locked
}

safer_sbx_cmd_update_locked() {
  local archive tmpdir
  [[ -f "$SAFER_SBX_MANAGED" ]] || safer_sbx_die "未发现本工具管理安装，拒绝 update"
  safer_sbx_detect_os
  safer_sbx_load_pinning
  safer_sbx_confirm "将仅更新到本工具包钉死版本 sing-box ${SING_BOX_VERSION}（不会跟踪 upstream main）"
  archive="$(safer_sbx_fetch_pinned_archive)"
  tmpdir="$(dirname "$archive")"
  # shellcheck disable=SC2064
  trap "safer_sbx_cleanup_dir '$tmpdir'" EXIT
  safer_sbx_extract_singbox_binary "$archive" "$(dirname "$SAFER_SBX_BIN")" >/dev/null
  # 配置校验；失败不替换运行中语义由 check + restart 体现
  [[ -f "$SAFER_SBX_CONFIG" ]] || safer_sbx_die "缺少配置"
  "$SAFER_SBX_BIN" check -c "$SAFER_SBX_CONFIG" || safer_sbx_die "更新后 check 失败，请检查配置"
  safer_sbx_write_manifest
  if [[ -z "${SAFER_SBX_PREFIX:-}" ]]; then
    systemctl restart safer-sbx.service
  fi
  trap - EXIT
  safer_sbx_cleanup_dir "$tmpdir"
  safer_sbx_info "更新完成: sing-box ${SING_BOX_VERSION}"
}
