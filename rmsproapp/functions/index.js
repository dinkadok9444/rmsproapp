const functions = require("firebase-functions");
const admin = require("firebase-admin");
const { GoogleAuth } = require("google-auth-library");

admin.initializeApp();
const db = admin.firestore();

const PROJECT_ID = "rmspro-2f454";
const SITE_ID = "rmspro-2f454"; // biasanya sama dengan project ID

/**
 * addCustomDomain
 * Dealer call function ni untuk add custom domain ke Firebase Hosting.
 * Return DNS records yang dealer perlu set.
 */
exports.addCustomDomain = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const { domain, ownerID } = req.body || {};

  if (!domain || !ownerID) {
    res.status(400).json({ error: "Domain dan ownerID diperlukan." });
    return;
  }

  // Clean domain — buang https://, trailing slash
  let cleanDomain = domain
    .replace(/^https?:\/\//, "")
    .replace(/\/+$/, "")
    .toLowerCase()
    .trim();

  // Validate domain format
  const domainRegex = /^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$/;
  if (!domainRegex.test(cleanDomain)) {
    res.status(400).json({ error: "Format domain tidak sah." });
    return;
  }

  // Check domain tak duplicate
  const existing = await db
    .collection("saas_dealers")
    .where("domain", "==", "https://" + cleanDomain)
    .limit(1)
    .get();

  if (!existing.empty && existing.docs[0].id !== ownerID) {
    res.status(409).json({ error: "Domain ini sudah digunakan oleh akaun lain." });
    return;
  }

  try {
    // Get auth token for Firebase Hosting API
    const auth = new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/firebase.hosting"],
    });
    const client = await auth.getClient();
    const token = await client.getAccessToken();

    // Call Firebase Hosting API to add custom domain
    const url = `https://firebasehosting.googleapis.com/v1beta1/projects/${PROJECT_ID}/sites/${SITE_ID}/customDomains?customDomainId=${cleanDomain}`;

    const response = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token.token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({}),
    });

    const result = await response.json();

    if (!response.ok) {
      // Domain mungkin dah ada — try get status
      if (result.error && result.error.code === 409) {
        const statusResult = await getDomainStatus(cleanDomain, token.token, ownerID);
        res.json(statusResult);
        return;
      }
      throw new Error(result.error?.message || "Gagal menambah domain.");
    }

    // Extract DNS records from response
    const dnsRecords = extractDnsRecords(result);

    // Save domain + DNS records to dealer record
    await db.collection("saas_dealers").doc(ownerID).set(
      {
        domain: "https://" + cleanDomain,
        domainStatus: "PENDING_DNS",
        dnsRecords: dnsRecords,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );

    res.json({
      success: true,
      domain: cleanDomain,
      status: "PENDING_DNS",
      dnsRecords: dnsRecords,
      message: "Domain ditambah. Sila set DNS records berikut.",
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * checkDomainStatus
 * Check status verification domain.
 */
exports.checkDomainStatus = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const { domain, ownerID } = req.body || {};

  if (!domain || !ownerID) {
    res.status(400).json({ error: "Domain dan ownerID diperlukan." });
    return;
  }

  let cleanDomain = domain
    .replace(/^https?:\/\//, "")
    .replace(/\/+$/, "")
    .toLowerCase()
    .trim();

  try {
    const auth = new GoogleAuth({
      scopes: ["https://www.googleapis.com/auth/firebase.hosting"],
    });
    const client = await auth.getClient();
    const token = await client.getAccessToken();

    const result = await getDomainStatus(cleanDomain, token.token, ownerID);
    res.json(result);
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * Helper: Get domain status from Firebase Hosting API
 */
async function getDomainStatus(cleanDomain, token, ownerID) {
  const url = `https://firebasehosting.googleapis.com/v1beta1/projects/${PROJECT_ID}/sites/${SITE_ID}/customDomains/${cleanDomain}`;

  const response = await fetch(url, {
    method: "GET",
    headers: {
      Authorization: `Bearer ${token}`,
    },
  });

  const result = await response.json();

  if (!response.ok) {
    throw new Error(result.error?.message || "Gagal check status domain.");
  }

  // Determine status
  let status = "PENDING_DNS";
  if (result.certState === "CERT_ACTIVE" || result.hostState === "HOST_ACTIVE") {
    status = "ACTIVE";
  } else if (result.ownershipState === "OWNERSHIP_ACTIVE") {
    status = "VERIFIED";
  }

  const dnsRecords = extractDnsRecords(result);

  // Update Firestore with status + DNS records
  await db.collection("saas_dealers").doc(ownerID).set(
    {
      domainStatus: status,
      dnsRecords: dnsRecords,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );

  return {
    success: true,
    domain: cleanDomain,
    status: status,
    dnsRecords: dnsRecords,
    message:
      status === "ACTIVE"
        ? "Domain aktif dan sedia digunakan!"
        : status === "VERIFIED"
        ? "Domain disahkan. SSL sedang diproses..."
        : "Menunggu DNS setup. Sila set records berikut.",
  };
}

/**
 * getDealers — HTTP endpoint (elak int64 issue pada Flutter Web)
 */
exports.getDealers = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  try {
    const snap = await db.collection("saas_dealers").get();
    const dealers = [];
    snap.forEach((doc) => {
      const d = doc.data();
      dealers.push({
        id: doc.id,
        namaKedai: String(d.namaKedai || doc.id),
      });
    });
    dealers.sort((a, b) => a.namaKedai.toLowerCase().localeCompare(b.namaKedai.toLowerCase()));
    res.json({ dealers });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * getDomains — HTTP endpoint
 */
exports.getDomains = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "GET");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  try {
    const snap = await db.collection("saas_dealers").get();
    const domains = [];
    snap.forEach((doc) => {
      const d = doc.data();
      if (d.domain && typeof d.domain === "string" && d.domain.length > 0) {
        domains.push({
          id: doc.id,
          namaKedai: String(d.namaKedai || doc.id),
          domain: String(d.domain),
          domainStatus: String(d.domainStatus || ""),
          dnsRecords: Array.isArray(d.dnsRecords) ? d.dnsRecords : [],
        });
      }
    });
    domains.sort((a, b) => a.namaKedai.toLowerCase().localeCompare(b.namaKedai.toLowerCase()));
    res.json({ domains });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

/**
 * pdfProxy — Download PDF dari URL dan return sebagai base64.
 * Bypass CORS untuk Flutter Web.
 */
exports.pdfProxy = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const { url } = req.body || {};
  if (!url) {
    res.status(400).json({ error: "URL diperlukan." });
    return;
  }

  try {
    const response = await fetch(url);
    if (!response.ok) {
      res.status(502).json({ error: `Gagal download: ${response.status}` });
      return;
    }
    const buffer = await response.arrayBuffer();
    const base64 = Buffer.from(buffer).toString("base64");
    res.json({ pdfBase64: base64 });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// ═══════════════════════════════════════════════════════════
// WHATSAPP BOT WEBHOOK
// ═══════════════════════════════════════════════════════════

/**
 * whatsappWebhook — Webhook untuk terima message dari Meta WhatsApp Cloud API
 * Meta akan POST message masuk ke sini.
 * GET request untuk verification.
 */
exports.whatsappWebhook = functions.https.onRequest(async (req, res) => {
  // ── GET: Webhook Verification ──
  if (req.method === "GET") {
    const mode = req.query["hub.mode"];
    const token = req.query["hub.verify_token"];
    const challenge = req.query["hub.challenge"];

    if (mode === "subscribe" && token) {
      // Cari dealer yang ada verifyToken ni
      const snap = await db.collection("saas_dealers")
        .where("botWhatsapp.verifyToken", "==", token)
        .limit(1)
        .get();

      if (!snap.empty) {
        console.log("Webhook verified for dealer:", snap.docs[0].id);
        res.status(200).send(challenge);
        return;
      }
    }
    res.status(403).send("Verification failed");
    return;
  }

  // ── POST: Incoming Message ──
  if (req.method === "POST") {
    try {
      const body = req.body;
      const entry = body?.entry?.[0];
      const changes = entry?.changes?.[0];
      const value = changes?.value;

      // Skip kalau bukan messages
      if (!value?.messages || value.messages.length === 0) {
        res.status(200).send("OK");
        return;
      }

      const message = value.messages[0];
      const from = message.from; // no telefon customer (60xxxxxxxxx)
      const msgBody = (message.text?.body || "").trim();
      const phoneNumberId = value.metadata?.phone_number_id;

      if (!phoneNumberId || !from) {
        res.status(200).send("OK");
        return;
      }

      // Cari dealer yang punya phoneNumberId ni
      const dealerSnap = await db.collection("saas_dealers")
        .where("botWhatsapp.phoneNumberId", "==", phoneNumberId)
        .limit(1)
        .get();

      if (dealerSnap.empty) {
        console.log("No dealer found for phoneNumberId:", phoneNumberId);
        res.status(200).send("OK");
        return;
      }

      const dealerDoc = dealerSnap.docs[0];
      const dealer = dealerDoc.data();
      const dealerId = dealerDoc.id;
      const bot = dealer.botWhatsapp || {};

      // Check bot aktif
      if (bot.status !== "AKTIF") {
        res.status(200).send("OK");
        return;
      }

      const accessToken = bot.accessToken;
      const greeting = bot.greeting || "Sila hantar nombor telefon anda untuk semak status repair.";
      const notFoundMsg = bot.notFound || "Maaf, tiada rekod repair dijumpai untuk nombor ini.";

      // Detect kalau customer hantar nombor telefon
      const cleanNum = msgBody.replace(/[\s\-\+\(\)]/g, "");
      const isPhoneNumber = /^(60|0)\d{9,11}$/.test(cleanNum);

      if (isPhoneNumber) {
        // Normalize — pastikan format 60xxxxxxxxx
        let searchNum = cleanNum;
        if (searchNum.startsWith("0")) {
          searchNum = "60" + searchNum.substring(1);
        }
        // Also prepare 0xx format for matching
        const searchNum0 = "0" + searchNum.substring(2);

        // Cari dalam semua shops dealer ni
        const shopsSnap = await db.collection("shops_" + dealerId).get();
        let foundJobs = [];

        for (const shopDoc of shopsSnap.docs) {
          const shopId = shopDoc.id;
          // Cari dalam jobs collection — match no telefon atau no backup
          const jobsSnap = await db.collection("shops_" + dealerId)
            .doc(shopId)
            .collection("jobs")
            .where("status", "!=", "Selesai Diambil")
            .get();

          for (const jobDoc of jobsSnap.docs) {
            const job = jobDoc.data();
            const custPhone = (job.noTelefon || "").replace(/[\s\-\+\(\)]/g, "");
            const backupPhone = (job.noBackup || "").replace(/[\s\-\+\(\)]/g, "");

            // Normalize for comparison
            const normCust = custPhone.startsWith("0") ? "60" + custPhone.substring(1) : custPhone;
            const normBackup = backupPhone.startsWith("0") ? "60" + backupPhone.substring(1) : backupPhone;

            if (normCust === searchNum || normBackup === searchNum ||
                custPhone === searchNum0 || backupPhone === searchNum0) {
              foundJobs.push({
                id: jobDoc.id,
                jenisPeranti: job.jenisPeranti || job.model || "-",
                masalah: job.masalah || job.kerosakan || "-",
                status: job.status || "-",
                shopName: shopDoc.data().shopName || shopId,
              });
            }
          }
        }

        let replyText;
        if (foundJobs.length > 0) {
          replyText = `✅ *Rekod Repair Dijumpai*\n\n`;
          for (let i = 0; i < foundJobs.length; i++) {
            const j = foundJobs[i];
            replyText += `*${i + 1}. ${j.jenisPeranti}*\n`;
            replyText += `   Masalah: ${j.masalah}\n`;
            replyText += `   Status: *${j.status}*\n`;
            replyText += `   ID: ${j.id}\n\n`;
          }
          replyText += `Terima kasih. Hubungi kedai untuk maklumat lanjut.`;
        } else {
          replyText = notFoundMsg;
        }

        await sendWhatsAppMessage(phoneNumberId, accessToken, from, replyText);
      } else {
        // Bukan nombor telefon — hantar greeting
        await sendWhatsAppMessage(phoneNumberId, accessToken, from, greeting);
      }

      res.status(200).send("OK");
    } catch (error) {
      console.error("Webhook error:", error);
      res.status(200).send("OK"); // Always return 200 to Meta
    }
    return;
  }

  res.status(405).send("Method not allowed");
});

/**
 * Helper: Hantar mesej WhatsApp via Cloud API
 */
async function sendWhatsAppMessage(phoneNumberId, accessToken, to, text) {
  const url = `https://graph.facebook.com/v21.0/${phoneNumberId}/messages`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      messaging_product: "whatsapp",
      to: to,
      type: "text",
      text: { body: text },
    }),
  });

  const result = await response.json();
  if (!response.ok) {
    console.error("WhatsApp send error:", JSON.stringify(result));
  }
  return result;
}

// ═══════════════════════════════════════════════════════════
// PUSH NOTIFICATION — BOOKING
// ═══════════════════════════════════════════════════════════

/**
 * sendBookingNotification
 * Dipanggil dari Flutter app selepas booking baru disimpan.
 * Hantar push notification ke semua device yang login branch tu.
 */
exports.sendBookingNotification = functions.https.onRequest(async (req, res) => {
  res.set("Access-Control-Allow-Origin", "*");
  res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.set("Access-Control-Allow-Headers", "Content-Type");
  if (req.method === "OPTIONS") { res.status(204).send(""); return; }

  const { ownerID, shopID, customerName, item, siriBooking } = req.body || {};

  if (!ownerID || !shopID) {
    res.status(400).json({ error: "ownerID dan shopID diperlukan." });
    return;
  }

  try {
    const branchID = `${ownerID}@${shopID}`;

    // Cari semua FCM token untuk branch ni
    const tokensSnap = await db
      .collection("fcm_tokens")
      .where("branchID", "==", branchID)
      .get();

    if (tokensSnap.empty) {
      res.json({ success: true, sent: 0, message: "Tiada device berdaftar untuk branch ini." });
      return;
    }

    const tokens = [];
    tokensSnap.forEach((doc) => {
      const t = doc.data().token;
      if (t) tokens.push(t);
    });

    if (tokens.length === 0) {
      res.json({ success: true, sent: 0 });
      return;
    }

    // Hantar notification ke semua device
    const message = {
      notification: {
        title: "📱 Booking Baru!",
        body: `${customerName || "Customer"} — ${item || "Item"} (${siriBooking || ""})`,
      },
      data: {
        type: "booking",
        ownerID: ownerID,
        shopID: shopID,
        siriBooking: siriBooking || "",
      },
    };

    const response = await admin.messaging().sendEachForMulticast({
      tokens: tokens,
      notification: message.notification,
      data: message.data,
    });

    // Cleanup invalid tokens
    const tokensToDelete = [];
    response.responses.forEach((resp, idx) => {
      if (!resp.success) {
        const errCode = resp.error?.code;
        if (
          errCode === "messaging/invalid-registration-token" ||
          errCode === "messaging/registration-token-not-registered"
        ) {
          tokensToDelete.push(tokens[idx]);
        }
      }
    });

    // Delete invalid tokens dari Firestore
    const batch = db.batch();
    for (const t of tokensToDelete) {
      batch.delete(db.collection("fcm_tokens").doc(t));
    }
    if (tokensToDelete.length > 0) await batch.commit();

    res.json({
      success: true,
      sent: response.successCount,
      failed: response.failureCount,
      cleaned: tokensToDelete.length,
    });
  } catch (error) {
    console.error("sendBookingNotification error:", error);
    res.status(500).json({ error: error.message });
  }
});

/**
 * Helper: Extract DNS records from Firebase Hosting API response
 */
function extractDnsRecords(result) {
  const records = [];

  // Required DNS records dari response
  if (result.requiredDnsUpdates && result.requiredDnsUpdates.desired) {
    for (const record of result.requiredDnsUpdates.desired) {
      records.push({
        type: record.type || "A",
        host: record.domainName || "@",
        value: record.rrdatas ? record.rrdatas.join(", ") : "",
      });
    }
  }

  // Fallback — standard Firebase Hosting IPs
  if (records.length === 0) {
    records.push(
      { type: "A", host: "@", value: "199.36.158.100" },
      { type: "TXT", host: "@", value: "hosting-site=" + SITE_ID }
    );
  }

  return records;
}

// ═══════════════════════════════════════════════════════════
// EMAIL TRIGGER — replikasi Firebase Extension "Trigger Email"
// ═══════════════════════════════════════════════════════════

const nodemailer = require("nodemailer");

let _mailTransporter = null;
function getMailTransporter() {
  if (_mailTransporter) return _mailTransporter;
  _mailTransporter = nodemailer.createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: {
      user: process.env.GMAIL_EMAIL,
      pass: process.env.GMAIL_PASSWORD,
    },
  });
  return _mailTransporter;
}

/**
 * sendMailTrigger
 * Listen collection `mail/{docId}` — bila ada doc baru, hantar emel.
 * Format doc sama dengan Firebase Extension "Trigger Email":
 *   { to, message: { subject, html, text } }
 * Status update balik ke doc: delivery.state = SUCCESS / ERROR
 */
exports.sendMailTrigger = functions
  .runWith({ secrets: ["GMAIL_EMAIL", "GMAIL_PASSWORD", "GMAIL_FROM"] })
  .firestore
  .document("mail/{docId}")
  .onCreate(async (snap, context) => {
    const data = snap.data() || {};
    const to = data.to;
    const message = data.message || {};

    if (!to || (!message.html && !message.text)) {
      await snap.ref.set(
        { delivery: { state: "ERROR", error: "Missing 'to' or 'message'", attempts: 1, endTime: admin.firestore.FieldValue.serverTimestamp() } },
        { merge: true }
      );
      return;
    }

    try {
      const fromAddr = process.env.GMAIL_FROM || `RMS Pro <${process.env.GMAIL_EMAIL}>`;

      const info = await getMailTransporter().sendMail({
        from: fromAddr,
        to: Array.isArray(to) ? to.join(", ") : String(to),
        subject: message.subject || "(no subject)",
        html: message.html || undefined,
        text: message.text || undefined,
      });

      await snap.ref.set(
        {
          delivery: {
            state: "SUCCESS",
            attempts: 1,
            messageId: info.messageId || null,
            endTime: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    } catch (error) {
      console.error("sendMailTrigger error:", error);
      await snap.ref.set(
        {
          delivery: {
            state: "ERROR",
            attempts: 1,
            error: String(error.message || error),
            endTime: admin.firestore.FieldValue.serverTimestamp(),
          },
        },
        { merge: true }
      );
    }
  });

// ═══════════════════════════════════════════════════════════════════
// MARKETPLACE STATS AGGREGATION
// Maintains marketplace_summary/stats doc incrementally so admin
// dashboard reads 1 doc instead of scanning all orders.
// ═══════════════════════════════════════════════════════════════════
exports.onMarketplaceOrderWrite = functions.firestore
  .document("marketplace_orders/{orderId}")
  .onWrite(async (change, context) => {
    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    const beforeStatus = before ? before.status || "" : "";
    const afterStatus = after ? after.status || "" : "";
    if (beforeStatus === afterStatus && before && after) return null;

    const ref = db.collection("marketplace_summary").doc("stats");
    const inc = admin.firestore.FieldValue.increment;

    const updates = {};
    const total = after ? Number(after.totalPrice || 0) : 0;
    const commission = after ? Number(after.commission || 0) : 0;
    const prevTotal = before ? Number(before.totalPrice || 0) : 0;
    const prevCommission = before ? Number(before.commission || 0) : 0;

    if (beforeStatus === "completed" && afterStatus !== "completed") {
      updates.totalGMV = inc(-prevTotal);
      updates.totalCommission = inc(-prevCommission);
      updates.completedOrders = inc(-1);
    }
    if (afterStatus === "completed" && beforeStatus !== "completed") {
      updates.totalGMV = inc(total);
      updates.totalCommission = inc(commission);
      updates.completedOrders = inc(1);
    }
    const wasActive = ["paid", "shipped"].includes(beforeStatus);
    const isActive = ["paid", "shipped"].includes(afterStatus);
    if (wasActive && !isActive) updates.activeOrders = inc(-1);
    if (!wasActive && isActive) updates.activeOrders = inc(1);

    if (Object.keys(updates).length > 0) {
      await ref.set(updates, { merge: true });
    }
    return null;
  });

// Nightly refresh of listings + sellers count (cheaper than per-write)
exports.refreshMarketplaceCounts = functions.pubsub
  .schedule("every 24 hours")
  .onRun(async () => {
    const products = await db
      .collection("marketplace_global")
      .where("isActive", "==", true)
      .count()
      .get();
    const shops = await db.collection("marketplace_shops").count().get();
    await db.collection("marketplace_summary").doc("stats").set(
      {
        activeListings: products.data().count,
        activeSellers: shops.data().count,
        refreshedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return null;
  });

// ═══════════════════════════════════════════════════════════════════
// PER-DEALER SALES AGGREGATION
// Trigger on any repairs_* doc write. Maintains totalSales + ticketCount
// on saas_dealers/{ownerID} so admin dashboard avoids N+1 scans.
// Path uses a single wildcard {collection} matching `repairs_<ownerID>`.
// ═══════════════════════════════════════════════════════════════════
exports.onRepairWrite = functions.firestore
  .document("{collection}/{docId}")
  .onWrite(async (change, context) => {
    const collection = context.params.collection;
    if (!collection.startsWith("repairs_")) return null;
    const ownerID = collection.substring("repairs_".length);
    if (!ownerID) return null;

    const before = change.before.exists ? change.before.data() : null;
    const after = change.after.exists ? change.after.data() : null;

    const paidBefore = before && before.payment_status === "PAID";
    const paidAfter = after && after.payment_status === "PAID";
    if (!paidBefore && !paidAfter) return null;

    const amountOf = (d) =>
      parseFloat(String(d.totalCharges ?? d.total ?? "0")) || 0;

    const prev = paidBefore ? amountOf(before) : 0;
    const curr = paidAfter ? amountOf(after) : 0;
    const delta = curr - prev;
    const countDelta =
      (paidAfter ? 1 : 0) - (paidBefore ? 1 : 0);

    if (delta === 0 && countDelta === 0) return null;

    await db.collection("saas_dealers").doc(ownerID).set(
      {
        totalSales: admin.firestore.FieldValue.increment(delta),
        ticketCount: admin.firestore.FieldValue.increment(countDelta),
        lastSaleAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true }
    );
    return null;
  });

// ═══════════════════════════════════════════════════════════════════
// CLEANUP UNBOUNDED COLLECTIONS
// Runs daily. Deletes old docs to prevent unbounded growth.
// ═══════════════════════════════════════════════════════════════════
async function deleteOlderThan(collectionName, dateField, days) {
  const cutoff = admin.firestore.Timestamp.fromMillis(
    Date.now() - days * 24 * 60 * 60 * 1000
  );
  let deleted = 0;
  while (true) {
    const snap = await db
      .collection(collectionName)
      .where(dateField, "<", cutoff)
      .limit(300)
      .get();
    if (snap.empty) break;
    const batch = db.batch();
    snap.docs.forEach((d) => batch.delete(d.ref));
    await batch.commit();
    deleted += snap.size;
    if (snap.size < 300) break;
  }
  return deleted;
}

exports.dailyCleanup = functions.pubsub
  .schedule("every 24 hours")
  .timeZone("Asia/Kuala_Lumpur")
  .onRun(async () => {
    const results = {};
    try {
      results.mail = await deleteOlderThan("mail", "delivery.endTime", 30);
    } catch (e) { results.mailError = String(e.message || e); }
    try {
      results.aduan = await deleteOlderThan("aduan_sistem", "createdAt", 90);
    } catch (e) { results.aduanError = String(e.message || e); }
    try {
      results.feedback = await deleteOlderThan("app_feedback", "createdAt", 180);
    } catch (e) { results.feedbackError = String(e.message || e); }
    try {
      results.notifications = await deleteOlderThan(
        "marketplace_notifications",
        "createdAt",
        60
      );
    } catch (e) { results.notifError = String(e.message || e); }

    await db.collection("system_logs").doc("cleanup").set(
      {
        lastRun: admin.firestore.FieldValue.serverTimestamp(),
        results,
      },
      { merge: true }
    );
    return null;
  });
