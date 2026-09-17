import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location(
    "connector", Path(__file__).resolve().parents[1] / "connector/splunk_to_shuffle.py"
)
connector = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(connector)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        folder = Path(self.temp.name)
        self.patch = patch.multiple(
            connector, FOLDER=folder, STATE_FILE=folder / "state.json", LOG_FILE=folder / "connector.log"
        )
        self.patch.start()
        self.addCleanup(self.patch.stop)
        self.result = {
            "detection": "Password Spraying Detected", "severity": "High",
            "last_seen": "1787250000", "first_seen": "1787249900",
            "source_ip": "192.168.226.133", "source_hosts": ["VICTIM-B"],
            "targeted_accounts": "5", "failed_attempts": "5",
            "targeted_users": [f"spray.user{i:02d}" for i in range(1, 6)],
            "mitre_technique": "T1110.003", "status": "New",
        }

    def test_delivery_acknowledgement_is_not_containment_success(self):
        with patch.object(connector, "search_splunk", return_value=self.result), patch.object(
            connector, "send_to_shuffle", return_value=(200, {"success": True, "execution_id": "test"})
        ):
            connector.run_once("-10m")
        state = connector.json.loads(connector.STATE_FILE.read_text())
        self.assertEqual(state["delivery_status"], "accepted_by_shuffle")
        self.assertIn("requires operator approval", connector.LOG_FILE.read_text())
        self.assertNotIn("verified_accounts", state)

    def test_failed_delivery_does_not_save_successful_state(self):
        with patch.object(connector, "search_splunk", return_value=self.result), patch.object(
            connector, "send_to_shuffle", return_value=(500, {"success": False})
        ):
            with self.assertRaises(RuntimeError):
                connector.run_once("-10m")
        self.assertFalse(connector.STATE_FILE.exists())

    def test_identical_result_is_delivered_once(self):
        with patch.object(connector, "search_splunk", return_value=self.result), patch.object(
            connector, "send_to_shuffle", return_value=(200, {"success": True})
        ) as send:
            connector.run_once("-10m")
            connector.run_once("-10m")
            send.assert_called_once()

    def test_check_only_never_sends(self):
        with patch.object(connector, "search_splunk", return_value=self.result), patch.object(
            connector, "send_to_shuffle"
        ) as send:
            connector.run_once("-10m", check_only=True)
            send.assert_not_called()
        self.assertFalse(connector.STATE_FILE.exists())

    def test_no_detection_never_sends(self):
        with patch.object(connector, "search_splunk", return_value=None), patch.object(
            connector, "send_to_shuffle"
        ) as send:
            connector.run_once("-10m")
            send.assert_not_called()


if __name__ == "__main__":
    unittest.main()
