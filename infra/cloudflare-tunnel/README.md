# Cloudflare Tunnel 上线 fragment_time_good

> **6/25 上线 Phase 2 准备** — 公网可访问 fragment_time
> 
> **当前状态（6/25 探测结果）**：
> - NAS 有公网 IP 183.210.250.219
> - NAS 公网上传 ~8 Mbps（httpbin 3 次稳定 1 MB/s）
> - NAS 80/443 被 UGOS Pro 系统 nginx 占用 → **必须用 cloudflared，不能直接 nginx 反代**
> - 推测用户数 ≤ 20 人并发 OK

## 5 步部署

### 1. 买域名（你做）
- NameSilo / Cloudflare Registrar 买 `fengpietai.com`（~¥50/年）
- 域名 DNS 改到 Cloudflare（NS 记录）

### 2. 在 Cloudflare 创建 Tunnel（你做）
- 登录 https://one.dash.cloudflare.com/
- Networks → Tunnels → Create a tunnel
- 选 "Cloudflared" connector
- 复制 `TUNNEL_TOKEN`（很长一串）

### 3. 配置 Public Hostname（你做）
- Subdomain: `app`
- Domain: `fengpietai.com`
- Service Type: `HTTP`
- URL: `host.docker.internal:9090`（容器内访问 host 网络）

### 4. 部署（NAS 上跑）
```bash
cd /volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/infra/cloudflare-tunnel
cp .env.example .env
# 把 TUNNEL_TOKEN 粘到 .env
docker compose up -d
docker logs ft-cloudflared  # 看连接状态
```

### 5. 验证
- 浏览器开 `https://app.fengpietai.com`
- 应该看到 fragment_time 首页
- devtools 看证书：应该 Cloudflare 签发

## 已知坑

**坑 1**: 容器内 `localhost:9090` = 找不到 host 端口  
**修**: 用 `host.docker.internal:9090`（Mac/Win）或 `172.17.0.1:9090`（Linux）

**坑 2**: Cloudflare Tunnel 免费版有 100 GB/月流量限制  
**修**: 试运行够用，Phase 3 商用切 $5/月 paid

**坑 3**: 多人并发上传会卡（8 Mbps 上传）  
**修**: 10-20 人并发 OK，超出加 $5/月 Argo Smart Routing

**坑 4**: 域名必须用 Cloudflare DNS  
**修**: 买完域名后改 NS 记录到 Cloudflare

## 验证清单（部署后跑）

- [ ] `https://app.fengpietai.com` 浏览器打开看到首页
- [ ] 详情页点击能进
- [ ] AI 鼓励 banner 显示（验证 worker 真连了 9090）
- [ ] 收藏 tab 顶部显示 `@你的收藏 · ...`（验证新代码生效）
- [ ] 5 角色 × 4 场景都点一遍
- [ ] devtools console 0 error
- [ ] 移动端 4G 测试（开手机流量测）
- [ ] 老人模式 1.3x 缩放测试

## 回滚

```bash
cd /volume1/AI_Jarvis/OpenClaw/workspace/projects/fragment_time_good/infra/cloudflare-tunnel
docker compose down
```

5 分钟内可恢复 LAN 9090 访问。
