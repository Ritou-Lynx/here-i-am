[Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
$ErrorActionPreference = 'Stop'
# 只读冒烟：确认脚本轮能在本机运行并回帖，不读写任何文件或配置。
$node = Get-Command node -ErrorAction SilentlyContinue
[pscustomobject]@{ step = 'env'; psVersion = $PSVersionTable.PSVersion.ToString(); edition = $PSVersionTable.PSEdition; nodeFound = [bool]$node } | ConvertTo-Json -Compress
[pscustomobject]@{ step = 'utf8'; text = '中文输出正常' } | ConvertTo-Json -Compress
[pscustomobject]@{ step = 'done'; ok = $true } | ConvertTo-Json -Compress
