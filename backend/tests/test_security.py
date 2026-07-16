import asyncio
import io
import unittest
from unittest.mock import patch

from fastapi import HTTPException

import main


class FakeUpload:
    def __init__(self, chunks):
        self._chunks = iter(chunks)

    async def read(self, _size):
        return next(self._chunks, b"")


class FakeWebSocket:
    def __init__(self, headers):
        self.headers = headers
        self.closed = None
        self.accepted = False

    async def close(self, code, reason):
        self.closed = (code, reason)

    async def accept(self):
        self.accepted = True


class SecurityControlsTests(unittest.TestCase):
    def setUp(self):
        main._auth_token = "test-token"

    def test_loopback_host_and_origin_boundary(self):
        self.assertTrue(main._loopback_hostname("127.0.0.1:8080"))
        self.assertTrue(main._allowed_origin("http://localhost:8080"))
        self.assertFalse(main._loopback_hostname("attacker.example"))
        self.assertFalse(main._allowed_origin("https://attacker.example"))

    def test_bearer_auth_rejects_missing_and_wrong_tokens(self):
        with self.assertRaises(HTTPException) as missing:
            main.verify_auth_token(None)
        self.assertEqual(missing.exception.status_code, 401)
        with self.assertRaises(HTTPException) as wrong:
            main.verify_auth_token("Bearer wrong")
        self.assertEqual(wrong.exception.status_code, 403)
        self.assertEqual(main.verify_auth_token("Bearer test-token"), "test-token")

    def test_config_never_returns_the_token(self):
        response = asyncio.run(main.get_config("test-token"))
        self.assertNotIn(b"auth_token", response.body)

    def test_remote_actions_are_clipboard_only(self):
        self.assertTrue(main._is_safe_remote_action({"name": "copy", "type": "clipboard", "config": {}}))
        for action_type in ("terminal_command", "open_app", "http_request"):
            self.assertFalse(main._is_safe_remote_action({"name": "unsafe", "type": action_type, "config": {}}))

    def test_sensitive_http_routes_require_auth(self):
        protected = {"/api/actions", "/api/settings", "/api/config", "/api/history", "/api/transcribe"}
        for route in main.app.routes:
            if getattr(route, "path", None) not in protected:
                continue
            dependencies = [dependency.call for dependency in route.dependant.dependencies]
            self.assertIn(main.verify_auth_token, dependencies, route.path)

    def test_oversized_upload_is_rejected_before_transcription(self):
        destination = io.BytesIO()
        upload = FakeUpload([b"1234", b"5"])
        with patch.object(main, "MAX_UPLOAD_BYTES", 4):
            with self.assertRaises(HTTPException) as oversized:
                asyncio.run(main._copy_bounded_upload(upload, destination))
        self.assertEqual(oversized.exception.status_code, 413)

    def test_websocket_rejects_missing_auth_before_accept(self):
        websocket = FakeWebSocket({"host": "127.0.0.1:8080"})
        asyncio.run(main.websocket_endpoint(websocket))
        self.assertFalse(websocket.accepted)
        self.assertEqual(websocket.closed[0], 1008)


if __name__ == "__main__":
    unittest.main()
