"""CloudFlareScan 入口文件。

`pyside6-android-deploy` 要求入口文件名必须是 ``main.py``，因此这里只做转发，
真正的界面在 CloudFlareScan.py 里，桌面版与 Android 版共用同一份代码。
"""
import sys

from CloudFlareScan import run_app

if __name__ == "__main__":
    sys.exit(run_app())
