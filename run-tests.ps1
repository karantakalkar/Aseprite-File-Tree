param(
    [string]$AsepritePath = "C:\Program Files\Aseprite\Aseprite.exe"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$testPath = Join-Path $root "tests\filesystem_tests.lua"

if (-not (Test-Path -LiteralPath $AsepritePath)) {
    throw "Aseprite executable not found: $AsepritePath"
}

if (-not (Test-Path -LiteralPath $testPath)) {
    throw "Filesystem test script not found: $testPath"
}

$resultPath = [System.IO.Path]::GetTempFileName()
Remove-Item -LiteralPath $resultPath

try {
    & $AsepritePath -b -script-param "result=$resultPath" -script $testPath

    for ($attempt = 0; $attempt -lt 50 -and -not (Test-Path -LiteralPath $resultPath); $attempt++) {
        Start-Sleep -Milliseconds 100
    }

    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "Filesystem behavior tests did not create the success marker."
    }

    $result = Get-Content -LiteralPath $resultPath -Raw
    if ($result -ne "passed") {
        throw "Filesystem behavior tests wrote an invalid success marker."
    }
}
finally {
    if (Test-Path -LiteralPath $resultPath) {
        Remove-Item -LiteralPath $resultPath
    }
}

Write-Host "Filesystem behavior tests passed."
