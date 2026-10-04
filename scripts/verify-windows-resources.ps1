param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [int]$DurationSeconds = 120,
    [string]$ReportPath
)
$ErrorActionPreference = 'Stop'
if ($DurationSeconds -lt 30) { throw 'Observe at least 30 seconds after warm-up.' }
$exe = (Resolve-Path -LiteralPath $Executable).Path
$app = Start-Process -FilePath $exe -WorkingDirectory (Split-Path $exe) -WindowStyle Hidden -PassThru
$samples = [Collections.Generic.List[object]]::new()
try {
    if ($app.WaitForExit(10000)) { throw 'App exited during warm-up.' }
    for ($second = 0; $second -le $DurationSeconds; $second++) {
        $app.Refresh()
        if ($app.HasExited) { throw 'App exited during resource observation.' }
        $samples.Add([pscustomobject]@{
            Seconds = $second
            PrivateMB = [math]::Round($app.PrivateMemorySize64 / 1MB, 2)
            WorkingMB = [math]::Round($app.WorkingSet64 / 1MB, 2)
            Threads = $app.Threads.Count
            Handles = $app.HandleCount
        })
        if ($second -lt $DurationSeconds) { Start-Sleep -Seconds 1 }
    }
    if ($ReportPath) {
        $samples | ConvertTo-Json | Set-Content -LiteralPath $ReportPath -Encoding utf8
    }
    $first = $samples[0]
    $last = $samples[$samples.Count - 1]
    $summary = [pscustomobject]@{
        Seconds = $DurationSeconds
        StartPrivateMB = $first.PrivateMB
        EndPrivateMB = $last.PrivateMB
        StartThreads = $first.Threads
        EndThreads = $last.Threads
        StartHandles = $first.Handles
        EndHandles = $last.Handles
    }
    $summary | ConvertTo-Json -Compress | Write-Output
    # Allow engine warm-up/caches, but reject the prior per-poll resource leak.
    if ($last.Threads - $first.Threads -gt 20) { throw 'Thread count is accumulating.' }
    if ($last.Handles - $first.Handles -gt 100) { throw 'Handle count is accumulating.' }
    if ($last.PrivateMB - $first.PrivateMB -gt 96) { throw 'Private memory is accumulating.' }
} finally {
    $app.Refresh()
    if (-not $app.HasExited) { Stop-Process -Id $app.Id }
}
