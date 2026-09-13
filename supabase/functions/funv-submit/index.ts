// ============================================================
// 婦女再就業補助報名：funv-apply.html 的送出端點
// 收 multipart/form-data → 兩張身分證存進私有 bucket funv-ids → 其餘欄位寫進 funv_applications。
// 不寄信、不打 LINE：通知一律人工處理（公司規則「人決定、AI 執行」）。
//
// 部署設定：Verify JWT = OFF（報名表沒有登入，前端只帶 anon key）
// 部署前先在 Supabase SQL Editor 跑 supabase/sql/funv_applications.sql（建表 + 建 bucket），
// 再執行：supabase functions deploy funv-submit
// （SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY 是系統內建的 Secret，不用自己填）
// ============================================================
import { createClient } from "npm:@supabase/supabase-js@2";

const SB_URL  = Deno.env.get("SUPABASE_URL")!;
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const BUCKET  = "funv-ids";
const MAX_BYTES = 10 * 1024 * 1024;
const RATE_LIMIT = 5;          // 同一個 IP
const RATE_WINDOW_MIN = 10;    // 10 分鐘內最多 5 次

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const J = (o: unknown, s = 200) =>
  new Response(JSON.stringify(o), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// 單選／簡答欄位（對應表單第 1～30 題，多選題另外處理）
const TEXT_FIELDS = [
  "labor_insurance", "name", "line_id", "id_number", "birthday", "mobile", "address", "email",
  "education", "skills", "last_company", "last_title", "leave_reason", "work_start", "work_end",
  "referrer", "course_choice", "course_reason", "target_job", "job_relevance",
  "family_care", "job_search", "commute_pref", "work_hours", "transport",
];
// 表單上沒有星號的三題：專長、理想工時、交通工具
const OPTIONAL = new Set(["skills", "work_hours", "transport"]);
const MULTI_FIELDS = ["after_training", "self_improvement"];

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return J({ ok: false, error: "method not allowed" }, 405);

  try {
    const ip = (req.headers.get("x-forwarded-for") || "").split(",")[0].trim() || "unknown";
    const ua = (req.headers.get("user-agent") || "").slice(0, 500);
    const admin = createClient(SB_URL, SERVICE);

    // ── 同一個 IP 10 分鐘內最多 5 次 ──
    const since = new Date(Date.now() - RATE_WINDOW_MIN * 60 * 1000).toISOString();
    const { count } = await admin.from("funv_applications")
      .select("id", { count: "exact", head: true })
      .eq("ip", ip).gte("created_at", since);
    if ((count ?? 0) >= RATE_LIMIT) return J({ ok: false, error: "太頻繁了，請稍後再試" }, 429);

    const fd = await req.formData();

    // ── honeypot：真人看不到這個欄位，有值就是機器人 ──
    if (String(fd.get("website") || "").trim() !== "") return J({ ok: false, error: "提交失敗" }, 400);

    const row: Record<string, unknown> = {};
    for (const key of TEXT_FIELDS) {
      const v = String(fd.get(key) ?? "").trim();
      if (!v && !OPTIONAL.has(key)) return J({ ok: false, error: `缺少必填欄位：${key}` }, 400);
      row[key] = v || null;
    }
    for (const key of MULTI_FIELDS) {
      const v = fd.getAll(key).map((x) => String(x).trim()).filter(Boolean);
      if (!v.length) return J({ ok: false, error: `缺少必填欄位：${key}` }, 400);
      row[key] = v;
    }
    if (String(fd.get("confirm") || "") !== "是") return J({ ok: false, error: "缺少必填欄位：confirm" }, 400);
    row.confirmed = true;

    const id_number = String(row.id_number || "").toUpperCase();
    if (!validTwId(id_number)) return J({ ok: false, error: "身分證字號格式不正確" }, 400);
    row.id_number = id_number;

    if (!/^09\d{8}$/.test(String(row.mobile || "").replace(/[\s-]/g, "")))
      return J({ ok: false, error: "手機號碼格式不正確" }, 400);
    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(String(row.email || "")))
      return J({ ok: false, error: "電子信箱格式不正確" }, 400);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(String(row.birthday || "")))
      return J({ ok: false, error: "生日格式不正確" }, 400);

    const front = fd.get("id_front");
    const back  = fd.get("id_back");
    for (const [label, f] of [["身分證正面", front], ["身分證背面", back]] as [string, unknown][]) {
      if (!(f instanceof File) || f.size === 0) return J({ ok: false, error: `請上傳${label}照片` }, 400);
      if (!f.type.startsWith("image/")) return J({ ok: false, error: `${label}請上傳圖片檔` }, 400);
      if (f.size > MAX_BYTES) return J({ ok: false, error: `${label}超過 10MB` }, 400);
    }

    // ── 先產 id，兩張圖放在 <申請id>/ 底下，再連同路徑寫進資料表 ──
    const id = crypto.randomUUID();
    for (const [name, f] of [["front", front as File], ["back", back as File]] as [string, File][]) {
      const { error } = await admin.storage.from(BUCKET)
        .upload(`${id}/${name}.jpg`, f, { contentType: f.type || "image/jpeg", upsert: true });
      if (error) return J({ ok: false, error: "照片上傳失敗：" + error.message }, 500);
    }

    row.id = id;
    row.id_front_path = `${id}/front.jpg`;
    row.id_back_path  = `${id}/back.jpg`;
    row.ip = ip;
    row.user_agent = ua;

    const { error: insErr } = await admin.from("funv_applications").insert(row);
    if (insErr) return J({ ok: false, error: "寫入失敗：" + insErr.message }, 500);

    return J({ ok: true, id });
  } catch (e) {
    return J({ ok: false, error: String((e as Error)?.message || e) }, 500);
  }
});

// 台灣身分證字號檢查碼：英文字母換成兩位數，加權 1,9,8,7,6,5,4,3,2,1,1 後除以 10 要整除
function validTwId(s: string): boolean {
  s = s.trim().toUpperCase();
  if (!/^[A-Z][12]\d{8}$/.test(s)) return false;
  const map = "ABCDEFGHJKLMNPQRSTUVXYWZIO";
  const n = map.indexOf(s.charAt(0)) + 10;
  if (n < 10) return false;
  let sum = Math.floor(n / 10) + (n % 10) * 9;
  for (let i = 1; i <= 8; i++) sum += Number(s.charAt(i)) * (9 - i);
  sum += Number(s.charAt(9));
  return sum % 10 === 0;
}
