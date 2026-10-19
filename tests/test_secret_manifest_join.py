"""The public metadata produces encrypted objects under the watched source path."""
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
import yaml

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("public_seal_join", ROOT / ".github/scripts/seal_manifest.py")
sealer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sealer)


class SecretManifestJoin(unittest.TestCase):
    def test_common_manifest_reaches_watched_path_with_selected_namespace_and_keys(self):
        manifest = ROOT / "apps/sealed-secrets/secrets-manifest.yaml"
        groups = yaml.safe_load(manifest.read_text())["secrets"]
        expected = {
            (group["namespace"], secret["name"]): {key["name"] for key in secret["keys"]}
            for group in groups if group["scope"] == "_common"
            for secret in group["secrets"]
        }
        environment = {
            key["github_secret"]: "SYNTHETIC-NOT-A-CREDENTIAL"
            for group in groups for secret in group["secrets"] for key in secret["keys"]
        }
        application = yaml.safe_load((ROOT / "clusters/_base/tier1-core/sealed-secrets.yaml").read_text())
        watched = Path(application["spec"]["source"]["path"])
        self.assertTrue(application["spec"]["source"]["directory"]["recurse"])

        def seal(command, **kwargs):
            plaintext = yaml.safe_load(kwargs["input"])
            ciphertext = {
                "kind": "SealedSecret", "metadata": plaintext["metadata"],
                "spec": {"encryptedData": {key: "synthetic-cipher" for key in plaintext["stringData"]}},
            }
            return subprocess.CompletedProcess(command, 0, yaml.safe_dump(ciphertext), "")

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            count = sealer.generate(manifest, root, "_common", False, "synthetic-cert", environment, seal)
            outputs = list((root / watched).glob("*/*.yaml"))
            self.assertEqual(count, len(expected))
            self.assertEqual(len(outputs), count)
            for output in outputs:
                document = yaml.safe_load(output.read_text())
                identity = (document["metadata"]["namespace"], document["metadata"]["name"])
                self.assertEqual(output.parent.name, identity[0])
                self.assertEqual(set(document["spec"]["encryptedData"]), expected[identity])
                self.assertNotIn("SYNTHETIC-NOT-A-CREDENTIAL", output.read_text())


if __name__ == "__main__":
    unittest.main()
