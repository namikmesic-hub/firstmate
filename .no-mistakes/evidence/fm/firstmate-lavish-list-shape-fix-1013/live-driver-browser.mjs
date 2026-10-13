import {callTool} from '/opt/homebrew/lib/node_modules/chrome-devtools-axi/dist/src/client.js';
import fs from 'node:fs';
const args=JSON.parse(fs.readFileSync(0,'utf8'));
console.log(await callTool(args.name,{pageId:2,...args.args}));
