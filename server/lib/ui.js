"use strict";
// ブラウザから使う画面。iPhone のアプリが署名切れで動かない日でも、
// Safari でここを開けば送れる——という保険なので、ここも手を抜かない。
// 🔴 外部の CSS/JS/フォントは読まない（LAN 内にネットが無くても開けること）。
// 🔴 この中の <script> では ` と ${ を使わない（外側のテンプレート文字列と喧嘩するため）。

function esc(s) {
  return String(s).replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

function page(cfg) {
  const name = esc(cfg.displayName || "この PC");
  const token = esc(cfg.token || "");
  return `<!doctype html>
<html lang="ja">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="apple-mobile-web-app-capable" content="yes">
<meta name="apple-mobile-web-app-title" content="YasDrop">
<meta name="theme-color" content="#0b0d12">
<title>${name} へ送る — YasDrop</title>
<style>
  :root{
    --bg:#f4f5f8; --card:#fff; --text:#12151c; --sub:#5d6472; --line:#dfe2ea;
    --accent:#2f6df6; --accent-ink:#fff; --ok:#1f9d55; --warn:#c2410c;
  }
  @media (prefers-color-scheme:dark){
    :root{ --bg:#0b0d12; --card:#161a22; --text:#e8eaf0; --sub:#98a0b0; --line:#272d3a;
           --accent:#4d84ff; --accent-ink:#fff; --ok:#3ecf8e; --warn:#fb923c; }
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--bg);color:var(--text);
       font-family:-apple-system,BlinkMacSystemFont,"Hiragino Kaku Gothic ProN","Yu Gothic UI","Meiryo",sans-serif;
       padding:env(safe-area-inset-top) 0 env(safe-area-inset-bottom);}
  .wrap{max-width:640px;margin:0 auto;padding:20px 16px 48px}
  header{display:flex;align-items:baseline;gap:10px;margin:8px 0 20px}
  h1{font-size:19px;margin:0;letter-spacing:.02em}
  .to{color:var(--sub);font-size:13px}
  .card{background:var(--card);border:1px solid var(--line);border-radius:16px;padding:16px;margin-bottom:16px}
  .btns{display:grid;gap:10px;grid-template-columns:1fr 1fr}
  @media (max-width:420px){.btns{grid-template-columns:1fr}}
  button{font:inherit;font-weight:600;border:0;border-radius:12px;padding:16px 14px;cursor:pointer;
         background:var(--accent);color:var(--accent-ink);-webkit-tap-highlight-color:transparent}
  button.sub{background:transparent;color:var(--text);border:1px solid var(--line);font-weight:500}
  button:active{opacity:.75}
  input[type=file]{display:none}
  #drop{border:2px dashed var(--line);border-radius:14px;padding:22px 12px;text-align:center;color:var(--sub);
        font-size:13px;margin-top:12px}
  #drop.on{border-color:var(--accent);color:var(--accent)}
  h2{font-size:13px;color:var(--sub);margin:0 0 10px;font-weight:600;letter-spacing:.04em}
  .row{display:flex;align-items:center;gap:10px;padding:9px 0;border-top:1px solid var(--line);font-size:14px}
  .row:first-of-type{border-top:0}
  .nm{flex:1;min-width:0;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
  .sz{color:var(--sub);font-size:12px;font-variant-numeric:tabular-nums;flex:none}
  .bar{height:4px;background:var(--line);border-radius:2px;overflow:hidden;margin-top:6px}
  .bar>i{display:block;height:100%;width:0;background:var(--accent);transition:width .15s}
  .done .nm{color:var(--ok)} .fail .nm{color:var(--warn)}
  a.dl{color:var(--accent);text-decoration:none;font-size:13px;flex:none}
  .empty{color:var(--sub);font-size:13px;padding:6px 0}
  .hint{color:var(--sub);font-size:12px;line-height:1.7;margin-top:18px}
</style>
</head>
<body>
<div class="wrap">
  <header><h1>YasDrop</h1><span class="to">${name} へ送る</span></header>

  <div class="card">
    <div class="btns">
      <button id="bPhoto">写真・動画を選ぶ</button>
      <button class="sub" id="bFile">ファイルを選ぶ</button>
    </div>
    <input type="file" id="fPhoto" multiple accept="image/*,video/*">
    <input type="file" id="fFile" multiple>
    <div id="drop">ここにドラッグしても送れます</div>
  </div>

  <div class="card" id="qCard" hidden><h2>送っているもの</h2><div id="q"></div></div>

  <div class="card">
    <h2>この PC から受け取る</h2>
    <div id="list"><div class="empty">読み込み中…</div></div>
  </div>

  <p class="hint">
    共有ボタン →「ホーム画面に追加」しておくと、次からアプリのように開けます。<br>
    送ったものは PC の受信箱に入ります。ここに出ているのは PC の送信箱の中身です。
  </p>
</div>
<script>
var TOKEN = "${token}";
function q(u){ return TOKEN ? u + (u.indexOf("?")<0?"?":"&") + "t=" + encodeURIComponent(TOKEN) : u; }
function human(n){
  if(!isFinite(n)||n<0) return "-";
  var u=["B","KB","MB","GB","TB"], i=0;
  while(n>=1024&&i<u.length-1){n/=1024;i++;}
  return (i===0? n : n.toFixed(n<10?1:0))+" "+u[i];
}
var queue=[], busy=false;

function addFiles(files){
  if(!files||!files.length) return;
  document.getElementById("qCard").hidden=false;
  for(var i=0;i<files.length;i++){
    var f=files[i];
    var row=document.createElement("div");
    row.className="row";
    row.innerHTML='<div style="flex:1;min-width:0"><div class="nm"></div><div class="bar"><i></i></div></div><div class="sz"></div>';
    row.querySelector(".nm").textContent=f.name;
    row.querySelector(".sz").textContent=human(f.size);
    document.getElementById("q").prepend(row);
    queue.push({file:f,row:row});
  }
  pump();
}

function pump(){
  if(busy) return;
  var job=queue.shift();
  if(!job){ refresh(); return; }
  busy=true;
  var f=job.file, row=job.row, bar=row.querySelector(".bar>i"), sz=row.querySelector(".sz");
  var xhr=new XMLHttpRequest();
  xhr.open("PUT", q("/put/"+encodeURIComponent(f.name)));
  if(f.lastModified) xhr.setRequestHeader("X-YasDrop-Modified", String(f.lastModified));
  xhr.upload.onprogress=function(e){
    if(!e.lengthComputable) return;
    var p=e.loaded/e.total;
    bar.style.width=(p*100).toFixed(1)+"%";
    sz.textContent=human(e.loaded)+" / "+human(e.total);
  };
  xhr.onload=function(){
    busy=false;
    if(xhr.status>=200&&xhr.status<300){
      row.className="row done"; bar.style.width="100%";
      var saved=f.name;
      try{ saved=JSON.parse(xhr.responseText).saved||saved; }catch(_){}
      row.querySelector(".nm").textContent="送りました　"+saved;
      sz.textContent=human(f.size);
    }else{
      row.className="row fail";
      row.querySelector(".nm").textContent="送れませんでした　"+f.name+"（"+(xhr.responseText||xhr.status)+"）";
    }
    pump();
  };
  xhr.onerror=function(){
    busy=false;
    row.className="row fail";
    row.querySelector(".nm").textContent="通信が切れました　"+f.name;
    pump();
  };
  xhr.send(f);
}

function refresh(){
  fetch(q("/api/list")).then(function(r){return r.json();}).then(function(d){
    var box=document.getElementById("list");
    box.innerHTML="";
    if(!d.files.length){ box.innerHTML='<div class="empty">送信箱は空です</div>'; return; }
    d.files.forEach(function(f){
      var row=document.createElement("div");
      row.className="row";
      row.innerHTML='<div class="nm"></div><div class="sz"></div><a class="dl">受け取る</a>';
      row.querySelector(".nm").textContent=f.name;
      row.querySelector(".sz").textContent=f.human;
      var a=row.querySelector(".dl");
      a.href=q("/get/"+encodeURIComponent(f.name));
      a.setAttribute("download", f.name);
      box.appendChild(row);
    });
  }).catch(function(){
    document.getElementById("list").innerHTML='<div class="empty">PC につながりません</div>';
  });
}

document.getElementById("bPhoto").onclick=function(){document.getElementById("fPhoto").click();};
document.getElementById("bFile").onclick=function(){document.getElementById("fFile").click();};
document.getElementById("fPhoto").onchange=function(e){addFiles(e.target.files); e.target.value="";};
document.getElementById("fFile").onchange=function(e){addFiles(e.target.files); e.target.value="";};

var drop=document.getElementById("drop");
["dragenter","dragover"].forEach(function(ev){
  document.addEventListener(ev,function(e){e.preventDefault(); drop.classList.add("on");});
});
["dragleave","drop"].forEach(function(ev){
  document.addEventListener(ev,function(e){e.preventDefault(); if(ev==="drop"&&e.dataTransfer) addFiles(e.dataTransfer.files); drop.classList.remove("on");});
});

refresh();
setInterval(function(){ if(!busy&&!queue.length) refresh(); }, 5000);
</script>
</body>
</html>`;
}

module.exports = { page, esc };
