# 计划：ncm-api-rs Docker 镜像 CI 流水线

## 背景分析

- 本仓库（`xiaocaoooo/ncm-api-rs-docker`）目前只有一个 README，作为「CI / 镜像发布」专用仓库。
- 上游 `SPlayer-Dev/ncm-api-rs` 是 Rust 项目：
  - `[[bin]] name = "ncm-server"`，位于 `src/bin/server.rs`，需要 `--features server`（axum HTTP 服务）。
  - HTTP 服务默认监听 `0.0.0.0:3000`（环境变量 `NCM_HOST` / `NCM_PORT` / `CORS_ALLOW_ORIGIN` 可调）。
  - TLS 使用 rustls，**不需要 OpenSSL**，运行时可用精简基础镜像。

## 用户需求（已确认）

- 镜像标签策略：`latest` + `v<Cargo 版本号>` + `sha-<commit short sha>`。
- 触发策略：手动（workflow_dispatch）+ 定时（schedule）；**定时构建仅在检测到上游新提交时执行**，无新提交则跳过。

## 交付内容（本仓库新增/修改 4 个文件）

### 1. `Dockerfile`（多阶段构建，全量拷贝简化版）

```dockerfile
FROM rust:slim AS builder
WORKDIR /build
COPY . .
RUN cargo build --release --features server --bin ncm-server

FROM debian:trixie-slim
COPY --from=builder /build/target/release/ncm-server /usr/local/bin/ncm-server
EXPOSE 3000
ENTRYPOINT ["ncm-server"]
```

基础镜像 `debian:trixie-slim`：体积小巧、rustls 无 OpenSSL 依赖、无需额外安装系统库。

### 2. `.github/workflows/docker-publish.yml`（GitHub Actions）

**Triggers**
- `workflow_dispatch`：输入项 `upstream-ref`（默认 `main`）、`image-name`（默认 `xiaocaoooo/ncm-api-rs`）、`force`（默认 false，强制重建）。
- `schedule`：`cron: '*/30 * * * *'`（每 30 分钟检查一次）。

**Job 1：`check-update`（判断是否需要构建）**
1. `git ls-remote https://github.com/SPlayer-Dev/ncm-api-rs main` 取上游最新 commit SHA（公开仓库无需鉴权，不受 API rate limit 影响）。
2. 从本仓库读 `last-build.json`（记录上次构建的上游 SHA；文件不存在视为首次，需要构建）。
3. 输出 `should_build`：`$LATEST != $LAST` 或 `force == true` 时为 true。

**Job 2：`build-push`（needs: check-update，`if: github.event_name == 'workflow_dispatch' || needs.check-update.outputs.should_build == 'true'`）**
1. `actions/checkout` 本仓库（取 Dockerfile 与 last-build.json）。
2. `actions/checkout` 拉取 `SPlayer-Dev/ncm-api-rs` 到 `src/`（`ref: ${{ inputs.upstream-ref }}` 或 `main`）。
3. `cp Dockerfile src/`。
4. `docker/setup-buildx-action`。
5. `docker/login-action`：Secrets `DOCKERHUB_USERNAME` + `DOCKERHUB_TOKEN`（或 `DOCKERHUB_PASSWORD`）。
6. 从 `src/Cargo.toml` 提取 `version`，计算标签：
   - `${IMAGE}:${LATEST_TAG}`（默认 latest）
   - `${IMAGE}:v${VERSION}`（如 `v0.1.0`）
   - `${IMAGE}:sha-$(git rev-parse --short HEAD 于 src)`（如 `sha-a1b2c3d`）
7. `docker/build-push-action`：`context ./src`、`file ./src/Dockerfile`、`push: true`、`platforms: linux/amd64,linux/arm64`。
8. 更新 `last-build.json` 为本次构建的上游 SHA，`git add/commit/push` 回本仓库（需要 workflow `permissions: contents: write`，默认 GITHUB_TOKEN 具备）。

### 3. `last-build.json`

首次提交一个占位文件：
```json
{ "upstream_sha": "", "image": "xiaocaoooo/ncm-api-rs", "version": "" }
```
CI 每次成功推送后自动更新并 commit 回仓库。

### 4. `README.md`（更新）

说明：用途、所需 Secrets（`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`）、触发方式（手动 + 每 30 分钟自动检查）、标签策略、本地验证命令、镜像运行示例：
```bash
docker run -d -p 3000:3000 -e NCM_PORT=3000 xiaocaoooo/ncm-api-rs:latest
```

## 前置条件（用户一次性配置）

- 本仓库 Settings → Secrets and variables → Actions：
  - `DOCKERHUB_USERNAME`
  - `DOCKERHUB_TOKEN`（Docker Hub 个人访问令牌，需 Push 权限）

## 风险与权衡

- 定时检查本身零成本（一次 ls-remote + 读文件），只有发现新提交才产生 buildx 构建费用。
- 多架构构建需 QEMU（buildx 自动处理），首次/上游变更时构建较慢。
- `v<版本号>` 取自上游 `Cargo.toml`，若上游未升版本号则 v 标签会覆盖旧镜像（配合 sha 标签可追溯）。
- 上游若修改 build.rs / 依赖结构，Dockerfile 全量拷贝方案自动适应；可靠性优先于缓存优化。
- schedule 在 GitHub 上有 10–60 分钟延迟属正常现象。

## 实施步骤

1. 新建 `Dockerfile`。
2. 新建 `last-build.json`。
3. 新建 `.github/workflows/docker-publish.yml`。
4. 更新 `README.md`。
5. 校验：本地用 `yamllint`/`actionlint`（如有）检查 workflow；若本机有 docker 则 `docker build` 语法验证 Dockerfile。
