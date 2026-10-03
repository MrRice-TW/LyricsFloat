param(
    [Parameter(Mandatory = $true)][string]$Installer,
    [Parameter(Mandatory = $true)][string]$TestRoot
)
$ErrorActionPreference = 'Stop'
$installerPath = (Resolve-Path -LiteralPath $Installer).Path
$rootPath = [IO.Path]::GetFullPath($TestRoot)
$registryPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{9248678E-8577-4B21-968C-84032EB63782}_is1'
if (Test-Path -LiteralPath $registryPath) {
    throw 'An existing LyricsFloat installation is registered; use a clean test account.'
}
if (Test-Path -LiteralPath $rootPath) { throw 'TestRoot must be a new directory.' }
$appPath = Join-Path $rootPath 'LyricsFloat-安裝測試'
New-Item -ItemType Directory -Path $rootPath | Out-Null
$arguments = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/TASKS=', '/GROUP="LyricsFloat Installer QA"', ('/DIR="' + $appPath + '"'))
$appProcess = $null
try {
    $install = Start-Process -FilePath $installerPath -ArgumentList $arguments -WindowStyle Hidden -PassThru -Wait
    if ($install.ExitCode -ne 0) { throw "Install failed: $($install.ExitCode)" }
    $exe = Join-Path $appPath 'lyrics_float.exe'
    if (-not (Test-Path -LiteralPath $exe)) { throw 'Installed executable missing.' }
    if (-not (Test-Path -LiteralPath (Join-Path $appPath 'vcruntime140.dll'))) { throw 'MSVC runtime missing.' }
    $initialLocation = (Get-ItemProperty -LiteralPath $registryPath).InstallLocation
    $appProcess = Start-Process -FilePath $exe -WorkingDirectory $appPath -WindowStyle Hidden -PassThru
    if ($appProcess.WaitForExit(10000)) { throw "App exited during startup: $($appProcess.ExitCode)" }
    Stop-Process -Id $appProcess.Id
    $appProcess.WaitForExit()
    $appProcess = $null
    # Omit /DIR on the second install to test recovery of the previous path.
    $upgradeArguments = $arguments | Where-Object { -not $_.StartsWith('/DIR=') }
    $upgrade = Start-Process -FilePath $installerPath -ArgumentList $upgradeArguments -WindowStyle Hidden -PassThru -Wait
    if ($upgrade.ExitCode -ne 0) { throw "Upgrade failed: $($upgrade.ExitCode)" }
    $upgradedLocation = (Get-ItemProperty -LiteralPath $registryPath).InstallLocation
    if ($upgradedLocation -ne $initialLocation) { throw 'Upgrade changed installation directory.' }
    Write-Output 'Install, Unicode-path startup, runtime bundling and repeated-install upgrade passed.'
} finally {
    if ($appProcess -and -not $appProcess.HasExited) { Stop-Process -Id $appProcess.Id }
    $uninstaller = Join-Path $appPath 'unins000.exe'
    if (Test-Path -LiteralPath $uninstaller) {
        $remove = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -WindowStyle Hidden -PassThru -Wait
        if ($remove.ExitCode -ne 0) { throw "Uninstall failed: $($remove.ExitCode)" }
        if (Test-Path -LiteralPath $registryPath) { throw 'Uninstall registration remains.' }
        if (Test-Path -LiteralPath (Join-Path $appPath 'lyrics_float.exe')) { throw 'Installed executable remains after uninstall.' }
        Write-Output 'Uninstall passed.'
    }
}
