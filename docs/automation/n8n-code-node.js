// n8n Code node — mode "Run Once for All Items", language JavaScript.
// Put it right after the Webhook node that receives TuitMate events. Every
// output item is { event, id, sent_at, source, payload, verified }; route on
// `event` with a Switch node.
//
// Key: set the environment variable TUITMATE_KEY on your n8n server (the base64
// key from TuitMate › Profile › Automation), or replace $env.TUITMATE_KEY below
// with the key in quotes (only in a private workflow).
// Self-hosted n8n must allow the crypto module: NODE_FUNCTION_ALLOW_BUILTIN=crypto
const crypto = require('crypto');

const keyText = String($env.TUITMATE_KEY || '').replace(/\s+/g, '');
const KEY = /^[0-9a-fA-F]{64}$/.test(keyText)
  ? Buffer.from(keyText, 'hex')
  : Buffer.from(keyText.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
if (KEY.length !== 32) throw new Error('TUITMATE_KEY must be the 32-byte AES-256 key (base64)');

return $input.all().map((item) => {
  const env = item.json.body || item.json; // Webhook node puts the JSON body under "body"
  if (env.v !== 1) throw new Error('Not a TuitMate event');
  let opened;
  let verified;
  if (env.enc === 'A256GCM') {
    // AES-256-GCM authenticates the payload and the readable fields (AAD).
    const data = Buffer.from(env.data, 'base64');
    const decipher = crypto.createDecipheriv('aes-256-gcm', KEY, Buffer.from(env.iv, 'base64'));
    decipher.setAAD(Buffer.from(`tuitmate.v1|${env.id}|${env.event}|${env.sent_at}`, 'utf8'));
    decipher.setAuthTag(data.subarray(data.length - 16));
    opened = JSON.parse(Buffer.concat([decipher.update(data.subarray(0, data.length - 16)), decipher.final()]).toString('utf8'));
    verified = true;
  } else {
    // Plain mode: check the HMAC signature. Exact only when the body has no
    // decimal numbers; for a byte-exact check enable "Raw Body" on the Webhook node.
    const header = (item.json.headers || {})['x-tuitmate-signature'] || '';
    const expected = 'sha256=' + crypto.createHmac('sha256', KEY).update(JSON.stringify(env), 'utf8').digest('hex');
    verified = header.length === expected.length && crypto.timingSafeEqual(Buffer.from(header), Buffer.from(expected));
    opened = { v: 1, id: env.id, event: env.event, sent_at: env.sent_at, payload: env.payload };
  }
  return { json: { event: opened.event, id: opened.id, sent_at: opened.sent_at, source: env.source, payload: opened.payload, verified } };
});
