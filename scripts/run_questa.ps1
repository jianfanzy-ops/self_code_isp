param(
    [string]$QuestaBin = 'A:\software\Questa\questa24.1\win64',
    [switch]$Waves
)

$ErrorActionPreference = 'Stop'
$sourceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$logRoot = Join-Path $PSScriptRoot 'logs'
$buildRoot = Join-Path ([IO.Path]::GetTempPath()) ('matrix_3x3_gen_questa_' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logRoot, $buildRoot -Force | Out-Null
$library = (Join-Path $buildRoot 'work').Replace('\', '/')
$rtl = (Join-Path $sourceRoot 'rtl').Replace('\', '/')
$tb = (Join-Path $sourceRoot 'tb').Replace('\', '/')

foreach ($tool in 'vlib.exe', 'vlog.exe', 'vsim.exe') {
    if (-not (Test-Path -LiteralPath (Join-Path $QuestaBin $tool))) {
        throw "Questa executable missing: $QuestaBin\$tool"
    }
}

& (Join-Path $QuestaBin 'vlib.exe') $library
if ($LASTEXITCODE -ne 0) { throw 'vlib failed' }
$compileLog = Join-Path $logRoot 'compile.log'
# matrix_3x3_gen includes "./../define_isp.sv", so its own directory is an include directory too.
& (Join-Path $QuestaBin 'vlog.exe') -sv -svinputport=net -work $library '+define+SIMULATION' `
    "+incdir+$rtl" "+incdir+$rtl/matrix_3x3_gen" `
    "$rtl/ip/fifo/isp_dc_fifo.sv" "$rtl/matrix_3x3_gen/matrix_3x3_gen.sv" `
    "$tb/tb_matrix_3x3_gen.sv" 2>&1 |
    Tee-Object -FilePath $compileLog
if ($LASTEXITCODE -ne 0) { throw 'RTL/TB compile failed' }

# Every simulation runs its entire case list. Generics only vary hardware shape.
$runs = @(
    @{ Name='matrix_tap8'; Top='tb_matrix_3x3_gen'; Args=@('-gTAP=8','-gPIX=10','-gLINE_BEATS=8');  Cases=7 },
    @{ Name='matrix_tap4'; Top='tb_matrix_3x3_gen'; Args=@('-gTAP=4','-gPIX=10','-gLINE_BEATS=8');  Cases=7 },
    @{ Name='matrix_tap2'; Top='tb_matrix_3x3_gen'; Args=@('-gTAP=2','-gPIX=10','-gLINE_BEATS=8');  Cases=7 },
    @{ Name='matrix_tap1'; Top='tb_matrix_3x3_gen'; Args=@('-gTAP=1','-gPIX=10','-gLINE_BEATS=16'); Cases=7 },
    @{ Name='matrix_gap0'; Top='tb_matrix_3x3_gen'; Args=@('-gTAP=4','-gPIX=12','-gLINE_GAP=0');    Cases=7 },
    @{ Name='matrix_gap1'; Top='tb_matrix_3x3_gen'; Args=@('-gTAP=2','-gPIX=8','-gLINE_GAP=1');     Cases=7 },
    @{ Name='matrix_h2';   Top='tb_matrix_3x3_gen'; Args=@('-gTAP=8','-gPIX=10','-gHEIGHT=2');      Cases=7 },
    @{ Name='matrix_h1';   Top='tb_matrix_3x3_gen'; Args=@('-gTAP=4','-gPIX=10','-gHEIGHT=1');      Cases=7 },
    @{ Name='matrix_full'; Top='tb_matrix_3x3_gen'; Args=@('-gTAP=8','-gPIX=10','-gLINE_BEATS=32','-gLINE_MAX=256'); Cases=7 }
)

# All runs are executed even when one fails, the summary lists every case of every run.
$results = @()
$caseLines = @()
foreach ($run in $runs) {
    $simLog = (Join-Path $logRoot ($run.Name + '.log')).Replace('\', '/')
    $waveLog = (Join-Path $logRoot ($run.Name + '.wlf')).Replace('\', '/')
    $top = $run.Top
    $waveCommand = if ($Waves) { "log -r /$top/*; " } else { '' }
    # Treat a fatal/watchdog break as failure, including a fatal that returns to Tcl.
    $doText = "onerror {quit -code 1}; onbreak {if {[examine -radix decimal /$top/test_complete] != 0} {quit -code 0} else {quit -code 1}}; ${waveCommand}run -all; " +
              "if {[examine -radix decimal /$top/test_complete] == 0} {quit -code 1}; quit -code 0"
    $doPath = Join-Path $buildRoot ($run.Name + '.do')
    [IO.File]::WriteAllText($doPath, $doText, [Text.UTF8Encoding]::new($false))
    Write-Output "Running $($run.Name)..."
    $simArguments = @('-c','-onfinish','stop','-voptargs=+acc','-lib',$library,$top) + $run.Args +
                    @('-do',('do {' + $doPath.Replace('\','/') + '}'),'-l',$simLog,'-wlf',$waveLog)
    & (Join-Path $QuestaBin 'vsim.exe') @simArguments 2>&1 | Out-File -LiteralPath ($simLog + '.console') -Encoding utf8
    $simExit = $LASTEXITCODE
    $logText = if (Test-Path -LiteralPath $simLog) { Get-Content -LiteralPath $simLog -Raw } else { '' }
    $casePasses = ([regex]::Matches($logText, '(?m)^# ========== CASE \d+ .+ PASS \(0 errors\) ==========\s*$')).Count
    $passed = $simExit -eq 0 -and $logText -match '(?m)^# TEST PASSED\s*$' -and
              $logText -notmatch 'TEST FAILED|\*\* (?:Error|Fatal):|# ERROR cycle=' -and $casePasses -eq $run.Cases
    $results += [pscustomobject]@{Run=$run.Name; Top=$top; Cases=$casePasses; Expected=$run.Cases; Result= $(if ($passed) {'PASS'} else {'FAIL'})}
    $caseLines += "[$($run.Name)]"
    $caseLines += [regex]::Matches($logText, '(?m)^# (\d+ \S+ +(?:PASS|FAIL|INCOMPLETE) .*|    wrong positions .*)$') | ForEach-Object { $_.Groups[1].Value.TrimEnd() }
}

$results | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $logRoot 'results.json') -Encoding utf8
$failed = @($results | Where-Object { $_.Result -ne 'PASS' }).Count
$verdict = if ($failed -eq 0) { "ALL TESTS PASSED: $($results.Count) runs." } else { "TESTS FAILED: $failed of $($results.Count) runs." }
$summary = ($caseLines -join "`r`n") + "`r`n" + ($results | Format-Table -AutoSize | Out-String) + $verdict + "`r`n"
$summary | Set-Content -LiteralPath (Join-Path $logRoot 'summary.txt') -Encoding utf8
Write-Output $summary
if ($failed -ne 0) { exit 1 }
