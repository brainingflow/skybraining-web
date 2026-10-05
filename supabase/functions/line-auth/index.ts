// ============================================================
// 強腦力 — Supabase Edge Function: line-auth
//
// 一支函式三種用途（用 ?action= 區分）：
//   ?action=config                     → 前端問「LINE 設定好了沒」
//   ?action=start&mode=bind|login&...  → 產生 LINE 授權網址
//   ?action=callback  (POST)           → 拿 code 換身分，綁定 or 登入
//                                        （登入時沒綁過的 LINE 會自動建會員並綁定，回 is_new: true）
//
// 部署前先在 SQL Editor 跑 supabase/sql/2026-10-05_line_signup.sql（LINE 註冊用的兩個函式）。
//
// 需要的 Secrets（在 Supabase → Edge Functions → Secrets 設定）：
//   LINE_CHANNEL_ID       LINE Developers → 你的 Login Channel → Channel ID
//   LINE_CHANNEL_SECRET   同一頁的 Channel secret
//   （SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 是系統內建，不用自己填）
//
// 部署設定：Verify JWT 請「關閉」（登入模式下使用者還沒有 token）。
//           安全性由 LINE 的 authorization code + 下面的驗證負責。
// ============================================================

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CH_ID     = Deno.env.get("LINE_CHANNEL_ID") ?? "";
const CH_SECRET = Deno.env.get("LINE_CHANNEL_SECRET") ?? "";
const SB_URL    = Deno.env.get("SUPABASE_URL") ?? "";
const SB_KEY    = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
// LINE 沒給 Email 時開佔位信箱用的網域：用自己的網域，信才不會落到別人手上
const PLACEHOLDER_DOMAIN = "members.skybraining.com";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json; charset=utf-8" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const url    = new URL(req.url);
  const action = url.searchParams.get("action") ?? "config";

  // ── 0) 前端探測：LINE 到底設定好了沒 ──────────────────────
  if (action === "config") {
    return json({ ok: true, ready: Boolean(CH_ID && CH_SECRET) });
  }

  if (!CH_ID || !CH_SECRET) {
    return json({ ok: false, reason: "not_configured",
                  message: "LINE Channel ID / Channel Secret 還沒填到 Supabase Secrets" });
  }

  // ── 1) 產生 LINE 授權網址 ─────────────────────────────────
  if (action === "start") {
    const mode     = url.searchParams.get("mode") === "login" ? "login" : "bind";
    const redirect = url.searchParams.get("redirect_uri") ?? "";
    if (!redirect) return json({ ok: false, reason: "no_redirect" }, 400);

    const nonce = crypto.randomUUID().replace(/-/g, "");
    const state = `${mode}.${nonce}`;
    const a = new URL("https://access.line.me/oauth2/v2.1/authorize");
    a.searchParams.set("response_type", "code");
    a.searchParams.set("client_id", CH_ID);
    a.searchParams.set("redirect_uri", redirect);
    a.searchParams.set("state", state);
    a.searchParams.set("scope", "profile openid email");
    return json({ ok: true, url: a.toString(), state });
  }

  // ── 2) 回呼：拿 code 換 LINE 身分，然後綁定 or 登入 ────────
  if (action === "callback" && req.method === "POST") {
    const body: Record<string, string> = await req.json().catch(() => ({}));
    const code     = body.code ?? "";
    const redirect = body.redirect_uri ?? "";
    const mode     = body.mode === "login" ? "login" : "bind";
    if (!code || !redirect) return json({ ok: false, reason: "bad_request" }, 400);

    // 2-1 code → access_token / id_token（這一步一定要 Channel Secret，所以必須在後端）
    const tokRes = await fetch("https://api.line.me/oauth2/v2.1/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "authorization_code",
        code, redirect_uri: redirect,
        client_id: CH_ID, client_secret: CH_SECRET,
      }),
    });
    const tok = await tokRes.json().catch(() => ({}));
    if (!tokRes.ok || !tok.access_token) {
      return json({ ok: false, reason: "line_token_failed", detail: tok });
    }

    // 2-2 驗證 id_token（LINE 官方驗證端點）→ 取得 userId / 名稱 / 頭像 / Email
    let sub = "", name = "", picture = "", email = "";
    if (tok.id_token) {
      const vRes = await fetch("https://api.line.me/oauth2/v2.1/verify", {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ id_token: tok.id_token, client_id: CH_ID }),
      });
      const v = await vRes.json().catch(() => ({}));
      if (vRes.ok) {
        sub = v.sub ?? ""; name = v.name ?? ""; picture = v.picture ?? ""; email = v.email ?? "";
      }
    }
    // id_token 沒給就退回 profile API（LINE 沒開 email 權限時很常見）
    if (!sub) {
      const pRes = await fetch("https://api.line.me/v2/profile", {
        headers: { Authorization: `Bearer ${tok.access_token}` },
      });
      const p = await pRes.json().catch(() => ({}));
      if (pRes.ok) {
        sub = p.userId ?? ""; name = p.displayName ?? name; picture = p.pictureUrl ?? picture;
      }
    }
    if (!sub) return json({ ok: false, reason: "no_line_user" });

    const admin = createClient(SB_URL, SB_KEY, { auth: { persistSession: false } });

    // 2-3A 綁定：使用者已經登入，把 LINE 掛到他的會員編號上
    if (mode === "bind") {
      const auth = req.headers.get("Authorization") ?? "";
      const jwt  = auth.startsWith("Bearer ") ? auth.slice(7) : "";
      if (!jwt) return json({ ok: false, reason: "no_session" });
      const { data: u, error: ue } = await admin.auth.getUser(jwt);
      if (ue || !u?.user) return json({ ok: false, reason: "bad_session" });

      const { data, error } = await admin.rpc("member_bind_line", {
        p_user_id:      u.user.id,
        p_line_user_id: sub,
        p_display_name: name,
        p_picture_url:  picture,
        p_email:        email,
      });
      if (error) return json({ ok: false, reason: "bind_failed", message: error.message });
      return json({ ok: true, mode: "bind", result: data, line: { name, picture } });
    }

    // 2-3B 登入：用 LINE userId 找回這個人；沒綁過就當新朋友，自動建會員並綁這個 LINE，
    //       再發一次性登入 token
    const { data: look, error: le } = await admin.rpc("member_lookup_line", { p_line_user_id: sub });
    if (le) return json({ ok: false, reason: "lookup_failed", message: le.message });

    let who: { email: string; member_no: string; is_new: boolean };
    if (look && look.ok === true) {
      who = { email: look.email, member_no: look.member_no, is_new: false };
    } else if ((look?.reason ?? "not_bound") === "not_bound") {
      const su = await signUpWithLine(admin, { sub, name, picture, email });
      if (!su.ok) return json({ ok: false, reason: su.reason, message: su.message, line: { name, picture } });
      who = { email: su.email, member_no: su.member_no, is_new: su.created };
    } else {
      return json({ ok: false, reason: look.reason, line: { name, picture } });
    }

    const { data: link, error: ge } = await admin.auth.admin.generateLink({
      type: "magiclink", email: who.email,
    });
    if (ge || !link?.properties?.hashed_token) {
      return json({ ok: false, reason: "link_failed", message: ge?.message ?? "no token" });
    }
    return json({
      ok: true, mode: "login", is_new: who.is_new,
      email: who.email, member_no: who.member_no,
      token_hash: link.properties.hashed_token,
      line: { name, picture },
    });
  }

  return json({ ok: false, reason: "unknown_action" }, 400);
});

type SignUp =
  | { ok: true; created: boolean; email: string; member_no: string }
  | { ok: false; reason: string; message?: string };

// LINE 新朋友註冊。同一個 LINE 永遠算出同一個記號、同一個佔位信箱，所以重送或兩個分頁同時回來
// 都只會有一個帳號：auth 的 Email 不能重複，member_line 的 line_user_id 是主鍵。
// created 只在「這次 createUser 真的開出新帳號、而且這次真的綁上」時為 true：解除綁定後再登入、接續先前建到一半的帳號、
// 同時另一個請求先建好、剛建好就被別的會員綁走，都不算新註冊（GA 的 sign_up 才不會多算）。
async function signUpWithLine(
  // deno-lint-ignore no-explicit-any
  admin: any,
  p: { sub: string; name: string; picture: string; email: string },
): Promise<SignUp> {
  const marker = (await sha256Hex("line-signup:" + p.sub)).slice(0, 24);
  const raw = p.email.trim().toLowerCase();
  const lineEmail = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(raw) ? raw : "";
  const placeholder = !lineEmail;
  const target = lineEmail || `line_${marker}@${PLACEHOLDER_DOMAIN}`;
  // LINE 的 Email 已經是別的會員在用：不搶，前端請他用 Email／Google 登入後再綁 LINE
  const taken: SignUp = { ok: false, reason: placeholder ? "signup_conflict" : "email_taken" };
  const owner = () => admin.rpc("member_line_email_owner", { p_email: target, p_marker: marker });

  let { data: o, error: oe } = await owner();
  // 後台還沒跑 2026-10-05_line_signup.sql：照舊回 not_bound，不要變成看不懂的錯誤
  if (oe && isMissingFn(oe)) return { ok: false, reason: "not_bound" };
  if (oe) return { ok: false, reason: "signup_failed", message: oe.message };

  let uid = "";
  let createdNow = false;
  if (o?.exists) {
    if (!o.line_owned) return taken;
    uid = o.user_id;
  } else {
    const { data: cu, error: ce } = await admin.auth.admin.createUser({
      email: target,
      email_confirm: true,
      user_metadata: { display_name: p.name || undefined, avatar_url: p.picture || undefined },
      app_metadata: { line_signup: marker },
    });
    if (cu?.user?.id) {
      uid = cu.user.id;
      createdNow = true;
    } else {
      // 多半是同一個 LINE 的另一個請求剛建好，或這個 Email 剛好被別人註冊走
      ({ data: o, error: oe } = await owner());
      if (!oe && o?.exists && o.line_owned) uid = o.user_id;
      else if (!oe && o?.exists) return taken;
      else return { ok: false, reason: "signup_failed", message: ce?.message ?? oe?.message };
    }
  }

  const { data: b, error: be } = await admin.rpc("member_line_signup", {
    p_user_id: uid, p_line_user_id: p.sub, p_marker: marker,
    p_display_name: p.name, p_picture_url: p.picture,
    p_email: lineEmail || null, p_email_placeholder: placeholder,
  });
  if (be || !b?.ok || !b.email) {
    return { ok: false, reason: "signup_failed", message: be?.message ?? b?.reason };
  }
  return { ok: true, created: createdNow && b.created === true, email: b.email, member_no: b.member_no };
}

function isMissingFn(e: { code?: string; message?: string }) {
  return e.code === "PGRST202" || e.code === "42883" || /could not find the function/i.test(e.message ?? "");
}

async function sha256Hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}
