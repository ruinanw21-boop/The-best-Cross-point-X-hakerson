import unittest
from unittest.mock import Mock, call

from translation_service.app import create_app
from translation_service.iphone_check import create_iphone_app
from translation_service.provider import TranslationFailed


PHONE_IP = "192.168.1.52"
PHONE = {"REMOTE_ADDR": PHONE_IP}
ENGLISH = "Which desk should I go to?"
CHINESE = "请把护照复印件交到一楼服务台。"
EN_ZH = {"text": ENGLISH, "source_language": "en", "target_language": "zh"}
ZH_EN = {"text": CHINESE, "source_language": "zh", "target_language": "en"}
DISPLAYED = {
    "en_zh": "这次我应该去哪个窗口？",
    "zh_en": "Hand a photocopy of your passport to the service desk on the first floor.",
}


class IphoneCheckTests(unittest.TestCase):
    def setUp(self):
        self.translator = Mock(side_effect=[DISPLAYED["en_zh"], DISPLAYED["zh_en"]])
        self.client = create_iphone_app(PHONE_IP, translator=self.translator).test_client()

    def post(self, path, body):
        return self.client.post(path, json=body, environ_overrides=PHONE)

    def test_page_only_exists_in_phone_check_app(self):
        page = self.client.get("/", environ_overrides=PHONE)
        self.addCleanup(page.close)
        self.assertEqual(page.status_code, 200)
        self.assertEqual(page.mimetype, "text/html")
        self.assertIn("<button", page.get_data(as_text=True).lower())
        default = create_app(translator=self.translator).test_client()
        self.assertEqual(default.get("/").status_code, 404)
        self.translator.assert_not_called()

    def test_other_hosts_cannot_open_submit_or_confirm(self):
        for address in ("192.168.1.24", "192.168.1.87", "127.0.0.1"):
            with self.subTest(source=address):
                peer = {"REMOTE_ADDR": address}
                page = self.client.get("/", environ_overrides=peer)
                translate = self.client.post("/translate", json=EN_ZH, environ_overrides=peer)
                displayed = self.client.post("/displayed", json=DISPLAYED, environ_overrides=peer)
                self.assertEqual(page.status_code, 403)
                self.assertEqual(translate.status_code, 403)
                self.assertEqual(displayed.status_code, 403)
        self.translator.assert_not_called()

    def test_confirm_requires_both_returned_translations(self):
        self.assertEqual(self.post("/displayed", DISPLAYED).status_code, 400)
        first = self.post("/translate", EN_ZH)
        self.assertEqual(first.status_code, 200)
        self.assertEqual(first.get_json(), {"translation": DISPLAYED["en_zh"]})
        self.assertEqual(self.post("/displayed", DISPLAYED).status_code, 400)
        second = self.post("/translate", ZH_EN)
        self.assertEqual(second.status_code, 200)
        self.assertEqual(second.get_json(), {"translation": DISPLAYED["zh_en"]})

        for body in [
            {"zh_en": DISPLAYED["zh_en"]},
            {**DISPLAYED, "en_zh": "别的译文"},
            {**DISPLAYED, "zh_en": DISPLAYED["zh_en"] + "!"},
        ]:
            with self.subTest(body=body):
                self.assertEqual(self.post("/displayed", body).status_code, 400)
        other_host = self.client.post(
            "/displayed", json=DISPLAYED, environ_overrides={"REMOTE_ADDR": "192.168.1.87"}
        )
        self.assertEqual(other_host.status_code, 403)
        self.assertEqual(self.post("/displayed", DISPLAYED).status_code, 200)
        self.assertEqual(self.post("/displayed", DISPLAYED).status_code, 200)
        self.assertEqual(
            self.translator.call_args_list,
            [call(ENGLISH, "en", "zh"), call(CHINESE, "zh", "en")],
        )

    def test_failed_translation_does_not_count_as_displayed(self):
        self.translator.side_effect = [DISPLAYED["en_zh"], TranslationFailed("offline failure")]
        self.assertEqual(self.post("/translate", EN_ZH).status_code, 200)
        self.assertEqual(self.post("/translate", ZH_EN).status_code, 502)
        self.assertEqual(self.post("/displayed", DISPLAYED).status_code, 400)


if __name__ == "__main__":
    unittest.main()
