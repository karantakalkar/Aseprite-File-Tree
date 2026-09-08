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
    $arguments = @('-b', '-script-param', ('"result={0}"' -f $resultPath), '-script', ('"{0}"' -f $testPath))
    $process = Start-Process -FilePath $AsepritePath -ArgumentList $arguments -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput "$resultPath.stdout" -RedirectStandardError "$resultPath.stderr"
    $process.WaitForExit()
    Get-Content -LiteralPath "$resultPath.stdout", "$resultPath.stderr"

    if (-not (Test-Path -LiteralPath $resultPath)) {
        throw "Filesystem behavior tests did not create the success marker."
    }

    $result = Get-Content -LiteralPath $resultPath -Raw
    if ($result -ne "passed") {
        throw "Filesystem behavior tests wrote an invalid success marker."
    }
}
finally {
    foreach ($temporaryPath in @($resultPath, "$resultPath.stdout", "$resultPath.stderr")) {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath
        }
    }
}

Write-Host "Filesystem behavior tests passed."
