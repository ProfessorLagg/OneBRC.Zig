using namespace System.IO
using namespace System.Diagnostics

Param(
    [ValidateRange(1,[int]::MaxValue)]
    [int]$Count = 5,

    [string]$Path = "C:\CodeProjects\1BillionRowChallenge\data\NoHashtag\1_000_000_000.txt",

    [switch]$Clean,

    [IntPtr]$Affinity = 0
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
    [decimal]$ticks_per_ns_f80 = [Convert]::ToDecimal([TimeSpan]::TicksPerMillisecond) / $([decimal]1000000)
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

function Get-Median{
    Param(
        [long[]]$Values
    )
    $c = $Values.Count;
    $v = @($Values | Sort-Object);
    [int]$i0 = [Math]::Floor($c / 2);
    [double]$r = $v[$i0]
    if($c % 2 -eq 0){
        $r = ($r + [double]$v[$i0 + 1]) / 2.0
    }
    return $r
}

[Int64]$FileSize = Get-ItemPropertyValue -Path $Path -Name Length
[Int64]$Affinity64 = [Int64]::Parse($Affinity.ToString());

if($Clean){
    $cacheDir = [DirectoryInfo]::new(".zig-cache")
    if($cacheDir.Exists){$cacheDir | Remove-Item -Recurse -Force}
    $outDir = [DirectoryInfo]::new("zig-out")
    if($outDir.Exists){$outDir | Remove-Item -Recurse -Force}
}
zig build -freference-trace "-Doptimize=ReleaseFast"

$exeFile = [FileInfo]::new('zig-out\bin\brc.exe')

$times = @()
[Stopwatch]$timer = [Stopwatch]::StartNew()
for($i = 0; $i -lt $Count; $i++){
    [double]$prog = ([double]$i / [double]$Count) * 100.0; 
    [string]$stat = "$($i.ToString('0')) / $($Count.ToString('0')) | $($prog.ToString('n'))%"


    [double]$secondsLeft = 0;
    if($i -gt 0){
        [double]$itemsLeft = [Convert]::ToDouble($Count - $i);
        [double]$secondsPerItem = $timer.Elapsed.TotalSeconds / [double]$i;
        $secondsLeft = $secondsPerItem * $itemsLeft;
    }
    Write-Progress "Benchmarking $($exeFile.FullName)" -Status $stat -PercentComplete $prog -SecondsRemaining $secondsLeft

    $proc = Start-Process -FilePath $exeFile.FullName -ArgumentList $Path -WorkingDirectory $PSScriptRoot -PassThru -WindowStyle Hidden
    if($Affinity64 -gt [uint64]0){
        $proc.ProcessorAffinity = $Affinity;    
    }
    
    $proc.PriorityClass = [ProcessPriorityClass]::AboveNormal;
    $proc.WaitForExit() | Out-Null
    
    $time = $proc.ExitTime - $proc.StartTime;
    $times += $time;
    Remove-Variable prog, stat, proc, time
    [GC]::Collect([GC]::MaxGeneration, [GCCollectionMode]::Optimized, $true, $true)
}

$times = $times | Sort-Object
$ticks = [long[]]@($times | %{[Convert]::ToDouble($_.Ticks)})
$tickMeasure = $ticks | Measure-Object -Minimum -Average -Maximum

$medianTime = [TimeSpan]::FromTicks($(Get-Median -Values $ticks));
$minTime = [TimeSpan]::FromTicks($tickMeasure.Minimum);
$avgTime = [TimeSpan]::FromTicks($tickMeasure.Average);
$maxTime = [TimeSpan]::FromTicks($tickMeasure.Maximum);

Write-Host "Times:"
$times | %{Write-Host "`t$($_ | Format-LargestUnitString) | $(Format-Throughput -Duration $_ -Size $FileSize)"}
Write-Host "Best  : $($minTime | Format-LargestUnitString) | $(Format-Throughput -Duration $minTime -Size $FileSize)"
Write-Host "Mean  : $($avgTime | Format-LargestUnitString) | $(Format-Throughput -Duration $avgTime -Size $FileSize)"
Write-Host "Median: $($medianTime | Format-LargestUnitString) | $(Format-Throughput -Duration $medianTime -Size $FileSize)"
Write-Host "Worst : $($maxTime | Format-LargestUnitString) | $(Format-Throughput -Duration $maxTime -Size $FileSize)"

if($Count -ceq 5){
    $brcTicks = $times | %{[Convert]::ToDouble($_.Ticks)} | Sort-Object | Select -Skip 1 | select -SkipLast 1 | Measure-Object -Average | select -ExpandProperty Average
    $brcTime = [TimeSpan]::FromTicks($brcTicks);
    Write-Host "BRC   : $($brcTime | Format-LargestUnitString) | $(Format-Throughput -Duration $brcTime -Size $FileSize)"
}


$dataObj = [PSCustomObject]@{
    Length = $FileSize;
    Nanoseconds = @($times | %{$_ | Get-TotalNanoSeconds})
}
return $($dataObj | ConvertTo-Json -Compress)