"""Run the task 04 acceptance page for one iPhone on the local network."""

import argparse
import json
import logging
import os
from getpass import getpass
from ipaddress import IPv4Address
from pathlib import Path
from threading import Lock

from flask import abort, jsonify, request, send_file
from waitress import serve

from .app import create_app
from .provider import translate


SAMPLES = {
    ("en", "zh", "Which desk should I go to?"): "en_zh",
    ("zh", "en", "请把护照复印件交到一楼服务台。"): "zh_en",
}


def create_iphone_app(phone: str, *, translator=translate):
    phone = str(IPv4Address(phone))
    app = create_app(translator)
    translations = {}
    lock = Lock()

    @app.before_request
    def allow_test_phone():
        if request.remote_addr != phone:
            abort(403)

    @app.get("/")
    def acceptance_page():
        app.logger.info("IPHONE_CHECK opened iphone_agent=%s", "iPhone" in request.user_agent.string)
        return send_file(Path(__file__).with_name("iphone_check.html"), max_age=0)

    @app.after_request
    def record_sample(response):
        response.headers["Cache-Control"] = "no-store"
        if request.path == "/translate" and response.status_code == 200:
            body = request.get_json()
            direction = SAMPLES.get((body["source_language"], body["target_language"], body["text"]))
            if direction:
                with lock:
                    translations[direction] = response.get_json()["translation"]
                app.logger.info("IPHONE_CHECK %s HTTP 200", direction)
        return response

    @app.post("/displayed")
    def confirm_display():
        displayed = request.get_json(silent=True)
        with lock:
            if len(translations) != len(SAMPLES) or displayed != translations:
                return jsonify(confirmed=False), 400
            evidence = json.dumps(translations, ensure_ascii=True)
        app.logger.info("IPHONE_CHECK displayed %s", evidence)
        return jsonify(confirmed=True)

    return app


def main():
    parser = argparse.ArgumentParser(description="任务 04：iPhone 双向翻译验收")
    parser.add_argument("--host", required=True, type=IPv4Address, help="Windows 的 Wi-Fi IPv4 地址")
    parser.add_argument("--phone", required=True, type=IPv4Address, help="iPhone 的 Wi-Fi IPv4 地址")
    parser.add_argument("--port", default=8000, type=int)
    args = parser.parse_args()
    if args.host == args.phone or any(
        address.is_unspecified or address.is_loopback or address.is_multicast
        for address in (args.host, args.phone)
    ):
        parser.error("请填写电脑和 iPhone 各自的局域网地址")
    if not os.environ.get("ZHIPUAI_API_KEY", "").strip():
        key = getpass("请输入智谱模型标准 API Key（隐藏输入）：").strip()
        if not key:
            parser.error("需要智谱 API Key 才能验收真实翻译")
        os.environ["ZHIPUAI_API_KEY"] = key

    logging.basicConfig(level=logging.INFO)
    serve(create_iphone_app(str(args.phone)), host=str(args.host), port=args.port)


if __name__ == "__main__":
    main()
