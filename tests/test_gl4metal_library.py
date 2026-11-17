import importlib.util
from pathlib import Path
import struct
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("validator", Path(__file__).parents[1] / "scripts/validate_gl4metal.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)


def dylib(names=None, cpu=0x0100000C, platform=2, flags=0x0F):
    names = sorted(validator.REQUIRED if names is None else names)
    strings = b"\0"
    records = b""
    for name in names:
        records += struct.pack("<IBBHQ", len(strings), flags, 1, 0, 0x1000)
        strings += name.encode() + b"\0"
    build_version = struct.pack("<6I", 0x32, 24, platform, 0xE0000, 0x110000, 0)
    symbol_table = struct.pack("<6I", 2, 24, 80, len(names), 80 + len(records), len(strings))
    header = struct.pack("<8I", 0xFEEDFACF, cpu, 0, 6, 2, 48, 0, 0)
    return header + build_version + symbol_table + records + strings


class LibraryValidation(unittest.TestCase):
    def test_valid_device_library(self):
        validator.validate(dylib())

    def test_reject_wrong_platform_and_architecture(self):
        for data in [dylib(platform=7), dylib(platform=1), dylib(cpu=0x01000007)]:
            with self.assertRaises(ValueError):
                validator.validate(data)

    def test_required_export_cannot_be_missing_mangled_or_undefined(self):
        names = validator.REQUIRED - {"_gl4metalInit"}
        for data in [dylib(names), dylib(names | {"__Z12gl4metalInitv"}), dylib(flags=1), dylib(flags=0x1F)]:
            with self.assertRaisesRegex(ValueError, "missing C exports"):
                validator.validate(data)

    def test_truncated_or_corrupt_binary(self):
        binary = dylib()
        for length in [0, 31, 40, 79, len(binary) - 1]:
            with self.assertRaises(ValueError):
                validator.validate(binary[:length])
        corrupt = bytearray(binary)
        struct.pack_into("<I", corrupt, 36, 0)
        with self.assertRaisesRegex(ValueError, "load command size"):
            validator.validate(corrupt)

    @unittest.skipUnless(os.name != "nt" and shutil.which("bash"), "requires a POSIX shell")
    def test_prebuilt_staging_and_failure_preserves_existing_library(self):
        script = Path(__file__).parents[1] / "scripts/build_gl4metal.sh"
        with tempfile.TemporaryDirectory(prefix="gl4metal staging ") as temporary:
            root = Path(temporary)
            library = root / "prebuilt library.dylib"
            library.write_bytes(dylib())
            output = root / "output folder"
            args = ["bash", str(script), "unused source", str(output), "unused sdk", "Debug", "1", str(library)]
            env = dict(os.environ, PYTHON=sys.executable)
            subprocess.run(args, env=env, check=True, capture_output=True)
            staged = output / "libgl4metal.dylib"
            self.assertEqual(staged.read_bytes(), dylib())
            # An already-staged library should not cause cp's same-file error.
            subprocess.run(args[:-1] + [str(staged)], env=env, check=True, capture_output=True)
            library.write_bytes(dylib(platform=7))
            result = subprocess.run(args, env=env, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(staged.read_bytes(), dylib())


if __name__ == "__main__":
    unittest.main()
