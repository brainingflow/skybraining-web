// ============================================================
// 強腦力金流 webhook：付款成功 → 驗證簽章 → 標記訂單已付 → 自動開課
// 開課「只認」這裡——使用者自己跳回成功頁不算數，偽造不了。
// 部署設定：Verify JWT = OFF（金流伺服器呼叫時不帶 Supabase JWT）
// Stripe 端設定：Dashboard → Developers → Webhooks → 新增端點
//   URL: https://gfuqizxzihgydzyqywun.supabase.co/functions/v1/pay-webhook?provider=stripe
//   事件: checkout.session.completed, checkout.session.async_payment_succeeded
//   把 Signing secret（whsec_…）存到 Edge Function Secrets 的 STRIPE_WEBHOOK_SECRET
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_WH  = Deno.env.get("STRIPE_WEBHOOK_SECRET") || "";
const PAYUNI_KEY = Deno.env.get("PAYUNI_HASH_KEY") || "";
const PAYUNI_IV  = Deno.env.get("PAYUNI_HASH_IV") || "";

Deno.serve(async (req) => {
  const url = new URL(req.url);
  const provider = url.searchParams.get("provider") || "stripe";
  const admin = createClient(SB_URL, SERVICE);

  // ───────────────────────── Stripe ─────────────────────────
  if (provider === "stripe") {
    if (!STRIPE_WH) return new Response("webhook secret not set", { status: 503 });
    const payload = await req.text();
    const sig = req.headers.get("stripe-signature") || "";
    if (!(await verifyStripeSig(payload, sig, STRIPE_WH))) {
      return new Response("bad signature", { status: 400 });
    }
    const evt = JSON.parse(payload);
    if (evt.type === "checkout.session.completed" || evt.type === "checkout.session.async_payment_succeeded") {
      const s = evt.data.object;
      if (s.payment_status === "paid") {
        const orderId = s.metadata?.order_id || s.client_reference_id;
        if (orderId) await settle(admin, orderId, s.id, "stripe");
      }
    }
    return new Response(JSON.stringify({ received: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // ──────────────────── 統一金流 PAYUNi ─────────────────────
  if (provider === "payuni") {
    if (!(PAYUNI_KEY && PAYUNI_IV)) return new Response("payuni not configured", { status: 503 });
    try {
      const ct = req.headers.get("content-type") || "";
      let enc = "", hash = "";
      if (ct.includes("application/json")) {
        const b = await req.json(); enc = b.EncryptInfo || ""; hash = b.HashInfo || "";
      } else {
        const b = await req.formData(); enc = String(b.get("EncryptInfo") || ""); hash = String(b.get("HashInfo") || "");
      }
      // 驗雜湊
      const expect = (await sha256Hex(PAYUNI_KEY + enc + PAYUNI_IV)).toUpperCase();
      if (!enc || expect !== hash.toUpperCase()) return new Response("bad hash", { status: 400 });
      // 解密取結果
      const plain = await aesGcmDecryptHex(enc, PAYUNI_KEY, PAYUNI_IV);
      const q = new URLSearchParams(plain);
      const status  = (q.get("Status") || "").toUpperCase();
      const tradeNo = q.get("MerTradeNo") || "";
      const uniNo   = q.get("TradeNo") || "";
      if (status === "SUCCESS" && tradeNo) {
        const { data: order } = await admin.from("orders").select("*").eq("provider_order_id", tradeNo).maybeSingle();
        if (order) await settle(admin, order.id, uniNo || tradeNo, "payuni");
      }
      return new Response("SUCCESS", { status: 200 });
    } catch (_e) {
      return new Response("error", { status: 400 });
    }
  }

  return new Response("unknown provider", { status: 400 });
});

// 標記已付 + 幂等開課
async function settle(admin: ReturnType<typeof createClient>, orderId: string, ref: string, src: string) {
  const { data: order } = await admin.from("orders").select("*").eq("id", orderId).maybeSingle();
  if (!order) return;
  if (order.status !== "paid") {
    await admin.from("orders").update({
      status: "paid", paid_at: new Date().toISOString(),
      provider_order_id: ref || order.provider_order_id,
    }).eq("id", orderId);
  }
  if (order.user_id && order.course_id) {
    const { data: en } = await admin.from("enrollments").select("id")
      .eq("user_id", order.user_id).eq("course_id", order.course_id).maybeSingle();
    if (!en) {
      await admin.from("enrollments").insert({ user_id: order.user_id, course_id: order.course_id, source: src });
    }
  }
}

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
// Stripe 簽章：v1 = HMAC-SHA256(`${t}.${payload}`, secret)，10 分鐘時間窗
async function verifyStripeSig(payload: string, sigHeader: string, secret: string): Promise<boolean> {
  const parts = sigHeader.split(",").map((p) => p.trim());
  const t = (parts.find((p) => p.startsWith("t=")) || "").slice(2);
  const v1s = parts.filter((p) => p.startsWith("v1=")).map((p) => p.slice(3));
  if (!t || !v1s.length) return false;
  if (Math.abs(Date.now() / 1000 - Number(t)) > 600) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(t + "." + payload));
  const hex = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, "0")).join("");
  return v1s.includes(hex);
}
async function aesGcmDecryptHex(encStr: string, key: string, iv: string): Promise<string> {
  const [bodyHex, tagHex] = encStr.split(":::");
  const un = (h: string) => new Uint8Array((h.match(/../g) || []).map((x) => parseInt(x, 16)));
  const body = un(bodyHex), tag = un(tagHex || "");
  const buf = new Uint8Array(body.length + tag.length); buf.set(body); buf.set(tag, body.length);
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), "AES-GCM", false, ["decrypt"]);
  const pt = await crypto.subtle.decrypt({ name: "AES-GCM", iv: new TextEncoder().encode(iv), tagLength: 128 }, k, buf);
  return new TextDecoder().decode(pt);
}
