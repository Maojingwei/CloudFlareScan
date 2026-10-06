#!/usr/bin/env python3
"""写入/修正 pysidedeploy.spec 中与 Android 打包相关的字段。

由 android/build_apk.sh 调用：
    python android/patch_spec.py <spec 路径> <项目目录>

采用「键存在则替换、不存在则追加到对应 section」的方式，因此无论 spec 是由
`pyside6-android-deploy --init` 生成的，还是用户自己维护的，都能安全地打补丁。
"""
import configparser
import os
import sys

SECTIONS = ["app", "python", "qt", "android", "buildozer"]


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: patch_spec.py <spec-file> <project-dir>", file=sys.stderr)
        return 2

    spec_path = os.path.abspath(sys.argv[1])
    project_dir = os.path.abspath(sys.argv[2])
    wheel_dir = os.path.join(project_dir, ".android-wheels")

    wheel_pyside = os.environ.get("WHEEL_PYSIDE", os.path.join(wheel_dir, "PySide6-android.whl"))
    wheel_shiboken = os.environ.get("WHEEL_SHIBOKEN", os.path.join(wheel_dir, "shiboken6-android.whl"))
    ndk_path = os.environ.get("ANDROID_NDK_PATH", "")
    sdk_path = os.environ.get("ANDROID_SDK_PATH", "")
    arch = os.environ.get("ANDROID_ARCH", "aarch64")
    mode = os.environ.get("BUILDOZER_MODE", "debug")

    cfg = configparser.ConfigParser(interpolation=None)
    # utf-8-sig：兼容带 BOM 的 spec 文件（某些编辑器/PowerShell 会写入 BOM）
    cfg.read(spec_path, encoding="utf-8-sig")
    for section in SECTIONS:
        if not cfg.has_section(section):
            cfg.add_section(section)

    def put(section: str, key: str, value: str, overwrite: bool = True):
        if not value and cfg.has_option(section, key) and not overwrite:
            return
        cfg.set(section, key, value)

    put("app", "title", "CloudFlareScan")
    put("app", "project_dir", project_dir)
    put("app", "input_file", os.path.join(project_dir, "main.py"))
    put("app", "exec_directory", project_dir)

    put("qt", "modules", "QtCore, QtGui, QtWidgets")

    put("android", "wheel_pyside", wheel_pyside)
    put("android", "wheel_shiboken", wheel_shiboken)
    put("android", "arch", arch)

    put("buildozer", "mode", mode)
    if ndk_path:
        put("buildozer", "ndk_path", ndk_path)
    if sdk_path:
        put("buildozer", "sdk_path", sdk_path)

    with open(spec_path, "w", encoding="utf-8") as fh:
        cfg.write(fh)

    print(f"[patch_spec] wrote {spec_path}")
    print(f"[patch_spec] wheel_pyside  = {wheel_pyside}")
    print(f"[patch_spec] wheel_shiboken= {wheel_shiboken}")
    print(f"[patch_spec] arch={arch} mode={mode}")
    if ndk_path:
        print(f"[patch_spec] ndk_path     = {ndk_path}")
    if sdk_path:
        print(f"[patch_spec] sdk_path     = {sdk_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
