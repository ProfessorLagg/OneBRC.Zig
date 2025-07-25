using namespace System.IO

Param(
    [string]$Mode = "ReleaseSafe"
)

$validModes = @(
    'ReleaseFast',
    'RealeaseSmall',
    'ReleaseSafe',
    'Debug'
)

if($Mode -cnotin $validModes){
    Write-Error "Expected one of $([string]::join(', ', $validModes)). But found $($Mode)";
    exit 1;
}

cd $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot

$cacheDir = [DirectoryInfo]::new(".zig-cache")
if($cacheDir.Exists){$cacheDir | Remove-Item -Recurse -Force}

$outDir = [DirectoryInfo]::new("zig-out")
if($outDir.Exists){$outDir | Remove-Item -Recurse -Force}

zig build "-Doptimize=$($Mode)"

$exeFile = [FileInfo]::new('zig-out\bin\brc.exe')
$logDirPath = $PSScriptRoot
$stdoutFilePath = Join-Path -Path $logDirPath -ChildPath "stdout.txt"
$stderrFilePath = Join-Path -Path $logDirPath -ChildPath "stderr.txt"
Start-Process -FilePath $exeFile.FullName -RedirectStandardOutput $stdoutFilePath -RedirectStandardError $stderrFilePath -WindowStyle Minimized