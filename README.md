# ncm-api-rs-docker

CI 专用仓库：拉取 [SPlayer-Dev/ncm-api-rs](https://github.com/SPlayer-Dev/ncm-api-rs) 最新代码，构建多架构（linux/amd64 + linux/arm64）Docker 镜像并推送到 Docker Hub。

## 镜像标签策略

| 标签 | 说明 |
| --- | --- |
| `latest` | 最近一次构建的镜像 |
| `v<version>` | 上游 `Cargo.toml` 中的 crate 版本号（如 `v0.1.0`） |
| `sha-<commit>` | 对应上游提交，可精确追溯（如 `sha-a1b2c3d`） |

## 触发方式

- **手动**：Actions 页面运行 `Publish Docker image`，可指定 `upstream-ref`（分支/标签）、`image-name`、`force`（无新提交时强制重建）。
- **定时**：每 30 分钟检查一次上游 `main` 分支，**仅当检测到新提交时**才构建并推送；构建成功后自动把上游 SHA 记录到 `last-build.json` 并 commit 回本仓库。

## 一次性配置：Docker Hub 凭证

在本仓库 Settings → Secrets and variables → Actions 中配置：

- `DOCKERHUB_USERNAME`：Docker Hub 用户名
- `DOCKERHUB_TOKEN`：Docker Hub 个人访问令牌（需 Push 权限）；也可用 `DOCKERHUB_PASSWORD`

## 本地验证

```bash
git clone https://github.com/SPlayer-Dev/ncm-api-rs.git ncm-api-rs
cp Dockerfile ncm-api-rs/
docker build -t ncm-api-rs:latest ncm-api-rs/
```

## 运行镜像

```bash
docker run -d --name ncm-api-rs -p 3000:3000 \
  -e NCM_HOST=0.0.0.0 -e NCM_PORT=3000 \
  xiaocaoooo/ncm-api-rs:latest
```

可选环境变量：`NCM_HOST`（默认 `0.0.0.0`）、`NCM_PORT`（默认 `3000`）、`CORS_ALLOW_ORIGIN`（默认 `*`）。

接口与 Node.js 版 NeteaseCloudMusicApi 兼容，如：`GET http://localhost:3000/cloudsearch?keywords=晴天`。
