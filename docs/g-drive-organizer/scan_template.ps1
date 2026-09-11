<#
  01_scan_G.ps1  —  盤點 G 槽（只讀取，不搬移、不刪除、不改名）

  執行方式：對同一個資料夾裡的 01_scan_G.bat 按兩下即可。
  結果會存到桌面兩個檔案：
    G槽盤點_日期時間.txt   給人看的摘要（資料夾樹、副檔名、最大檔案、重複檔名…）
    G槽盤點_日期時間.csv   完整清單，傳給 Claude 做搬移對照表用
  進階：想直接指定路徑可執行
    powershell -NoProfile -ExecutionPolicy Bypass -File .\01_scan_G.ps1 -Root "G:\我的雲端硬碟"
#>
param(
  [string]$Root,
  [string]$OutDir = [Environment]::GetFolderPath('Desktop'),
  [int]$Depth = 3,
  [int]$TopN = 60
)

$ErrorActionPreference = 'SilentlyContinue'
$utf8bom = New-Object System.Text.UTF8Encoding($true)

if (-not $PSBoundParameters.ContainsKey('Root')) {
  Write-Host ''
  Write-Host '=== 強腦力 G 槽盤點（只讀取，不會更動任何檔案）===' -ForegroundColor Cyan
  $answer = Read-Host '要盤點的根目錄？直接按 Enter 就用 G:\ （如果是 Google Drive，也可以填 G:\我的雲端硬碟）'
  $Root = if ([string]::IsNullOrWhiteSpace($answer)) { 'G:\' } else { $answer.Trim().Trim('"') }
}

if (-not (Test-Path -LiteralPath $Root)) {
  Write-Host "找不到 $Root ，請確認磁碟代號或路徑後再試一次。" -ForegroundColor Red
  exit 1
}

$rootFull = (Get-Item -LiteralPath $Root).FullName
if (-not $rootFull.EndsWith('\')) { $rootFull += '\' }

$stamp   = Get-Date -Format 'yyyy-MM-dd_HHmm'
$txtPath = Join-Path $OutDir ("G槽盤點_{0}.txt" -f $stamp)
$csvPath = Join-Path $OutDir ("G槽盤點_{0}.csv" -f $stamp)

# 系統或同步工具自己的資料夾，跳過不算
$skipTop = @('$RECYCLE.BIN', 'System Volume Information', '.tmp.drivedownload', '.tmp.driveupload', '.Trash', 'found.000', '.shortcut-targets-by-id')

Write-Host ''
Write-Host "開始盤點：$rootFull" -ForegroundColor Cyan
Write-Host '只讀取資料夾與檔名，不會更動任何檔案。檔案很多的話要等一下，請不要關掉視窗。'
$sw = [System.Diagnostics.Stopwatch]::StartNew()

$rows = New-Object 'System.Collections.Generic.List[object]'
$count = 0
$readErrors = @()

Get-ChildItem -LiteralPath $Root -Recurse -File -ErrorAction SilentlyContinue -ErrorVariable +readErrors |
  ForEach-Object {
    $rel   = $_.FullName.Substring($rootFull.Length)
    $parts = $rel.Split('\')
    $first = if ($parts.Length -gt 1) { $parts[0] } else { '(根目錄散檔)' }
    if ($skipTop -contains $first) { return }
    $count++
    if ($count % 2000 -eq 0) { Write-Progress -Activity '掃描中' -Status ("已讀取 {0:N0} 個檔案" -f $count) }
    $rows.Add([pscustomobject]@{
      相對路徑 = $rel
      第一層   = $first
      第二層   = $(if ($parts.Length -gt 2) { $parts[1] } else { '' })
      檔名     = $_.Name
      副檔名   = $(if ($_.Extension) { $_.Extension.ToLower() } else { '(無副檔名)' })
      大小MB   = [math]::Round($_.Length / 1MB, 2)
      修改日期 = $_.LastWriteTime.ToString('yyyy-MM-dd')
      修改年份 = $_.LastWriteTime.Year
    })
  }
Write-Progress -Activity '掃描中' -Completed

if ($rows.Count -eq 0) {
  Write-Host '這個位置裡沒有讀到任何檔案。' -ForegroundColor Yellow
  exit 0
}

function Format-Size([double]$mb) {
  if ($mb -ge 1024) { return ('{0:N2} GB' -f ($mb / 1024)) }
  if ($mb -ge 1)    { return ('{0:N1} MB' -f $mb) }
  return ('{0:N0} KB' -f ($mb * 1024))
}

# ---- 統計 ----
$totalMB = ($rows | Measure-Object -Property 大小MB -Sum).Sum
$dirCount = (Get-ChildItem -LiteralPath $Root -Recurse -Directory -ErrorAction SilentlyContinue | Where-Object { $skipTop -notcontains $_.FullName.Substring($rootFull.Length).Split('\')[0] } | Measure-Object).Count

# 第一層
$byTop = $rows | Group-Object 第一層 | ForEach-Object {
  $g = $_.Group
  [pscustomobject]@{
    名稱     = $_.Name
    檔案數   = $_.Count
    大小MB   = ($g | Measure-Object -Property 大小MB -Sum).Sum
    最近修改 = ($g | Sort-Object 修改日期 -Descending | Select-Object -First 1).修改日期
  }
} | Sort-Object 大小MB -Descending

# 前幾層的資料夾樹（含空資料夾）
$agg = @{}
Get-ChildItem -LiteralPath $Root -Recurse -Directory -Depth ($Depth - 1) -ErrorAction SilentlyContinue | ForEach-Object {
  $key = $_.FullName.Substring($rootFull.Length)
  if ($skipTop -contains $key.Split('\')[0]) { return }
  $agg[$key] = [pscustomobject]@{ 路徑 = $key; 層 = $key.Split('\').Length; 檔案數 = 0; 大小MB = 0.0; 最近修改 = '' }
}
$rootLoose = 0
foreach ($r in $rows) {
  $parts  = $r.相對路徑.Split('\')
  $levels = $parts.Length - 1
  if ($levels -eq 0) { $rootLoose++; continue }
  $n = [math]::Min($levels, $Depth)
  for ($i = 1; $i -le $n; $i++) {
    $key = [string]::Join('\', $parts[0..($i - 1)])
    if (-not $agg.ContainsKey($key)) { $agg[$key] = [pscustomobject]@{ 路徑 = $key; 層 = $i; 檔案數 = 0; 大小MB = 0.0; 最近修改 = '' } }
    $a = $agg[$key]
    $a.檔案數++
    $a.大小MB += $r.大小MB
    if ($r.修改日期 -gt $a.最近修改) { $a.最近修改 = $r.修改日期 }
  }
}

$byExt   = $rows | Group-Object 副檔名 | ForEach-Object { [pscustomobject]@{ 副檔名 = $_.Name; 檔案數 = $_.Count; 大小MB = ($_.Group | Measure-Object -Property 大小MB -Sum).Sum } } | Sort-Object 檔案數 -Descending
$largest = $rows | Sort-Object 大小MB -Descending | Select-Object -First $TopN
$byYear  = $rows | Group-Object 修改年份 | ForEach-Object { [pscustomobject]@{ 年份 = $_.Name; 檔案數 = $_.Count; 大小MB = ($_.Group | Measure-Object -Property 大小MB -Sum).Sum } } | Sort-Object 年份 -Descending
$dupes   = $rows | Group-Object 檔名 | Where-Object { $_.Count -gt 1 } | Sort-Object Count -Descending | Select-Object -First 40
$messyPattern = '副本|新增資料夾|未命名|\(\d+\)|final|最終|最新|新版|copy|untitled|new folder'
$messy   = $rows | Where-Object { $_.相對路徑 -match $messyPattern }

# ---- 寫 TXT ----
$L = New-Object 'System.Collections.Generic.List[string]'
$L.Add('強腦力 G 槽盤點報告')
$L.Add('=' * 60)
$L.Add("盤點位置：$rootFull")
$L.Add("盤點時間：$(Get-Date -Format 'yyyy-MM-dd HH:mm')")
$L.Add(("檔案總數：{0:N0} 個　資料夾：{1:N0} 個　總大小：{2}" -f $rows.Count, $dirCount, (Format-Size $totalMB)))
$L.Add(("根目錄散檔：{0:N0} 個（直接放在根目錄、沒進任何資料夾的檔案）" -f $rootLoose))
if ($readErrors.Count -gt 0) { $L.Add(("讀不到的項目：{0:N0} 個（多半是路徑太長或沒有權限）" -f $readErrors.Count)) }
$L.Add(("耗時：{0:N0} 秒" -f $sw.Elapsed.TotalSeconds))
$L.Add('')

$L.Add('一、第一層資料夾（依大小排序）')
$L.Add('-' * 60)
foreach ($t in $byTop) { $L.Add(('{0,-40} {1,8:N0} 個  {2,12}  最近修改 {3}' -f $t.名稱, $t.檔案數, (Format-Size $t.大小MB), $t.最近修改)) }
$L.Add('')

$L.Add(("二、資料夾樹（前 {0} 層；每個資料夾顯示裡面所有檔案的數量與大小）" -f $Depth))
$L.Add('-' * 60)
foreach ($a in ($agg.Values | Sort-Object 路徑)) {
  $indent = '    ' * ($a.層 - 1)
  $leaf   = $a.路徑.Split('\')[-1]
  $L.Add(('{0}{1}    [{2:N0} 個, {3}, 最近 {4}]' -f $indent, $leaf, $a.檔案數, (Format-Size $a.大小MB), $a.最近修改))
}
$L.Add('')

$L.Add('三、副檔名統計（前 30 種）')
$L.Add('-' * 60)
foreach ($e in ($byExt | Select-Object -First 30)) { $L.Add(('{0,-16} {1,8:N0} 個  {2,12}' -f $e.副檔名, $e.檔案數, (Format-Size $e.大小MB))) }
$L.Add('')

$L.Add(("四、最大的 {0} 個檔案" -f $TopN))
$L.Add('-' * 60)
foreach ($f in $largest) { $L.Add(('{0,12}  {1}' -f (Format-Size $f.大小MB), $f.相對路徑)) }
$L.Add('')

$L.Add('五、依修改年份')
$L.Add('-' * 60)
foreach ($y in $byYear) { $L.Add(('{0}  {1,8:N0} 個  {2,12}' -f $y.年份, $y.檔案數, (Format-Size $y.大小MB))) }
$L.Add('')

$L.Add('六、同名檔案出現在不同地方（可能重複，前 40 組）')
$L.Add('-' * 60)
if ($dupes) {
  foreach ($d in $dupes) {
    $L.Add(('{0}  x{1}' -f $d.Name, $d.Count))
    foreach ($g in ($d.Group | Select-Object -First 6)) { $L.Add('      ' + $g.相對路徑) }
  }
} else { $L.Add('（沒有）') }
$L.Add('')

$L.Add(("七、名稱看起來需要整理的檔案（含「副本」「新增資料夾」「未命名」「(1)」「最終」「final」等，共 {0:N0} 個，列前 80 個）" -f ($messy | Measure-Object).Count))
$L.Add('-' * 60)
foreach ($m in ($messy | Select-Object -First 80)) { $L.Add('  ' + $m.相對路徑) }
$L.Add('')
$L.Add('（完整清單在同名的 .csv 檔）')

[System.IO.File]::WriteAllLines($txtPath, [string[]]$L, $utf8bom)

# ---- 寫 CSV ----
$csvLines = $rows | Select-Object 相對路徑, 第一層, 第二層, 檔名, 副檔名, 大小MB, 修改日期 | ConvertTo-Csv -NoTypeInformation
[System.IO.File]::WriteAllLines($csvPath, [string[]]$csvLines, $utf8bom)

Write-Host ''
Write-Host ('盤點完成：{0:N0} 個檔案，{1}，耗時 {2:N0} 秒' -f $rows.Count, (Format-Size $totalMB), $sw.Elapsed.TotalSeconds) -ForegroundColor Green
Write-Host "摘要：$txtPath"
Write-Host "清單：$csvPath"
Write-Host ''
Write-Host '下一步：把桌面上這兩個檔案傳給 Claude，就能產生「現有資料夾 → 新架構」的搬移對照表。' -ForegroundColor Yellow
Invoke-Item $txtPath
