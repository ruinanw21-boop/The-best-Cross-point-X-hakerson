import json
import os
import unittest
from contextlib import ExitStack
from unittest.mock import Mock, patch

import httpx

from translation_service.app import create_app
from translation_service.provider import TranslationFailed, UpstreamTimeout


ENGLISH = "Which desk should I go to?"
CHINESE = "请把护照复印件交到一楼服务台。"
ENGLISH_REQUEST = {"text": ENGLISH, "source_language": "en", "target_language": "zh"}


class TranslationApiTests(unittest.TestCase):
    def setUp(self):
        self.translator = Mock()
        self.client = create_app(translator=self.translator).test_client()

    def assert_error(self, response, status, code):
        self.assertEqual(response.status_code, status)
        self.assertEqual(response.get_json(), {"error": {"code": code}})

    def test_both_translation_directions(self):
        examples = [
            (ENGLISH, "en", "zh", "我应该去哪个服务台？"),
            (CHINESE, "zh", "en", "Take a copy of your passport to the first-floor service desk."),
        ]
        for text, source, target, translation in examples:
            with self.subTest(source=source, target=target):
                self.translator.reset_mock()
                self.translator.return_value = translation
                response = self.client.post(
                    "/translate",
                    json={"text": text, "source_language": source, "target_language": target},
                )
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.get_json(), {"translation": translation})
                self.translator.assert_called_once_with(text, source, target)

    def test_rejects_invalid_input_before_calling_upstream(self):
        invalid_bodies = [
            {},
            {"text": ENGLISH, "source_language": "en"},
            {**ENGLISH_REQUEST, "text": " \t\n "},
            {**ENGLISH_REQUEST, "text": 17},
            {**ENGLISH_REQUEST, "source_language": "fr"},
            {**ENGLISH_REQUEST, "target_language": "en"},
            {**ENGLISH_REQUEST, "target_language": ["zh"]},
            {**ENGLISH_REQUEST, "draftID": "local-only"},
            ["en", "zh"],
        ]
        for body in invalid_bodies:
            with self.subTest(body=body):
                response = self.client.post("/translate", json=body)
                self.assert_error(response, 400, "invalid_request")
        self.translator.assert_not_called()

    def test_requires_valid_json(self):
        for body, content_type in [
            (ENGLISH, "text/plain"),
            ('{"text":', "application/json"),
            ("null", "application/json"),
        ]:
            with self.subTest(body=body, content_type=content_type):
                response = self.client.post("/translate", data=body, content_type=content_type)
                self.assert_error(response, 400, "invalid_request")
        self.translator.assert_not_called()

    def test_transient_errors_and_successful_retry(self):
        self.translator.side_effect = [
            UpstreamTimeout("internal detail"),
            TranslationFailed("internal detail"),
            "我应该去哪个服务台？",
        ]
        for status, code in [(504, "upstream_timeout"), (502, "translation_failed")]:
            response = self.client.post("/translate", json=ENGLISH_REQUEST)
            self.assert_error(response, status, code)
        retry = self.client.post("/translate", json=ENGLISH_REQUEST)
        self.assertEqual(retry.status_code, 200)
        self.assertEqual(retry.get_json(), {"translation": "我应该去哪个服务台？"})
        self.assertEqual(self.translator.call_count, 3)


class ZhipuTranslationTests(unittest.TestCase):
    """Exercise the Zhipu REST mapping without sending requests over the network."""

    def setUp(self):
        self.client = create_app().test_client()
        self.contexts = ExitStack()
        self.addCleanup(self.contexts.close)
        self.contexts.enter_context(patch.dict(os.environ, {
            "ZHIPUAI_API_KEY": "offline-test-key",
            "TRANSLATION_TERMS_JSON": "[]",
        }))
        self.send = self.contexts.enter_context(patch.object(httpx.Client, "send", autospec=True))

    def test_authenticated_request_and_directional_glossary(self):
        glossary = [{"zh": "测试楼", "en": "Test Building"}]
        os.environ["TRANSLATION_TERMS_JSON"] = json.dumps(glossary)
        for source, target, text, translated, source_name, target_name in [
            ("zh", "en", "测试楼", "Test Building", "Chinese", "English"),
            ("en", "zh", "Test Building", "测试楼", "English", "Chinese"),
        ]:
            with self.subTest(source=source):
                self.send.reset_mock()
                choice = {
                    "finish_reason": "stop",
                    "message": {"role": "assistant", "reasoning_content": "internal", "content": translated},
                }
                self.send.return_value = self.response(200, {"choices": [choice]})
                response = self.client.post("/translate", json={
                    "text": text, "source_language": source, "target_language": target,
                })
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.get_json(), {"translation": translated})
                self.send.assert_called_once()
                request = self.send.call_args.args[1]
                self.assertEqual(request.method, "POST")
                self.assertEqual(str(request.url), "https://open.bigmodel.cn/api/paas/v4/chat/completions")
                self.assertEqual(request.headers["Authorization"], "Bearer offline-test-key")
                payload = json.loads(request.content)
                self.assertEqual(payload["model"], "glm-5.3")
                self.assertEqual(payload["reasoning_effort"], "low")
                self.assertNotIn("thinking", payload)
                self.assertEqual(
                    request.extensions["timeout"],
                    {"connect": 15.0, "read": 90.0, "write": 15.0, "pool": 15.0},
                )
                system, user = payload["messages"]
                self.assertEqual(user, {"role": "user", "content": text})
                self.assertEqual(system["role"], "system")
                prompt = system["content"]
                self.assertIn(f"Translate from {source_name} to {target_name}", prompt)
                # The glossary must retain the direction in each JSON entry.
                entry_start = prompt.index("{")
                entry, _ = json.JSONDecoder().raw_decode(prompt[entry_start:])
                self.assertEqual(entry, {"source": text, "target": translated})

    @staticmethod
    def response(status, body):
        return httpx.Response(status, json=body, request=httpx.Request("POST", "https://example.invalid"))

    def test_transport_errors(self):
        error_body = {"error": {"code": "internal", "message": "internal detail"}}
        for upstream, status, code in [
            (httpx.ReadTimeout("internal detail"), 504, "upstream_timeout"),
            (self.response(408, error_body), 504, "upstream_timeout"),
            (self.response(504, error_body), 504, "upstream_timeout"),
            (self.response(401, error_body), 502, "translation_failed"),
            (self.response(503, error_body), 502, "translation_failed"),
        ]:
            with self.subTest(upstream=upstream):
                self.send.reset_mock()
                self.send.side_effect = [upstream]
                response = self.client.post("/translate", json=ENGLISH_REQUEST)
                self.assertEqual(response.status_code, status)
                self.assertEqual(response.get_json(), {"error": {"code": code}})
                self.send.assert_called_once()

    def test_429_logs_only_safe_business_code(self):
        for upstream, expected_code in [
            (self.response(429, {"error": {"code": "1302", "message": ENGLISH}}), "1302"),
            (self.response(429, {"error": {"code": 1303}}), "1303"),
            (self.response(429, {"error": {"code": "１３０２"}}), "unknown"),
            (self.response(429, {"error": {"code": "1302\nprivate detail"}}), "unknown"),
            (self.response(429, {"error": [ENGLISH]}), "unknown"),
            (httpx.Response(429, text=ENGLISH), "unknown"),
        ]:
            with self.subTest(expected_code=expected_code):
                self.send.return_value = upstream
                with self.assertLogs("translation_service.provider", level="WARNING") as logs:
                    response = self.client.post("/translate", json=ENGLISH_REQUEST)
                self.assertEqual(response.status_code, 502)
                self.assertEqual(response.get_json(), {"error": {"code": "translation_failed"}})
                self.assertEqual(
                    logs.output,
                    [f"WARNING:translation_service.provider:Zhipu HTTP 429; business_code={expected_code}"],
                )

    def test_incomplete_or_malformed_completions(self):
        cases = [
            {"choices": [{"finish_reason": reason, "message": {"content": "partial output"}}]}
            for reason in ["sensitive", "length", "network_error", None]
        ]
        cases.extend([
            {"choices": []},
            {"choices": [{"finish_reason": "stop", "message": {"content": " \t "}}]},
            {"choices": [{"finish_reason": "stop", "message": {}}]},
            {"choices": [{"finish_reason": "stop", "message": {"reasoning_content": "internal"}}]},
            {"error": {"message": "internal detail"}},
            [],
        ])
        for body in cases:
            with self.subTest(body=body):
                self.send.return_value = self.response(200, body)
                response = self.client.post("/translate", json=ENGLISH_REQUEST)
                self.assertEqual(response.status_code, 502)
                self.assertEqual(response.get_json(), {"error": {"code": "translation_failed"}})

    def test_auth_diagnostic_requires_numeric_business_code(self):
        for status in (401, 403):
            with self.subTest(status=status):
                self.send.return_value = self.response(status, {"error": {"code": 1001, "message": ENGLISH}})
                with self.assertLogs("translation_service.provider", level="WARNING") as logs:
                    response = self.client.post("/translate", json=ENGLISH_REQUEST)
                self.assertEqual(response.status_code, 502)
                self.assertEqual(response.get_json(), {"error": {"code": "translation_failed"}})
                self.assertEqual(
                    [record.getMessage() for record in logs.records],
                    [f"Zhipu HTTP {status}; business_code=1001"],
                )
                self.send.return_value = self.response(status, {"error": {"message": ENGLISH}})
                with self.assertNoLogs("translation_service.provider", level="WARNING"):
                    response = self.client.post("/translate", json=ENGLISH_REQUEST)
                self.assertEqual(response.status_code, 502)

    def test_missing_key_does_not_call_provider(self):
        os.environ.pop("ZHIPUAI_API_KEY")
        response = self.client.post("/translate", json=ENGLISH_REQUEST)
        self.assertEqual(response.status_code, 502)
        self.assertEqual(response.get_json(), {"error": {"code": "translation_failed"}})
        self.send.assert_not_called()


if __name__ == "__main__":
    unittest.main()
