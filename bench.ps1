using namespace System.IO
using namespace System.Diagnostics

Param(
    [ValidateRange(1,[int]::MaxValue)]
    [int]$RunCount = 5,

    [string]$Path = "C:\CodeProjects\1BillionRowChallenge\data\NoHashtag\1_000_000_000.txt"

    
)


cd $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot
$ErrorActionPreference = 'Stop'

$MpComputerStatus = Get-MpComputerStatus
if($MpComputerStatus.RealTimeProtectionEnabled){
    Write-Error "Please Disable windows defender for accurate results"
    exit 1;
}

function Get-TotalNanoSeconds{
    Param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [TimeSpan]$duration
    )

    [decimal]$ticks_f80 = [Convert]::ToDecimal($duration.Ticks)
    [decimal]$ticks_per_ns_f80 = [Convert]::ToDecimal([TimeSpan]::TicksPerMillisecond * [Int64]1000 * [Int64]1000)
    return [Convert]::ToDouble($ticks_f80 / $ticks_per_ns_f80)
}

function Get-TotalMicroSeconds{
    Param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [TimeSpan]$duration
    )

    [decimal]$ticks_f80 = [Convert]::ToDecimal($duration.Ticks)
    [decimal]$ticks_per_us_f80 = [Convert]::ToDecimal([TimeSpan]::TicksPerMillisecond * [Int64]1000)
    return [Convert]::ToDouble($ticks_f80 / $ticks_per_us_f80)
}

function Format-LargestUnitString{
    Param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [TimeSpan]$duration
    )
    [Int64]$ticksPerWeek = [TimeSpan]::TicksPerDay * 7;
    [Int64]$ticksPerMicrosecond = [TimeSpan]::TicksPerMillisecond * [Int64]1000;

    [double]$val = $duration | Get-TotalNanoSeconds;
    [string]$tag = 'ns'

    if($duration.Ticks -ge $ticksPerWeek){$val = $duration.TotalDays / 7.0; $tag = 'wk'}
    elseif($duration.Ticks -ge [TimeSpan]::TicksPerDay){$val = $duration.TotalDays; $tag = 'd'}
    elseif($duration.Ticks -ge [TimeSpan]::TicksPerHour){$val = $duration.TotalHours; $tag = 'h'}
    elseif($duration.Ticks -ge [TimeSpan]::TicksPerMinute){$val = $duration.TotalMinutes; $tag = 'm'}
    elseif($duration.Ticks -ge [TimeSpan]::TicksPerSecond){$val = $duration.TotalSeconds; $tag = 's'}
    elseif($duration.Ticks -ge [TimeSpan]::TicksPerMillisecond){$val = $duration.TotalMilliseconds; $tag = 'ms'}
    elseif($duration.Ticks -ge $ticksPerMicrosecond){$val = $duration | Get-TotalMicroSeconds; $tag = 'us'}

    return "$($val.ToString('0.000', [cultureinfo]::InvariantCulture)) $($tag)"
}

function Format-Throughput{
    Param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [ValidateNotNull()]
        [TimeSpan]$Duration,

        [Parameter(Mandatory, ValueFromPipeline, Position = 1)]
        [ValidateNotNull()]
        [ValidateRange(1, [Int64]::MaxValue)]
        [Int64]$Size
    )

    $size_f = [Convert]::ToDouble($Size);
    $bps = $size_f / $Duration.TotalSeconds
    
    [double]$val = $bps;
    [string]$tag = 'B'

    if($bps -gt 1tb){$val = $bps / 1tb;$tag = 'TB'}
    elseif($bps -gt 1gb){$val = $bps / 1gb;$tag = 'GB'}
    elseif($bps -gt 1mb){$val = $bps / 1mb;$tag = 'MB'}
    elseif($bps -gt 1kb){$val = $bps / 1kb;$tag = 'KB'}

    return "$($val.ToString('0.0000', [cultureinfo]::InvariantCulture)) $($tag)/s"
}

[Int64]$FileSize = Get-ItemPropertyValue -Path $Path -Name Length

$cacheDir = [DirectoryInfo]::new(".zig-cache")
if($cacheDir.Exists){$cacheDir | Remove-Item -Recurse -Force}

$outDir = [DirectoryInfo]::new("zig-out")
if($outDir.Exists){$outDir | Remove-Item -Recurse -Force}

zig build -freference-trace "-Doptimize=ReleaseFast"

$exeFile = [FileInfo]::new('zig-out\bin\brc.exe')



$times = @()
for($i = 0; $i -lt $RunCount; $i++){
    [double]$prog = ([double]$i / [double]$RunCount) * 100.0; 
    [string]$stat = "$($i.ToString('0')) / $($RunCount.ToString('0')) | $($prog.ToString('n'))%"
    Write-Progress "Benchmarking $($exeFile.FullName)" -Status $stat -PercentComplete $prog

    $proc = Start-Process -FilePath $exeFile.FullName -ArgumentList $Path -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden
    $proc.PriorityClass = [ProcessPriorityClass]::AboveNormal;
    $proc.WaitForExit() | Out-Null
    
    $time = $proc.ExitTime - $proc.StartTime;
    $times += $time;
    Remove-Variable prog, stat, proc, time
    [GC]::Collect([GC]::MaxGeneration, [GCCollectionMode]::Optimized, $true, $true)
}

$tickMeasure = $times | %{[Convert]::ToDouble($_.Ticks)} | Measure-Object -Minimum -Average -Maximum
$minTime = [TimeSpan]::FromTicks($tickMeasure.Minimum);
$avgTime = [TimeSpan]::FromTicks($tickMeasure.Average);
$maxTime = [TimeSpan]::FromTicks($tickMeasure.Maximum);




Write-Host "Times:"
$times | %{Write-Host "`t$($_ | Format-LargestUnitString) | $(Format-Throughput -Duration $_ -Size $FileSize)"}
Write-Host "Best : $($minTime | Format-LargestUnitString) | $(Format-Throughput -Duration $minTime -Size $FileSize)"
Write-Host "Mean : $($avgTime | Format-LargestUnitString) | $(Format-Throughput -Duration $avgTime -Size $FileSize)"
Write-Host "Worst: $($maxTime | Format-LargestUnitString) | $(Format-Throughput -Duration $maxTime -Size $FileSize)"

if($RunCount -ceq 5){
    $brcTicks = $times | %{[Convert]::ToDouble($_.Ticks)} | Sort-Object | Select -Skip 1 | select -SkipLast 1 | Measure-Object -Average | select -ExpandProperty Average
    $brcTime = [TimeSpan]::FromTicks($brcTicks);
    Write-Host "BRC  : $($brcTime | Format-LargestUnitString) | $(Format-Throughput -Duration $brcTime -Size $FileSize)"
}
