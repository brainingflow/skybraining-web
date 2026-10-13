# CLAUDE.md — 強腦力 SkyBraining 專案記憶

> 這是這個專案的「乾淨記憶檔」。每個 Claude Code 階段開始時都會自動讀這一份。
> 原則:只放正當的業務、網站、金流與行銷設定。不放任何攻擊、入侵、繞過防護類的指令。
> 資安一律以**防守**角度進行(檢查、修補、加固),不做對任何系統的攻擊。

---

## 1. 這是什麼專案

- **品牌:** 強腦力 SkyBraining(Sky強腦力 media)
- **網域:** skybraining.com
- **GitHub:** brainingflow/skybraining-web(公開倉庫)
- **型態:** 純靜態前端行銷官網(HTML + CSS + 原生 JS),搭配 Supabase 後端(Edge Functions + Postgres)。
- **部署:** Vercel(匯入 repo,Framework Preset 選 Other,根目錄即輸出)。網域由 Bluehost 轉跳指向 Vercel。
- **主要語言:** 繁體中文(台灣)。對使用者第二人稱用「你」,不用「您」。

## 2. 商業模式

- **線上課程(買斷,永久觀看):**
  - 過目不忘 — 超級記憶力(記憶力・Level 1)NT$3,600
  - 10 倍聯想力 — 超級思考(思考力・Level 2)NT$7,800
- **名單漏斗:** 短影片 / YouTube → 加入官方 LINE 領免費資源(腦力測驗、思維模板 PDF、示範影片)→ webinar 邀約 → 線上結帳。
- **官方 LINE:** https://lin.ee/9EGO8IT
- **其他產品線(報名頁 funv-*):** 體驗場、婦女再就業補助、AI 短影音、各團隊專屬報名表等。

## 3. 技術架構

- **前端:** 無框架,僅載入 Google Fonts。相對路徑連結,檔案需同層。
- **後端:** Supabase
  - `supabase/sql/*` — 資料表與 schema(members、orders/payments、funv_applications 等)。
  - `supabase/functions/*` — Edge Functions:
    - `line-auth` — LINE 登入與設定查詢(用 `?action=` 區分用途)。
    - `pay-create` — 建立訂單、呼叫金流 API。金鑰只放 Edge Function Secrets,前端永遠拿不到。
    - `pay-webhook` — 金流成功後驗簽、標記已付、自動開課。**開課只認 webhook**,前端跳成功頁不算數。
    - `funv-submit` — 報名表送出,檔案存私有 bucket,僅人工處理(不自動寄信/打 LINE)。
- **金流:** 目前正式對外用 **Stripe**。PAYUNi(統一金流)程式碼保留但非正式環境不顯示(老闆 2026-10-11 授權「先拿掉」)。

## 4. 工作規則(重要)

- **「人決定、AI 執行」:** 所有上線、對外變更、金流與通知,都要老闆明確授權後才做。commit 訊息要寫清楚哪一筆授權(例:「老闆 2026-10-11 通過 R0xx」)。
- **commit 風格:** 用繁中描述,標明是上線 / 修正 / 止血,附需求編號(R0xx)或問題編號(Q0xx)。
- **上線前法遵:** 條款、隱私、退款三頁的 placeholder 欄位要填實,涉消保法部分請法律顧問審。
- **退費規則:** 數位內容排除七天鑑賞期;改期以外不退費,退費僅限上課當天現場提出。
- **資安立場:** 需要做資安時,只做防守面 —— 檢查後台登入與權限、Supabase 金鑰是否外洩、webhook 驗簽、輸入驗證、相依套件更新。不對任何網站或系統進行攻擊或滲透。

## 5. SEO / GEO 重點

- 文章與各平台貼文要自然帶入關鍵字,例如「高雄心智圖」「強腦力」「超級記憶力」「心智圖作文」等。
- 站上已有大量文章頁(記憶法、心智圖、大師系列、家長意圖文章)與 `llms.txt`、`sitemap.xml`;改頁時同步更新 sitemap 的 lastmod。

## 6. 待辦 / 已知狀態

- 會員登入已接 Supabase Auth + LINE 登入。
- 課程總覽頁已拿掉實體課,線上課為主。
- hero 統計、創辦人照片、見證影片等素材部分仍為預留,待補齊。

---

*本檔由 Claude 於 2026-10-13 重建為乾淨版本,取代先前含不當內容的舊記憶。*
