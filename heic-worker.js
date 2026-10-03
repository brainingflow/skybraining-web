// 婦女報名頁 HEIC 轉 JPG 用的 worker。放同網域：script-src 'self' 就放行，不用 blob: worker、不用 eval，vercel.json 的 CSP 不必改。
// 頁面每轉一張就 new 一個，轉完 terminate，所以這裡不回收記憶體。
var MAX_PIXELS = 30000000; // 48MP 解碼峰值約 1.5GB，手機會把分頁整個殺掉、填好的資料全沒了，所以先讀尺寸、太大就不解
var replied = false;
function reply(d, transfer){
  if(replied) return;
  replied = true;
  postMessage(d, transfer || []);
}
// libheif 解碼中途 abort 會變成沒人接的 rejection，不回話頁面就只能等 30 秒逾時
self.onunhandledrejection = function(){ reply({ err:'decode' }); };
self.onmessage = function(e){
  var buf = e.data;
  try{ importScripts('/libheif-1.23.2.js'); }catch(err){ return reply({ err:'load' }); }
  var ready = false, mod;
  new Promise(function(res, rej){
    // onRuntimeInitialized 可能在 libheif() 回傳前就同步呼叫
    mod = libheif({ onRuntimeInitialized:function(){ ready = true; if(mod) res(mod); }, onAbort:function(){ rej(); } });
    if(ready) res(mod);
  }).then(function(m){
    var imgs = new m.HeifDecoder().decode(new Uint8Array(buf));
    if(!imgs || !imgs.length) return reply({ err:'decode' });
    var im = imgs.filter(function(i){ return i.is_primary(); })[0] || imgs[0];
    // decode() 只讀檔頭，真正解碼在 display()；這裡的寬高已含 irot 旋轉
    var w = im.get_width(), h = im.get_height();
    if(!(w > 0 && h > 0)) return reply({ err:'decode' });
    if(w * h > MAX_PIXELS) return reply({ err:'toobig', w:w, h:h });
    var out = new Uint8ClampedArray(w * h * 4);
    im.display({ data:out, width:w, height:h }, function(r){
      if(!r) return reply({ err:'decode' });
      reply({ w:w, h:h, data:out.buffer }, [out.buffer]);
    });
  }).then(null, function(){ reply({ err:'decode' }); });
};
