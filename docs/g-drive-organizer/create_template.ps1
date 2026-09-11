<#
  02_create_folders.ps1  —  建立「G 槽整理提案」的空資料夾架構

  只做兩件事：建立空資料夾、在根目錄放一個 _資料夾說明.txt。
  不搬移、不刪除、不改名任何現有檔案；已經存在的資料夾會跳過。
  執行方式：對同一個資料夾裡的 02_create_folders.bat 按兩下。
  進階：只想看會建哪些、先不要真的建：
    powershell -NoProfile -ExecutionPolicy Bypass -File .\02_create_folders.ps1 -Root "G:\" -DryRun
#>
param(
  [string]$Root,
  [switch]$DryRun,
  [switch]$Yes
)

$ErrorActionPreference = 'Stop'
$utf8bom = New-Object System.Text.UTF8Encoding($true)

$folders = @(
__FOLDERS__
)

$readme = @'
__README__
'@

if (-not $PSBoundParameters.ContainsKey('Root')) {
  Write-Host ''
  Write-Host '=== 強腦力 G 槽：建立空資料夾架構 ===' -ForegroundColor Cyan
  $answer = Read-Host '要建在哪裡？直接按 Enter 就用 G:\ （如果是 Google Drive，可以填 G:\我的雲端硬碟）'
  $Root = if ([string]::IsNullOrWhiteSpace($answer)) { 'G:\' } else { $answer.Trim().Trim('"') }
}

if (-not (Test-Path -LiteralPath $Root)) {
  Write-Host "找不到 $Root ，請確認磁碟代號或路徑後再試一次。" -ForegroundColor Red
  exit 1
}
$rootFull = (Get-Item -LiteralPath $Root).FullName

Write-Host ''
Write-Host ("將在 {0} 建立 {1} 個資料夾（已存在的會跳過；不會動到任何現有檔案）" -f $rootFull, $folders.Count)
if ($DryRun) { Write-Host '目前是「只列出、不建立」模式。' -ForegroundColor Yellow }
elseif (-not $Yes) {
  $go = Read-Host '確定要建立嗎？輸入 Y 開始，其他任意鍵取消'
  if ($go -notmatch '^[Yy]') { Write-Host '已取消，什麼都沒有改。'; exit 0 }
}
Write-Host ''

$created = 0; $skipped = 0
foreach ($f in $folders) {
  $path = Join-Path $rootFull $f
  if (Test-Path -LiteralPath $path) {
    $skipped++
    Write-Host ('  [已存在] ' + $f) -ForegroundColor DarkGray
  } else {
    $created++
    if ($DryRun) { Write-Host ('  [會建立] ' + $f) }
    else {
      New-Item -ItemType Directory -Path $path | Out-Null
      Write-Host ('  [已建立] ' + $f) -ForegroundColor Green
    }
  }
}

$readmePath = Join-Path $rootFull '_資料夾說明.txt'
if (-not (Test-Path -LiteralPath $readmePath)) {
  if ($DryRun) { Write-Host '  [會建立] _資料夾說明.txt' }
  else {
    [System.IO.File]::WriteAllText($readmePath, $readme, $utf8bom)
    Write-Host '  [已建立] _資料夾說明.txt' -ForegroundColor Green
  }
} else { Write-Host '  [已存在] _資料夾說明.txt' -ForegroundColor DarkGray }

Write-Host ''
if ($DryRun) { Write-Host ("預覽完成：會建立 {0} 個，已存在 {1} 個。" -f $created, $skipped) -ForegroundColor Yellow }
else {
  Write-Host ("完成：新建 {0} 個資料夾，跳過 {1} 個已存在的。" -f $created, $skipped) -ForegroundColor Green
  Write-Host '現有檔案都還在原位，下一步是照搬移對照表分批搬進去。'
  Invoke-Item $rootFull
}
