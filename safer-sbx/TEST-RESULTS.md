# 测试结果（证据）

日期（UTC）：2026-11-20

## 钉死校验来源

- Release API：`https://api.github.com/repos/SagerNet/sing-box/releases/tags/v1.14.4`
- 标签：`v1.14.4`（stable，非 prerelease）
- `sing-box-1.14.4-linux-amd64.tar.gz`  
  SHA-256：`699a1b510aa4396b2176d32d1181920399ebf1e267835da6f3b598d0f7c24968`
- `sing-box-1.14.4-linux-arm64.tar.gz`  
  SHA-256：`436441f76ee2f7fe21b5b2d426d3cb261a480455a704865789ad533e4273ec26`
- 摘要字段：GitHub Releases `asset.digest`（与二进制同通道；**非**独立签名声明）

## 命令

```bash
./safer-sbx/tests/run-tests.sh
```

## 结果摘要

```
PASS≥15 FAIL=0 SKIP=0
```

覆盖：

- ShellCheck（生产脚本）
- 架构映射
- Reality 主机名校验（合法 / IP / 非法字符 / `..`）
- SHA-256 错误即失败
- 归档路径安全（逻辑 + 正常 tar 列表）
- 卸载仅删精确托管路径；MANIFEST `../` 穿越条目被拒绝；缺省幂等
- `safer_sbx_info` 走 stderr，不污染 `$(...)` 捕获
- 拒绝无关 `sing-box.service`
- **隔离前缀**下真实下载钉死包 → 校验哈希 → 解压 → `generate` → `sing-box check` → 客户端 `0600`
- Codex P1 修复：MANIFEST/MANAGED/lock 置于 root 控制的 `/etc/safer-sbx`；卸载精确 allowlist + realpath

## 限制

- 未在真实 VPS / 未以生产 root 跑完整 `install`（按用户要求）
- 未执行仓库内既有 `sb.sh` 等脚本
- 未宣称二进制已审计
- ShellCheck 对动态 `source` 使用了有限排除（SC1090/1091/2034/2016）
