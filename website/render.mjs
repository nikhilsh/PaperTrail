import { existsSync } from "node:fs";
import http from "node:http"; import { readFile } from "node:fs/promises";
import path from "node:path"; import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.join(__dirname, "out");
const exe = "/root/.cache/ms-playwright/chromium-1217/chrome-linux64/chrome";
const MIME={".html":"text/html",".css":"text/css",".js":"text/javascript",".json":"application/json",".png":"image/png",".plist":"text/xml"};
const server=http.createServer(async(req,res)=>{try{const rel=decodeURIComponent(req.url.split("?")[0]);const fp=path.join(root, rel==="/"?"index.html":rel);const b=await readFile(fp);res.writeHead(200,{"Content-Type":MIME[path.extname(fp)]||"application/octet-stream"});res.end(b);}catch{res.writeHead(404);res.end();}});
await new Promise(r=>server.listen(0,"127.0.0.1",r));
const port=server.address().port;
const b=await puppeteer.launch({executablePath:exe,headless:true,args:["--no-sandbox","--hide-scrollbars"]});
// desktop full page
let p=await b.newPage(); await p.setViewport({width:1200,height:900,deviceScaleFactor:2});
await p.goto(`http://127.0.0.1:${port}/`,{waitUntil:"networkidle0"}); await new Promise(r=>setTimeout(r,600));
await p.screenshot({path:"/tmp/ptsite/render-desktop.png",fullPage:true}); await p.close();
// mobile full page
p=await b.newPage(); await p.setViewport({width:420,height:900,deviceScaleFactor:2});
await p.goto(`http://127.0.0.1:${port}/`,{waitUntil:"networkidle0"}); await new Promise(r=>setTimeout(r,600));
await p.screenshot({path:"/tmp/ptsite/render-mobile.png",fullPage:true}); await p.close();
await b.close(); server.close(); console.log("rendered");
