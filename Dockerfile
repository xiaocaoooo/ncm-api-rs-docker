# ncm-api-rs 极简多阶段构建
# 构建：musl 静态编译（ring 含 C 代码需 musl 工具链；优先交叉 musl-gcc，缺失则回退本机 musl-tools）
# 运行：scratch，最终镜像仅含静态二进制（~10MB 级）

FROM rust:slim AS builder
ARG TARGETARCH
RUN MUA="$( case "$TARGETARCH" in arm64) echo aarch64 ;; amd64) echo x86_64 ;; *) echo "$TARGETARCH" ;; esac )" \
    && MU="${MUA}-unknown-linux-musl" \
    && MUGCC="${MUA}-linux-musl-gcc" \
    && apt-get update \
    && ( apt-get install -y --no-install-recommends binutils "$MUGCC" \
         || apt-get install -y --no-install-recommends binutils musl-tools ) \
    && rm -rf /var/lib/apt/lists/* \
    && rustup target add "$MU" \
    && if command -v "$MUGCC" >/dev/null 2>&1; then CCBIN="$MUGCC"; else CCBIN="musl-gcc"; fi \
    && CCV="$(printf 'CC_%s' "$MU" | tr 'a-z.-' 'A-Z__')" \
    && LKV="$(printf 'CARGO_TARGET_%s_LINKER' "$MU" | tr 'a-z.-' 'A-Z__')" \
    && printf '%s\n' "MU=$MU" "CCBIN=$CCBIN" "CCV=$CCV" "LKV=$LKV" > /build-musl.env
WORKDIR /build
COPY . .
RUN . /build-musl.env \
    && export "$CCV=$CCBIN" "$LKV=$CCBIN" \
    && cargo build --release --features server --bin ncm-server --target "$MU" \
    && strip "target/$MU/release/ncm-server" \
    && cp "target/$MU/release/ncm-server" /ncm-server

FROM scratch
COPY --from=builder /ncm-server /ncm-server
EXPOSE 3000
ENTRYPOINT ["/ncm-server"]
