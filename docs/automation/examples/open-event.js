// Opens a TuitMate webhook event (Node.js 16+, no packages needed).
//
//   node open-event.js <body.json> [signature-header]      key from env TUITMATE_KEY (base64)
//
// The same code works inside an n8n Code node (see ../n8n-code-node.js).
'use strict';
const crypto = require('crypto');

/** Key: 32 bytes, given as base64 (standard or URL-safe) or 64 hex characters. */
function parseKey(text) {
  const t = String(text || '').replace(/\s+/g, '');
  const key = /^[0-9a-fA-F]{64}$/.test(t) ? Buffer.from(t, 'hex') : Buffer.from(t.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
  if (key.length !== 32) throw new Error('TUITMATE_KEY must be 32 bytes (AES-256)');
  return key;
}

/** True when the X-TuitMate-Signature header matches the raw request body. */
function verifySignature(rawBody, header, key) {
  const expected = 'sha256=' + crypto.createHmac('sha256', key).update(rawBody, 'utf8').digest('hex');
  const a = Buffer.from(String(header || ''));
  const b = Buffer.from(expected);
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

/** Envelope (parsed JSON body) -> { v, id, event, sent_at, payload }. Throws if it was tampered with. */
function openEvent(envelope, key) {
  if (envelope.v !== 1) throw new Error('unknown version ' + envelope.v);
  if (envelope.enc === 'none') {
    return { v: 1, id: envelope.id, event: envelope.event, sent_at: envelope.sent_at, payload: envelope.payload };
  }
  if (envelope.enc !== 'A256GCM') throw new Error('unknown enc ' + envelope.enc);
  const data = Buffer.from(envelope.data, 'base64');
  const decipher = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(envelope.iv, 'base64'));
  decipher.setAAD(Buffer.from(`tuitmate.v1|${envelope.id}|${envelope.event}|${envelope.sent_at}`, 'utf8'));
  decipher.setAuthTag(data.subarray(data.length - 16));
  const clear = Buffer.concat([decipher.update(data.subarray(0, data.length - 16)), decipher.final()]);
  return JSON.parse(clear.toString('utf8'));
}

module.exports = { parseKey, verifySignature, openEvent };

if (require.main === module) {
  const fs = require('fs');
  const raw = fs.readFileSync(process.argv[2], 'utf8');
  const key = parseKey(process.env.TUITMATE_KEY);
  if (process.argv[3] !== undefined && !verifySignature(raw, process.argv[3], key)) {
    console.error('bad signature');
    process.exit(2);
  }
  process.stdout.write(JSON.stringify(openEvent(JSON.parse(raw), key)));
}
