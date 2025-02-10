using namespace System.Text;
using namespace System.IO;
# ===== Parameters ======
Param(
    [string]$Path = $(Join-Path -Path $PSScriptRoot -ChildPath 'TestData.txt'),
    [long]$count = 10000,
    [int]$seed = $([Convert]::ToInt32([DateTime]::Now.TimeOfDay.TotalMilliseconds)),
    [string]$keyListPath = $(Join-Path -Path $PSScriptRoot -ChildPath '\src\benchmarking\data\worldcities.txt')
)
# ===== SCRIPT ======
cls
$ErrorActionPreference = 'Stop'
cd $PSScriptRoot

$outFile = [FileInfo]::new($Path)
$outFileStream = $outFile.Open([FileMode]::Create);
[string[]]$keyList = [File]::ReadAllLines($keyListPath);
[Random]$rand = [Random]::new($seed);
[long]$i = 0;
while($i -lt $count){
    $ki = $rand.Next(0, $keyList.Count);
    [string]$k = $keyList[$ki]
    [double]$v = [Convert]::ToDouble($rand.Next(-999, 999)) / 100.0;
    
    $line = "$($k);$($v.ToString('0.0'))"
    if($i -ne ($count - 1)){$line += "`n"}
    $bytes = [Encoding]::UTF8.GetBytes($line)
    $outFileStream.Write($bytes, 0, $bytes.Count);
    $i++;
}

$outFileStream.Close()