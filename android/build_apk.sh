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
# 官方缓存目录名是 .pyside6_android_deploy（下划线）；Qt 文档里写的连字符版本是错的
DEFAULT_CACHE="$HOME/.pyside6_android_deploy"
if [[ -d "$HOME/.pyside6-android-deploy" ]]; then
  DEFAULT_CACHE="$HOME/.pyside6-android-deploy"
fi
CACHE_DIR="${PYSIDE_ANDROID_CACHE:-$DEFAULT_CACHE}"
WHEEL_DIR="${WHEEL_DIR:-$PROJECT_DIR/.android-wheels}"
WORK_DIR="${WORK_DIR:-$PROJECT_DIR/.android-work}"
mkdir -p "$WORK_DIR"
QT_BASE="https://download.qt.io/official_releases/QtForPython"

log()  { printf '\n===== %s =====\n' "$*"; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# 任何命令失败时，把「行号 + 失败命令」以 GitHub 注解形式输出。
# 这样即使拿不到完整日志，也能通过 check-run annotations API 读到失败位置。
# 存成变量，便于在「自己处理错误」的管道前后临时关闭再恢复。
ERR_TRAP='rc=$?; echo "::error title=build_apk.sh failed::exit=$rc line=$LINENO cmd=$BASH_COMMAND"; exit $rc'
trap "$ERR_TRAP" ERR

# 外部命令的输出同时打到日志并留存文件；失败时把尾部内容作为注解发出。
# 这样即使拿不到完整 Actions 日志（下载需要管理员权限），也能通过
# check-run annotations API 读到真正的报错原因。
emit_annotation_from_log() { # <标题> <日志文件> [尾部行数]
  local label="$1" logfile="$2" n="${3:-20}" body
  if [[ ! -f "$logfile" ]]; then return 0; fi
  body="$(tail -n "$n" "$logfile")"
  body="${body//'%'/%25}"
  body="${body//$'\r'/}"
  body="${body//$'\n'/%0A}"
  echo "::error title=${label}::${body}"
}

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

# pyside6-android-deploy 会检查它自带的 requirements-android.txt，缺包会直接退出
log "安装 pyside6-android-deploy 运行依赖"
# 用单引号包住 -c 的内容，避免嵌套双引号带来的歧义
ANDROID_REQ="$(python3 -c 'import PySide6.scripts, os; print(os.path.join(os.path.dirname(PySide6.scripts.__file__), "requirements-android.txt"))' 2>/dev/null || true)"
if [[ -n "$ANDROID_REQ" && -f "$ANDROID_REQ" ]]; then
  python3 -m pip install -r "$ANDROID_REQ"
else
  echo "未找到 requirements-android.txt，改为安装已知依赖"
  python3 -m pip install jinja2 pkginfo tqdm "packaging==24.1"
fi

# pyside6-android-deploy 的 install() 会拿 [python] android_packages 里钉的版本
# 和当前环境比对，不一致时它自己跑 pip install（写法里带了 --force）。
# 先照它自己的 default.spec 把版本装准，避免走它那条不确定的路径。
DEFAULT_SPEC="$(python3 -c 'import PySide6.scripts.deploy_lib as d, os; print(os.path.join(os.path.dirname(d.__file__), "default.spec"))' 2>/dev/null || true)"
if [[ -n "$DEFAULT_SPEC" && -f "$DEFAULT_SPEC" ]]; then
  ANDROID_PKGS="$(python3 -c 'import configparser, sys; c = configparser.ConfigParser(); c.read(sys.argv[1]); print(c.get("python", "android_packages"))' "$DEFAULT_SPEC" 2>/dev/null || true)"
  if [[ -n "$ANDROID_PKGS" ]]; then
    log "预装 android_packages: $ANDROID_PKGS"
    # shellcheck disable=SC2086
    python3 -m pip install $(printf '%s' "$ANDROID_PKGS" | tr ',' ' ')
  fi
fi

# ---------------------------------------------------------------- 下载 wheel
log "下载 Qt for Python Android wheel (架构 $ANDROID_ARCH)"
mkdir -p "$WHEEL_DIR"

# 千万不要把 wheel 改成 PySide6-android.whl 这类短名！
# pyside6-android-deploy 的 get_wheel_android_arch() 是直接从「文件名」里
# 找 aarch64/armv7a/i686/x86_64 的（wheel.stem），改名会导致架构解析为 None 而失败。
PYSIDE_WHEEL_NAME="PySide6-${QTPY_VERSION}-${QTPY_VERSION}-cp311-cp311-android_${ANDROID_ARCH}.whl"
SHIBOKEN_WHEEL_NAME="shiboken6-${QTPY_VERSION}-${QTPY_VERSION}-cp311-cp311-android_${ANDROID_ARCH}.whl"
PYSIDE_WHEEL="$WHEEL_DIR/$PYSIDE_WHEEL_NAME"
SHIBOKEN_WHEEL="$WHEEL_DIR/$SHIBOKEN_WHEEL_NAME"

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

# 6.10.x 的 wheel 文件名是大写 PySide6-，6.11+ 变成小写 pyside6-，两种都试
download_first "$PYSIDE_WHEEL" \
  "$QT_BASE/pyside6/$PYSIDE_WHEEL_NAME" \
  "$QT_BASE/pyside6/pyside6-${QTPY_VERSION}-${QTPY_VERSION}-cp311-cp311-android_${ANDROID_ARCH}.whl" \
  || die "无法下载 PySide6 Android wheel ($QTPY_VERSION / $ANDROID_ARCH)"

download_first "$SHIBOKEN_WHEEL" \
  "$QT_BASE/shiboken6/$SHIBOKEN_WHEEL_NAME" \
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
if [[ -z "$NDK_PATH" ]]; then
  # 兜底：直接找 android-ndk-* 目录
  NDK_PATH="$(find "$CACHE_DIR" -maxdepth 3 -type d -name 'android-ndk*' 2>/dev/null | head -n 1 || true)"
fi
if [[ -z "$NDK_PATH" ]]; then
  die "在 $CACHE_DIR 下找不到 Android NDK。检查 SDK/NDK 下载步骤，或用 ANDROID_NDK_PATH 显式指定。"
fi
if [[ -n "$SDK_PATH" ]]; then
  echo "SDK: $SDK_PATH"
else
  echo "SDK: 交给 pyside6-android-deploy 自动侦测"
fi
if [[ -n "$NDK_PATH" ]]; then
  echo "NDK: $NDK_PATH"
else
  echo "NDK: 交给 pyside6-android-deploy 自动侦测"
fi

# ---------------------------------------------------------------- 生成配置
log "生成 pysidedeploy.spec"
cd "$PROJECT_DIR"
if [[ ! -f "$PROJECT_DIR/pysidedeploy.spec" ]]; then
  # 注意：android_deploy.py 里 --wheel-pyside/--wheel-shiboken 的 required
  # 取决于「命令行是否给了 -c/--config-file」。这里没给 -c，所以必须显式传 wheel，
  # 否则 argparse 直接以 exit code 2 退出（--init 也会走同一套参数解析）。
  INIT_ARGS=(--init --force
             --wheel-pyside "$PYSIDE_WHEEL"
             --wheel-shiboken "$SHIBOKEN_WHEEL"
             --name "CloudFlareScan")
  # ndk/sdk 的类型是 Path().resolve()，传空字符串会被解析成当前目录，所以仅在非空时传
  if [[ -n "$NDK_PATH" ]]; then INIT_ARGS+=(--ndk-path "$NDK_PATH"); fi
  if [[ -n "$SDK_PATH" ]]; then INIT_ARGS+=(--sdk-path "$SDK_PATH"); fi

  INIT_LOG="$WORK_DIR/init.log"
  # 临时关掉 ERR 陷阱：否则管道一失败它就抢先 exit，
  # emit_annotation_from_log 就没机会把真正的报错发出来
  trap - ERR
  set +e
  pyside6-android-deploy "${INIT_ARGS[@]}" 2>&1 | tee "$INIT_LOG"
  INIT_RC=${PIPESTATUS[0]}
  set -e
  trap "$ERR_TRAP" ERR
  if [[ $INIT_RC -ne 0 ]]; then
    emit_annotation_from_log "pyside6-android-deploy --init failed (rc=$INIT_RC)" "$INIT_LOG" 25
    exit $INIT_RC
  fi
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
BUILD_LOG="$WORK_DIR/build.log"
# ndk/sdk 必须在命令行上给出：AndroidConfig 会直接拿 AndroidData.ndk_path，
# 为空时它去调 get_llvm_readobj(None) 就崩了（TypeError: NoneType / str）。
BUILD_ARGS=(--config-file "$PROJECT_DIR/pysidedeploy.spec"
            --wheel-pyside "$PYSIDE_WHEEL"
            --wheel-shiboken "$SHIBOKEN_WHEEL"
            --keep-deployment-files
            --force)
if [[ -n "$NDK_PATH" ]]; then BUILD_ARGS+=(--ndk-path "$NDK_PATH"); fi
if [[ -n "$SDK_PATH" ]]; then BUILD_ARGS+=(--sdk-path "$SDK_PATH"); fi

trap - ERR
set +e
pyside6-android-deploy "${BUILD_ARGS[@]}" 2>&1 | tee "$BUILD_LOG"
BUILD_RC=${PIPESTATUS[0]}
set -e
trap "$ERR_TRAP" ERR
if [[ $BUILD_RC -ne 0 ]]; then
  emit_annotation_from_log "pyside6-android-deploy build failed (rc=$BUILD_RC)" "$BUILD_LOG" 45
  exit $BUILD_RC
fi

# ---------------------------------------------------------------- 汇总产物
log "构建产物"
ARTIFACTS=()
while IFS= read -r artifact; do
  if [[ -n "$artifact" ]]; then
    ARTIFACTS+=("$artifact")
  fi
done < <(find "$PROJECT_DIR" -maxdepth 3 \( -name '*.apk' -o -name '*.aab' \) -type f 2>/dev/null | sort)

if [[ ${#ARTIFACTS[@]} -eq 0 ]]; then
  die "没有找到 apk/aab，请检查上方构建日志"
fi
for f in "${ARTIFACTS[@]}"; do
  printf '  %s  (%s)\n' "$f" "$(du -h "$f" | cut -f1)"
done
