// ============================================================
// 強腦力金流：建立訂單 + 呼叫金流 API（Stripe / 統一金流 PAYUNi）
// 金鑰全部來自 Edge Function Secrets，前端永遠拿不到。
// 部署設定：Verify JWT = OFF（本函式自行驗證使用者 JWT；config 查詢不需登入）
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const STRIPE_KEY = Deno.env.get("STRIPE_SECRET_KEY") || "";
const PAYUNI_MER = Deno.env.get("PAYUNI_MER_ID") || "";
const PAYUNI_KEY = Deno.env.get("PAYUNI_HASH_KEY") || "";
const PAYUNI_IV  = Deno.env.get("PAYUNI_HASH_IV") || "";
const PAYUNI_ENV = Deno.env.get("PAYUNI_ENV") || "sandbox";
const SITE = "https://skybraining.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = new URL(req.url);

  // 前端查詢哪些金流已開通（不需登入）
  if (url.searchParams.get("action") === "config") {
    return J({ ok: true, stripe: !!STRIPE_KEY, payuni: !!(PAYUNI_MER && PAYUNI_KEY && PAYUNI_IV), payuni_env: PAYUNI_ENV });
  }

  try {
    // ── 驗證使用者 ──
    const jwt = (req.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    if (!jwt) return J({ ok: false, error: "請先登入" }, 401);
    const admin = createClient(SB_URL, SERVICE);
    const { data: { user }, error: uErr } = await admin.auth.getUser(jwt);
    if (uErr || !user) return J({ ok: false, error: "登入狀態失效，請重新登入" }, 401);

    const { course_id, provider } = await req.json();
    if (!course_id || !provider) return J({ ok: false, error: "缺少參數" }, 400);

    // ── 價格永遠以資料庫為準（不信前端）──
    const { data: course } = await admin.from("courses").select("*").eq("id", course_id).maybeSingle();
    if (!course || !course.is_published) return J({ ok: false, error: "找不到這門課程" }, 404);
    if (course.category === "career") return J({ ok: false, error: "此課程採 LINE 洽詢報名" }, 400);
    const price = course.price;
    if (price == null || price <= 0) return J({ ok: false, error: "此課程免費，直接開通即可" }, 400);

    // 已擁有就不重複收費
    const { data: owned } = await admin.from("enrollments").select("id")
      .eq("user_id", user.id).eq("course_id", course_id).maybeSingle();
    if (owned) return J({ ok: false, error: "你已經擁有這門課程了，直接去上課吧！" }, 400);

    // ── 建立訂單（pending）──
    const { data: order, error: oErr } = await admin.from("orders").insert({
      user_id: user.id, course_id, amount: price, currency: "TWD", provider, status: "pending",
    }).select("*").single();
    if (oErr) return J({ ok: false, error: "建立訂單失敗：" + oErr.message }, 500);

    // ── Stripe Checkout ──
    if (provider === "stripe") {
      if (!STRIPE_KEY) return J({ ok: false, error: "Stripe 尚未開通（金鑰未設定）" }, 503);
      const f = new URLSearchParams();
      f.set("mode", "payment");
      f.set("client_reference_id", order.id);
      f.set("success_url", `${SITE}/success.html?order=${order.id}`);
      f.set("cancel_url", `${SITE}/checkout.html?course=${encodeURIComponent(course_id)}&canceled=1`);
      f.set("line_items[0][quantity]", "1");
      f.set("line_items[0][price_data][currency]", "twd");
      f.set("line_items[0][price_data][unit_amount]", String(price * 100)); // TWD 需可被 100 整除
      f.set("line_items[0][price_data][product_data][name]", course.name);
      if (course.subtitle) f.set("line_items[0][price_data][product_data][description]", course.subtitle);
      f.set("metadata[order_id]", order.id);
      f.set("metadata[course_id]", course_id);
      f.set("metadata[user_id]", user.id);
      if (user.email) f.set("customer_email", user.email);
      const r = await fetch("https://api.stripe.com/v1/checkout/sessions", {
        method: "POST",
        headers: { "Authorization": "Bearer " + STRIPE_KEY, "Content-Type": "application/x-www-form-urlencoded" },
        body: f.toString(),
      });
      const j = await r.json();
      if (!r.ok) {
        await admin.from("orders").update({ status: "failed" }).eq("id", order.id);
        return J({ ok: false, error: "Stripe 建立失敗：" + (j?.error?.message || r.status) }, 502);
      }
      await admin.from("orders").update({ provider_order_id: j.id }).eq("id", order.id);
      return J({ ok: true, redirect: j.url });
    }

    // ── 統一金流 PAYUNi（UPP 幕前支付）──
    if (provider === "payuni") {
      if (!(PAYUNI_MER && PAYUNI_KEY && PAYUNI_IV)) return J({ ok: false, error: "統一金流尚未開通（商店代號申請中）" }, 503);
      const tradeNo = ("SB" + order.id.replace(/-/g, "").slice(0, 18)).toUpperCase(); // ≤25 碼、[A-Za-z0-9_-]
      const ts = Math.floor(Date.now() / 1000);
      // PAYUNi 明文用 querystring 格式；空白必須是 %20（不是 +），所以不能用 URLSearchParams.toString()
      const fields: Record<string, string> = {
        MerID: PAYUNI_MER,
        MerTradeNo: tradeNo,
        TradeAmt: String(price),
        Timestamp: String(ts),
        ProdDesc: String(course.name || "").slice(0, 550),
        UsrMail: user.email || "",
        ReturnURL: `${SITE}/success.html?order=${order.id}`,
        NotifyURL: `${SB_URL}/functions/v1/pay-webhook?provider=payuni`, // 僅限 80 / 443 port
        BackURL: `${SITE}/checkout.html?course=${course_id}&canceled=1`,
        Lang: "zh-tw",
      };
      const plain = Object.entries(fields).filter(([, v]) => v !== "")
        .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`).join("&");
      const enc = await aesGcmEncryptHex(plain, PAYUNI_KEY, PAYUNI_IV);
      const hash = (await sha256Hex(PAYUNI_KEY + enc + PAYUNI_IV)).toUpperCase();
      await admin.from("orders").update({ provider_order_id: tradeNo }).eq("id", order.id);
      const endpoint = PAYUNI_ENV === "prod"
        ? "https://api.payuni.com.tw/api/upp"
        : "https://sandbox-api.payuni.com.tw/api/upp";
      // UPP Ver 2.0：外層只送 MerID / Version / EncryptInfo / HashInfo，Version 固定 "2.0"
      return J({ ok: true, form: { action: endpoint, fields: { MerID: PAYUNI_MER, Version: "2.0", EncryptInfo: enc, HashInfo: hash } } });
    }

    return J({ ok: false, error: "未知付款方式" }, 400);
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
// PAYUNi：AES-256-GCM
// ⚠️ 官方格式 = hex( base64(密文) + ":::" + base64(tag) )
//    也就是「整串 ASCII 字串再做一次 hex」，不是 hex(密文):::hex(tag)。
//    對照官方 Node 範例：Buffer.from(`${cipherText}:::${tag}`).toString("hex")
async function aesGcmEncryptHex(plain: string, key: string, iv: string): Promise<string> {
  const k = await crypto.subtle.importKey("raw", new TextEncoder().encode(key), "AES-GCM", false, ["encrypt"]);
  const out = new Uint8Array(await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: new TextEncoder().encode(iv), tagLength: 128 }, k, new TextEncoder().encode(plain)));
  const body = out.slice(0, out.length - 16), tag = out.slice(out.length - 16);
  const b64 = (a: Uint8Array) => { let s = ""; for (const b of a) s += String.fromCharCode(b); return btoa(s); };
  const joined = `${b64(body)}:::${b64(tag)}`;
  return [...new TextEncoder().encode(joined)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
