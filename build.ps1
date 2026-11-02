$ErrorActionPreference = 'Stop'
$env:JAVA_HOME = 'E:\DevTools\Java\jdk-17'
Push-Location (Join-Path $PSScriptRoot 'AI-dianping-backend')
try {
    & 'E:\DevTools\Maven\apache-maven-3.10.0\bin\mvn.cmd' -B -ntp '-DskipTests' package
    if ($LASTEXITCODE -ne 0) { throw 'Maven build failed.' }
} finally {
    Pop-Location
}
