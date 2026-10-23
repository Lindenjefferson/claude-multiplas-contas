# Funcoes compartilhadas pelos scripts de ~/.claude-contas.
# Cada conta tem sua pasta de config (CLAUDE_CONFIG_DIR) com login proprio;
# o resto aponta para a pasta mestre ~/.claude via symlink (arquivos) ou junction (pastas).
# Arquivos .ps1 ficam em ASCII: o Windows PowerShell 5.1 le .ps1 sem BOM como ANSI.

$Script:Base   = Join-Path $env:USERPROFILE '.claude-contas'
$Script:Mestre = Join-Path $env:USERPROFILE '.claude'
$Script:EstadoMestre = Join-Path $env:USERPROFILE '.claude.json'  # .claude.json da conta da pasta mestre

$Script:Claude = Get-Command claude.exe -CommandType Application -ErrorAction SilentlyContinue |
    Where-Object { $_.Source -notlike "$Base*" } | Select-Object -First 1 -ExpandProperty Source
if (-not $Claude) { $Script:Claude = Join-Path $env:USERPROFILE '.local\bin\claude.exe' }

# O que e compartilhado com a pasta mestre. Login (.credentials.json), .claude.json,
# cache, state, shell-snapshots, backups etc. ficam separados por conta.
$Script:ArquivosCompartilhados = @('settings.json', 'history.jsonl', 'CLAUDE.md', 'keybindings.json')
$Script:PastasCompartilhadas   = @('projects', 'file-history', 'session-env', 'sessions', 'skills',
                                   'plugins', 'dev-mods', 'agents', 'commands', 'output-styles', 'hooks', 'rules')

# Chaves do ~/.claude.json copiadas para uma conta nova (config, nao dados da conta).
$Script:ChavesSemente = @('mcpServers', 'projects', 'githubRepoPaths', 'hasCompletedOnboarding',
                          'lastOnboardingVersion', 'installMethod', 'autoUpdates', 'autoUpdatesProtectedForNative',
                          'claudeInChromeDefaultEnabled', 'hasCompletedClaudeInChromeOnboarding',
                          'cachedChromeExtensionInstalled')

$Script:MarcaInicio = '<!-- multiplas-contas:inicio -->'
$Script:MarcaFim    = '<!-- multiplas-contas:fim -->'

function Get-Contas {
    $cfg = Get-Content (Join-Path $Base 'contas.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $principal = if ($cfg.principal) { $cfg.principal } else { $cfg.padrao }
    # So uma conta usa a pasta mestre ~/.claude: a que tiver "pasta" ou, se nenhuma tiver, a principal.
    $algumaComPasta = [bool]($cfg.contas.PSObject.Properties | Where-Object { $_.Value.pasta })
    $lista = foreach ($p in $cfg.contas.PSObject.Properties) {
        $pasta = if ($p.Value.pasta) { $p.Value.pasta -replace '^~', $env:USERPROFILE }
                 elseif (-not $algumaComPasta -and $p.Name -eq $principal) { $Mestre }
                 else { Join-Path $Base $p.Name }
        $pasta = [IO.Path]::GetFullPath($pasta)
        [pscustomobject]@{
            Nome   = $p.Name
            Email  = $p.Value.email
            Pasta  = $pasta
            Mestre = ($pasta.TrimEnd('\') -eq $Mestre.TrimEnd('\'))
            # Remote Control ao abrir com cc: so liga com "rc": true explicito.
            Rc     = ($p.Value.rc -is [bool] -and $p.Value.rc)
        }
    }
    $aviso = 80
    if ($cfg.avisoUso -is [int] -and $cfg.avisoUso -ge 1 -and $cfg.avisoUso -le 100) { $aviso = $cfg.avisoUso }
    # "principal" e a conta padrao do cc e onde se publica; "padrao"/"publicar" separam os dois papeis.
    [pscustomobject]@{
        Principal = $principal
        Padrao   = $(if ($cfg.padrao) { $cfg.padrao } else { $principal })
        Publicar = $(if ($cfg.publicar) { $cfg.publicar } else { $principal })
        Atalho   = $(if ($cfg.atalhoExplorer) { $cfg.atalhoExplorer } else { 'cc' })
        # Conta em que a extensao Claude in Chrome esta logada (informada pelo usuario; nao da para detectar).
        Chrome   = $cfg.chrome
        # Porcentagem (5h ou semanal) a partir da qual o cc avisa e a status line fica amarela.
        AvisoUso = $aviso
        Contas   = @($lista)
    }
}

function Test-Link([string]$caminho) {
    $i = Get-Item -LiteralPath $caminho -Force -ErrorAction SilentlyContinue
    return ($i -and $i.LinkType)
}

function Write-TextoSemBom([string]$caminho, [string]$texto) {
    [IO.File]::WriteAllText($caminho, $texto, (New-Object Text.UTF8Encoding $false))
}

# Symlink de arquivo exige modo desenvolvedor (ou admin). Sem ele, cai para hard link,
# que tambem funciona; se um programa salvar por cima e quebrar o link, Sync-LinksConta refaz.
function New-LinkArquivo([string]$link, [string]$alvo) {
    cmd /c mklink "$link" "$alvo" 2>$null | Out-Null
    if (-not (Test-Link $link)) { cmd /c mklink /H "$link" "$alvo" 2>$null | Out-Null }
    if (-not (Test-Path -LiteralPath $link)) { throw "Nao consegui criar link de $link para $alvo" }
}

function Test-LinkArquivoOk([string]$link, [string]$alvo) {
    $i = Get-Item -LiteralPath $link -Force -ErrorAction SilentlyContinue
    if (-not $i) { return $false }
    if ($i.LinkType -eq 'SymbolicLink') { return $true }
    if ($i.LinkType -eq 'HardLink') {
        # Hard link so vale se ainda aponta para o mesmo arquivo da mestre.
        $a = cmd /c fsutil hardlink list "$alvo" 2>$null
        $nome = $link.Substring(2)  # fsutil lista sem a letra da unidade
        return [bool]($a | Where-Object { $_ -ieq $nome })
    }
    return $false
}

# Garante os links de uma conta. Se um link de arquivo virou arquivo comum (alguns programas
# salvam gravando um temporario e renomeando por cima), a versao mais nova vai para a mestre
# antes de refazer o link, para nao perder a alteracao. Retorna mensagens do que fez.
function Sync-LinksConta($conta) {
    $msgs = @()
    if ($conta.Mestre) { return $msgs }
    New-Item -ItemType Directory -Force $conta.Pasta | Out-Null
    $carimbo = Get-Date -Format 'yyyyMMdd_HHmmss'

    foreach ($nome in $ArquivosCompartilhados) {
        $alvo = Join-Path $Mestre $nome
        $link = Join-Path $conta.Pasta $nome
        if (-not (Test-Path -LiteralPath $alvo)) { continue }
        if (Test-LinkArquivoOk $link $alvo) { continue }
        if (Test-Path -LiteralPath $link) {
            $local = Get-Item -LiteralPath $link -Force
            $bak = Join-Path $Base ("backups\relink_{0}_{1}_{2}" -f $conta.Nome, $carimbo, $nome)
            New-Item -ItemType Directory -Force (Split-Path $bak) | Out-Null
            if ($local.LastWriteTime -gt (Get-Item -LiteralPath $alvo).LastWriteTime) {
                Copy-Item -LiteralPath $alvo $bak
                Copy-Item -LiteralPath $link $alvo -Force
                $msgs += "${nome}: alteracao feita na conta $($conta.Nome) levada para a mestre (anterior em $bak)"
            } else {
                Copy-Item -LiteralPath $link $bak
            }
            Remove-Item -LiteralPath $link -Force
        }
        New-LinkArquivo $link $alvo
        $msgs += "link: $link"
    }

    foreach ($nome in $PastasCompartilhadas) {
        $alvo = Join-Path $Mestre $nome
        $link = Join-Path $conta.Pasta $nome
        if (-not (Test-Path -LiteralPath $alvo)) { continue }
        if (Test-Link $link) { continue }
        if (Test-Path -LiteralPath $link) {
            # Pasta real criada pelo Claude antes do link: preserva em backups e liga.
            $bak = Join-Path $Base ("backups\relink_{0}_{1}_{2}" -f $conta.Nome, $carimbo, $nome)
            New-Item -ItemType Directory -Force (Split-Path $bak) | Out-Null
            Move-Item -LiteralPath $link $bak
            $msgs += "${nome}: pasta local da conta $($conta.Nome) movida para $bak"
        }
        New-Item -ItemType Junction -Path $link -Target $alvo | Out-Null
        $msgs += "junction: $link"
    }

    # .claude.json inicial: so as chaves de configuracao da mestre, sem dados da conta.
    $estado = Join-Path $conta.Pasta '.claude.json'
    $origem = Join-Path $env:USERPROFILE '.claude.json'
    if (-not (Test-Path -LiteralPath $estado) -and (Test-Path -LiteralPath $origem)) {
        $orig = Get-Content $origem -Raw -Encoding UTF8 | ConvertFrom-Json
        $novo = [ordered]@{}
        foreach ($k in $ChavesSemente) { if ($null -ne $orig.$k) { $novo[$k] = $orig.$k } }
        Write-TextoSemBom $estado (([pscustomobject]$novo) | ConvertTo-Json -Depth 100)
        $msgs += "estado inicial: $estado"
    }
    return $msgs
}

# Remove so os links (nunca o conteudo da mestre).
function Remove-LinksConta($conta) {
    if ($conta.Mestre -or -not (Test-Path -LiteralPath $conta.Pasta)) { return }
    Get-ChildItem -LiteralPath $conta.Pasta -Force | Where-Object { $_.LinkType } | ForEach-Object {
        if ($_.PSIsContainer) { [IO.Directory]::Delete($_.FullName, $false) } else { [IO.File]::Delete($_.FullName) }
    }
    foreach ($nome in $ArquivosCompartilhados) {
        # Hard links nao aparecem como LinkType em todas as versoes; so remove se ainda for
        # o mesmo arquivo da mestre (copia que divergiu fica, para nao perder alteracao).
        $f = Join-Path $conta.Pasta $nome
        if ((Test-Path -LiteralPath $f) -and (Test-LinkArquivoOk $f (Join-Path $Mestre $nome))) { [IO.File]::Delete($f) }
    }
}

function Invoke-ComConta($conta, [scriptblock]$bloco) {
    $antes = $env:CLAUDE_CONFIG_DIR
    try {
        # A conta da pasta mestre roda sem a variavel, senao o Claude procura .claude.json dentro de ~/.claude.
        if ($conta.Mestre) { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue } else { $env:CLAUDE_CONFIG_DIR = $conta.Pasta }
        & $bloco
    } finally {
        if ($null -ne $antes) { $env:CLAUDE_CONFIG_DIR = $antes } else { Remove-Item Env:CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue }
    }
}

# Um cc chamado de dentro de uma sessao do Claude (abrir-conta.ps1, ! no prompt) herda as variaveis
# CLAUDE* dela; com CLAUDE_CODE_CHILD_SESSION, a sessao nova nao salva transcript nem aparece no
# ListAgents. Tira essas, menos CLAUDE_CONFIG_DIR (que o proprio cc controla) e as que o usuario
# definiu no ambiente dele (User/Machine), como CLAUDE_CODE_GIT_BASH_PATH. Devolve os nomes tirados.
function Get-NomesClaudePersistentes {
    foreach ($alvo in 'User', 'Machine') {
        [Environment]::GetEnvironmentVariables($alvo).Keys | Where-Object { "$_" -like 'CLAUDE*' }
    }
}

function Clear-AmbienteSessaoPai([string[]]$persistentes = @(Get-NomesClaudePersistentes)) {
    Get-ChildItem Env: | Where-Object {
        $_.Name -like 'CLAUDE*' -and $_.Name -ne 'CLAUDE_CONFIG_DIR' -and $persistentes -notcontains $_.Name
    } | ForEach-Object {
        Remove-Item "Env:$($_.Name)"
        $_.Name
    }
}

# Sem TMP no ambiente do usuario, o Windows herda o da maquina (C:\Windows\TEMP). Ali o compilador
# do Add-Type grava o .cs e nao consegue le-lo de volta ("arquivo de origem nao pode ser encontrado").
# Aponta TMP e TEMP desta sessao para a temp do usuario quando estao vazias ou dentro da pasta do
# Windows. Nao mexe no ambiente salvo do usuario. Devolve os nomes trocados.
function Repair-TempSessao([string]$pastaWindows = $env:windir, [string]$tempUsuario = (Join-Path $env:LOCALAPPDATA 'Temp')) {
    $prefixo = $pastaWindows.TrimEnd('\') + '\'
    foreach ($nome in 'TMP', 'TEMP') {
        $valor = [Environment]::GetEnvironmentVariable($nome)
        if (-not $valor -or ($valor.TrimEnd('\') + '\').StartsWith($prefixo, [StringComparison]::OrdinalIgnoreCase)) {
            Set-Item "Env:$nome" $tempUsuario
            $nome
        }
    }
}

function Get-StatusConta($conta) {
    Invoke-ComConta $conta { & $Claude auth status --json 2>$null | ConvertFrom-Json }
}

# ---- uso (janela de 5h e semanal), o mesmo que o /usage mostra ----
# O token da conta e lido do .credentials.json dela so em memoria: nunca copiado, gravado,
# impresso nem renovado aqui. Sem token valido, vale o ultimo uso que o Claude salvou na conta.

function Get-ArquivoEstado($conta) {
    if ($conta.Mestre) { $EstadoMestre } else { Join-Path $conta.Pasta '.claude.json' }
}

function Get-TokenConta($conta, [datetime]$agora = (Get-Date)) {
    try {
        $f = Join-Path $conta.Pasta '.credentials.json'
        if (-not (Test-Path -LiteralPath $f)) { return $null }
        $o = (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json).claudeAiOauth
        $limite = [DateTimeOffset]::new($agora.AddSeconds(60)).ToUnixTimeMilliseconds()
        if (-not $o.accessToken -or [int64]$o.expiresAt -le $limite) { return $null }
        return $o.accessToken
    } catch { return $null }
}

function Invoke-UsoApi([string]$token, [int]$timeoutSeg = 3) {
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -TimeoutSec $timeoutSeg -ErrorAction Stop -Headers @{
        Authorization    = "Bearer $token"
        'anthropic-beta' = 'oauth-2025-04-20'
    }
}

function ConvertTo-DataLocal($v) {
    if (-not $v) { return $null }
    if ($v -is [datetime]) { return $v.ToLocalTime() }
    try { return [DateTimeOffset]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture).LocalDateTime } catch { return $null }
}

function ConvertTo-Uso($util, [string]$fonte, $quando, [datetime]$agora = (Get-Date)) {
    $r = [ordered]@{ Cinco = $null; Semana = $null; ResetCinco = $null; ResetSemana = $null; Fonte = $null; Quando = $null }
    if (-not $util) { return [pscustomobject]$r }
    foreach ($j in @(@('five_hour', 'Cinco', 'ResetCinco'), @('seven_day', 'Semana', 'ResetSemana'))) {
        $w = $util.($j[0])
        if ($null -eq $w -or $null -eq $w.utilization) { continue }
        $reset = ConvertTo-DataLocal $w.resets_at
        # Janela que ja reiniciou: o uso dela voltou a zero.
        if ($reset -and $reset -le $agora) { $r[$j[1]] = 0 }
        else { $r[$j[1]] = [int][math]::Round([double]$w.utilization); $r[$j[2]] = $reset }
    }
    if ($null -ne $r.Cinco -or $null -ne $r.Semana) { $r.Fonte = $fonte; $r.Quando = $quando }
    [pscustomobject]$r
}

function Get-UsoConta($conta, [int]$timeoutSeg = 3, [datetime]$agora = (Get-Date)) {
    $token = Get-TokenConta $conta $agora
    if ($token) {
        try { return ConvertTo-Uso (Invoke-UsoApi $token $timeoutSeg) 'agora' $null $agora } catch { }
    }
    try {
        $f = Get-ArquivoEstado $conta
        if (Test-Path -LiteralPath $f) {
            $c = (Get-Content -LiteralPath $f -Raw -Encoding UTF8 | ConvertFrom-Json).cachedUsageUtilization
            if ($c) {
                $quando = if ($c.fetchedAtMs) { [DateTimeOffset]::FromUnixTimeMilliseconds([int64]$c.fetchedAtMs).LocalDateTime } else { $null }
                return ConvertTo-Uso $c.utilization 'salvo' $quando $agora
            }
        }
    } catch { }
    ConvertTo-Uso $null $null $null $agora
}

function Get-MaxUso($uso) {
    $v = @($uso.Cinco, $uso.Semana) | Where-Object { $null -ne $_ }
    if (-not $v) { return $null }
    ($v | Measure-Object -Maximum).Maximum
}

# "Sessao (5h): x% . Semana: y%" (com acento e ponto medio), a partir dos textos ja prontos de cada janela.
$Script:Ponto = [char]0xB7
function Format-Janelas([string]$cinco, [string]$semana) {
    'Sess{0}o (5h): {1} {2} Semana: {3}' -f [char]0xE3, $cinco, $Ponto, $semana
}

function Format-Uso($uso) {
    if ($null -eq (Get-MaxUso $uso)) { return '-' }
    $p = { param($x) if ($null -eq $x) { '?' } else { "$x%" } }
    $t = Format-Janelas (& $p $uso.Cinco) (& $p $uso.Semana)
    if ($uso.Fonte -eq 'salvo') {
        # Valor salvo em outro dia leva a data, para nao parecer de hoje.
        $t += if (-not $uso.Quando) { ' (salvo, sem data)' }
              elseif ($uso.Quando.Date -eq (Get-Date).Date) { ' (salvo {0})' -f $uso.Quando.ToString('HH:mm') }
              else { ' (salvo {0})' -f $uso.Quando.ToString('dd/MM HH:mm') }
    }
    $t
}

function Select-ContaSugerida([hashtable]$usos, [string]$excluir) {
    $c = foreach ($k in $usos.Keys) {
        $m = Get-MaxUso $usos[$k]
        if ($k -ne $excluir -and $null -ne $m) { [pscustomobject]@{ Nome = $k; Max = $m } }
    }
    ($c | Sort-Object Max | Select-Object -First 1).Nome
}

# ---- Remote Control por conta ----
# O settings.json e compartilhado entre as contas; o cc decide o RC de cada sessao passando
# --settings com um arquivo de rc\ (linha de comando vence o settings.json do usuario).

function Split-ArgsRc($conta, [object[]]$argumentos) {
    $ligado = [bool]$conta.Rc
    $resto = @()
    foreach ($a in @($argumentos)) {
        if ($a -eq '--no-rc') { $ligado = $false; continue }
        # --rc [nome] fica nos argumentos: o proprio claude aceita e usa o nome.
        if ($a -in '--rc', '--remote-control') { $ligado = $true }
        $resto += $a
    }
    [pscustomobject]@{
        Ligado            = $ligado
        Resto             = $resto
        SettingsDoUsuario = [bool]($resto | Where-Object { "$_" -eq '--settings' -or "$_".StartsWith('--settings=') })
    }
}

function Get-ArquivoRc([bool]$ligado) {
    $f = Join-Path $Base ('rc\{0}.json' -f $(if ($ligado) { 'ligado' } else { 'desligado' }))
    if (-not (Test-Path -LiteralPath $f)) {
        New-Item -ItemType Directory -Force (Split-Path $f) | Out-Null
        Write-TextoSemBom $f ('{{ "remoteControlAtStartup": {0} }}' -f "$ligado".ToLower())
    }
    $f
}

# Argumentos finais para o claude: os do usuario mais o --settings com a decisao do RC.
# Se o usuario passou o proprio --settings, ele manda e o cc nao acrescenta outro.
function Get-ArgsClaude($decisaoRc) {
    if ($decisaoRc.SettingsDoUsuario) { return @($decisaoRc.Resto) }
    @($decisaoRc.Resto) + @('--settings', (Get-ArquivoRc $decisaoRc.Ligado))
}

# Insere um par "chave": valor logo depois do primeiro "{" de um JSON, sem reformatar o resto.
function Add-NoInicioJson([string]$texto, [string]$par) {
    if ($texto -match '^\s*\{\s*\}\s*$') { return "{`n  $par`n}`n" }
    $i = $texto.IndexOf('{')
    if ($i -lt 0) { throw 'settings.json sem objeto JSON' }
    $texto.Substring(0, $i + 1) + "`n  $par," + $texto.Substring($i + 1)
}

function Test-JsonValido([string]$texto) {
    try { $null = $texto | ConvertFrom-Json -ErrorAction Stop; return $true } catch { return $false }
}

$Script:MsgSettingsInvalido = 'settings.json invalido (JSON quebrado): nao mexi; corrija o arquivo e rode setup-contas.ps1'

# Arquivo ausente ou vazio vale como {}. Valido = $false quando o JSON do usuario ja esta quebrado:
# nesse caso nenhuma funcao grava nada.
function Get-SettingsMestre {
    $f = Join-Path $Mestre 'settings.json'
    $t = if (Test-Path -LiteralPath $f) { Get-Content -LiteralPath $f -Raw -Encoding UTF8 } else { $null }
    if (-not "$t".Trim()) { $t = '{}' }
    [pscustomobject]@{ Arquivo = $f; Texto = $t; Valido = (Test-JsonValido $t) }
}

# Sessoes abertas sem o cc (claude direto, IDE, app) nunca ligam o RC sozinhas.
function Set-RcDesligadoCompartilhado {
    $s = Get-SettingsMestre
    if (-not $s.Valido) { return $MsgSettingsInvalido }
    $chave = '"remoteControlAtStartup"\s*:\s*'
    if ($s.Texto -match ($chave + 'false')) { return $null }
    if ($s.Texto -match ($chave + 'true')) {
        $novo = $s.Texto -replace ($chave + 'true'), '"remoteControlAtStartup": false'
        $msg = "settings.json: remoteControlAtStartup estava true; agora false (o cc liga o RC so nas contas com rc ou com --rc)"
    } else {
        $novo = Add-NoInicioJson $s.Texto '"remoteControlAtStartup": false'
        $msg = 'settings.json: remoteControlAtStartup false gravado (RC so liga pelo cc)'
    }
    if (-not (Test-JsonValido $novo)) { return $MsgSettingsInvalido }
    Write-TextoSemBom $s.Arquivo $novo
    $msg
}

# ---- status line: conta e uso da sessao (statusline.ps1) ----

function Get-ContaAtual {
    $cs = (Get-Contas).Contas
    if (-not $env:CLAUDE_CONFIG_DIR) { return $cs | Where-Object Mestre | Select-Object -First 1 }
    $dir = [IO.Path]::GetFullPath($env:CLAUDE_CONFIG_DIR).TrimEnd('\')
    $cs | Where-Object { $_.Pasta.TrimEnd('\') -ieq $dir } | Select-Object -First 1
}

function Format-StatusLine($entrada, $conta, [int]$aviso) {
    $e = [char]27
    $pct = {
        param($v)
        if ($null -eq $v) { return '?' }
        $n = [int][math]::Round([double]$v)
        $cor = if ($n -ge 95) { '31' } elseif ($n -ge $aviso) { '33' } else { $null }
        if ($cor) { "$e[${cor}m$n%$e[0m" } else { "$n%" }
    }
    $partes = @()
    if ($conta) { $partes += $conta.Nome }
    $rl = $entrada.rate_limits
    if ($rl -and ($rl.five_hour -or $rl.seven_day)) {
        $partes += Format-Janelas (& $pct $rl.five_hour.used_percentage) (& $pct $rl.seven_day.used_percentage)
    }
    $partes -join " $Ponto "
}

$Script:MarcaStatusLine = 'statusline.ps1'

function Register-StatusLine {
    $s = Get-SettingsMestre
    if (-not $s.Valido) { return $MsgSettingsInvalido }
    if ($s.Texto -match '"statusLine"\s*:') {
        if ($s.Texto -match [regex]::Escape($MarcaStatusLine)) { return $null }
        return 'settings.json ja tem outra statusLine: nao mexi (a de conta e uso fica sem registrar)'
    }
    $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File \"{0}/{1}\"' -f ($Base -replace '\\', '/'), $MarcaStatusLine
    $novo = Add-NoInicioJson $s.Texto ('"statusLine": {{"type": "command", "command": "{0}"}}' -f $cmd)
    if (-not (Test-JsonValido $novo)) { return $MsgSettingsInvalido }
    Write-TextoSemBom $s.Arquivo $novo
    'settings.json: statusLine registrada (conta e uso da sessao)'
}

function Unregister-StatusLine {
    $s = Get-SettingsMestre
    if (-not $s.Valido) { return $MsgSettingsInvalido }
    $obj = '"statusLine"\s*:\s*\{[^{}]*' + [regex]::Escape($MarcaStatusLine) + '[^{}]*\}'
    if ($s.Texto -notmatch $obj) { return $null }
    $novo = [regex]::Replace($s.Texto, $obj + '\s*,\s*', '')
    if ($novo -eq $s.Texto) { $novo = [regex]::Replace($s.Texto, ',\s*' + $obj, '') }
    if ($novo -eq $s.Texto) { $novo = [regex]::Replace($s.Texto, $obj, '') }
    if (-not (Test-JsonValido $novo)) { return $MsgSettingsInvalido }
    Write-TextoSemBom $s.Arquivo $novo
    'settings.json: statusLine de conta e uso removida'
}

# Atualiza o bloco entre as marcas no ~/.claude/CLAUDE.md a partir de modelo-CLAUDE.md.
function Update-ClaudeMd {
    $cfg = Get-Contas
    $modelo = Get-Content (Join-Path $Base 'modelo-CLAUDE.md') -Raw -Encoding UTF8
    $linhas = foreach ($c in $cfg.Contas) {
        $papel = if ($c.Nome -eq $cfg.Publicar) { 'principal' } else { 'secundaria' }
        if ($c.Nome -eq $cfg.Padrao -and $cfg.Padrao -ne $cfg.Publicar) { $papel += ', padrao do cc' }
        $p = if ($c.Mestre) { '`~/.claude` (pasta mestre)' } else { '`~/.claude-contas/' + $c.Nome + '`' }
        '| {0} | {1} | {2} | {3} |' -f $c.Nome, $papel, $c.Email, $p
    }
    $pub = $cfg.Contas | Where-Object Nome -eq $cfg.Publicar
    $chr = $cfg.Contas | Where-Object Nome -eq $cfg.Chrome
    $chrome = if ($chr) { '`{0}` ({1})' -f $chr.Nome, $chr.Email } else { "n$([char]0xE3)o informada" }
    $bloco = $modelo.Replace('{{TABELA}}', ($linhas -join "`n")).
        Replace('{{PUBLICAR}}', $cfg.Publicar).Replace('{{EMAIL_PUBLICAR}}', $pub.Email).Replace('{{ATALHO}}', $cfg.Atalho).
        Replace('{{CHROME}}', $chrome)
    $bloco = "$MarcaInicio`n$($bloco.Trim())`n$MarcaFim"

    $md = Join-Path $Mestre 'CLAUDE.md'
    $atual = if (Test-Path $md) { Get-Content $md -Raw -Encoding UTF8 } else { '' }
    $i = $atual.IndexOf($MarcaInicio); $f = $atual.IndexOf($MarcaFim)
    if ($i -ge 0 -and $f -gt $i) {
        $novo = $atual.Substring(0, $i) + $bloco + $atual.Substring($f + $MarcaFim.Length)
    } elseif ($atual.Trim()) {
        $novo = $atual.TrimEnd() + "`n`n" + $bloco + "`n"
    } else {
        $novo = $bloco + "`n"
    }
    Write-TextoSemBom $md $novo
}

function Remove-BlocoClaudeMd {
    $md = Join-Path $Mestre 'CLAUDE.md'
    if (-not (Test-Path $md)) { return }
    $atual = Get-Content $md -Raw -Encoding UTF8
    $i = $atual.IndexOf($MarcaInicio); $f = $atual.IndexOf($MarcaFim)
    if ($i -lt 0 -or $f -lt $i) { return }
    $novo = ($atual.Substring(0, $i) + $atual.Substring($f + $MarcaFim.Length)).Trim()
    if ($novo) { Write-TextoSemBom $md ($novo + "`n") } else { Remove-Item $md }
}

function Get-ChaveAppPaths([string]$atalho) { "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\$atalho.exe" }
