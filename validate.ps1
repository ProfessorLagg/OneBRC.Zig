using namespace System.IO
using namespace System.Diagnostics

Param(
    [string]$Path = 'C:\CodeProjects\1BillionRowChallenge\data\NoHashtag\1_000_000_000.txt',
    [string]$ValidPath = 'C:\CodeProjects\1BillionRowChallenge\data\NoHashtag\1_000_000_000.val.txt',
    [switch]$ExportCsv,
    [switch]$Clean
)

cd $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot
$ErrorActionPreference = 'Stop'

# Build the exe
[Int64]$FileSize = Get-ItemPropertyValue -Path $Path -Name Length

if($Clean){
    $cacheDir = [DirectoryInfo]::new(".zig-cache")
    if($cacheDir.Exists){$cacheDir | Remove-Item -Recurse -Force}
    $outDir = [DirectoryInfo]::new("zig-out")
    if($outDir.Exists){$outDir | Remove-Item -Recurse -Force}
}
zig build -freference-trace "-Doptimize=ReleaseFast"
$exeFile = [FileInfo]::new('zig-out\bin\brc.exe')


# Run the exe
$stdoutPath = Join-Path -Path $PSScriptRoot -ChildPath "stdout.txt"
$stderrPath = Join-Path -Path $PSScriptRoot -ChildPath "stderr.txt"
Start-Process -FilePath $exeFile.FullName -ArgumentList $Path -WorkingDirectory $PSScriptRoot -WindowStyle Hidden -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -Wait

$expectContent = Get-Content -Path $ValidPath -Raw;
if($null -eq $expectContent){$expectContent = ''}else{$expectContent = $expectContent.Trim()}
$foundContent = Get-Content -Path $stdoutPath -Raw
if($null -eq $foundContent){$foundContent = ''}else{$foundContent = $foundContent.Trim()}
$sameContent = $expectContent -ceq $foundContent

if($sameContent){
    Write-Host "Produced correct output" -ForegroundColor Green
} else {
    Write-Host "Produced incorrect output" -ForegroundColor Red
}

if($ExportCsv){
    $expectCSV = $expectContent.Replace('{','').Replace('}','').Replace('=',';').Replace('/',';').Replace(', ', ',').Replace(',',"`n").Trim()
    $expectCSV | Out-File -FilePath 'expect.csv' -Encoding utf8
    $foundCSV = $foundContent.Replace('{','').Replace('}','').Replace('=',';').Replace('/',';').Replace(', ', ',').Replace(',',"`n").Trim()
    $foundCSV | Out-File -FilePath 'found.csv' -Encoding utf8
}
