#Requires -Version 5.1
<#
  OpenCode Portable - backup housekeeping

  Every snapshot in data\backups is a full copy (sessions are ~350 MB, an
  OpenCode app backup is ~600 MB), so an unbounded history fills the stick.
  Policy: keep the newest snapshot of each prefix and delete the rest.
#>

function Remove-OldBackups {
    param(
        [string] $BackupDir,
        [string] $Prefix,
        [int]    $Keep = 1
    )
    $removed = @()
    if (-not (Test-Path -LiteralPath $BackupDir)) { return $removed }

    $dirs = @(Get-ChildItem -LiteralPath $BackupDir -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like "$Prefix*" } |
              Sort-Object Name -Descending)   # names are timestamped: newest first

    if ($dirs.Count -le $Keep) { return $removed }

    foreach ($d in ($dirs | Select-Object -Skip $Keep)) {
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $d.FullName)) { $removed += $d.FullName }
    }
    return $removed
}
