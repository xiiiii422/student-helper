# 后端部署指南

后端是**无状态** FastAPI，部署目标只要能跑 Python/容器即可。三种方案按省心程度排序。

---

## 方案 A · 低配 VPS + Docker + Caddy（最稳，推荐）

成本：约 5–30 元/月。

```bash
# 1. 装 Docker + Caddy
curl -fsSL https://get.docker.com | sh
apt install -y caddy

# 2. 拉代码、构建、运行
git clone <你的仓库> && cd <仓库>/backend
cp .env.example .env && vim .env        # 填 CHAT_API_KEY、BACKEND_SECRET_TOKEN
docker build -t student-helper-backend .
docker run -d --name shb --restart=always -p 8000:8000 --env-file .env student-helper-backend

# 3. Caddy 反代 + 自动 HTTPS
cat > /etc/caddy/Caddyfile <<'EOF'
api.yourdomain.com {
    reverse_proxy localhost:8000
}
EOF
systemctl reload caddy

# 4. 验证
curl https://api.yourdomain.com/health
```

把 `api.yourdomain.com` 填进 App 的后端地址设置即可。

---

## 方案 B · Cloudflare Workers（免费，SSE 需验证）

```bash
npm i -g wrangler
wrangler login
wrangler init shb-backend --type python
# 把 backend/*.py 拷进 src/，requirements.txt 放 src/
wrangler secret put CHAT_API_KEY
wrangler secret put BACKEND_SECRET_TOKEN
wrangler deploy
# 得到 https://shb-backend.<sub>.workers.dev
```

注意：Workers 对长连接 SSE 有超时限制（免费版较短）。若流式不稳定，把
`/api/chat` 也改成非流式一次性返回（App 端已能处理无 delta 的最终文本）。

---

## 方案 C · 家里旧电脑 + frp 内网穿透（0 元）

1. 家里机器跑 `uvicorn main:app --host 0.0.0.0 --port 8000`
2. 用 frp / cloudflared tunnel 暴露一个 HTTPS 域名
3. App 填该域名

---

## 安全清单

- [ ] `BACKEND_SECRET_TOKEN` 改成 ≥32 位随机串（`openssl rand -hex 32`）
- [ ] 一定走 HTTPS（Android 9+ 默认拒绝明文）
- [ ] 建议加防火墙，只放行 443
- [ ] 自用版无账号，Token 泄露=可被蹭额度；可给后端加简单每日请求上限
