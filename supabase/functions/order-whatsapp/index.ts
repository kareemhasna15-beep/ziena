// supabase/functions/order-whatsapp/index.ts
//
// Deploy-ready owner WhatsApp notification.
//
// Invoked by an AFTER INSERT trigger on `orders` (via pg_net — see
// supabase_task28_order_whatsapp_webhook.sql). Builds a plain-text summary
// of the order and posts it to the owner's WhatsApp number through the Meta
// WhatsApp Cloud API.
//
// SECRETS (set once via `supabase secrets set` — see the deploy checklist
// in the repo's Task-1 summary):
//   WHATSAPP_TOKEN     — Meta Business system-user access token (long-lived)
//   WHATSAPP_PHONE_ID  — the WhatsApp phone_number_id from Meta Business
//   OWNER_WA_NUMBER    — the owner's WhatsApp number in E.164 without '+'
//                        (e.g. 96181830202)
//   WEBHOOK_SECRET     — (optional) shared secret. If set, the trigger MUST
//                        send it in the X-Webhook-Secret header. Recommended.
//
// The function is intentionally forgiving: if any secret is missing it
// responds 500 (so the trigger row lands in the pg_net error log without
// silently succeeding). If Meta's API returns a 4xx/5xx the response body
// includes Meta's error text so you can debug from the Supabase function logs.

// deno-lint-ignore-file no-explicit-any
import { serve } from 'https://deno.land/std@0.203.0/http/server.ts';

const WHATSAPP_TOKEN    = Deno.env.get('WHATSAPP_TOKEN');
const WHATSAPP_PHONE_ID = Deno.env.get('WHATSAPP_PHONE_ID');
const OWNER_WA_NUMBER   = Deno.env.get('OWNER_WA_NUMBER');
const WEBHOOK_SECRET    = Deno.env.get('WEBHOOK_SECRET') || '';

/* Meta Cloud API endpoint. v18.0 is current-stable at the time of writing;
   bump if Meta deprecates it. */
const META_URL = (phoneId: string) =>
  `https://graph.facebook.com/v18.0/${phoneId}/messages`;

function moneyUsd(v: any): string {
  const n = Number(v);
  return isFinite(n) ? '$' + n.toFixed(2) : 'TBD';
}

function buildText(order: any): string {
  const lines: string[] = [];
  lines.push(`🛎 *New order #${order.id}*`);
  lines.push('');
  if (order.name)     lines.push(`👤 ${order.name}`);
  if (order.phone)    lines.push(`📞 ${order.phone}`);
  if (order.city)     lines.push(`🏙 ${order.city}`);
  if (order.address)  lines.push(`📍 ${order.address}`);
  if (order.note)     lines.push(`📝 ${order.note}`);
  lines.push('');
  const items = Array.isArray(order.items) ? order.items : [];
  if (items.length) {
    lines.push('*Items:*');
    for (const it of items) {
      const name = it?.name || 'item';
      const qty  = it?.qty || 1;
      const tbd  = it?.tbd === true || it?.unit == null;
      const unit = tbd ? 'TBD' : moneyUsd(it?.unit);
      lines.push(`• ${qty} × ${name} — ${unit}`);
    }
    lines.push('');
  }
  if (order.delivery_fee_usd != null) {
    lines.push(`🚚 Delivery: ${moneyUsd(order.delivery_fee_usd)}`);
  }
  lines.push(`💰 *Total: ${moneyUsd(order.total)}*`);
  return lines.join('\n');
}

serve(async (req) => {
  if (req.method !== 'POST') {
    return new Response('POST only', { status: 405 });
  }

  /* Optional shared-secret gate. When configured, this makes it safe to
     deploy the function with `--no-verify-jwt` (i.e. public) because
     nobody without the secret can trigger it. */
  if (WEBHOOK_SECRET) {
    const sig = req.headers.get('X-Webhook-Secret');
    if (sig !== WEBHOOK_SECRET) {
      return new Response(JSON.stringify({ ok: false, error: 'unauthorized' }), {
        status: 401, headers: { 'Content-Type': 'application/json' }
      });
    }
  }

  if (!WHATSAPP_TOKEN || !WHATSAPP_PHONE_ID || !OWNER_WA_NUMBER) {
    return new Response(JSON.stringify({
      ok: false,
      error: 'missing secrets',
      required: ['WHATSAPP_TOKEN', 'WHATSAPP_PHONE_ID', 'OWNER_WA_NUMBER']
    }), { status: 500, headers: { 'Content-Type': 'application/json' } });
  }

  let payload: any;
  try {
    payload = await req.json();
  } catch (_) {
    return new Response('invalid json', { status: 400 });
  }

  /* Payload shape from the pg_net trigger:
       { type: 'INSERT', table: 'orders', record: { ... } }
     Some Supabase environments also POST { record: {...} } directly — accept
     either. */
  const order = payload?.record || payload?.new || payload;
  if (!order || !order.id) {
    return new Response('no order record', { status: 400 });
  }

  const text = buildText(order);

  const r = await fetch(META_URL(WHATSAPP_PHONE_ID), {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${WHATSAPP_TOKEN}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      messaging_product: 'whatsapp',
      to: OWNER_WA_NUMBER,
      type: 'text',
      text: { body: text, preview_url: false }
    })
  });
  const metaBody = await r.text();

  return new Response(JSON.stringify({
    ok: r.ok,
    meta_status: r.status,
    meta_body: metaBody,
    text_length: text.length
  }), {
    status: r.ok ? 200 : 502,
    headers: { 'Content-Type': 'application/json' }
  });
});
