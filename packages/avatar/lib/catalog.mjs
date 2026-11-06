import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export const packageRoot = fileURLToPath(new URL('../', import.meta.url));
export const definitions = [
  ['sailor', '蓝白水手服'], ['hoodie', '鲸鱼帽衫'], ['researcher', '深海小研究员'],
  ['ocean-dress', '海洋轻礼装'], ['classic-maid', '经典鲸鱼女仆'],
];

export async function loadCatalog(root = path.join(packageRoot, 'models')) {
  const catalog = [];
  for (const [id, label] of definitions) {
    const model = JSON.parse(await readFile(path.join(root, id, 'model.json'), 'utf8'));
    const rig = JSON.parse(await readFile(path.join(root, id, 'stage.json'), 'utf8'));
    if (model.format !== 'livliv-model' || model.version !== 4 || rig.model_id !== id) throw Error('Invalid model package: ' + id);
    const files = new Set(['model.json', 'stage.json', 'cover.png']);
    for (const layer of model.layers) for (const file of [layer.texture, ...(layer.frames ?? []), layer.mask, layer.talk, layer.brow_tex].filter(Boolean)) {
      if (!/^textures\/[A-Za-z0-9_-]+\.png$/.test(file)) throw Error('Invalid image path');
      await readFile(path.join(root, id, file));
      files.add(file);
    }
    catalog.push({ id, label, model, rig, files });
  }
  return catalog;
}
