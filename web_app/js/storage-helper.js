/* Supabase Storage helper — mirror lib/services/supabase_storage.dart pattern. */
(function () {
  'use strict';

  async function uploadFile({ bucket, path, file, contentType }) {
    const ct = contentType || file.type || 'application/octet-stream';
    const { error } = await window.sb.storage.from(bucket).upload(path, file, {
      contentType: ct, upsert: true,
    });
    if (error) throw new Error(`upload ${bucket}/${path}: ${error.message}`);
    return window.sb.storage.from(bucket).getPublicUrl(path).data.publicUrl;
  }

  async function uploadBytes({ bucket, path, bytes, contentType = 'image/jpeg' }) {
    const blob = bytes instanceof Blob ? bytes : new Blob([bytes], { type: contentType });
    return uploadFile({ bucket, path, file: blob, contentType });
  }

  async function deleteFile({ bucket, path }) {
    const { error } = await window.sb.storage.from(bucket).remove([path]);
    if (error) throw new Error(`delete ${bucket}/${path}: ${error.message}`);
  }

  function publicUrl({ bucket, path }) {
    return window.sb.storage.from(bucket).getPublicUrl(path).data.publicUrl;
  }

  /** Trigger file picker, return File or null. */
  function pickImage({ accept = 'image/*', multiple = false } = {}) {
    return new Promise((resolve) => {
      const inp = document.createElement('input');
      inp.type = 'file';
      inp.accept = accept;
      inp.multiple = multiple;
      inp.style.display = 'none';
      inp.onchange = () => resolve(multiple ? Array.from(inp.files) : (inp.files[0] || null));
      document.body.appendChild(inp);
      inp.click();
      setTimeout(() => inp.remove(), 1000);
    });
  }

  const MAX_BYTES = 80 * 1024; // 80KB hard cap per image

  async function _loadImg(file) {
    const img = new Image();
    const url = URL.createObjectURL(file);
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
    URL.revokeObjectURL(url);
    return img;
  }

  function _draw(img, w, h) {
    const canvas = document.createElement('canvas');
    canvas.width = w; canvas.height = h;
    canvas.getContext('2d').drawImage(img, 0, 0, w, h);
    return canvas;
  }

  function _toBlob(canvas, quality) {
    return new Promise((resolve) => canvas.toBlob((b) => resolve(b), 'image/jpeg', quality));
  }

  /** Compress image to ≤ maxBytes (default 80KB). Iteratively reduce quality & dims. */
  async function compressImage(file, maxBytes = MAX_BYTES, maxDim = 1280) {
    if (!file || !(file.type || '').startsWith('image/')) return file;
    const img = await _loadImg(file);
    let scale = Math.min(1, maxDim / Math.max(img.width, img.height));
    let w = Math.max(50, Math.round(img.width * scale));
    let h = Math.max(50, Math.round(img.height * scale));
    let quality = 0.85;
    let blob = await _toBlob(_draw(img, w, h), quality);
    // Step 1: reduce quality down to 0.3
    while (blob && blob.size > maxBytes && quality > 0.3) {
      quality -= 0.1;
      blob = await _toBlob(_draw(img, w, h), quality);
    }
    // Step 2: reduce dims by 20% iteratively (min 200px)
    while (blob && blob.size > maxBytes && Math.max(w, h) > 200) {
      w = Math.round(w * 0.8); h = Math.round(h * 0.8);
      blob = await _toBlob(_draw(img, w, h), 0.5);
    }
    return blob;
  }

  /** Legacy resize — now enforces 80KB cap. */
  async function resizeImage(file, maxDim = 1280, _quality = 0.85) {
    return compressImage(file, MAX_BYTES, maxDim);
  }

  /** All-in-one: pick → compress (≤80KB) → upload → return public URL. */
  async function pickAndUpload({ bucket, pathFn, maxDim = 1280 }) {
    const file = await pickImage();
    if (!file) return null;
    const blob = await compressImage(file, MAX_BYTES, maxDim);
    const path = typeof pathFn === 'function' ? pathFn(file) : pathFn;
    return uploadFile({ bucket, path, file: blob, contentType: 'image/jpeg' });
  }

  window.SupabaseStorage = {
    uploadFile, uploadBytes, deleteFile, publicUrl,
    pickImage, resizeImage, compressImage, pickAndUpload,
  };
})();
