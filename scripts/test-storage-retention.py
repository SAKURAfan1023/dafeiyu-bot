#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import json

spec = importlib.util.spec_from_file_location('retention', Path(__file__).with_name('qq-storage-maintenance.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
now = 2_000_000_000
date = now - module.SWIFT_EPOCH
state = {'config': {'artwork': {'repeatDays': 30}}, 'memoryBooks': {'fixture': {'items': ['keep']}},
         'usage': {'calls': 20}, 'artworkLedger': {'deliveries': [{'at': date - 8 * 86400}, {'at': date - 6 * 86400}],
                                                'schedules': {'old': date - 8 * 86400, 'new': date - 6 * 86400}, 'continuation': {'fixture': {'mode': 'hot'}}},
         'logs': [{'date': date - 8 * 86400}, {'date': date}]}
result = module.prune_state(state, now)
assert len(result['artworkLedger']['deliveries']) == 1
assert set(result['artworkLedger']['schedules']) == {'new'}
assert result['config']['artwork']['repeatDays'] == 7
assert result['memoryBooks'] == {'fixture': {'items': ['keep']}}
assert result['usage']['calls'] == 20
assert result['artworkLedger']['continuation']['fixture']['mode'] == 'hot'
with tempfile.TemporaryDirectory() as temp:
    file = Path(temp) / 'checks.jsonl'
    file.write_text('\n'.join(json.dumps({'timestamp': t}) for t in [now - 8 * 86400, now - 2, now - 1]))
    assert module.rotate_records(file, now, limit=1) == [{'timestamp': now - 1}]
    module.write_json(Path(temp) / 'state.json', result)
    assert (Path(temp) / 'state.json').stat().st_mode & 0o777 == 0o600
print('Host retention: week boundary, existing state, memories, counters and permissions passed')
