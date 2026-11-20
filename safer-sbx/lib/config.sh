# shellcheck shell=bash

safer_sbx_validate_hostname() {
  local h="$1"
  local label
  [[ -n "$h" ]] || safer_sbx_die "Reality 目标主机名为空"
  [[ ${#h} -le 253 ]] || safer_sbx_die "主机名过长"
  # 拒绝 IP、空格、危险字符；要求 FQDN 风格标签
  if [[ "$h" =~ ^[0-9.]+$ || "$h" =~ : ]]; then
    safer_sbx_die "请提供域名形式的 Reality 目标，不要使用 IP: $h"
  fi
  [[ "$h" =~ ^[A-Za-z0-9.-]+$ ]] || safer_sbx_die "主机名含非法字符: $h"
  [[ "$h" != *..* && "$h" != .* && "$h" != *. ]] || safer_sbx_die "主机名格式无效: $h"
  IFS='.' read -r -a _labels <<<"$h"
  for label in "${_labels[@]}"; do
    [[ -n "$label" ]] || safer_sbx_die "主机名含空标签: $h"
    [[ ${#label} -le 63 ]] || safer_sbx_die "主机名标签过长: $label"
    [[ "$label" =~ ^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$ ]] || safer_sbx_die "主机名标签无效: $label"
  done
}

safer_sbx_validate_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] || safer_sbx_die "端口必须是数字: $p"
  ((p >= 1 && p <= 65535)) || safer_sbx_die "端口越界: $p"
}

safer_sbx_load_operator_env() {
  local f="$1"
  [[ -f "$f" ]] || safer_sbx_die "缺少运营商配置: $f（请先复制 templates/operator.env.example）"
  set -a
  # shellcheck disable=SC1090,SC1091
  source "$f"
  set +a
  : "${LISTEN_PORT:?LISTEN_PORT 未设置}"
  : "${REALITY_SERVER_NAME:?REALITY_SERVER_NAME 未设置}"
  : "${REALITY_HANDSHAKE_SERVER:?REALITY_HANDSHAKE_SERVER 未设置}"
  : "${REALITY_HANDSHAKE_PORT:?REALITY_HANDSHAKE_PORT 未设置}"
  safer_sbx_validate_port "$LISTEN_PORT"
  safer_sbx_validate_port "$REALITY_HANDSHAKE_PORT"
  safer_sbx_validate_hostname "$REALITY_SERVER_NAME"
  safer_sbx_validate_hostname "$REALITY_HANDSHAKE_SERVER"
  safer_sbx_info "Reality 兼容说明: server_name 与 handshake.server 通常应为同一可达 TLS 站点；"
  safer_sbx_info "目标需支持 TLS1.3 且证书/SNI 行为与 Reality 兼容。本工具不会主动探测你的目标主机。"
}

safer_sbx_generate_secrets() {
  local bin="$1"
  local out_creds="$2"
  local uuid kp priv pub sid tmp
  tmp="$(dirname "$out_creds")"
  mkdir -p "$tmp"
  uuid="$("$bin" generate uuid)"
  kp="$("$bin" generate reality-keypair)"
  priv="$(printf '%s\n' "$kp" | awk '/PrivateKey/{print $2}' | tr -d '"')"
  pub="$(printf '%s\n' "$kp" | awk '/PublicKey/{print $2}' | tr -d '"')"
  sid="$("$bin" generate rand --hex 8)"
  [[ -n "$uuid" && -n "$priv" && -n "$pub" && -n "$sid" ]] || safer_sbx_die "本地凭证生成失败"
  umask 077
  cat >"$out_creds" <<EOF
{
  "uuid": "${uuid}",
  "reality_private_key": "${priv}",
  "reality_public_key": "${pub}",
  "short_id": "${sid}"
}
EOF
  chmod 600 "$out_creds"
  # 绝不向 stdout 打印机密
  safer_sbx_info "已生成本地凭证文件（权限 0600）: $out_creds"
}

safer_sbx_write_server_config() {
  local bin="$1"
  local creds="$2"
  local conf_out="$3"
  local uuid priv sid tmp_new tmp_bak
  safer_sbx_load_operator_env "$SAFER_SBX_OPERATOR_ENV"
  uuid="$(jq -r '.uuid' "$creds")"
  priv="$(jq -r '.reality_private_key' "$creds")"
  sid="$(jq -r '.short_id' "$creds")"
  tmp_new="${conf_out}.new.$$"
  tmp_bak="${conf_out}.bak"
  umask 077
  cat >"$tmp_new" <<EOF
{
  "log": {
    "level": "warn",
    "timestamp": true
  },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-reality-in",
      "listen": "::",
      "listen_port": ${LISTEN_PORT},
      "users": [
        {
          "uuid": "${uuid}",
          "flow": "xtls-rprx-vision"
        }
      ],
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SERVER_NAME}",
        "reality": {
          "enabled": true,
          "handshake": {
            "server": "${REALITY_HANDSHAKE_SERVER}",
            "server_port": ${REALITY_HANDSHAKE_PORT}
          },
          "private_key": "${priv}",
          "short_id": [
            "${sid}"
          ]
        }
      }
    }
  ],
  "outbounds": [
    {
      "type": "direct",
      "tag": "direct"
    }
  ]
}
EOF
  chmod 600 "$tmp_new"
  "$bin" check -c "$tmp_new" || {
    rm -f -- "$tmp_new"
    safer_sbx_die "sing-box check 失败，已回滚（未替换正式配置）"
  }
  if [[ -f "$conf_out" ]]; then
    cp -a -- "$conf_out" "$tmp_bak"
  fi
  mv -f -- "$tmp_new" "$conf_out"
  chmod 600 "$conf_out"
  safer_sbx_info "服务端配置已原子写入: $conf_out"
}

safer_sbx_write_client_config() {
  local creds="$1"
  local client_out="$2"
  local uuid pub sid server_ip
  safer_sbx_load_operator_env "$SAFER_SBX_OPERATOR_ENV"
  uuid="$(jq -r '.uuid' "$creds")"
  pub="$(jq -r '.reality_public_key' "$creds")"
  sid="$(jq -r '.short_id' "$creds")"
  server_ip="${CLIENT_SERVER_ADDRESS:-YOUR_SERVER_IP_OR_DNS}"
  umask 077
  cat >"$client_out" <<EOF
{
  "log": { "level": "warn", "timestamp": true },
  "outbounds": [
    {
      "type": "vless",
      "tag": "proxy",
      "server": "${server_ip}",
      "server_port": ${LISTEN_PORT},
      "uuid": "${uuid}",
      "flow": "xtls-rprx-vision",
      "tls": {
        "enabled": true,
        "server_name": "${REALITY_SERVER_NAME}",
        "utls": { "enabled": true, "fingerprint": "chrome" },
        "reality": {
          "enabled": true,
          "public_key": "${pub}",
          "short_id": "${sid}"
        }
      }
    },
    { "type": "direct", "tag": "direct" }
  ]
}
EOF
  chmod 600 "$client_out"
  safer_sbx_info "客户端配置已写入（0600）: $client_out"
  safer_sbx_info "请在服务器本机用 root 查看该文件；本工具不会在日志/聊天中打印机密。"
}
