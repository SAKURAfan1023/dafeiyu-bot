#!/usr/bin/env python3
"""Build the canonical QQ sources as an isolated product; never include social or WeChat execution code."""
import argparse, importlib.util, json, os, pathlib, platform, re, shutil, subprocess, sys

root = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--configuration', choices=['debug', 'release'], default='release')
parser.add_argument('--prepare-only', action='store_true')
parser.add_argument('--test-node-transport', action='store_true', help='Exercise the Windows Node transport on the local host')
parser.add_argument('--output', default='dist/qq', help='Generated output directory inside dist/')
args = parser.parse_args()
destination = (root / args.output).resolve()
if not destination.is_relative_to(root / 'dist') or destination == root / 'dist':
    parser.error('--output must name a generated subdirectory inside dist/')
package = root / '.build' / 'qq-package'
sources = json.loads((root / 'qq-sources.json').read_text())
target = package / 'Sources' / 'QQWorker'
if target.exists():
    shutil.rmtree(target)
target.mkdir(parents=True)
core = package / 'Sources' / 'BotCore'
if core.exists():
    shutil.rmtree(core)
shutil.copytree(root / 'Sources' / 'BotCore', core)
for name in sources:
    if pathlib.PurePath(name).name != name or not name.endswith('.swift'):
        raise SystemExit('Invalid QQ source manifest')
    shutil.copy2(root / 'Sources' / 'WeChatAIBot' / name, target / name)
(package / 'Package.swift').write_text('''// swift-tools-version: 5.9
import PackageDescription
#if os(Linux)
let dependencies: [Package.Dependency] = [
 .package(url: "https://github.com/apple/swift-crypto.git", exact: "3.12.3"),
 .package(url: "https://github.com/vapor/websocket-kit.git", exact: "2.16.2"),
 .package(url: "https://github.com/apple/swift-nio.git", exact: "2.81.0")]
let platform: [Target.Dependency] = [.product(name:"Crypto",package:"swift-crypto"), .product(name:"WebSocketKit",package:"websocket-kit"), .product(name:"NIOCore",package:"swift-nio"), .product(name:"NIOPosix",package:"swift-nio")]
let crypto: [Target.Dependency] = [.product(name:"Crypto",package:"swift-crypto")]
#elseif os(Windows)
let dependencies: [Package.Dependency] = [.package(url:"https://github.com/apple/swift-crypto.git",exact:"3.12.3")]
let crypto: [Target.Dependency] = [.product(name:"Crypto",package:"swift-crypto")]
let platform = crypto
#else
let dependencies: [Package.Dependency] = []
let crypto: [Target.Dependency] = []
let platform: [Target.Dependency] = []
#endif
let package = Package(name:"DaFeiYuQQ",platforms:[.macOS(.v14)],products:[.executable(name:"dafeiyu-qq",targets:["QQWorker"])],dependencies:dependencies,targets:[
 .target(name:"BotCore",dependencies:crypto),
 .executableTarget(name:"QQWorker",dependencies:[.target(name:"BotCore")]+platform,swiftSettings:[.define("DAFEIYU_QQ_ONLY")])])
''', encoding='utf-8')
if args.prepare_only:
    print(package)
    raise SystemExit(0)
flags = ['-Xswiftc', '-DDAFEIYU_NODE_TRANSPORT'] if args.test_node_transport else []
subprocess.run(['swift', 'build', '--package-path', str(package), '-c', args.configuration, '--jobs', os.environ.get('DAFEIYU_BUILD_JOBS', '2')] + flags, check=True)
binary_dir = subprocess.check_output(['swift', 'build', '--package-path', str(package), '-c', args.configuration, '--show-bin-path'], text=True).strip()
if destination.exists():
    shutil.rmtree(destination)
destination.mkdir(parents=True)
resources = destination / 'Resources'
if resources.exists():
    shutil.rmtree(resources)
resources.mkdir()
for name in ['QQControl', 'QQStickers', 'Linux', 'QQTransport']:
    shutil.copytree(root / 'Resources' / name, resources / name, ignore=shutil.ignore_patterns('node_modules', '__pycache__'))
# QQ-only clients must not offer controls whose execution modules are absent.
index = resources/'QQControl/index.html'
html = index.read_text(encoding='utf-8')
html, removed = re.subn(r'<details\b[^>]*data-module="(?:social|wechat)"[^>]*>.*?</details>', '', html, flags=re.S)
if removed != 2:
    raise SystemExit('QQ navigation module boundaries changed; review the QQ-only resource profile')
index.write_text(html, encoding='utf-8')
binary = 'dafeiyu-qq.exe' if sys.platform == 'win32' else 'dafeiyu-qq'
shutil.copy2(pathlib.Path(binary_dir) / binary, destination / binary)
# Include linked build products, then resolve Windows Swift DLLs from the actual PE imports.
for dependency in pathlib.Path(binary_dir).glob('*.dll'):
    shutil.copy2(dependency, destination / dependency.name)
if sys.platform == 'win32':
    spec = importlib.util.spec_from_file_location('windows_runtime', root/'scripts/windows-runtime.py')
    helper = importlib.util.module_from_spec(spec); spec.loader.exec_module(helper)
    helper.collect(destination, binary_dir)
licenses = destination/'licenses'
licenses.mkdir()
shutil.copy2(root/'docs/licenses/Swift-LICENSE.txt', licenses/'Swift-LICENSE.txt')
for checkout in (package/'.build/checkouts').glob('*'):
    for pattern in ['LICENSE*', 'NOTICE*', 'Sources/CCryptoBoringSSL/LICENSE*']:
        for notice in checkout.glob(pattern):
            if notice.is_file():
                shutil.copy2(notice, licenses/(checkout.name+'-'+notice.name))
(destination / 'module.json').write_text(json.dumps({'id':'qq','version':'0.3.0-preview.2','protocol':1,
    'binary':binary,'resources':'Resources','sourceFiles':sources, 'platform':sys.platform,
    'architecture':{'x86_64':'x64','amd64':'x64','aarch64':'arm64'}.get(platform.machine().lower(), platform.machine().lower()),
    'configuration':args.configuration}, indent=2), encoding='utf-8')
print(destination)
