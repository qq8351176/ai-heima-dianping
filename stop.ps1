$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$frontend = Join-Path $root 'AI-dianping-frontend'
$pidFile = Join-Path $root 'runtime\backend.pid'
if (Test-Path -LiteralPath (Join-Path $frontend 'logs\nginx.pid')) {
    & (Join-Path $frontend 'nginx.exe') -p ($frontend.Replace('\', '/') + '/') -s quit
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop the project Nginx instance.' }
}
if (Test-Path -LiteralPath $pidFile) {
    $backendId = [int](Get-Content -LiteralPath $pidFile)
    $backendProcess = Get-CimInstance Win32_Process -Filter "ProcessId=$backendId"
    if ($backendProcess) {
        $jar = Join-Path $root 'AI-dianping-backend\target\AI-dianping-backend-0.0.1-SNAPSHOT.jar'
        if ($backendProcess.CommandLine.IndexOf($jar, [StringComparison]::OrdinalIgnoreCase) -lt 0) { throw 'Saved PID belongs to another process; refusing to stop it.' }
        Stop-Process -Id $backendId
        Wait-Process -Id $backendId -Timeout 15 -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $pidFile
}
& wsl.exe -d Ubuntu-20.04 -- sh /mnt/e/java_learn/ai-dianping/deploy/redis-control.sh stop
if ($LASTEXITCODE -ne 0) { throw 'Could not stop the project Redis instance.' }
Write-Host 'Project stopped. Shared MySQL service is still running.'
