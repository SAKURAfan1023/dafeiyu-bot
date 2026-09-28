#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Create private bridge configs outside the repo; never overwrite or print tokens."""
import argparse,json,os,pathlib,secrets
p=argparse.ArgumentParser();p.add_argument('--directory',type=pathlib.Path,default=pathlib.Path.home()/'.local/qq-runtime/config');args=p.parse_args()
directory=args.directory.expanduser().resolve();repo=pathlib.Path(__file__).resolve().parents[1]
if directory==repo or repo in directory.parents: p.error('Store runtime credentials outside the repository.')
names=['onebot11.json','webui.json','napcat.json']
if any((directory/n).exists() for n in names):p.error('Configuration exists; refusing to overwrite.')
directory.mkdir(parents=True,exist_ok=True);os.chmod(directory,0o700)
configs={
'onebot11.json':{'network':{'websocketServers':[{'name':'dafeiyu-local','enable':True,'host':'0.0.0.0','port':3001,'messagePostFormat':'array','reportSelfMessage':True,'token':secrets.token_urlsafe(32),'enableForcePushEvent':True,'debug':False,'heartInterval':30000}]}},
'webui.json':{'host':'0.0.0.0','port':6099,'token':secrets.token_urlsafe(32),'autoLoginAccount':'','disableWebUI':False},
'napcat.json':{'fileLog':False,'consoleLog':False,'packetBackend':'auto'}}
for name,data in configs.items():
    fd=os.open(directory/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'w') as f:json.dump(data,f,ensure_ascii=False,indent=2)
print('Created three private config files. Read the tokens locally in your editor; do not paste them into issues or source control.')
