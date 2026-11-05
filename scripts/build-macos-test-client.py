#!/usr/bin/env python3
"""Add a distinct native window to the isolated Mac MCP test bundle."""
import argparse, pathlib, plistlib, subprocess
root=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('plugin')
parser.add_argument('--arch',choices=['arm64','x64'],required=True)
args=parser.parse_args()
plugin=pathlib.Path(args.plugin).resolve()
if not plugin.is_relative_to(root/'dist') or not (plugin/'mcp.json').is_file(): parser.error('Expected a generated test plugin inside dist/')
app=plugin/'DaFeiYu MCP Test.app'
macos=app/'Contents/MacOS';macos.mkdir(parents=True,exist_ok=True)
identifier='org.dafeiyu.macos-mcp-test'
info={'CFBundleName':'大肥鱼 MCP 测试','CFBundleDisplayName':'大肥鱼 MCP 测试','CFBundleIdentifier':identifier,
      'CFBundleExecutable':'DaFeiYuMacMCPTest','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.3.0',
      'CFBundleVersion':'1','LSMinimumSystemVersion':'14.0','NSHighResolutionCapable':True,
      'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}
(app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
arch='arm64' if args.arch=='arm64' else 'x86_64'
subprocess.run(['swiftc','-parse-as-library','-O','-target',arch+'-apple-macos14.0',
               str(root/'Sources/MacQQTestClient/main.swift'),str(root/'Sources/WeChatAIBot/QQSharedPanel.swift'),
               '-o',str(macos/'DaFeiYuMacMCPTest')],check=True)
subprocess.run(['codesign','--force','--sign','-','--identifier',identifier,str(app)],check=True)
subprocess.run(['codesign','--verify','--strict',str(app)],check=True)
print(app)
