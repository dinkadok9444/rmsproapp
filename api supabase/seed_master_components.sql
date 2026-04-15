-- Seed starter master_components data (Xiaomi / Oppo / Vivo / Huawei).
-- Codes di sini adalah part number BATERI/LCD yang common digunakan di pasaran.
-- Verify dengan supplier sebelum order. Admin boleh edit/padam via admin_database_komponen.html.

-- Categories (starter: BATERI + LCD. Admin boleh tambah via UI)
INSERT INTO master_component_categories (name, sort_order) VALUES
('BATERI', 1),
('LCD', 2)
ON CONFLICT (name) DO NOTHING;

-- ========================================================================
-- XIAOMI — BATERI
-- ========================================================================
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('BATERI', 'Xiaomi', 'Redmi Note 8 / Note 8T', 'BN46', '4000mAh 3.85V'),
('BATERI', 'Xiaomi', 'Redmi Note 9 / 10X 4G', 'BN54', '5020mAh'),
('BATERI', 'Xiaomi', 'Redmi Note 9 Pro / Note 9S', 'BN55', '5020mAh'),
('BATERI', 'Xiaomi', 'Redmi Note 10 / 10S', 'BN59', '5000mAh'),
('BATERI', 'Xiaomi', 'Redmi Note 10 Pro / Poco X3 Pro', 'BN57', '5020mAh'),
('BATERI', 'Xiaomi', 'Redmi 9A / 9C / 10A', 'BN56', '5000mAh'),
('BATERI', 'Xiaomi', 'Mi 9T / Redmi K20', 'BP41', '4000mAh'),
('BATERI', 'Xiaomi', 'Mi 9T Pro / Redmi K20 Pro', 'BP40', '4000mAh'),
('BATERI', 'Xiaomi', 'Redmi 8 / 8A', 'BN51', '5000mAh'),
('BATERI', 'Xiaomi', 'Redmi 7 / Y3', 'BN46', '4000mAh — compat Note 8');

-- XIAOMI — LCD (service part codes kebanyakannya OEM generic; pakai model ref)
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('LCD', 'Xiaomi', 'Redmi Note 8', 'LCD-RN8', 'IPS LCD w/ frame tersedia'),
('LCD', 'Xiaomi', 'Redmi Note 9', 'LCD-RN9', 'IPS LCD'),
('LCD', 'Xiaomi', 'Redmi Note 9 Pro / 9S', 'LCD-RN9P', 'IPS LCD'),
('LCD', 'Xiaomi', 'Redmi Note 10 / 10S', 'LCD-RN10-AMOLED', 'AMOLED — fingerprint in-display'),
('LCD', 'Xiaomi', 'Redmi Note 10 Pro', 'LCD-RN10P-AMOLED', 'AMOLED 120Hz');

-- ========================================================================
-- OPPO — BATERI (BLP series)
-- ========================================================================
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('BATERI', 'Oppo', 'A5 2020 / A9 2020', 'BLP727', '5000mAh'),
('BATERI', 'Oppo', 'A15 / A15s / A35', 'BLP805', '4230mAh'),
('BATERI', 'Oppo', 'A31 / A8 / A91 / F15', 'BLP721', '4025mAh'),
('BATERI', 'Oppo', 'A52 / A72 / A92', 'BLP781', '5000mAh'),
('BATERI', 'Oppo', 'A53 / A33 2020', 'BLP805', '5000mAh'),
('BATERI', 'Oppo', 'A54 4G', 'BLP805', '5000mAh'),
('BATERI', 'Oppo', 'A74 4G', 'BLP851', '5000mAh'),
('BATERI', 'Oppo', 'A74 5G / A54 5G / A93 5G', 'BLP849', '5000mAh'),
('BATERI', 'Oppo', 'F9 / A7x / F9 Pro', 'BLP681', '3500mAh'),
('BATERI', 'Oppo', 'F11', 'BLP717', '4020mAh'),
('BATERI', 'Oppo', 'F11 Pro', 'BLP699', '4000mAh'),
('BATERI', 'Oppo', 'Reno 2 / 2F / 2Z', 'BLP741', '4000mAh'),
('BATERI', 'Oppo', 'Reno 4 / F17 Pro', 'BLP781', '4015mAh'),
('BATERI', 'Oppo', 'Reno 5 / F19 Pro', 'BLP841', '4310mAh');

-- OPPO — LCD
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('LCD', 'Oppo', 'A5 2020 / A9 2020', 'LCD-OPA9-2020', 'IPS LCD'),
('LCD', 'Oppo', 'A15 / A15s', 'LCD-OPA15', 'IPS LCD'),
('LCD', 'Oppo', 'A31 / A8', 'LCD-OPA31', 'IPS LCD'),
('LCD', 'Oppo', 'A52 / A72 / A92', 'LCD-OPA52', 'IPS LCD'),
('LCD', 'Oppo', 'A53', 'LCD-OPA53', 'IPS LCD 90Hz'),
('LCD', 'Oppo', 'A74 4G', 'LCD-OPA74-AMOLED', 'AMOLED'),
('LCD', 'Oppo', 'F9 / A7x', 'LCD-OPF9', 'IPS LCD'),
('LCD', 'Oppo', 'F11 Pro', 'LCD-OPF11P', 'IPS LCD popup camera'),
('LCD', 'Oppo', 'Reno 5', 'LCD-OPR5-AMOLED', 'AMOLED 90Hz');

-- ========================================================================
-- VIVO — BATERI (B-series internal code)
-- ========================================================================
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('BATERI', 'Vivo', 'Y12 / Y15 / Y17', 'B-G6', '5000mAh'),
('BATERI', 'Vivo', 'Y20 / Y20s / Y12s / Y1s', 'B-O9', '5000mAh'),
('BATERI', 'Vivo', 'Y30 / Y50', 'B-L0', '5000mAh'),
('BATERI', 'Vivo', 'Y53s / Y73s', 'B-P6', '5000mAh'),
('BATERI', 'Vivo', 'Y91 / Y91i / Y93 / Y95', 'B-G0', '4030mAh'),
('BATERI', 'Vivo', 'V11 / V11 Pro', 'B-F0', '3400mAh'),
('BATERI', 'Vivo', 'V15 / S1', 'B-H2', '3900mAh'),
('BATERI', 'Vivo', 'V19 / V20 / V20 Pro', 'B-K9', '4000mAh'),
('BATERI', 'Vivo', 'V21 / V21e', 'B-P1', '4000mAh');

-- VIVO — LCD
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('LCD', 'Vivo', 'Y12 / Y15 / Y17', 'LCD-VVY15', 'IPS LCD'),
('LCD', 'Vivo', 'Y20 / Y20s / Y12s', 'LCD-VVY20', 'IPS LCD'),
('LCD', 'Vivo', 'Y30 / Y50', 'LCD-VVY50', 'IPS LCD'),
('LCD', 'Vivo', 'Y53s', 'LCD-VVY53S', 'IPS LCD'),
('LCD', 'Vivo', 'V15 / S1', 'LCD-VVV15', 'IPS LCD popup'),
('LCD', 'Vivo', 'V20 / V20 Pro', 'LCD-VVV20-AMOLED', 'AMOLED');

-- ========================================================================
-- HUAWEI — BATERI (HB series — official Huawei part numbers)
-- ========================================================================
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('BATERI', 'Huawei', 'P20', 'HB396285ECW', '3400mAh'),
('BATERI', 'Huawei', 'P20 Pro / Mate 10 / Mate 10 Pro', 'HB436486ECW', '4000mAh'),
('BATERI', 'Huawei', 'P30', 'HB436380ECW', '3650mAh'),
('BATERI', 'Huawei', 'P30 Pro / Mate 20 Pro', 'HB486486ECW', '4200mAh'),
('BATERI', 'Huawei', 'P30 Lite / Mate 20 Lite / Nova 3i / Nova 4e', 'HB356687ECW', '3340mAh'),
('BATERI', 'Huawei', 'P40', 'HB525777EEW', '3800mAh'),
('BATERI', 'Huawei', 'P40 Pro', 'HB536378EEW', '4200mAh'),
('BATERI', 'Huawei', 'P40 Lite / Nova 6 SE / Nova 7i', 'HB486586ECW', '4200mAh'),
('BATERI', 'Huawei', 'Mate 20', 'HB396689ECW', '4000mAh'),
('BATERI', 'Huawei', 'Y7 2019 / Y7 Prime 2019 / Y7 Pro 2019', 'HB406689ECW', '4000mAh'),
('BATERI', 'Huawei', 'Y9 2019 / Enjoy 9 Plus', 'HB406689ECW', '4000mAh'),
('BATERI', 'Huawei', 'Y9 Prime 2019 / Y9s / P Smart Pro', 'HB446486ECW', '4000mAh'),
('BATERI', 'Huawei', 'Nova 5T / Honor 20', 'HB396285ECW', '3750mAh — compat P20'),
('BATERI', 'Huawei', 'Y6 2019 / Y6 Pro 2019 / Honor 8A', 'HB405979ECW', '3020mAh');

-- HUAWEI — LCD
INSERT INTO master_components (category, brand, model, code, notes) VALUES
('LCD', 'Huawei', 'P20', 'LCD-HWP20', 'IPS LCD'),
('LCD', 'Huawei', 'P20 Pro', 'LCD-HWP20P-OLED', 'OLED'),
('LCD', 'Huawei', 'P30', 'LCD-HWP30-OLED', 'OLED in-display fingerprint'),
('LCD', 'Huawei', 'P30 Pro', 'LCD-HWP30P-OLED', 'OLED curved'),
('LCD', 'Huawei', 'P30 Lite / Nova 4e', 'LCD-HWP30L', 'IPS LCD'),
('LCD', 'Huawei', 'P40 Lite / Nova 7i', 'LCD-HWP40L', 'IPS LCD'),
('LCD', 'Huawei', 'Mate 20', 'LCD-HWM20', 'IPS LCD'),
('LCD', 'Huawei', 'Y7 2019', 'LCD-HWY7-19', 'IPS LCD'),
('LCD', 'Huawei', 'Y9 2019', 'LCD-HWY9-19', 'IPS LCD'),
('LCD', 'Huawei', 'Y9 Prime 2019 / Y9s', 'LCD-HWY9P-19', 'IPS LCD popup'),
('LCD', 'Huawei', 'Nova 5T / Honor 20', 'LCD-HWN5T', 'IPS LCD');
