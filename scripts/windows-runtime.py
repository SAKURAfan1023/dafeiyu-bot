#!/usr/bin/env python3
"""Copy the transitive PE import closure from build/toolchain paths; fail on missing DLLs."""
import os, pathlib, shutil, struct


def imports(file):
    data = file.read_bytes()
    def u16(offset): return struct.unpack_from('<H', data, offset)[0]
    def u32(offset): return struct.unpack_from('<I', data, offset)[0]
    if data[:2] != b'MZ': raise ValueError('Expected a PE executable')
    pe = u32(0x3c)
    if data[pe:pe+4] != b'PE\0\0': raise ValueError('Invalid PE header')
    count, optional_size = u16(pe+6), u16(pe+20)
    optional = pe+24
    if u16(optional) != 0x20b: raise ValueError('Only Windows x64 PE32+ is supported')
    sections = optional+optional_size
    def offset(rva):
        for index in range(count):
            section = sections+40*index
            size, address, raw_size, raw = struct.unpack_from('<IIII', data, section+8)
            if address <= rva < address+max(size,raw_size): return raw+rva-address
        raise ValueError('Invalid PE RVA')
    def name(rva):
        start=offset(rva); end=data.index(b'\0',start)
        value=data[start:end].decode('ascii')
        if pathlib.PureWindowsPath(value).name != value: raise ValueError('Invalid DLL import')
        return value
    # Both regular and delay-load import tables matter for a usable runtime.
    for directory, stride, name_index in [(1,20,12),(13,32,4)]:
        rva=u32(optional+112+directory*8)
        if not rva: continue
        cursor=offset(rva)
        while any(data[cursor:cursor+stride]):
            if directory == 13 and not u32(cursor)&1: raise ValueError('Unsupported delay import addressing')
            yield name(u32(cursor+name_index))
            cursor+=stride


def collect(destination, binary_dir):
    system = pathlib.Path(os.environ['SystemRoot'])/'System32'
    candidates = [pathlib.Path(binary_dir), pathlib.Path(shutil.which('swift')).parent]
    candidates += [pathlib.Path(item) for item in os.environ.get('PATH','').split(os.pathsep) if item]
    # Swift's SDK runtime path is normally already on PATH; accept the explicit SDK as well.
    if os.environ.get('SDKROOT'):
        sdk = pathlib.Path(os.environ['SDKROOT'])
        candidates += [sdk/'usr/bin',sdk/'usr/bin/x86_64']
    pending = list(destination.glob('*.exe')) + list(destination.glob('*.dll'))
    visited = set()
    while pending:
        file=pending.pop()
        if file.name.lower() in visited: continue
        visited.add(file.name.lower())
        for name in imports(file):
            if name.lower().startswith(('api-ms-win-','ext-ms-win-')): continue
            # OS libraries and the separately declared Visual C++ runtime are prerequisites, not copied from System32.
            if (system/name).is_file(): continue
            target=destination/name
            if not target.is_file():
                source=next((folder/name for folder in candidates if (folder/name).is_file()),None)
                if source is None: raise RuntimeError('Missing runtime dependency: '+name)
                shutil.copy2(source,target)
            pending.append(target)
    return sorted(visited)
