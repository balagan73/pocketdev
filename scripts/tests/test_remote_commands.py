import unittest

from remote_commands import parse_trigger_args, resolve_command


class ResolveCommandTest(unittest.TestCase):
    def test_restart_maps_to_docker_compose_restart(self):
        self.assertEqual(
            resolve_command("restart"), ["docker", "compose", "restart", "openclaw"]
        )

    def test_rebuild_maps_to_rebuild_script(self):
        self.assertEqual(resolve_command("rebuild"), ["bash", "rebuild.sh"])

    def test_unknown_command_returns_none(self):
        self.assertIsNone(resolve_command("frobnicate"))


class ParseTriggerArgsTest(unittest.TestCase):
    def test_no_args_defaults_to_restart(self):
        self.assertEqual(parse_trigger_args([]), "restart")

    def test_explicit_restart(self):
        self.assertEqual(parse_trigger_args(["restart"]), "restart")

    def test_explicit_rebuild(self):
        self.assertEqual(parse_trigger_args(["rebuild"]), "rebuild")

    def test_unknown_command_raises_value_error(self):
        with self.assertRaises(ValueError):
            parse_trigger_args(["frobnicate"])


if __name__ == "__main__":
    unittest.main()
