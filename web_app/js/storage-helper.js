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

  /** Resize image client-side sebelum upload (kurangkan saiz). */
  async function resizeImage(file, maxDim = 1280, quality = 0.8) {
    const img = new Image();
    const url = URL.createObjectURL(file);
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = url; });
    const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
    const w = Math.round(img.width * scale);
    const h = Math.round(img.height * scale);
    const canvas = document.createElement('canvas');
    canvas.width = w; canvas.height = h;
    canvas.getContext('2d').drawImage(img, 0, 0, w, h);
    URL.revokeObjectURL(url);
    return new Promise((resolve) => canvas.toBlob((b) => resolve(b), 'image/jpeg', quality));
  }

  /** All-in-one: pick → resize → upload → return public URL. */
  async function pickAndUpload({ bucket, pathFn, maxDim = 1280, quality = 0.8 }) {
    const file = await pickImage();
    if (!file) return null;
    const blob = await resizeImage(file, maxDim, quality);
    const path = typeof pathFn === 'function' ? pathFn(file) : pathFn;
    return uploadFile({ bucket, path, file: blob, contentType: 'image/jpeg' });
  }

  window.SupabaseStorage = {
    uploadFile, uploadBytes, deleteFile, publicUrl,
    pickImage, resizeImage, pickAndUpload,
  };
})();
