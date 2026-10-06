"""节点分享功能的回归测试。

运行： python test_node_share.py
依赖： PySide6, aiohttp（与主程序一致）。测试使用 Qt 的 offscreen 平台，不会弹出窗口。
"""
import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QSettings  # noqa: E402
from PySide6.QtWidgets import QApplication  # noqa: E402

# 让 QSettings 写到临时目录，避免污染真实注册表/配置文件
_SETTINGS_DIR = tempfile.mkdtemp(prefix="cfs_settings_")
QSettings.setDefaultFormat(QSettings.IniFormat)
QSettings.setPath(QSettings.IniFormat, QSettings.UserScope, _SETTINGS_DIR)

APP = QApplication.instance() or QApplication(sys.argv)

HERE = Path(__file__).resolve().parent
_spec = importlib.util.spec_from_file_location("cfs_module", HERE / "CloudFlareScan.py")
cfs = importlib.util.module_from_spec(_spec)
sys.modules["cfs_module"] = cfs
_spec.loader.exec_module(cfs)


# 用户给出的两个样本，逐字符比对
SAMPLE_1 = (
    "vless://73bcd72f-9545-4cb8-8daf-7d004501880d@104.17.214.222:443"
    "?path=%2F&security=tls&encryption=none&insecure=0&host=mjw04.ccwu.cc&fp=chrome"
    "&ech=cloudflare-ech.com%2Bhttps%3A%2F%2Fdns.alidns.com%2Fdns-query"
    "&type=ws&allowInsecure=0&sni=mjw04.ccwu.cc#CF%E7%A7%BB%E5%8A%A8%E4%BC%98%E9%80%892"
)
SAMPLE_2 = (
    "vless://73bcd72f-9545-4cb8-8daf-7d004501880d@104.17.119.39:2083"
    "?path=%2F&security=tls&encryption=none&insecure=0&host=mjw04.ccwu.cc&fp=chrome"
    "&ech=cloudflare-ech.com%2Bhttps%3A%2F%2Fdns.alidns.com%2Fdns-query"
    "&type=ws&allowInsecure=0&sni=mjw04.ccwu.cc#CF%E7%A7%BB%E5%8A%A8%E4%BC%98%E9%80%8914"
)

FAKE_RESULTS = [
    {"ip": "104.17.214.222", "latency": 30.0, "download_speed": 12.5, "iata_code": "HKG",
     "chinese_name": "香港", "test_type": "完全测速", "port": 443},
    {"ip": "104.17.119.39", "latency": 40.0, "download_speed": 8.0, "iata_code": "SJC",
     "chinese_name": "圣何塞", "test_type": "完全测速", "port": 2083},
    {"ip": "172.64.0.1", "latency": 50.0, "download_speed": 2.0, "iata_code": "SIN",
     "chinese_name": "新加坡", "test_type": "完全测速", "port": 443},
    {"ip": "104.16.0.1", "latency": 60.0, "download_speed": 1.5, "iata_code": "NRT",
     "chinese_name": "东京", "test_type": "完全测速", "port": 443},
]


class TestLinkFormat(unittest.TestCase):
    """分享链接必须与用户样本逐字符一致。"""

    def test_sample_1_exact(self):
        self.assertEqual(
            cfs.build_vless_link("104.17.214.222", 443, remark="CF移动优选2"),
            SAMPLE_1,
        )

    def test_sample_2_exact(self):
        self.assertEqual(
            cfs.build_vless_link("104.17.119.39", 2083, remark="CF移动优选14"),
            SAMPLE_2,
        )

    def test_query_parameter_order(self):
        link = cfs.build_vless_link("1.2.3.4", 443, remark="x")
        query = link.split("?", 1)[1].split("#", 1)[0]
        keys = [pair.split("=", 1)[0] for pair in query.split("&")]
        self.assertEqual(keys, cfs.SHARE_QUERY_ORDER)

    def test_ech_omitted_when_disabled(self):
        link = cfs.build_vless_link("1.2.3.4", 443, ech="", remark="x")
        self.assertNotIn("ech=", link)
        self.assertIn("&type=ws&", link)

    def test_no_remark_no_fragment(self):
        self.assertNotIn("#", cfs.build_vless_link("1.2.3.4", 443, remark=""))

    def test_ipv6_is_bracketed(self):
        link = cfs.build_vless_link("2606:4700::1", 443, remark="v6")
        self.assertIn("@[2606:4700::1]:443?", link)

    def test_ipv4_not_bracketed(self):
        self.assertIn("@104.17.214.222:443?", cfs.build_vless_link("104.17.214.222", 443))

    def test_custom_host_and_sni(self):
        link = cfs.build_vless_link("1.2.3.4", 8443, host="a.example.com",
                                    sni="b.example.com", path="/ws", remark="r")
        self.assertIn("host=a.example.com", link)
        self.assertIn("sni=b.example.com", link)
        self.assertIn("path=%2Fws", link)


class TestSpeedFilter(unittest.TestCase):
    """> 阈值 必须是严格大于，并且按速度降序。"""

    def test_strictly_greater_than_threshold(self):
        matched = cfs.filter_nodes_by_speed(FAKE_RESULTS, 2.0)
        self.assertEqual([r["ip"] for r in matched],
                         ["104.17.214.222", "104.17.119.39"])

    def test_sorted_descending(self):
        matched = cfs.filter_nodes_by_speed(FAKE_RESULTS, 0)
        speeds = [r["download_speed"] for r in matched]
        self.assertEqual(speeds, sorted(speeds, reverse=True))

    def test_custom_threshold(self):
        matched = cfs.filter_nodes_by_speed(FAKE_RESULTS, 10)
        self.assertEqual([r["ip"] for r in matched], ["104.17.214.222"])

    def test_handles_bad_values(self):
        matched = cfs.filter_nodes_by_speed(
            [{"ip": "1.1.1.1", "download_speed": None},
             {"ip": "2.2.2.2", "download_speed": "abc"},
             {"ip": "3.3.3.3", "download_speed": "9.5"}], 2.0)
        self.assertEqual([r["ip"] for r in matched], ["3.3.3.3"])

    def test_empty_input(self):
        self.assertEqual(cfs.filter_nodes_by_speed([], 2.0), [])
        self.assertEqual(cfs.filter_nodes_by_speed(None, 2.0), [])


class TestBuildNodes(unittest.TestCase):
    def test_default_uses_each_result_port(self):
        nodes = cfs.build_share_nodes(FAKE_RESULTS, threshold=2.0)
        self.assertEqual(len(nodes), 2)
        self.assertEqual([remark for remark, _ in nodes], ["CF移动优选1", "CF移动优选2"])
        self.assertIn(":443?", nodes[0][1])
        self.assertIn(":2083?", nodes[1][1])

    def test_start_index_reproduces_samples(self):
        nodes = cfs.build_share_nodes(FAKE_RESULTS, threshold=2.0, start_index=2)
        self.assertEqual(nodes[0][1], SAMPLE_1)
        self.assertEqual(nodes[0][0], "CF移动优选2")

    def test_single_result_reproduces_sample_2(self):
        only = [dict(FAKE_RESULTS[1])]
        nodes = cfs.build_share_nodes(only, threshold=2.0, start_index=14)
        self.assertEqual(nodes[0][1], SAMPLE_2)

    def test_explicit_ports_override_and_multiply(self):
        nodes = cfs.build_share_nodes(FAKE_RESULTS, threshold=2.0, ports=[443, 2083])
        self.assertEqual(len(nodes), 4)
        self.assertEqual([r for r, _ in nodes],
                         ["CF移动优选1", "CF移动优选2", "CF移动优选3", "CF移动优选4"])
        self.assertIn(":443?", nodes[0][1])
        self.assertIn(":2083?", nodes[1][1])
        self.assertIn(":443?", nodes[2][1])
        self.assertIn(":2083?", nodes[3][1])

    def test_threshold_filters(self):
        self.assertEqual(len(cfs.build_share_nodes(FAKE_RESULTS, threshold=9)), 1)
        self.assertEqual(len(cfs.build_share_nodes(FAKE_RESULTS, threshold=100)), 0)

    def test_empty_prefix_falls_back_to_number(self):
        nodes = cfs.build_share_nodes(FAKE_RESULTS[:1], threshold=2.0, remark_prefix="")
        self.assertEqual(nodes[0][0], "1")

    def test_no_results(self):
        self.assertEqual(cfs.build_share_nodes([], threshold=2.0), [])


class TestHelpers(unittest.TestCase):
    def test_parse_share_ports(self):
        self.assertEqual(cfs.parse_share_ports("443,2083"), [443, 2083])
        self.assertEqual(cfs.parse_share_ports("443 2083 443"), [443, 2083])
        self.assertEqual(cfs.parse_share_ports(""), [])
        self.assertEqual(cfs.parse_share_ports("abc,-1,0,70000,8443"), [8443])

    def test_text_and_subscription_payloads(self):
        nodes = cfs.build_share_nodes(FAKE_RESULTS, threshold=2.0)
        text = cfs.nodes_to_text(nodes)
        self.assertEqual(text.splitlines(), [link for _, link in nodes])
        import base64 as b64
        decoded = b64.b64decode(cfs.nodes_to_subscription(nodes)).decode("utf-8")
        self.assertEqual(decoded, text)


class TestGuiIntegration(unittest.TestCase):
    def test_share_button_disabled_until_speed_results(self):
        win = cfs.CloudflareScanUI()
        self.assertTrue(hasattr(win, "btn_share"))
        self.assertFalse(win.btn_share.isEnabled())
        win.speed_results = list(FAKE_RESULTS)
        win.update_ui_state(False)
        self.assertTrue(win.btn_share.isEnabled())
        win.update_ui_state(True)
        self.assertFalse(win.btn_share.isEnabled())
        win.deleteLater()

    def test_dialog_generates_and_exports(self):
        dlg = cfs.NodeShareDialog(FAKE_RESULTS, default_port=443)
        # 清掉可能残留的设置，确保走默认值
        dlg.input_threshold.setText("2")
        dlg.input_uuid.setText(cfs.DEFAULT_SHARE_UUID)
        dlg.input_host.setText(cfs.DEFAULT_SHARE_HOST)
        dlg.input_sni.setText(cfs.DEFAULT_SHARE_SNI)
        dlg.input_path.setText(cfs.DEFAULT_SHARE_PATH)
        dlg.input_prefix.setText(cfs.DEFAULT_SHARE_REMARK_PREFIX)
        dlg.input_start_index.setText("2")
        dlg.input_ports.setText("")
        dlg.chk_ech.setChecked(True)
        dlg.input_ech.setText(cfs.DEFAULT_SHARE_ECH)
        dlg._refresh()

        self.assertEqual(len(dlg.nodes), 2)
        self.assertEqual(dlg.nodes[0][1], SAMPLE_1)
        self.assertIn("vless://", dlg.preview.toPlainText())
        self.assertTrue(dlg.btn_copy.isEnabled())

        # 阈值调高后节点变少
        dlg.input_threshold.setText("10")
        dlg._refresh()
        self.assertEqual(len(dlg.nodes), 1)

        # 端口覆盖
        dlg.input_threshold.setText("2")
        dlg.input_ports.setText("443,2053,2083")
        dlg._refresh()
        self.assertEqual(len(dlg.nodes), 6)

        # Base64 订阅负载
        dlg.chk_base64.setChecked(True)
        import base64 as b64
        decoded = b64.b64decode(dlg._payload()).decode("utf-8")
        self.assertEqual(decoded, cfs.nodes_to_text(dlg.nodes))
        dlg.chk_base64.setChecked(False)
        self.assertEqual(dlg._payload(), cfs.nodes_to_text(dlg.nodes))
        dlg.deleteLater()

    def test_dialog_writes_export_file(self):
        dlg = cfs.NodeShareDialog(FAKE_RESULTS, default_port=443)
        dlg.input_start_index.setText("2")
        dlg._refresh()
        out = HERE / "_test_export_nodes.txt"
        if out.exists():
            out.unlink()

        class _StubFileDialog:
            @staticmethod
            def getSaveFileName(*args, **kwargs):
                return (str(out), "文本文件 (*.txt)")

        original = cfs.QFileDialog
        cfs.QFileDialog = _StubFileDialog
        try:
            dlg.export_to_file()
        finally:
            cfs.QFileDialog = original
        self.assertTrue(out.exists())
        written = out.read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(written, [link for _, link in dlg.nodes])
        self.assertEqual(written[0], SAMPLE_1)
        out.unlink()
        dlg.deleteLater()

    def test_validation_blocks_empty_uuid(self):
        dlg = cfs.NodeShareDialog(FAKE_RESULTS, default_port=443)
        dlg.input_uuid.setText("")
        dlg._refresh()
        self.assertFalse(dlg._validate())
        self.assertIn("UUID", dlg.feedback.text())
        dlg.deleteLater()

    def test_validation_blocks_low_threshold_misses(self):
        dlg = cfs.NodeShareDialog(FAKE_RESULTS, default_port=443)
        dlg.input_threshold.setText("1000")
        dlg._refresh()
        self.assertFalse(dlg._validate())
        self.assertFalse(dlg.btn_copy.isEnabled())
        dlg.deleteLater()


class TestAndroidPackaging(unittest.TestCase):
    """Android 打包相关的约束与适配。"""

    def test_source_has_no_aiohttp(self):
        # aiohttp 及其 8 个 C 扩展依赖在 python-for-android 下很难编，已改为纯标准库实现
        source = (HERE / "CloudFlareScan.py").read_text(encoding="utf-8")
        self.assertNotIn("aiohttp", source)

    def test_is_android_false_on_desktop(self):
        self.assertFalse(cfs.is_android())

    def test_save_dir_is_usable(self):
        path = cfs.get_default_save_dir()
        self.assertTrue(path)
        self.assertTrue(os.path.isdir(path))

    def test_patch_spec_script_exists(self):
        self.assertTrue((HERE / "android" / "patch_spec.py").exists())
        self.assertTrue((HERE / "android" / "build_apk.sh").exists())
        self.assertTrue((HERE / "main.py").exists())
        self.assertTrue((HERE / ".github" / "workflows" / "android.yml").exists())


class TestHttpParsing(unittest.TestCase):
    """aiohttp 替换成标准库后，HTTP 响应解析必须仍然正确。"""

    def test_dechunk_two_chunks(self):
        raw = b"9\r\ncolo=HKG\n\r\nb\r\nip=1.2.3.4\n\r\n0\r\n\r\n"
        self.assertEqual(cfs.dechunk_body(raw), b"colo=HKG\nip=1.2.3.4\n")

    def test_dechunk_single_chunk(self):
        raw = b"14\r\ncolo=HKG\nip=1.2.3.4\n\r\n0\r\n\r\n"
        self.assertEqual(cfs.dechunk_body(raw), b"colo=HKG\nip=1.2.3.4\n")

    def test_parse_plain_response(self):
        raw = b"HTTP/1.1 200 OK\r\nCf-Ray: abc123-SJC\r\nContent-Type: text/plain\r\n\r\ncolo=SJC\nip=1.2.3.4\n"
        status, headers, body = cfs.parse_http_response(raw)
        self.assertEqual(status, 200)
        self.assertEqual(headers["cf-ray"], "abc123-SJC")
        self.assertEqual(body, b"colo=SJC\nip=1.2.3.4\n")

    def test_parse_chunked_response(self):
        raw = (b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\nCF-RAY: 8a1b-HKG\r\n\r\n"
               b"14\r\ncolo=HKG\nip=1.2.3.4\n\r\n0\r\n\r\n")
        status, headers, body = cfs.parse_http_response(raw)
        self.assertEqual(status, 200)
        self.assertEqual(headers["cf-ray"], "8a1b-HKG")
        self.assertEqual(body, b"colo=HKG\nip=1.2.3.4\n")

    def test_parse_headers_are_lowercased(self):
        _, headers, _ = cfs.parse_http_response(b"HTTP/1.1 200 OK\r\nX-Weird-Header: V\r\n\r\n")
        self.assertEqual(headers["x-weird-header"], "V")

    def test_parse_garbage_is_safe(self):
        self.assertEqual(cfs.parse_http_response(b""), (0, {}, b""))
        self.assertEqual(cfs.parse_http_response(b"not http at all"), (0, {}, b""))
        status, _, _ = cfs.parse_http_response(b"BROKEN\r\n\r\nbody")
        self.assertEqual(status, 0)

    def test_non_200_status(self):
        status, _, _ = cfs.parse_http_response(b"HTTP/1.1 403 Forbidden\r\n\r\n")
        self.assertEqual(status, 403)


if __name__ == "__main__":
    unittest.main(verbosity=2)
