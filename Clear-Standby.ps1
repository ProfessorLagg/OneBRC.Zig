$EmptyList = Get-WmiObject -Class Win32_Process -Filter "Name = 'System'" | Select-Object -ExpandProperty CommandLine
Clear-Content -Path "C:\Windows\Prefetch\*"