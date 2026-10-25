'use strict';
// Parse descriptive image data only. Pack content cannot supply actions, paths or runtime settings.
async function readStickerPack(file){
  if(!file||file.size<1||file.size>24000000)throw new Error('资源包最多 24 MB。');
  const pack=JSON.parse(await file.text());
  if(pack?.format!=='dafeiyu-stickers'||pack.version!==1||!Array.isArray(pack.items)||pack.items.length<1||pack.items.length>50)throw new Error('请选择有效的表情资源包，每包 1–50 张。');
  const hashes=new Set(),result=[];
  for(const item of pack.items){
    if(!item||!['neutral','joy','smug','annoyed','sad','sleepy','flustered','teasing'].includes(item.emotion))throw new Error('资源包情绪无效。');
    for(const [key,max] of Object.entries({title:80,context:300,source:500,author:80,license:100}))if(typeof item[key]!=='string'||item[key].length>max)throw new Error('资源包元数据无效。');
    if(!item.title.trim())throw new Error('资源包缺少图片名称。');
    if(item.source){const url=new URL(item.source);if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash)throw new Error('资源包来源必须是不含凭证的公开 HTTPS 地址。');}
    if(typeof item.imageBase64!=='string'||item.imageBase64.length>4000000||item.imageBase64.length%4!==0||!/^[A-Za-z0-9+/]*={0,2}$/.test(item.imageBase64))throw new Error('资源包图片编码无效。');
    const binary=atob(item.imageBase64);if(binary.length<1||binary.length>3000000)throw new Error('单张图片最多 3 MB。');
    const bytes=Uint8Array.from(binary,character=>character.charCodeAt(0));
    const digest=[...new Uint8Array(await crypto.subtle.digest('SHA-256',bytes))].map(value=>value.toString(16).padStart(2,'0')).join('');
    if(digest!==item.sha256||hashes.has(digest))throw new Error('资源包图片重复或校验不符，未开始导入。');
    hashes.add(digest);
    const sticker={publicSharing:false};for(const key of ['title','emotion','context','source','author','license'])sticker[key]=item[key];
    result.push({sticker,stickerImage:item.imageBase64});
  }
  return result;
}
