/* Settings → Tetapan Printer (Bluetooth / USB / WiFi) */
(function () {
  'use strict';
  if (!document.getElementById('sec-printer')) return;
  if (!window.RmsPrinter) { console.warn('RmsPrinter not loaded'); return; }

  const $ = id => document.getElementById(id);

  // Pre-fill WiFi fields
  const wifi = RmsPrinter.getWifi();
  $('prnWifiIp').value = wifi.ip || '';
  $('prnWifiPort').value = wifi.port || 9100;
  $('prnWifiBridge').value = wifi.bridge || '';

  // Reflect state
  function reflect(st) {
    // Bluetooth
    const bt = $('prnBT');
    const btNote = $('prnBTNote');
    if (!st.bleSupported) {
      $('prnBTConnect').disabled = true;
      $('prnBTTest').disabled = true;
      btNote.innerHTML = '<i class="fas fa-triangle-exclamation"></i> Browser ini tidak sokong Web Bluetooth. Guna Chrome/Edge (desktop) atau Chrome Android.';
      $('prnBTSub').textContent = 'Tidak disokong';
    } else {
      btNote.textContent = '';
      $('prnBTConnect').disabled = st.bleConnected;
      $('prnBTTest').disabled = !st.bleConnected;
      $('prnBTDisconnect').hidden = !st.bleConnected;
      $('prnBTSub').textContent = st.bleConnected ? ('Tersambung: ' + st.bleName) : 'Tidak disambung';
    }
    toggleDot('prnBTDot', st.bleConnected, !st.bleSupported);

    // USB
    const usbNote = $('prnUSBNote');
    if (!st.usbSupported) {
      $('prnUSBConnect').disabled = true;
      $('prnUSBTest').disabled = true;
      usbNote.innerHTML = '<i class="fas fa-triangle-exclamation"></i> Browser ini tidak sokong WebUSB. Guna Chrome/Edge desktop.';
      $('prnUSBSub').textContent = 'Tidak disokong';
    } else {
      usbNote.textContent = '';
      $('prnUSBConnect').disabled = st.usbConnected;
      $('prnUSBTest').disabled = !st.usbConnected;
      $('prnUSBDisconnect').hidden = !st.usbConnected;
      $('prnUSBSub').textContent = st.usbConnected ? ('Tersambung: ' + st.usbName) : 'Tidak disambung';
    }
    toggleDot('prnUSBDot', st.usbConnected, !st.usbSupported);

    // WiFi dot active only if both ip + bridge set (usable)
    const wifiOK = !!(st.wifi && st.wifi.ip && st.wifi.bridge);
    toggleDot('prnWIFIDot', wifiOK, false);
    $('prnWifiTest').disabled = !wifiOK;

    // Active transport
    const label = st.transport === 'bluetooth' ? 'BLUETOOTH'
      : st.transport === 'usb' ? 'USB'
      : st.transport === 'wifi' ? 'WIFI'
      : '—';
    const active = $('prnActive');
    active.textContent = label + (st.name && st.transport ? ' (' + st.name + ')' : '');
    active.className = 'prn-active__val' + (st.transport ? ' is-on' : '');
  }

  function toggleDot(id, on, disabled) {
    const el = $(id);
    el.classList.toggle('is-on', on);
    el.classList.toggle('is-off', !on && !disabled);
    el.classList.toggle('is-disabled', disabled);
  }

  RmsPrinter.onChange(reflect);

  // Handlers — Bluetooth
  $('prnBTConnect').addEventListener('click', async () => {
    try { await RmsPrinter.connect(); toast('Bluetooth tersambung'); }
    catch (e) { toast('Gagal: ' + e.message, true); }
  });
  $('prnBTDisconnect').addEventListener('click', async () => { await RmsPrinter.disconnect(); toast('Bluetooth diputuskan'); });
  $('prnBTTest').addEventListener('click', async () => {
    try { await RmsPrinter.testPrint('bluetooth'); toast('Uji cetak dihantar'); }
    catch (e) { toast('Gagal uji cetak: ' + e.message, true); }
  });

  // Handlers — USB
  $('prnUSBConnect').addEventListener('click', async () => {
    try { await RmsPrinter.connectUSB(); toast('USB tersambung'); }
    catch (e) { toast('Gagal: ' + e.message, true); }
  });
  $('prnUSBDisconnect').addEventListener('click', async () => { await RmsPrinter.disconnectUSB(); toast('USB diputuskan'); });
  $('prnUSBTest').addEventListener('click', async () => {
    try { await RmsPrinter.testPrint('usb'); toast('Uji cetak dihantar'); }
    catch (e) { toast('Gagal uji cetak: ' + e.message, true); }
  });

  // Handlers — WiFi
  $('prnWifiSave').addEventListener('click', () => {
    const cfg = {
      ip: $('prnWifiIp').value.trim(),
      port: parseInt($('prnWifiPort').value, 10) || 9100,
      bridge: $('prnWifiBridge').value.trim(),
    };
    RmsPrinter.setWifi(cfg);
    toast('Tetapan WiFi disimpan');
  });
  $('prnWifiTest').addEventListener('click', async () => {
    // Save current fields before testing
    const cfg = {
      ip: $('prnWifiIp').value.trim(),
      port: parseInt($('prnWifiPort').value, 10) || 9100,
      bridge: $('prnWifiBridge').value.trim(),
    };
    RmsPrinter.setWifi(cfg);
    try { await RmsPrinter.testPrint('wifi'); toast('Uji cetak dihantar ke bridge'); }
    catch (e) { toast('Gagal: ' + e.message, true); }
  });

  // Minimal toast (reuse save-bar toast if missing)
  function toast(msg, isErr) {
    let t = document.getElementById('prnToast');
    if (!t) {
      t = document.createElement('div');
      t.id = 'prnToast';
      t.className = 'prn-toast';
      document.body.appendChild(t);
    }
    t.textContent = msg;
    t.style.background = isErr ? '#DC2626' : '#0F172A';
    t.classList.add('is-show');
    clearTimeout(toast._t);
    toast._t = setTimeout(() => t.classList.remove('is-show'), 2500);
  }
})();
