# 強腦力 SkyBraining 官網（前端 MVP）

專業腦力訓練與思維方法課程平台的行銷官網。目前為**純靜態前端**（HTML + CSS + 原生 JS），可直接部署到 Vercel / Netlify / GitHub Pages，或作為後續 Next.js 站台的設計基礎。

## 頁面

| 檔案 | 說明 |
|------|------|
| `index.html` | 官網首頁：品牌訴求、學習路徑、兩堂課程、LINE 免費資源區塊、浮動 LINE 按鈕 |
| `terms.html` | 服務條款（含數位內容授權、七天鑑賞期排除） |
| `privacy.html` | 隱私權政策（個資法、第三方服務揭露、未成年保護） |
| `refund.html` | 退款政策（七天鑑賞期排除、例外退款、電子發票折讓） |

## 課程

- **過目不忘 — 超級記憶力**（記憶力・Level 1）NT$3,600　買斷・永久觀看
- **10倍聯想力 — 超級思考**（思考力・Level 2）NT$7,800　買斷・永久觀看

## 名單漏斗

短影片 / YouTube → 加入 LINE 官方帳號領免費資源（腦力測驗 / 思維模板 PDF / 示範影片）→ webinar 邀約 → 綠界結帳。
LINE 官方帳號：https://lin.ee/9EGO8IT

## 部署

無須建置，直接部署靜態檔即可。

- **Vercel：** 匯入本 repo，Framework Preset 選 `Other`，Output/Root 為專案根目錄。
- **網域：** skybraining.com（Bluehost 網域轉跳指向 Vercel）。

## 上線前待辦

- [ ] 三頁法遵中標為〔…〕的欄位（公司名稱、統一編號、客服信箱、管轄法院等）填實際資料，並請法律顧問審閱（七天鑑賞期排除涉及消保法）。
- [ ] 首頁「會員登入」目前為佔位連結（`#`），需接 Supabase Auth 才能真正登入。
- [ ] hero 統計、創辦人照片、見證影片為預留內容，待素材補齊。
- [ ] 後續完整站台：Next.js（App Router, TypeScript）+ Tailwind + Supabase + 綠界/Stripe 金流 + Vimeo 觀看頁（見專案「網站需求規格」）。

## 技術備註

- 無外部框架，僅載入 Google Fonts。
- 無使用 localStorage / 後端 / 資料庫。
- LINE 連結、頁尾法遵連結、返回鍵皆為相對路徑，四個檔需放在同一層。
