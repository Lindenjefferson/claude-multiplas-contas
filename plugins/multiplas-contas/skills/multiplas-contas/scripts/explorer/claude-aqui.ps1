# Chamado por claude-aqui.cmd. O Explorer nao repassa a pasta atual para comandos do App Paths,
# entao pegamos a pasta da janela do Explorer mais a frente (aba ativa = titulo da janela).
. (Join-Path $PSScriptRoot '..\comum.ps1')
$null = Repair-TempSessao
Add-Type -Namespace W -Name U -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetTopWindow(IntPtr h);
[DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr h, uint cmd);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
'@

function Get-PastaExplorer {
    $h = [W.U]::GetTopWindow([IntPtr]::Zero)
    while ($h -ne [IntPtr]::Zero) {
        $cls = New-Object System.Text.StringBuilder 256
        [void][W.U]::GetClassName($h, $cls, 256)
        if ($cls.ToString() -eq 'CabinetWClass' -and [W.U]::IsWindowVisible($h)) {
            $tit = New-Object System.Text.StringBuilder 512
            [void][W.U]::GetWindowText($h, $tit, 512)
            $abas = @((New-Object -ComObject Shell.Application).Windows() | Where-Object { $_.HWND -eq [int64]$h })
            $aba = $abas | Where-Object { $_.LocationName -eq $tit.ToString() } | Select-Object -First 1
            if (-not $aba) { $aba = $abas | Select-Object -First 1 }
            if ($aba) { try { return $aba.Document.Folder.Self.Path } catch { } }
            return $null
        }
        $h = [W.U]::GetWindow($h, 2)  # GW_HWNDNEXT
    }
}

$pasta = Get-PastaExplorer
if ($pasta -and (Test-Path -LiteralPath $pasta -PathType Container)) { Set-Location -LiteralPath $pasta }

& (Join-Path $PSScriptRoot '..\cc.ps1') @args
