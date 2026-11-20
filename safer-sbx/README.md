# safer-sbx（独立最小安装器）

面向个人 VPS（例如 RackNerd 1 核 1GB）的 **sing-box + VLESS Reality** 精简安装工具。

本目录与仓库根目录的 `sb.sh` / `serv00*` / `kp.sh` 等**完全独立**，互不调用。

## 这不是“完全安全”

请先阅读 [`TRUST-MODEL.md`](./TRUST-MODEL.md)。任何一键安装器都要求你信任：本仓库内容、官方发布通道、以及你自己的主机与网络。

## 范围（刻意收窄）

| 包含 | 不包含 |
|------|--------|
| Debian/Ubuntu + systemd | 其他发行版/OpenRC/无 systemd |
| amd64 / arm64 | 其他架构 |
| 官方钉死版 sing-box 二进制 | 跟踪 `main`、自动升到“最新” |
| VLESS + Reality（vision） | Argo / WARP / Psiphon / 面板 / 订阅 HTTP / 转换器 / 遥测 / cron |
| SHA-256 校验（fail-closed） | 声称独立签名验证（官方未作为本工具输入时） |
| 打印防火墙手工提示 | 清空/改写防火墙、DNS、sysctl、SSH |
| 最小 apt 依赖（若缺 curl/jq 等） | `apt upgrade` / 发行版大升级 |

## 钉死来源

见 [`pinning/sing-box.env`](./pinning/sing-box.env)：

- 项目：https://github.com/SagerNet/sing-box
- 标签：`v1.14.4`
- 资产：`sing-box-1.14.4-linux-{amd64,arm64}.tar.gz`
- 哈希：取自 GitHub Releases API 的 `asset.digest`（与二进制同属 GitHub 发布通道）
- 核对日：`2026-11-20`

更换版本：由维护者更新 `pinning/sing-box.env` 并重新审查，而不是让安装器去拉 `latest`。

## 安装占用（约）

- 官方 tarball：约 30MB（amd64）/ 28MB（arm64）
- 安装后二进制：约同等量级（单文件）
- 配置/凭证：很小（KB 级）
- 运行时内存：通常远小于 1GB；仍建议预留系统余量，并做好备份

## 权限与路径

| 路径 | 权限意图 |
|------|----------|
| `/usr/local/lib/safer-sbx/bin/sing-box` | `0755` |
| `/etc/safer-sbx/operator.env` | `0640` root:safer-sbx |
| `/etc/safer-sbx/config.json` | `0640`（含私钥，勿外传） |
| `/var/lib/safer-sbx/credentials.json` | `0600` |
| `/var/lib/safer-sbx/client.json` | `0600` |
| `/etc/systemd/system/safer-sbx.service` | `0644`，最小能力集 |

系统用户：`safer-sbx`（无登录 shell）。systemd：`NoNewPrivileges`、`ProtectSystem=strict`、`CAP_NET_BIND_SERVICE` 等。

## 用法（中文）

```bash
# 1) 只读预检
sudo ./safer-sbx/safer-sbx.sh preflight

# 2) 准备运营商参数（域名由你提供，勿随便冒充无关站点）
sudo mkdir -p /etc/safer-sbx
sudo cp safer-sbx/templates/operator.env.example /etc/safer-sbx/operator.env
sudo chmod 600 /etc/safer-sbx/operator.env
sudoedit /etc/safer-sbx/operator.env

# 3) 安装（会要求输入 YES；下载到临时目录、校验哈希、再调用二进制）
sudo ./safer-sbx/safer-sbx.sh install

# 4) 状态（不打印密钥）
sudo ./safer-sbx/safer-sbx.sh status

# 5) 更新到本工具包钉死版本
sudo ./safer-sbx/safer-sbx.sh update

# 6) 卸载（仅 MANIFEST 中的托管文件）
sudo ./safer-sbx/safer-sbx.sh uninstall
```

客户端配置在服务器本地：`/var/lib/safer-sbx/client.json`（`0600`）。**不要**把真实 UUID/密钥粘贴到聊天或提交到 Git。仓库内仅有脱敏示例：`templates/client.json.example.redacted`。

### Reality 目标说明

- `REALITY_SERVER_NAME` / `REALITY_HANDSHAKE_SERVER` **必须由你提供并自行确认合法与兼容**。
- 本工具**不会**默认硬编码第三方伪装站，也**不会**主动探测你的目标主机。
- 兼容性因目标站点 TLS 行为、网络路径而异；不保证任何特定域名可用。

### 防火墙

安装器只打印窄提示（例如 `ufw allow <端口>/tcp`），**不会**静默开放管理端口（本工具无面板）。

### 与既有 sing-box 的关系

默认若检测到无关的 `sing-box.service` 等，**拒绝安装**。不会接管或改写旧服务。仅管理 `safer-sbx.service` 与清单内文件。

## 回滚

- 配置写入：先 `sing-box check`，失败不替换；已有配置会留 `.bak`。
- 更新失败：保持旧二进制/配置语义依赖你是否已重启；`check` 失败会中止更新流程。
- 卸载：按 `MANIFEST` 删除；缺省状态幂等。

## 测试

```bash
./safer-sbx/tests/run-tests.sh
```

测试在 `SAFER_SBX_PREFIX` 沙箱中进行，**不会**对真实主机执行安装器写路径（除可选的只读下载校验沙箱）。详见测试输出。

## 依赖

`bash`、`curl`、`tar`、`sha256sum`、`jq`、`systemd`（生产）、`awk`/`find`/`install`。不执行本仓库其他脚本。
