#!/usr/bin/env python3
"""Extract reviewed DeepSeek whale-maid frames from pinned, attributed community atlases."""
import hashlib
import io
import json
from pathlib import Path
import urllib.request
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
REVISION = '7661c8b304c5400701f91da01b1a643a207331de'
BASE = 'https://raw.githubusercontent.com/YunYueSama/codex-deepseek-pet/' + REVISION + '/'
# Visually reviewed cells: blue hair, whale fins/tail and navy maid uniform.
# Expressions/actions use a 4x4 atlas; motion-extra uses 8x8.
CURATED = [
    ('expressions', 0, 'hello', '在听', 'neutral', '平静听对方说话、普通招呼'),
    ('expressions', 4, 'smile', '小得意', 'smug', '轻松得意，不用于对方认真纠错'),
    ('expressions', 6, 'drink', '喝口水', 'neutral', '聊喝水、喝饮料、短暂休息'),
    ('expressions', 7, 'delighted', '开心', 'joy', '明确的喜讯与轻松庆祝'),
    ('expressions', 8, 'thinking', '想一想', 'teasing', '双方轻松接梗、俏皮思考，不用于求助'),
    ('expressions', 9, 'surprised', '欸', 'flustered', '意外消息、惊讶，不凭空升级恐惧'),
    ('expressions', 10, 'pout', '哼', 'annoyed', '轻微不满或玩笑中的鼓嘴，不攻击纠错者'),
    ('expressions', 11, 'apologetic', '委屈', 'sad', '委屈、自己出错后收住，不幸灾乐祸'),
    ('expressions', 12, 'music', '哼歌', 'joy', '聊音乐、唱歌、轻快心情'),
    ('expressions', 14, 'sleepy', '困了', 'sleepy', '疲惫、准备休息、睡前收尾'),
    ('expressions', 15, 'goodnight', '睡着啦', 'sleepy', '晚安、准备睡觉，不用于白天问候'),
    ('actions', 1, 'cheer', '好耶', 'joy', '庆祝好消息、完成目标'),
    ('actions', 5, 'welcome', '来啦', 'joy', '欢迎对方、轻松招呼'),
    ('actions', 6, 'hands', '期待', 'flustered', '期待普通好消息、礼物或活动'),
    ('actions', 7, 'confident', '哼哼', 'smug', '轻松自信、得意，不捏造能力'),
    ('actions', 10, 'wave', '招招手', 'neutral', '打招呼、道别'),
    ('actions', 12, 'leaving', '先走啦', 'neutral', '临时离开、告别，不假装执行了真实操作'),
    ('actions', 13, 'back', '路过', 'neutral', '路过、轻松冒泡，不硬插严肃话题'),
    ('actions', 14, 'wow', '哇', 'joy', '惊喜、赞叹好消息'),
    ('actions', 15, 'jump', '开心蹦跶', 'joy', '庆祝、兴奋，不用于对方失败'),
    ('motion-extra', 1, 'sit', '歇一会儿', 'neutral', '休息、短暂放松'),
    ('motion-extra', 4, 'yay', '举手欢呼', 'joy', '开心庆祝、赞同好点子'),
    ('motion-extra', 8, 'dance', '转个圈', 'joy', '轻松愉快、跳舞相关话题'),
    ('motion-extra', 16, 'listening', '你说', 'neutral', '耐心听对方说话，不催促'),
    ('motion-extra', 20, 'calm', '缓一缓', 'neutral', '平静休息、温和收尾'),
    ('motion-extra', 26, 'turn', '回头看看', 'neutral', '临时道别或回头打招呼，不字面假称看见现场'),
    ('motion-extra', 34, 'peek', '偷偷看', 'teasing', '双方轻松接梗，不声称窥视对方设备'),
    ('motion-extra', 36, 'mischief', '小坏心思', 'teasing', '明确的轻松互损、玩笑，不用于认真求助'),
    ('motion-extra', 42, 'wink', '眨眨眼', 'flustered', '俏皮回应善意或夸奖，不编造亲密关系'),
    ('motion-extra', 44, 'content', '满足', 'joy', '开心、放松、事情顺利完成'),
    ('motion-extra', 49, 'awkward', '有点不好意思', 'flustered', '收到夸奖、轻度害羞，不影射对方心虚'),
    ('motion-extra', 54, 'kneel', '安静待着', 'sad', '轻度失落、安静陪伴，不嘲讽困境'),
    ('motion-extra', 62, 'rest', '晚安好梦', 'sleepy', '睡前道晚安、休息'),
]


def fetch(path):
    with urllib.request.urlopen(BASE + path, timeout=45) as response:
        return response.read(25_000_001)


if __name__ == '__main__':
    directory = ROOT / 'Resources' / 'QQStickers'
    atlases = {}
    for name in dict.fromkeys(row[0] for row in CURATED):
        data = fetch('assets/whale/' + name + '.png')
        if len(data) > 25_000_000:
            raise ValueError('Atlas too large')
        image = Image.open(io.BytesIO(data)).convert('RGBA')
        side = 8 if name == 'motion-extra' else 4
        expected = side * 512
        if image.size != (expected, expected):
            raise ValueError('Unexpected atlas layout')
        atlases[name] = image
    license_text = fetch('LICENSE').decode() + '\n\n' + fetch('ASSET_LICENSE.md').decode()
    catalog = json.loads((directory / 'manifest.json').read_text())
    old = [item for item in catalog if item['id'].startswith(('pysio-', 'whale-'))]
    catalog = [item for item in catalog if item not in old]
    staged = []
    for atlas, index, key, title, emotion, context in CURATED:
        columns = 8 if atlas == 'motion-extra' else 4
        x, y = (index % columns) * 512, (index // columns) * 512
        image = atlases[atlas].crop((x, y, x + 512, y + 512))
        bbox = image.getchannel('A').getbbox()
        if not bbox:
            raise ValueError('Empty frame')
        image = image.crop(bbox)
        output = io.BytesIO()
        image.save(output, format='WEBP', lossless=True, method=6)
        data = output.getvalue()
        item = dict(id='whale-' + key, title=title, emotion=emotion, file='whale-' + key + '.webp',
            sha256=hashlib.sha256(data).hexdigest(), context=context, author='YunYueSama',
            source='https://github.com/YunYueSama/codex-deepseek-pet/blob/' + REVISION + '/assets/whale/' + atlas + '.png',
            license='大肥鱼项目署名许可 1.0', publicSharing=True, character='deepseek-whale-maid',
            sourceFrame=index, modification='图集独立帧拆分、透明留白裁剪、无损 WebP 编码；未重绘角色')
        staged.append((item, data))
    for item in catalog:
        item['character'] = 'deepseek-whale-maid'
    for item, data in staged:
        (directory / item['file']).write_bytes(data)
        catalog.append(item)
    (directory / 'WHALE-LICENSE.txt').write_text(license_text)
    (directory / 'manifest.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    # Remove only the explicitly replaced bundled pack, never the user's data directory.
    new_files = {item['file'] for item in catalog}
    for item in old:
        if item['file'] not in new_files and Path(item['file']).name == item['file']:
            (directory / item['file']).unlink(missing_ok=True)
    (directory / 'PYSIO-LICENSE.txt').unlink(missing_ok=True)
    print('Reviewed DeepSeek whale-maid frames:', len(staged), 'total:', len(catalog))
