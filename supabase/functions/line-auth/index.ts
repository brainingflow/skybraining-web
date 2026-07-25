// ============================================================
// 強腦力 — Supabase Edge Function: line-auth
//
// 一支函式三種用途（用 ?action= 區分）：
//   ?action=config                     → 前端問「LINE 設定好了沒」
//   ?action=start&mode=bind|login&...  → 產生 LINE 授權網址
//   ?action=callback  (POST)           → 拿 code 換身分，綁定 or 登入
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

    // 2-3B 登入：用 LINE userId 找回這個人，再發一次性登入 token
    const { data: look, error: le } = await admin.rpc("member_lookup_line", { p_line_user_id: sub });
    if (le) return json({ ok: false, reason: "lookup_failed", message: le.message });
    if (!look || look.ok !== true) {
      return json({ ok: false, reason: look?.reason ?? "not_bound", line: { name, picture } });
    }

    const { data: link, error: ge } = await admin.auth.admin.generateLink({
      type: "magiclink", email: look.email,
    });
    if (ge || !link?.properties?.hashed_token) {
      return json({ ok: false, reason: "link_failed", message: ge?.message ?? "no token" });
    }
    return json({
      ok: true, mode: "login",
      email: look.email, member_no: look.member_no,
      token_hash: link.properties.hashed_token,
      line: { name, picture },
    });
  }

  return json({ ok: false, reason: "unknown_action" }, 400);
});
