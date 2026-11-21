from collections.abc import Callable

from flask import Flask, jsonify, request

from .provider import TranslationFailed, UpstreamTimeout, translate


def create_app(translator: Callable[[str, str, str], str] = translate) -> Flask:
    app = Flask(__name__)
    app.json.ensure_ascii = False
    app.json.mimetype = "application/json; charset=utf-8"

    @app.post("/translate")
    def translate_reply():
        body = request.get_json(silent=True)
        if not isinstance(body, dict) or body.keys() != {
            "text", "source_language", "target_language"
        }:
            return jsonify(error={"code": "invalid_request"}), 400

        text = body["text"]
        source = body["source_language"]
        target = body["target_language"]
        if (
            not isinstance(text, str)
            or not text.strip()
            or (source, target) not in (("en", "zh"), ("zh", "en"))
        ):
            return jsonify(error={"code": "invalid_request"}), 400

        try:
            translation = translator(text, source, target)
        except UpstreamTimeout:
            return jsonify(error={"code": "upstream_timeout"}), 504
        except TranslationFailed:
            return jsonify(error={"code": "translation_failed"}), 502
        return jsonify(translation=translation)

    return app
