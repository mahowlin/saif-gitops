"""Render actual chart consumers offline; kubectl is used only for local Kustomize."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which("helm"), "Helm is required for chart rendering")
class CiliumSelectedConsumer(unittest.TestCase):
    def render(self, parameters):
        command = ["helm", "template", "fixture", str(ROOT / "charts/cilium-config")]
        for name, value in parameters.items():
            command.extend(["--set", f"{name}={value}"])
        return [document for document in yaml.safe_load_all(
            subprocess.check_output(command, text=True)
        ) if document]

    def test_devices_and_direct_routing_device_have_separate_inputs(self):
        documents = self.render({
            "clusterName": "fixture", "ciliumConfig.apiHost": "api.fixture.invalid",
            "ciliumConfig.restartJobImage": "fixture.invalid/tools:v1",
            "ciliumConfig.ipam.cidr": "192.0.2.0/24",
            "ciliumConfig.devices[0]": "fixture-mgmt",
            "ciliumConfig.devices[1]": "fixture-tenant.42",
            "ciliumConfig.directRoutingDevice": "fixture-mgmt",
        })
        config = next(item for item in documents if item["kind"] == "CiliumConfig")
        self.assertEqual(config["spec"]["devices"], ["fixture-mgmt", "fixture-tenant.42"])
        self.assertEqual(config["spec"]["nodePort"]["directRoutingDevice"], "fixture-mgmt")

    def test_legacy_peering_requires_separate_opt_in(self):
        parameters = {"clusterName": "fixture", "ciliumConfig.enabled": "false", "bgp.enabled": "true"}
        self.assertFalse(any(item["kind"] == "CiliumBGPPeeringPolicy" for item in self.render(parameters)))
        parameters["bgp.peeringPolicy.enabled"] = "true"
        self.assertTrue(any(item["kind"] == "CiliumBGPPeeringPolicy" for item in self.render(parameters)))

    def test_selected_application_helm_parameters_reach_datapath(self):
        selected = os.environ.get("SELECTED_CLUSTER_ROOT")
        if not selected or not shutil.which("kubectl"):
            self.skipTest("SELECTED_CLUSTER_ROOT and local kubectl Kustomize are required")
        applications = list(yaml.safe_load_all(subprocess.check_output(
            ["kubectl", "kustomize", str(ROOT / selected)], text=True,
        )))
        app = next(item for item in applications if item and item.get("kind") == "Application"
                   and item["metadata"]["name"] == "cilium-config")
        parameters = {item["name"]: item["value"] for item in app["spec"]["source"]["helm"]["parameters"]}
        config = next(item for item in self.render(parameters) if item["kind"] == "CiliumConfig")
        expected_devices = [value for name, value in sorted(parameters.items())
                            if name.startswith("ciliumConfig.devices[")]
        self.assertEqual(config["spec"]["devices"], expected_devices)
        self.assertEqual(config["spec"]["nodePort"]["directRoutingDevice"], parameters["ciliumConfig.directRoutingDevice"])


if __name__ == "__main__":
    unittest.main()
