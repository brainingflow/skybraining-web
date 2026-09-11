# G 槽整理提案（內部作業文件，不會部署到網站）

強腦力 G:\ 的資料夾架構提案、檔名規則，以及兩支 PowerShell 腳本。

- `dist/強腦力G槽整理提案.html` — 提案頁，直接用瀏覽器打開
- `dist/01_scan_G.bat` / `.ps1` — 盤點 G:\（只讀取，不搬移、不刪除）
- `dist/02_create_folders.bat` / `.ps1` — 建立空資料夾架構（已存在的跳過，不動現有檔案）
- `dist/_資料夾說明.txt` — 建立架構時會放到 G:\ 根目錄的一頁說明

## 改名稱、改架構

資料夾架構的唯一來源是 `structure.py`。改完後執行：

```
python3 build.py
```

會同步重新產生 `dist/` 裡的提案頁、兩支腳本和說明檔（`build.py` 會把輸出寫到它所在目錄的 `dist/`）。

`docs/` 已加進 `.vercelignore`，不會隨網站部署。
