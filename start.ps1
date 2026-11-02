$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$backend = Join-Path $root 'AI-dianping-backend'
$frontend = Join-Path $root 'AI-dianping-frontend'
$jar = Join-Path $backend 'target\AI-dianping-backend-0.0.1-SNAPSHOT.jar'
$java = 'E:\DevTools\Java\jdk-17\bin\java.exe'
$wslScript = '/mnt/e/java_learn/ai-dianping/deploy/redis-control.sh'

function Get-ProjectListener([int]$Port, [string]$ExpectedPath) {
    $listener = Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($listener) {
        $owner = Get-CimInstance Win32_Process -Filter "ProcessId=$($listener.OwningProcess)"
        if (($owner.CommandLine + ' ' + $owner.ExecutablePath).IndexOf($ExpectedPath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            throw "Port $Port is occupied by another process (PID $($listener.OwningProcess))."
        }
    }
    return $listener
}

if (!(Test-Path -LiteralPath $jar)) { throw 'Build first: run build.ps1.' }
if ((Get-Service MySQL80).Status -ne 'Running') { Start-Service MySQL80 }
& wsl.exe -d Ubuntu-20.04 -- sh $wslScript start
if ($LASTEXITCODE -ne 0) { throw 'Could not start the project Redis instance.' }

. (Join-Path $root 'deploy\deepseek.env.ps1')
if (![string]::IsNullOrWhiteSpace($env:DEEPSEEK_API_KEY)) {
    Write-Host 'DeepSeek API key is configured (value hidden).'
} else {
    Write-Warning 'DeepSeek key is empty. Fill deploy\deepseek.env.ps1 and restart to enable real AI calls.'
    Remove-Item Env:\DEEPSEEK_API_KEY -ErrorAction SilentlyContinue
}

if (!(Get-ProjectListener 8091 $jar)) {
    $config = 'file:' + ($root.Replace('\', '/') + '/deploy/application-local.yml')
    $backendProcess = Start-Process -FilePath $java -ArgumentList @('-Dfile.encoding=UTF-8', '-jar', "`"$jar`"", '--spring.profiles.active=local', "--spring.config.additional-location=$config") -WorkingDirectory $backend -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'logs\backend.stdout.log') -RedirectStandardError (Join-Path $root 'logs\backend.stderr.log') -PassThru
    $backendProcess.Id | Set-Content -LiteralPath (Join-Path $root 'runtime\backend.pid')
}

$ready = $false
for ($attempt = 0; $attempt -lt 60; $attempt++) {
    try {
        $result = Invoke-RestMethod 'http://127.0.0.1:8091/shop-type/list' -TimeoutSec 2
        if ($result.success) { $ready = $true; break }
    } catch { }
    if ($backendProcess -and $backendProcess.HasExited) { throw 'Backend exited. Check logs\backend.stdout.log and backend.stderr.log.' }
    Start-Sleep -Seconds 1
}
if (!$ready) { throw 'Backend did not become ready. Check the backend logs.' }

if (!(Get-ProjectListener 8090 $frontend)) {
    $prefix = $frontend.Replace('\', '/') + '/'
    & (Join-Path $frontend 'nginx.exe') -t -p $prefix
    if ($LASTEXITCODE -ne 0) { throw 'Nginx configuration check failed.' }
    Start-Process -FilePath (Join-Path $frontend 'nginx.exe') -ArgumentList @('-p', $prefix) -WorkingDirectory $frontend -WindowStyle Hidden
}
for ($attempt = 0; $attempt -lt 15; $attempt++) {
    try {
        $result = Invoke-RestMethod 'http://127.0.0.1:8090/api/shop-type/list' -TimeoutSec 2
        if ($result.success) { Write-Host 'Ready: http://localhost:8090/'; exit 0 }
    } catch { }
    Start-Sleep -Seconds 1
}
throw 'Frontend proxy check failed. Check AI-dianping-frontend\logs\error.log.'
