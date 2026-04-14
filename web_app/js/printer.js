/* Web Bluetooth thermal printer (ESC/POS) — port dari lib/services/printer_service.dart
   Limit: Web Bluetooth hanya pada Chrome/Edge desktop + Chrome Android. Bukan iOS Safari. */
(function (global) {
  'use strict';

  // Common ESC/POS BLE service UUIDs
  const OPTIONAL_SERVICES = [
    '000018f0-0000-1000-8000-00805f9b34fb',
    '0000ff00-0000-1000-8000-00805f9b34fb',
    '0000ffe0-0000-1000-8000-00805f9b34fb',
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    '0000ffb0-0000-1000-8000-00805f9b34fb',
    '0000ae30-0000-1000-8000-00805f9b34fb',
  ];

  const RECEIPT_WIDTH = 48;
  const CHUNK = 180;
  const LS_ID = 'pos_printer_id';
  const LS_NAME = 'pos_printer_name';
  const LS_USB = 'pos_printer_usb_filter';
  const LS_WIFI = 'pos_printer_wifi';

  // BLE state
  let device = null;
  let writeChar = null;
  // USB state (WebUSB)
  let usbDevice = null;
  let usbEndpoint = 0;
  // WiFi config (saved only; actual print needs bridge)
  let wifiCfg = loadWifi();

  const listeners = new Set();

  function bleSupported() { return !!(navigator.bluetooth && navigator.bluetooth.requestDevice); }
  function usbSupported() { return !!(navigator.usb && navigator.usb.requestDevice); }
  function isSupported() { return bleSupported() || usbSupported(); }
  function bleConnected() { return !!(device && device.gatt && device.gatt.connected && writeChar); }
  function usbConnected() { return !!(usbDevice && usbDevice.opened); }
  function isConnected() { return bleConnected() || usbConnected(); }
  function getTransport() { return bleConnected() ? 'bluetooth' : (usbConnected() ? 'usb' : (wifiCfg.ip ? 'wifi' : '')); }
  function getName() {
    if (bleConnected()) return device.name || 'BLE';
    if (usbConnected()) return (usbDevice.productName || 'USB');
    if (wifiCfg.ip) return wifiCfg.ip + ':' + (wifiCfg.port || 9100);
    return '';
  }
  function onChange(fn) { listeners.add(fn); fn(getState()); return () => listeners.delete(fn); }
  function getState() {
    return {
      supported: isSupported(),
      bleSupported: bleSupported(), usbSupported: usbSupported(),
      connected: isConnected(), transport: getTransport(), name: getName(),
      bleConnected: bleConnected(), bleName: device ? (device.name || '—') : '',
      usbConnected: usbConnected(), usbName: usbDevice ? (usbDevice.productName || '—') : '',
      wifi: Object.assign({}, wifiCfg),
    };
  }
  function notify() { const st = getState(); listeners.forEach(fn => { try { fn(st); } catch (_) {} }); }

  function loadWifi() {
    try { return JSON.parse(localStorage.getItem(LS_WIFI) || '{}') || {}; }
    catch (_) { return {}; }
  }
  function saveWifi(cfg) {
    wifiCfg = Object.assign({}, cfg || {});
    localStorage.setItem(LS_WIFI, JSON.stringify(wifiCfg));
    notify();
  }

  async function findWriteChar(server) {
    const services = await server.getPrimaryServices();
    for (const svc of services) {
      try {
        const chars = await svc.getCharacteristics();
        for (const ch of chars) {
          if (ch.properties.write || ch.properties.writeWithoutResponse) return ch;
        }
      } catch (_) {}
    }
    return null;
  }

  async function connect() {
    if (!bleSupported()) throw new Error('Web Bluetooth tidak disokong oleh browser ini. Guna Chrome/Edge.');
    const d = await navigator.bluetooth.requestDevice({
      acceptAllDevices: true,
      optionalServices: OPTIONAL_SERVICES,
    });
    device = d;
    device.addEventListener('gattserverdisconnected', () => { writeChar = null; notify(); });
    const server = await device.gatt.connect();
    const ch = await findWriteChar(server);
    if (!ch) { await device.gatt.disconnect(); writeChar = null; notify(); throw new Error('Printer tiada write characteristic'); }
    writeChar = ch;
    try {
      localStorage.setItem(LS_ID, device.id || '');
      localStorage.setItem(LS_NAME, device.name || '');
    } catch (_) {}
    notify();
    return getState();
  }

  async function disconnect() {
    try { if (device && device.gatt && device.gatt.connected) device.gatt.disconnect(); } catch (_) {}
    writeChar = null;
    notify();
  }

  // ─── USB (WebUSB) ───
  async function connectUSB() {
    if (!usbSupported()) throw new Error('WebUSB tidak disokong oleh browser ini. Guna Chrome/Edge desktop.');
    const d = await navigator.usb.requestDevice({ filters: [] });
    await d.open();
    if (d.configuration === null) await d.selectConfiguration(1);
    // Claim first interface with bulk OUT endpoint
    let claimed = false, bulkOut = 0;
    for (const iface of d.configuration.interfaces) {
      for (const alt of iface.alternates) {
        for (const ep of alt.endpoints) {
          if (ep.direction === 'out' && ep.type === 'bulk') {
            try {
              await d.claimInterface(iface.interfaceNumber);
              if (alt.alternateSetting !== 0) await d.selectAlternateInterface(iface.interfaceNumber, alt.alternateSetting);
              bulkOut = ep.endpointNumber;
              claimed = true;
              break;
            } catch (e) { /* try next */ }
          }
        }
        if (claimed) break;
      }
      if (claimed) break;
    }
    if (!claimed) { try { await d.close(); } catch (_) {} throw new Error('Tiada bulk OUT endpoint pada device ini'); }
    usbDevice = d;
    usbEndpoint = bulkOut;
    try { localStorage.setItem(LS_USB, JSON.stringify({ vendorId: d.vendorId, productId: d.productId })); } catch (_) {}
    notify();
    return getState();
  }

  async function disconnectUSB() {
    try { if (usbDevice) await usbDevice.close(); } catch (_) {}
    usbDevice = null;
    usbEndpoint = 0;
    notify();
  }

  async function printRaw(bytes, opts) {
    const transport = (opts && opts.transport) || getTransport();
    if (!transport) throw new Error('Printer tidak disambung');
    const data = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);

    if (transport === 'bluetooth') {
      if (!bleConnected()) throw new Error('Bluetooth tidak disambung');
      for (let i = 0; i < data.length; i += CHUNK) {
        const chunk = data.slice(i, Math.min(i + CHUNK, data.length));
        if (writeChar.writeValueWithoutResponse && writeChar.properties.writeWithoutResponse) {
          await writeChar.writeValueWithoutResponse(chunk);
        } else {
          await writeChar.writeValue(chunk);
        }
      }
      return true;
    }
    if (transport === 'usb') {
      if (!usbConnected()) throw new Error('USB tidak disambung');
      for (let i = 0; i < data.length; i += 4096) {
        await usbDevice.transferOut(usbEndpoint, data.slice(i, Math.min(i + 4096, data.length)));
      }
      return true;
    }
    if (transport === 'wifi') {
      if (!wifiCfg.ip) throw new Error('WiFi printer tidak dikonfigur');
      // Browser can't open raw TCP. Route via optional bridge URL.
      // Convention: if wifiCfg.bridge is set (e.g. http://localhost:3333/print),
      // POST the raw bytes there. Otherwise throw with guidance.
      if (!wifiCfg.bridge) {
        throw new Error('WiFi printer perlu bridge HTTP (raw TCP tiada di browser). Set Bridge URL.');
      }
      const resp = await fetch(wifiCfg.bridge, {
        method: 'POST',
        headers: { 'Content-Type': 'application/octet-stream', 'X-Printer-Host': wifiCfg.ip, 'X-Printer-Port': String(wifiCfg.port || 9100) },
        body: data,
      });
      if (!resp.ok) throw new Error('Bridge HTTP ' + resp.status);
      return true;
    }
    throw new Error('Transport tidak dikenali: ' + transport);
  }

  function kickCashDrawer() {
    // ESC p m t1 t2 — m=0 (pin2), t1=25 (50ms on), t2=250 (500ms off)
    return printRaw(new Uint8Array([0x1B, 0x70, 0x00, 0x19, 0xFA]));
  }

  // ───── Receipt builder (port port ESC/POS dari Dart) ─────
  const ESC = {
    init:      '\x1B\x40',
    center:    '\x1B\x61\x01',
    left:      '\x1B\x61\x00',
    boldOn:    '\x1B\x45\x01',
    boldOff:   '\x1B\x45\x00',
    dblSize:   '\x1B\x21\x30',
    normal:    '\x1B\x21\x00',
    cut:       '\x1D\x56\x00',
  };

  function pad(s, n, char = ' ') { s = String(s); return s.length >= n ? s : s + char.repeat(n - s.length); }
  function padLeft(s, n, char = ' ') { s = String(s); return s.length >= n ? s : char.repeat(n - s.length) + s; }
  function baris(label, nilai, labelWidth = 18) {
    const l = pad(label, labelWidth);
    const gap = RECEIPT_WIDTH - l.length - nilai.length;
    return l + ' '.repeat(Math.max(1, gap)) + nilai + '\n';
  }
  function parseTarikh(raw) {
    let tStr = '', mStr = '';
    if (typeof raw === 'string' && raw) {
      const dt = new Date(raw);
      if (!isNaN(dt.getTime())) {
        const p = n => String(n).padStart(2, '0');
        tStr = `${p(dt.getDate())}/${p(dt.getMonth() + 1)}/${dt.getFullYear()}`;
        mStr = `${p(dt.getHours())}:${p(dt.getMinutes())}`;
      } else {
        tStr = raw.length > 10 ? raw.slice(0, 10) : raw;
      }
    } else {
      const now = new Date();
      const p = n => String(n).padStart(2, '0');
      tStr = `${p(now.getDate())}/${p(now.getMonth() + 1)}/${now.getFullYear()}`;
      mStr = `${p(now.getHours())}:${p(now.getMinutes())}`;
    }
    return { tStr, mStr };
  }
  function wrapText(text, width) {
    const words = String(text).split(' ');
    const lines = [];
    let cur = '';
    for (const w of words) {
      if (!cur) cur = w;
      else if ((cur + ' ' + w).length <= width) cur = cur + ' ' + w;
      else { lines.push(cur); cur = w; }
    }
    if (cur) lines.push(cur);
    return lines;
  }

  function buildReceipt(job, shop) {
    const garis = '='.repeat(RECEIPT_WIDTH) + '\n';
    const garis2 = '-'.repeat(RECEIPT_WIDTH) + '\n';

    const namaKedai = String(shop.shopName || shop.namaKedai || 'RMS PRO').toUpperCase();
    const telKedai = shop.phone || shop.ownerContact || '-';
    const alamat = shop.address || shop.alamat || '';
    const notaKaki = shop.notaInvoice || 'Terima kasih atas sokongan anda.';
    const siri = job.siri || '-';

    const { tStr, mStr } = parseTarikh(job.tarikh || job.tarikhMasuk || '');

    let items = [];
    if (Array.isArray(job.items_array) && job.items_array.length) {
      items = job.items_array.map(x => Object.assign({}, x));
    } else {
      items = [{ nama: String(job.kerosakan || '-'), harga: parseFloat(job.harga || 0) || 0 }];
    }

    const total = items.reduce((s, it) => {
      const h = parseFloat(it.harga) || 0;
      const q = parseInt(it.qty || 1, 10) || 1;
      return s + h * q;
    }, 0);

    let r = ESC.init + '\n\n';
    // Header
    r += ESC.center + ESC.dblSize + ESC.boldOn;
    r += (namaKedai.length > 24 ? namaKedai.slice(0, 24) : namaKedai) + '\n';
    r += ESC.normal + ESC.boldOff + '\n' + ESC.center;

    if (alamat) {
      const chunks = alamat.split(', ');
      let line = '';
      for (const w of chunks) {
        if (!line) line = w;
        else if ((line + ', ' + w).length <= RECEIPT_WIDTH) line = line + ', ' + w;
        else { r += line + '\n'; line = w; }
      }
      if (line) r += line + '\n';
    }
    r += 'Tel: ' + telKedai + '\n\n' + garis;

    // Info pelanggan
    r += '\n' + ESC.left;
    const tarikhLine = 'Tarikh: ' + tStr;
    const masaLine = mStr ? 'Masa: ' + mStr : '';
    if (masaLine) {
      const gap = RECEIPT_WIDTH - tarikhLine.length - masaLine.length;
      r += tarikhLine + ' '.repeat(Math.max(2, gap)) + masaLine + '\n';
    } else {
      r += tarikhLine + '\n';
    }
    r += '\n';
    r += baris('No. Siri', ': ' + siri);
    const nama = String(job.nama || '-');
    r += baris('Pelanggan', ': ' + (nama.length > 28 ? nama.slice(0, 28) : nama));
    r += baris('No. Tel', ': ' + (job.tel || '-'));
    const model = String(job.model || '-');
    r += baris('Model', ': ' + (model.length > 28 ? model.slice(0, 28) : model));
    r += '\n' + garis2;

    // Items
    r += '\n' + ESC.boldOn + 'ITEM                          QTY  HARGA(RM)\n' + ESC.boldOff + garis2 + '\n';
    for (const it of items) {
      const namaItem = String(it.nama || '-');
      const qty = parseInt(it.qty || 1, 10) || 1;
      const harga = parseFloat(it.harga) || 0;
      const qtyStr = String(qty);
      const hargaStr = harga.toFixed(2);
      if (namaItem.length > 30) {
        r += namaItem.slice(0, 30) + '\n';
        r += ' '.repeat(30) + padLeft(qtyStr, 3) + '  ' + padLeft(hargaStr, 10) + '\n';
      } else {
        r += pad(namaItem, 30) + padLeft(qtyStr, 3) + '  ' + padLeft(hargaStr, 10) + '\n';
      }
    }
    r += '\n' + garis2;

    // Total
    r += '\n' + ESC.boldOn;
    const totalStr = 'RM ' + total.toFixed(2);
    const totalLabel = 'TOTAL:';
    const gap = RECEIPT_WIDTH - totalLabel.length - totalStr.length;
    r += totalLabel + ' '.repeat(Math.max(1, gap)) + totalStr + '\n' + ESC.boldOff + '\n' + garis;

    // Nota kaki
    if (notaKaki) {
      r += '\n' + ESC.center;
      wrapText(notaKaki, RECEIPT_WIDTH).forEach(line => { r += line + '\n'; });
      r += '\n';
    }
    r += garis + '\n' + ESC.center + 'Terima Kasih\n' + '\n\n\n\n\n\n' + ESC.cut;

    return new TextEncoder().encode(r);
  }

  async function printReceipt(job, shop) {
    const bytes = buildReceipt(job || {}, shop || {});
    return printRaw(bytes);
  }

  async function testPrint(transport) {
    const bytes = new TextEncoder().encode(
      '\x1B\x40' +
      '\x1B\x61\x01' + '\x1B\x45\x01' + 'RMS PRO — TEST PRINT\n' + '\x1B\x45\x00' +
      new Date().toLocaleString() + '\n' +
      '\x1B\x61\x00' +
      '-'.repeat(RECEIPT_WIDTH) + '\n' +
      'Jika anda dapat baca ini, printer OK.\n' +
      '-'.repeat(RECEIPT_WIDTH) + '\n' +
      '\n\n\n\n\x1D\x56\x00'
    );
    return printRaw(bytes, { transport });
  }

  // Auto-reconnect to previously-granted devices (no re-prompt)
  async function autoReconnect() {
    if (bleSupported() && navigator.bluetooth.getDevices) {
      try {
        const savedId = localStorage.getItem(LS_ID) || '';
        const savedName = localStorage.getItem(LS_NAME) || '';
        if (savedId || savedName) {
          const devs = await navigator.bluetooth.getDevices();
          const match = devs.find(d => d.id === savedId || d.name === savedName);
          if (match) {
            device = match;
            device.addEventListener('gattserverdisconnected', () => { writeChar = null; notify(); });
            try {
              const server = await device.gatt.connect();
              const ch = await findWriteChar(server);
              if (ch) { writeChar = ch; notify(); }
            } catch (_) { /* user may need to power-on printer */ }
          }
        }
      } catch (_) {}
    }
    if (usbSupported() && navigator.usb.getDevices) {
      try {
        const saved = JSON.parse(localStorage.getItem(LS_USB) || '{}');
        const devs = await navigator.usb.getDevices();
        const match = devs.find(d => d.vendorId === saved.vendorId && d.productId === saved.productId);
        if (match) {
          try {
            if (!match.opened) await match.open();
            if (match.configuration === null) await match.selectConfiguration(1);
            let ok = false, ep = 0;
            for (const iface of match.configuration.interfaces) {
              for (const alt of iface.alternates) {
                for (const e of alt.endpoints) {
                  if (e.direction === 'out' && e.type === 'bulk') {
                    try {
                      await match.claimInterface(iface.interfaceNumber);
                      ep = e.endpointNumber; ok = true; break;
                    } catch (_) {}
                  }
                }
                if (ok) break;
              }
              if (ok) break;
            }
            if (ok) { usbDevice = match; usbEndpoint = ep; notify(); }
          } catch (_) {}
        }
      } catch (_) {}
    }
    notify();
  }

  global.RmsPrinter = {
    isSupported, bleSupported, usbSupported,
    isConnected, bleConnected, usbConnected,
    getName, getTransport, getState, onChange,
    // Bluetooth
    connect, disconnect,
    // USB
    connectUSB, disconnectUSB,
    // WiFi config
    getWifi: () => Object.assign({}, wifiCfg),
    setWifi: saveWifi,
    // Print
    printRaw, printReceipt, kickCashDrawer, testPrint,
    autoReconnect,
  };

  // Kick off auto-reconnect on load
  if (typeof window !== 'undefined') {
    setTimeout(() => { try { autoReconnect(); } catch (_) {} }, 100);
  }
})(window);
