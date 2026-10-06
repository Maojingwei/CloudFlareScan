#!/usr/bin/env bash
#
# 在 Linux / macOS 上构建 CloudFlareScan 的 Android 安装包 (APK)。
#
# 用法：
#   bash android/build_apk.sh
#
# 可用环境变量覆盖：
#   QTPY_VERSION           Qt for Python 版本          (默认 6.10.3)
#   PYSIDE_SETUP_BRANCH    pyside-setup 分支           (默认 6.10)
#   ANDROID_ARCH           目标架构 aarch64/x86_64     (默认 aarch64)
#   BUILDOZER_MODE         debug 出 apk，release 出 aab (默认 debug)
#   ANDROID_NDK_PATH       手动指定 NDK 路径
#   ANDROID_SDK_PATH       手动指定 SDK 路径
#
# 说明：官方工具 pyside6-android-deploy 只支持 Linux/macOS 主机，Windows 请用
#      仓库里的 GitHub Actions 工作流（.github/workflows/android.yml）云端构建。
set -euo pipefail

QTPY_VERSION="${QTPY_VERSION:-6.10.3}"
PYSIDE_SETUP_BRANCH="${PYSIDE_SETUP_BRANCH:-6.10}"
ANDROID_ARCH="${ANDROID_ARCH:-aarch64}"
BUILDOZER_MODE="${BUILDOZER_MODE:-debug}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CACHE_DIR="${PYSIDE_ANDROID_CACHE:-$HOME/.pyside6-android-deploy}"
WHEEL_DIR="${WHEEL_DIR:-$PROJECT_DIR/.android-wheels}"
WORK_DIR="${WORK_DIR:-$PROJECT_DIR/.android-work}"
QT_BASE="https://download.qt.io/official_releases/QtForPython"

log()  { printf '\n===== %s =====\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------- 环境检查
log "检查主机环境"
case "$(uname -s)" in
  Linux|Darwin) ;;
  *) die "pyside6-android-deploy 目前只支持 Linux/macOS 主机（当前：$(uname -s)）。Windows 请使用 GitHub Actions 工作流。" ;;
esac
command -v python3 >/dev/null || die "未找到 python3"
command -v git     >/dev/null || die "未找到 git"
command -v curl    >/dev/null || die "未找到 curl"
command -v java    >/dev/null || die "未找到 java，请安装 JDK 17 或更高版本"
echo "python3: $(python3 --version 2>&1)"
echo "java   : $(java -version 2>&1 | head -n 1)"
command -v pyside6-android-deploy >/dev/null \
  || die "未找到 pyside6-android-deploy，请先执行: python3 -m pip install PySide6==$QTPY_VERSION"

# ---------------------------------------------------------------- 下载 wheel
log "下载 Qt for Python Android wheel (架构 $ANDROID_ARCH)"
mkdir -p "$WHEEL_DIR"

PYSIDE_WHEEL="$WHEEL_DIR/PySide6-android.whl"
SHIBOKEN_WHEEL="$WHEEL_DIR/shiboken6-android.whl"

download_first() { # <输出文件> <候选 URL...>
  local out="$1"; shift
  if [[ -s "$out" ]]; then echo "已缓存: $out"; return 0; fi
  local url
  for url in "$@"; do
    echo "尝试: $url"
    if curl -fL --retry 3 --retry-delay 5 --connect-timeout 30 -o "$out" "$url"; then
      echo "OK -> $out"
      return 0
    fi
    rm -f "$out"
  done
  return 1
}

# 6.10.x 的 wheel 文件名是大写 PySide6-，6.11+ 变成小写 pyside6-
download_first "$PYSIDE_WHEEL" \
  "$QT_BASE/pyside6/PySide6-$QTPY_VERSION-$QTPY_VERSION-cp311-cp311-android_$ANDROID_ARCH.whl" \
  "$QT_BASE/pyside6/pyside6-$QTPY_VERSION-$QTPY_VERSION-cp311-cp311-android_$ANDROID_ARCH.whl" \
  || die "无法下载 PySide6 Android wheel ($QTPY_VERSION / $ANDROID_ARCH)"

download_first "$SHIBOKEN_WHEEL" \
  "$QT_BASE/shiboken6/shiboken6-$QTPY_VERSION-$QTPY_VERSION-cp311-cp311-android_$ANDROID_ARCH.whl" \
  || die "无法下载 shiboken6 Android wheel ($QTPY_VERSION / $ANDROID_ARCH)"

# ---------------------------------------------------------------- SDK / NDK
log "准备 Android SDK 与 NDK"
if [[ -n "$(find "$CACHE_DIR" -maxdepth 3 -type d -name platform-tools 2>/dev/null | head -n 1)" ]]; then
  echo "复用已有缓存: $CACHE_DIR"
else
  mkdir -p "$WORK_DIR"
  if [[ ! -d "$WORK_DIR/pyside-setup/.git" ]]; then
    rm -rf "$WORK_DIR/pyside-setup"
    git clone --depth 1 --branch "$PYSIDE_SETUP_BRANCH" \
      https://code.qt.io/pyside/pyside-setup.git "$WORK_DIR/pyside-setup"
  fi
  REQ="$WORK_DIR/pyside-setup/tools/cross_compile_android/requirements.txt"
  if [[ -f "$REQ" ]]; then
    python3 -m pip install -r "$REQ"
  fi
  python3 "$WORK_DIR/pyside-setup/tools/cross_compile_android/main.py" \
    --download-only --skip-update --auto-accept-license
fi

# 工具能自动从缓存目录识别，这里只在能明确找到时显式传参（更稳）
NDK_PATH="${ANDROID_NDK_PATH:-}"
SDK_PATH="${ANDROID_SDK_PATH:-}"
if [[ -z "$SDK_PATH" ]]; then
  SDK_PATH="$(find "$CACHE_DIR" -maxdepth 4 -type d -name platform-tools 2>/dev/null | head -n 1 || true)"
  SDK_PATH="${SDK_PATH%/platform-tools}"
fi
if [[ -z "$NDK_PATH" ]]; then
  NDK_PATH="$(find "$CACHE_DIR" -maxdepth 5 -type d -name toolchains 2>/dev/null | head -n 1 || true)"
  NDK_PATH="${NDK_PATH%/toolchains}"
fi
[[ -n "$SDK_PATH" ]] && echo "SDK: $SDK_PATH" || echo "SDK: 交给 pyside6-android-deploy 自动侦测"
[[ -n "$NDK_PATH" ]] && echo "NDK: $NDK_PATH" || echo "NDK: 交给 pyside6-android-deploy 自动侦测"

# ---------------------------------------------------------------- 生成配置
log "生成 pysidedeploy.spec"
cd "$PROJECT_DIR"
if [[ ! -f "$PROJECT_DIR/pysidedeploy.spec" ]]; then
  pyside6-android-deploy --init --force
fi

export WHEEL_PYSIDE="$PYSIDE_WHEEL"
export WHEEL_SHIBOKEN="$SHIBOKEN_WHEEL"
export ANDROID_NDK_PATH="$NDK_PATH"
export ANDROID_SDK_PATH="$SDK_PATH"
export ANDROID_ARCH
export BUILDOZER_MODE
python3 "$SCRIPT_DIR/patch_spec.py" "$PROJECT_DIR/pysidedeploy.spec" "$PROJECT_DIR"

# ---------------------------------------------------------------- 开始打包
log "开始构建 APK（首次构建需要编译 CPython 与 Qt 依赖，耗时较长）"
pyside6-android-deploy \
  --config-file "$PROJECT_DIR/pysidedeploy.spec" \
  --keep-deployment-files \
  --force

# ---------------------------------------------------------------- 汇总产物
log "构建产物"
ARTIFACTS=()
while IFS= read -r artifact; do
  [[ -n "$artifact" ]] && ARTIFACTS+=("$artifact")
done < <(find "$PROJECT_DIR" -maxdepth 3 \( -name '*.apk' -o -name '*.aab' \) -type f 2>/dev/null | sort)

if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
  die "没有找到 apk/aab，请检查上方构建日志"
fi
for f in "${ARTIFACTS[@]}"; do
  printf '  %s  (%s)\n' "$f" "$(du -h "$f" | cut -f1)"
done
