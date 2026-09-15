# 部署說明：匯款帳簿封面照片上傳（2026-09-15）

給總指揮在 Supabase Dashboard 做，只有兩步，順序不能反。

1. **Supabase → SQL Editor** → 開新查詢 → 貼上 `網頁專案/supabase/sql/2026-09-15_passbook.sql` 全部內容 → 按 Run。（只加一個欄位，可重複執行，不會刪資料。）
2. **Supabase → Edge Functions → funv-submit** → 把 `網頁專案/supabase/functions/funv-submit/index.ts` 的最新內容整份貼進去覆蓋 → 按 Deploy（或本機用 `supabase functions deploy funv-submit`）。（Verify JWT 維持原本的 OFF，這次沒有改權限設定，不用重設。）
