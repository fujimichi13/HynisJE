#!/usr/bin/env python3
"""Validate the deployable Mach-O ABI without loading an iOS binary on the host."""
import struct
import sys
from pathlib import Path

REQUIRED = {"_gl4metalInit", "_glMakeCurrent", "_glSwapBuffers", "_glSwapInterval",
            "_glFinish", "_glGetString", "_glGetIntegerv", "_glGetError"}


def validate(data):
    if len(data) < 32:
        raise ValueError("truncated Mach-O header")
    magic, cpu, _, kind, count, size, _, _ = struct.unpack_from("<8I", data)
    if magic != 0xFEEDFACF or cpu != 0x0100000C or kind != 6:
        raise ValueError("expected a thin arm64 Mach-O dylib for an iOS device")
    end = 32 + size
    if end > len(data):
        raise ValueError("truncated load commands")
    offset, ios, symbols = 32, False, set()
    for _ in range(count):
        if offset + 8 > end:
            raise ValueError("truncated load command")
        cmd, length = struct.unpack_from("<2I", data, offset)
        if length < 8 or offset + length > end:
            raise ValueError("invalid load command size")
        if cmd == 0x32 and length >= 24:  # LC_BUILD_VERSION
            ios = struct.unpack_from("<I", data, offset + 8)[0] == 2
        elif cmd == 0x25:  # LC_VERSION_MIN_IPHONEOS (older linkers)
            ios = True
        elif cmd == 2 and length >= 24:  # LC_SYMTAB
            start, nsyms, strings, string_size = struct.unpack_from("<4I", data, offset + 8)
            if start + nsyms * 16 > len(data) or strings + string_size > len(data):
                raise ValueError("truncated symbol table")
            table = data[strings:strings + string_size]
            for index in range(nsyms):
                name, flags, section, _, _ = struct.unpack_from("<IBBHQ", data, start + index * 16)
                # Only externally visible, defined symbols can satisfy dlsym.
                if flags & 0xE0 or flags & 0x10 or not flags & 1 or flags & 0x0E != 0x0E or not section:
                    continue
                if name >= len(table) or b"\0" not in table[name:]:
                    raise ValueError("invalid symbol name")
                symbols.add(table[name:table.index(b"\0", name)].decode("ascii", errors="replace"))
        offset += length
    if not ios:
        raise ValueError("library was not built for an iOS device")
    missing = REQUIRED - symbols
    if missing:
        raise ValueError("missing C exports: " + ", ".join(sorted(missing)))


if __name__ == "__main__":
    try:
        validate(Path(sys.argv[1]).read_bytes())
    except (OSError, ValueError, IndexError, struct.error) as error:
        sys.exit(f"Invalid gl4metal library: {error}")
    print("Validated gl4metal: arm64 iOS dylib and required C exports")
