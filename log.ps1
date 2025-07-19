using namespace System.IO

cd $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot

$cacheDir = [DirectoryInfo]::new(".zig-cache")
if($cacheDir.Exists){$cacheDir | Remove-Item -Recurse -Force}

$outDir = [DirectoryInfo]::new("zig-out")
if($outDir.Exists){$outDir | Remove-Item -Recurse -Force}

zig build --release=safe

$exeFile = [FileInfo]::new('zig-out\bin\brc.exe')


#$logDirPath = 'D:\Temp-SSD\1brc'
$logDirPath = $PSScriptRoot
$stdoutFilePath = Join-Path -Path $logDirPath -ChildPath "stdout.txt"
$stderrFilePath = Join-Path -Path $logDirPath -ChildPath "stderr.txt"
Start-Process -FilePath $exeFile.FullName -RedirectStandardOutput $stdoutFilePath -RedirectStandardError $stderrFilePath -WindowStyle Minimized