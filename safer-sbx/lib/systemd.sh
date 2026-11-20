# shellcheck shell=bash

safer_sbx_ensure_user() {
  if [[ -n "${SAFER_SBX_PREFIX:-}" ]]; then
    return 0
  fi
  if ! getent group "$SAFER_SBX_GROUP" >/dev/null; then
    groupadd --system "$SAFER_SBX_GROUP"
  fi
  if ! getent passwd "$SAFER_SBX_USER" >/dev/null; then
    useradd --system --gid "$SAFER_SBX_GROUP" --home-dir "$SAFER_SBX_VAR" \
      --shell /usr/sbin/nologin "$SAFER_SBX_USER"
  fi
}

safer_sbx_write_unit() {
  local unit_out="$1"
  local listen_port
  listen_port="${LISTEN_PORT:-443}"
  mkdir -p "$(dirname "$unit_out")"
  cat >"$unit_out" <<EOF
[Unit]
Description=safer-sbx (sing-box VLESS Reality, managed)
Documentation=file://$(safer_sbx_toolkit_root)/README.md
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SAFER_SBX_USER}
Group=${SAFER_SBX_GROUP}
ExecStart=${SAFER_SBX_BIN} run -c ${SAFER_SBX_CONFIG}
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=5
LimitNOFILE=65535
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
RestrictRealtime=true
SystemCallArchitectures=native
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
# 配置只读；不授予对安装元数据/凭证目录的写权限
ReadOnlyPaths=${SAFER_SBX_ETC}
# 配置与凭证仅服务账户可读（组读 config）；不写 VAR
UMask=0077

[Install]
WantedBy=multi-user.target
EOF
  chmod 644 "$unit_out"
  safer_sbx_info "已写入 systemd 单元: $unit_out（监听端口 ${listen_port}；未改防火墙）"
}

safer_sbx_print_firewall_hint() {
  local port="$1"
  cat <<EOF
防火墙提示（本安装器不会自动改防火墙）:
  若使用 ufw，可手动仅放行业务端口，例如:
    sudo ufw allow ${port}/tcp comment 'safer-sbx-vless'
  不要为管理面板等额外端口放行——本工具没有面板。
EOF
}

safer_sbx_systemd_reload_enable() {
  if [[ -n "${SAFER_SBX_PREFIX:-}" ]]; then
    safer_sbx_info "沙箱模式：跳过 systemctl daemon-reload/enable/start"
    return 0
  fi
  systemctl daemon-reload
  systemctl enable safer-sbx.service
  systemctl restart safer-sbx.service
  systemctl --no-pager --full status safer-sbx.service || true
}
