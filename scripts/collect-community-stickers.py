#!/usr/bin/env python3
"""Refresh the explicitly curated, pinned Pysio Chibi subset. No crawling or model calls."""
import concurrent.futures
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
REVISION = 'b76af11018348fcab3a4861e41995f17a8eabd1e'
BASE = 'https://raw.githubusercontent.com/pysio2007/emoji/' + REVISION + '/'
# Context describes the actual pose rather than inventing a reaction from its filename.
CURATED = [
    ('hi', '打招呼', 'neutral', '普通问候、刚上线'),
    ('hey', '嘿', 'neutral', '轻松招呼、引起注意'),
    ('ok', '收到', 'neutral', '确认已收到、同意普通安排'),
    ('noted', '记下了', 'neutral', '记录普通偏好、确认信息'),
    ('question', '疑惑', 'neutral', '不明白、需要澄清，不用于嘲讽纠错者'),
    ('dots', '沉默', 'neutral', '无奈或短暂语塞，不用于认真求助'),
    ('drawing', '画画中', 'neutral', '绘画创作相关话题'),
    ('eating_melon', '吃瓜', 'neutral', '轻松围观话题，不用于隐私事件或求助'),
    ('mmm', '思考一下', 'neutral', '犹豫、思考、暂时拿不准'),
    ('laugh', '开心大笑', 'joy', '明确的轻松笑话、开心，不嘲笑困境'),
    ('giggle', '偷笑', 'joy', '双方都在接梗的轻松玩笑'),
    ('good_job', '做得好', 'joy', '认可成绩、称赞完成的事情'),
    ('good_idea', '有主意了', 'joy', '想到办法、赞同好点子'),
    ('cheer_up', '加油', 'joy', '鼓励对方继续努力，不替代危机求助回应'),
    ('w_fireworks', '庆祝', 'joy', '庆祝喜讯、完成目标'),
    ('wow', '哇', 'joy', '惊喜、赞叹好消息'),
    ('singing', '哼歌', 'joy', '唱歌、听歌、轻松心情'),
    ('love', '喜欢', 'flustered', '感谢夸奖、表达善意，不编造亲密关系'),
    ('love_ww', '开心比心', 'flustered', '友好回应夸奖、轻松感谢'),
    ('thanks', '谢谢', 'joy', '感谢帮助、礼物或夸奖'),
    ('cool', '酷', 'smug', '轻松得意、认可帅气的事情'),
    ('hmph', '哼', 'teasing', '双方明确轻松斗嘴，不用于认错和求助'),
    ('coo', '咕', 'neutral', '轻松闲聊、短暂冒泡'),
    ('sweat', '汗', 'flustered', '尴尬、自嘲，不影射对方心虚'),
    ('sorry', '对不起', 'sad', '自己犯错后道歉，不甩锅'),
    ('crying', '哭哭', 'sad', '委屈、轻度难过，不用于幸灾乐祸'),
    ('qwq', '委屈', 'sad', '轻度委屈、温和撒娇，不夸大成危机'),
    ('sigh', '叹气', 'sad', '疲惫、无奈，不嘲讽对方遭遇'),
    ('sleeping', '睡觉了', 'sleepy', '晚安、准备睡觉'),
    ('sleep_love', '晚安好梦', 'sleepy', '温柔道晚安、睡前收尾'),
    ('slacking', '歇会儿', 'sleepy', '休息、摸鱼、放松'),
    ('hungry', '饿了', 'neutral', '明确聊到饿、吃饭，不替代其他话题'),
    ('chips_cola', '零食时间', 'joy', '聊零食、可乐、轻松休息'),
]


def collect(entry):
    key, title, emotion, context = entry
    filename = 'pysio_chibi_' + key + '.webp'
    request = urllib.request.Request(BASE + 'Chibi/' + filename, headers={'User-Agent': 'dafeiyu-curated-stickers'})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(3_000_001)
    if not data or len(data) > 3_000_000:
        raise ValueError('Invalid image size: ' + filename)
    return data, dict(id='pysio-' + key, title=title, emotion=emotion, file=filename,
        sha256=hashlib.sha256(data).hexdigest(), context=context, author='Pysio',
        source='https://github.com/pysio2007/emoji/blob/' + REVISION + '/Chibi/' + filename,
        license='CC-BY-NC-SA-4.0', publicSharing=True)


if __name__ == '__main__':
    directory = ROOT / 'Resources' / 'QQStickers'
    # Finish every download before changing the installed catalog.
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        downloads = list(pool.map(collect, CURATED))
    license_text = urllib.request.urlopen(BASE + 'LICENSE', timeout=30).read()
    catalog = json.loads((directory / 'manifest.json').read_text())
    catalog = [item for item in catalog if not item['id'].startswith('pysio-')]
    for item in catalog:
        if item['id'] in ('neutral', 'joy', 'sleepy', 'teasing'):
            item.update(author='大肥鱼项目', license='CC0-1.0', publicSharing=True)
    for data, item in downloads:
        (directory / item['file']).write_bytes(data)
        catalog.append(item)
    (directory / 'PYSIO-LICENSE.txt').write_bytes(license_text)
    (directory / 'manifest.json').write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + '\n')
    print('Curated community stickers:', len(downloads), 'total:', len(catalog))
