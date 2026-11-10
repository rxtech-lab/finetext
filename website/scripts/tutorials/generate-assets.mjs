// Render the two labeled UI illustrations. The other assets are native app captures.
// Run from website: node scripts/tutorials/generate-assets.mjs
import sharp from 'sharp';
const font = '-apple-system, BlinkMacSystemFont, Helvetica, Arial, sans-serif';
const text = (x,y,value,size=24,color='#f0f0f0',weight=400) => `<text x="${x}" y="${y}" font-family="${font}" font-size="${size}" fill="${color}" font-weight="${weight}">${value}</text>`;
const rect = (x,y,w,h,color,r=16) => `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" fill="${color}"/>`;
const shell = (title, body) => `<svg xmlns="http://www.w3.org/2000/svg" width="1160" height="1040" viewBox="0 0 1160 1040">${rect(0,0,1160,1040,'#222322',24)}${rect(0,0,1160,90,'#2c2d2c',24)}<circle cx="32" cy="43" r="10" fill="#ee6b61"/><circle cx="64" cy="43" r="10" fill="#efbf50"/><circle cx="96" cy="43" r="10" fill="#63c454"/>${text(580,53,title,26,'#eee',600).replace('<text ', '<text text-anchor="middle" ')}${body}</svg>`;
const flowcy = shell('FineText · Flowcy',
  text(55,145,'Settings  ›  General  ›  Flowcy',21,'#b6b9b6')+
  text(55,215,'Connect your Flowcy account',34,'#fff',600)+
  text(55,258,'Use your rxlab account for rewriting and translation.',23,'#b6b9b6')+
  rect(55,305,1050,245,'#303230')+
  text(85,353,'FLOWCY',18,'#aebbae',600)+
  text(85,408,'Sign in with Flowcy',28,'#fff',600)+
  text(85,451,'Complete the native sign-in sheet with your rxlab account.',22,'#c3c6c3')+
  rect(85,479,270,48,'#087cdd',10)+text(111,511,'Sign in with Flowcy',22,'#fff',500)+
  text(55,612,'After signing in',26,'#fff',600)+
  rect(55,642,1050,155,'#303230')+
  text(85,692,'Manage Flowcy Account',25,'#fff',500)+
  text(85,737,'Review the available models, then choose Refresh Models.',22,'#c3c6c3')+
  text(55,859,'Rewrite  ›  Add Platform  ›  your platform',23,'#b6b9b6')+
  rect(55,889,1050,80,'#193c52')+text(85,939,'Flowcy  ›  choose an available text model',26,'#d8edff',500)+
  text(55,1010,'INTERFACE WALKTHROUGH · ILLUSTRATION',16,'#aab5ab',500));
const rewrite = shell('FineText · Rewrite',
  text(55,145,'ORIGINAL POST',18,'#b6b9b6',600)+rect(55,172,1050,172,'#303230')+
  text(82,217,'we’ve been working on something new. excited to finally',26)+
  text(82,260,'share it with everyone next week!',26)+
  rect(55,379,1050,61,'#303230',12)+rect(60,384,344,51,'#5a5d5a',9)+
  text(182,418,'Rewrite',23,'#fff',500)+text(533,418,'Translate',23,'#babeba')+text(894,418,'Image',23,'#babeba')+
  text(55,493,'Add Platform  +',25,'#69b9ff',500)+
  rect(55,527,1050,368,'#303230')+text(84,579,'LinkedIn · Friendly',27,'#fff',600)+
  text(84,619,'Choose your model · Same as original',21,'#b6b9b6')+
  text(84,680,'Something new is taking shape. We can’t wait to share',26)+
  text(84,725,'what we’ve been building with you next week.',26)+
  rect(84,805,192,51,'#4c4f4c',10)+text(110,839,'Regenerate',22,'#fff',500)+
  rect(298,805,120,51,'#4c4f4c',10)+text(329,839,'Copy',22,'#fff',500)+
  rect(440,805,120,51,'#4c4f4c',10)+text(470,839,'Open',22,'#fff',500)+
  rect(820,926,285,56,'#087cdd',10)+text(862,963,'Rewrite All',25,'#fff',500)+
  text(55,1010,'EXAMPLE WORKFLOW · ILLUSTRATION',16,'#aab5ab',500));
for (const [name, svg] of [['flowcy',flowcy], ['refine-text',rewrite]]) {
  await sharp(Buffer.from(svg)).webp({quality:90}).toFile(`public/tutorials/${name}.webp`);
}
