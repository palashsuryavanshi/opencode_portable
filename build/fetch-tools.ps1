<#
  OpenCode Portable - tool fetcher
  Downloads the portable-friendly (ZIP / archive) builds of every tool.
  No installers are used, because installers write to the host machine.
#>
param(
  [string]$Root = "D:\VIBECODINGPROJECTS\OpenCode Portable"
)
$ErrorActionPreference = 'Continue'
$dl = Join-Path $Root 'downloads'
New-Item -ItemType Directory -Force -Path $dl | Out-Null

function Get-Latest {
  $o = [ordered]@{}
  $node = Invoke-RestMethod 'https://nodejs.org/dist/index.json'
  $n = $node | Where-Object { $_.lts -and $_.files -contains 'win-x64-zip' } | Select-Object -First 1
  $o['node']  = "https://nodejs.org/dist/$($n.version)/node-$($n.version)-win-x64.zip"
  $o['nodev'] = $n.version

  $go = Invoke-RestMethod 'https://go.dev/dl/?mode=json'
  $g = $go[0].files | Where-Object { $_.os -eq 'windows' -and $_.arch -eq 'amd64' -and $_.kind -eq 'archive' } | Select-Object -First 1
  $o['go']  = "https://go.dev/dl/$($g.filename)"
  $o['gov'] = $go[0].version

  $jdk = Invoke-RestMethod 'https://api.adoptium.net/v3/assets/latest/21/hotspot?architecture=x64&image_type=jdk&os=windows&vendor=eclipse'
  $o['jdk'] = $jdk[0].binary.package.link

  $o['vscode'] = 'https://update.code.visualstudio.com/latest/win32-x64-archive/stable'

  $rel = Invoke-RestMethod 'https://api.github.com/repos/git-for-windows/git/releases/latest' -Headers @{ 'User-Agent' = 'ps' }
  $ga = $rel.assets | Where-Object { $_.name -match 'PortableGit.*64-bit\.7z\.exe$' } | Select-Object -First 1
  $o['git'] = $ga.browser_download_url

  $xml = Invoke-WebRequest 'https://dl.google.com/android/repository/repository2-3.xml' -UseBasicParsing
  $m = [regex]::Match($xml.Content, 'commandlinetools-win-(\d+)_latest\.zip')
  $o['androidcmd'] = "https://dl.google.com/android/repository/commandlinetools-win-$($m.Groups[1].Value)_latest.zip"

  $h = Invoke-WebRequest 'https://dlcdn.apache.org/maven/maven-3/' -UseBasicParsing
  $v = ([regex]::Matches($h.Content, '3\.\d+\.\d+') | ForEach-Object { $_.Value } | Sort-Object -Unique -Descending | Select-Object -First 1)
  $o['maven'] = "https://dlcdn.apache.org/maven/maven-3/$v/binaries/apache-maven-$v-bin.zip"

  return $o
}

$L = Get-Latest
$L.GetEnumerator() | ForEach-Object { "RESOLVED {0,-9} {1}" -f $_.Key, $_.Value }

$targets = @(
  @{ key = 'vscode';    file = 'vscode.zip' },
  @{ key = 'jdk';       file = 'jdk.zip' },
  @{ key = 'git';       file = 'portablegit.exe' },
  @{ key = 'node';      file = 'node.zip' },
  @{ key = 'go';        file = 'go.zip' },
  @{ key = 'androidcmd';file = 'androidcmd.zip' },
  @{ key = 'maven';     file = 'maven.zip' }
)

$jobs = foreach ($t in $targets) {
  $url = $L[$t.key]
  $dest = Join-Path $dl $t.file
  Start-Job -Name $t.key -ArgumentList $url, $dest -ScriptBlock {
    param($u, $d)
    try {
      $ProgressPreference = 'SilentlyContinue'
      Invoke-WebRequest -Uri $u -OutFile $d -UseBasicParsing -TimeoutSec 3600
      "OK $d"
    } catch {
      "FAIL $u :: $($_.Exception.Message)"
    }
  }
}

$jobs | Wait-Job | Receive-Job
$jobs | Remove-Job
"DOWNLOADS DONE"
