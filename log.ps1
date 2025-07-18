using namespace System.IO

cd $PSScriptRoot
[Environment]::CurrentDirectory = $PSScriptRoot

$cacheDir = [DirectoryInfo]::new(".zig-cache")
if($cacheDir.Exists){$cacheDir | Remove-Item -Recurse -Force}

$outDir = [DirectoryInfo]::new("zig-out")
if($outDir.Exists){$outDir | Remove-Item -Recurse -Force}

zig build --release=fast

$exeFile = [FileInfo]::new('zig-out\bin\brc.exe')

Start-Process -FilePath $exeFile.FullName -RedirectStandardOutput stdout.txt -RedirectStandardError stderr.txt -WindowStyle Minimized