#!/usr/bin/env bash
set -euo pipefail

REPO_ZIP_URL="https://github.com/mdd-a11y/oci-helper-safe/raw/refs/heads/main/oci-helper-safe-v2.zip"
APP_DIR="/opt/oci-helper-safe-v2"
ZIP_FILE="/opt/oci-helper-safe-v2.zip"
IMAGE="oci-helper-safe-v2:latest"
CONTAINER="oci-helper-safe-v2"
VOLUME="oci-helper-data"
PORT="${PORT:-8088}"

echo "======================================"
echo " OCI Helper Safe V2 一键安装"
echo "======================================"

if [ "$(id -u)" -ne 0 ]; then
  echo "请使用 root 用户运行此脚本。"
  exit 1
fi

# Install required packages only when missing.
if ! command -v docker >/dev/null 2>&1; then
  echo "[1/6] 未检测到 Docker，正在安装..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io
  systemctl enable --now docker
else
  echo "[1/6] Docker 已存在：$(docker --version)"
fi

if ! command -v unzip >/dev/null 2>&1; then
  echo "[2/6] 正在安装 unzip..."
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y unzip
else
  echo "[2/6] unzip 已存在"
fi

echo "[3/6] 检查端口 ${PORT}..."
while ss -lnt "( sport = :${PORT} )" 2>/dev/null | grep -q LISTEN; do
  PORT=$((PORT + 1))
done
echo "使用端口：${PORT}"

echo "[4/6] 下载 V2..."
rm -f "$ZIP_FILE"
curl -fL --retry 3 --connect-timeout 15 -o "$ZIP_FILE" "$REPO_ZIP_URL"

echo "[5/6] 解压并构建 Docker 镜像..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR"
unzip -q "$ZIP_FILE" -d "$APP_DIR"

PROJECT_DIR="$(find "$APP_DIR" -maxdepth 3 -type f -name Dockerfile -print -quit | xargs -r dirname)"
if [ -z "${PROJECT_DIR:-}" ] || [ ! -f "$PROJECT_DIR/Dockerfile" ]; then
  echo "错误：ZIP 中没有找到 Dockerfile。"
  exit 1
fi

docker build -t "$IMAGE" "$PROJECT_DIR"

echo "[6/6] 创建持久化数据卷并启动..."
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker volume inspect "$VOLUME" >/dev/null 2>&1 || docker volume create "$VOLUME" >/dev/null

docker run -d \
  --name "$CONTAINER" \
  --restart unless-stopped \
  -p "${PORT}:8818" \
  -v "${VOLUME}:/app/oci-helper/data" \
  "$IMAGE" >/dev/null

sleep 3

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "容器启动失败，最后 100 行日志："
  docker logs --tail 100 "$CONTAINER" || true
  exit 1
fi

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
if [ -z "$PUBLIC_IP" ]; then
  PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
fi

echo
echo "======================================"
echo " 安装完成"
echo "======================================"
echo "容器：$CONTAINER"
echo "端口：$PORT"
echo "访问地址："
echo "http://${PUBLIC_IP}:${PORT}"
echo
echo "默认登录："
echo "账号：yohann1"
echo "密码：yohann1"
echo
echo "查看日志：docker logs -f $CONTAINER"
echo "重启容器：docker restart $CONTAINER"
echo "======================================"
