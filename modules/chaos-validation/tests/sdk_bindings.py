from pathlib import Path
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from azure.servicebus.exceptions import ServiceBusError
from business import make_client, TrafficFailure


class OfflineCredential:
    def get_token(self, *scopes, **kwargs):
        raise AssertionError("SDK binding checks must not request credentials or access the network.")


class SDKBindingTests(unittest.TestCase):
    def test_pinned_sdk_factories_construct_without_network_or_credentials(self):
        for kind, endpoint in (("blob", "https://canary.blob.core.windows.net"),
                               ("servicebus", "canary.servicebus.windows.net")):
            with self.subTest(kind=kind):
                client = make_client(kind, {"endpoint": endpoint, "entity": "chaos-test"}, 1, OfflineCredential())
                self.addCleanup(client.close)

    def test_sdk_send_failure_preserves_identity_and_is_not_retried_by_adapter(self):
        operation_id = "a" * 32
        client = make_client("servicebus", {"endpoint": "canary.servicebus.windows.net", "entity": "chaos-test"},
                             1, OfflineCredential())
        self.addCleanup(client.close)
        sender = MagicMock()
        sender.send_messages.side_effect = ServiceBusError("must not appear in public evidence")
        with patch.object(client.client, "get_queue_sender", return_value=sender):
            with self.assertRaises(TrafficFailure) as caught:
                client.send(operation_id, b"synthetic")
        self.assertEqual(str(caught.exception), "ServiceBusError")
        sender.send_messages.assert_called_once()
        message = sender.send_messages.call_args.args[0]
        self.assertEqual(message.message_id, operation_id)
        self.assertEqual(b"".join(message.body), b"synthetic")


if __name__ == "__main__":
    unittest.main()
