// ponytail: Web 虚拟背景 — MediaPipe + 锐化蒙版；音频由 WHIP 从 rawStream 单独上送
(function () {
  var SEG_CDN = 'https://cdn.jsdelivr.net/npm/@mediapipe/selfie_segmentation/';
  var scriptPromise = null;
  var MASK_THRESH = 0.68;
  var MASK_FEATHER = 0.05;
  var MORPH_R = 1;

  function loadScript(src) {
    return new Promise(function (resolve, reject) {
      var s = document.createElement('script');
      s.src = src;
      s.crossOrigin = 'anonymous';
      s.onload = function () { resolve(); };
      s.onerror = function () { reject(new Error('load failed: ' + src)); };
      document.head.appendChild(s);
    });
  }

  function ensureMediaPipe() {
    if (window.SelfieSegmentation) return Promise.resolve();
    if (!scriptPromise) scriptPromise = loadScript(SEG_CDN + 'selfie_segmentation.js');
    return scriptPromise;
  }

  function loadImage(url) {
    return new Promise(function (resolve, reject) {
      var img = new Image();
      img.crossOrigin = 'anonymous';
      img.onload = function () { resolve(img); };
      img.onerror = function () { reject(new Error('backdrop load failed')); };
      img.src = url;
    });
  }

  function waitVideoReady(video) {
    return new Promise(function (resolve) {
      if (video.videoWidth > 0 && video.videoHeight > 0) return resolve();
      video.onloadedmetadata = function () { resolve(); };
      setTimeout(resolve, 1500);
    });
  }

  function morphAlpha(buf, w, h, r, op) {
    var n = w * h, tmp = new Uint8ClampedArray(n);
    var x, y, dx, dy, nx, ny, p, v, i;
    for (y = 0; y < h; y++) {
      for (x = 0; x < w; x++) {
        p = y * w + x;
        if (op === 'erode') {
          v = 255;
          for (dy = -r; dy <= r; dy++) {
            for (dx = -r; dx <= r; dx++) {
              nx = x + dx; ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) { v = 0; break; }
              v = Math.min(v, buf[ny * w + nx]);
            }
            if (v === 0) break;
          }
          tmp[p] = v;
        } else {
          v = 0;
          for (dy = -r; dy <= r; dy++) {
            for (dx = -r; dx <= r; dx++) {
              nx = x + dx; ny = y + dy;
              if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
              v = Math.max(v, buf[ny * w + nx]);
            }
          }
          tmp[p] = v;
        }
      }
    }
    for (i = 0; i < n; i++) buf[i] = tmp[i];
  }

  function refineMask(maskSource, maskCanvas, w, h) {
    var mctx = maskCanvas.getContext('2d', { willReadFrequently: true });
    mctx.clearRect(0, 0, w, h);
    mctx.drawImage(maskSource, 0, 0, w, h);
    var id = mctx.getImageData(0, 0, w, h);
    var d = id.data;
    var alphas = new Uint8ClampedArray(w * h);
    var t0 = Math.max(0, MASK_THRESH - MASK_FEATHER);
    var t1 = MASK_THRESH;
    var i, p, v, a;
    for (i = 0, p = 0; i < d.length; i += 4, p++) {
      v = d[i] / 255;
      if (v >= t1) a = 255;
      else if (v <= t0) a = 0;
      else a = Math.round((v - t0) / (t1 - t0) * 255);
      alphas[p] = a;
    }
    if (MORPH_R > 0) {
      morphAlpha(alphas, w, h, MORPH_R, 'erode');
      morphAlpha(alphas, w, h, MORPH_R, 'dilate');
    }
    for (i = 0, p = 0; i < d.length; i += 4, p++) {
      d[i] = d[i + 1] = d[i + 2] = 255;
      d[i + 3] = alphas[p];
    }
    mctx.putImageData(id, 0, 0);
    return maskCanvas;
  }

  window.qdbotWrapVirtualBg = async function (cameraStream, backdropUrl) {
    var url = (backdropUrl || '').trim();
    if (!url || !cameraStream) return { stream: cameraStream, stop: function () {} };
    try {
      await ensureMediaPipe();
      var backdrop = await loadImage(url);
      var video = document.createElement('video');
      video.playsInline = true;
      video.muted = true;
      video.srcObject = cameraStream;
      await video.play();
      await waitVideoReady(video);

      var w = video.videoWidth || 1280;
      var h = video.videoHeight || 720;
      var canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      var ctx = canvas.getContext('2d');
      var maskCanvas = document.createElement('canvas');
      maskCanvas.width = w;
      maskCanvas.height = h;

      var seg = new SelfieSegmentation({
        locateFile: function (file) { return SEG_CDN + file; },
      });
      seg.setOptions({ modelSelection: 0, selfieMode: true });

      var running = true;
      var busy = false;
      seg.onResults(function (results) {
        if (!running) return;
        var mask = refineMask(results.segmentationMask, maskCanvas, w, h);
        ctx.save();
        ctx.clearRect(0, 0, w, h);
        ctx.drawImage(mask, 0, 0, w, h);
        ctx.globalCompositeOperation = 'source-in';
        ctx.drawImage(results.image, 0, 0, w, h);
        ctx.globalCompositeOperation = 'destination-over';
        ctx.drawImage(backdrop, 0, 0, w, h);
        ctx.restore();
      });

      function pump() {
        if (!running) return;
        if (!busy) {
          busy = true;
          seg.send({ image: video }).finally(function () {
            busy = false;
            if (running) requestAnimationFrame(pump);
          });
        } else {
          requestAnimationFrame(pump);
        }
      }
      pump();

      return {
        stream: canvas.captureStream(30),
        stop: function () {
          running = false;
          try { seg.close(); } catch (e) {}
        },
      };
    } catch (e) {
      console.warn('[qdbot] virtual bg fallback:', e);
      return { stream: cameraStream, stop: function () {} };
    }
  };
})();
