<#
  Linha de base — tira uma "foto" de todos os lugares onde um programa pode se agendar para
  rodar sozinho (tarefas, serviços, drivers, inícios automáticos, Winlogon, WMI, pastas de inicialização).
  Guarda essa foto enquanto o PC está limpo. Depois, rodando de novo, compara e mostra só o que MUDOU.
  Assim fica fácil perceber qualquer coisa nova e voltar ao normal.

  NÃO muda nada no PC. Só lê e compara.

  Uso:
    linha-base.ps1            compara com a foto guardada (ou tira a primeira foto, se não houver)
    linha-base.ps1 -Salvar    tira uma foto nova e passa a usá-la como "normal" (faça só com o PC limpo)
    linha-base.ps1 -Ver       só mostra o estado de agora, sem comparar nem guardar
  Foto guardada em: C:\ProgramData\Blindagem\linha-base.json (só administradores alteram).
#>
param([switch]$Salvar, [switch]$Ver, [switch]$SemPausa)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$esteArquivo = $MyInvocation.MyCommand.Path
$pasta = Split-Path -Parent $esteArquivo
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Sem administrador alguns itens ficam de fora (caminho de serviços, detalhe de tarefas). Reabre pedindo permissão.
if (-not $admin -and -not $Ver) {
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$esteArquivo`"")
    if ($Salvar) { $argumentos += '-Salvar' }
    if ($SemPausa) { $argumentos += '-SemPausa' }
    try { $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argumentos -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode }
    catch { Write-Host '  Precisa de administrador e o pedido do UAC foi recusado. Rodando o que dá sem administrador...' -ForegroundColor Yellow }
}

$inicio = Get-Date
function Secao([string]$t) { Write-Host ''; Write-Host ("== $t ").PadRight(78, '=') -ForegroundColor Cyan }
function Linha([string]$r, [ConsoleColor]$c, [string]$t) { Write-Host ('  ' + $r.PadRight(12) + $t) -ForegroundColor $c }
function Fim { if (-not $SemPausa -and [Environment]::UserInteractive) { Write-Host ''; $null = Read-Host '  Aperte Enter para fechar' } }

# Serviços "por usuário" (ex.: CDPUserSvc_1429eb) ganham um código novo a cada login ou reinício.
# Se o nome é <modelo>_<código> e o <modelo> está marcado no registro como serviço por usuário,
# troca o código por "(por usuário)", para o mesmo serviço não aparecer como NOVO depois de reiniciar.
# Se dois itens caírem no mesmo nome, o segundo fica com o nome original (continua aparecendo, não some).
$script:modeloPorUsuario = @{}
function ChaveServico([string]$nome, $usadas) {
    if ($nome -match '^(.+)_[0-9a-f]{4,8}$') {
        $modelo = $matches[1]
        if (-not $script:modeloPorUsuario.ContainsKey($modelo)) {
            $t = (Get-ItemProperty -LiteralPath "HKLM:\SYSTEM\CurrentControlSet\Services\$modelo" -Name Type -ErrorAction SilentlyContinue).Type
            $script:modeloPorUsuario[$modelo] = ($null -ne $t) -and [bool]($t -band 0x40) -and -not ($t -band 0x80)
        }
        $k = "${modelo}_(por usuário)"
        if ($script:modeloPorUsuario[$modelo] -and -not $usadas.Contains($k)) { return $k }
    }
    return $nome
}

# ---------- coletores: cada um devolve { chave = detalhe } ----------
# A "chave" identifica o item (ex.: nome da tarefa). O "detalhe" é o que, se mudar, interessa (ex.: o programa que ela roda).
function Coletar {
    $r = [ordered]@{}

    $tarefas = [ordered]@{}
    foreach ($t in @(Get-ScheduledTask -ErrorAction SilentlyContinue)) {
        $acoes = @($t.Actions | ForEach-Object { if ($_.Execute) { "$($_.Execute) $($_.Arguments)".Trim() } elseif ($_.ClassId) { "COM $($_.ClassId)" } }) -join ' ; '
        $gatilhos = (@($t.Triggers | ForEach-Object { "$($_.CimClass.CimClassName)" -replace 'MSFT_Task', '' }) | Sort-Object -Unique) -join ','
        $usuario = "$($t.Principal.UserId)$($t.Principal.GroupId)"
        $tarefas["$($t.TaskPath)$($t.TaskName)"] = "roda=[$acoes] quando=[$gatilhos] como=[$usuario] autor=[$($t.Author)]"
    }
    $r['Tarefas agendadas'] = $tarefas

    $servicos = [ordered]@{}
    foreach ($s in @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)) {
        $servicos[(ChaveServico $s.Name $servicos)] = "programa=[$($s.PathName)] inicio=[$($s.StartMode)] conta=[$($s.StartName)]"
    }
    $r['Serviços'] = $servicos

    $drivers = [ordered]@{}
    foreach ($d in @(Get-CimInstance Win32_SystemDriver -ErrorAction SilentlyContinue)) {
        $drivers[$d.Name] = "programa=[$($d.PathName)] inicio=[$($d.StartMode)]"
    }
    $r['Drivers'] = $drivers

    $inicio = [ordered]@{}
    $chavesRun = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Run', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run', 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer\Run'
    )
    foreach ($c in $chavesRun) {
        $p = Get-ItemProperty -LiteralPath $c -ErrorAction SilentlyContinue
        if ($p) { foreach ($n in $p.PSObject.Properties.Name) { if ($n -notmatch '^PS') { $inicio[("$c\$n" -replace 'SOFTWARE\\', '')] = "$($p.$n)" } } }
    }
    $r['Inícios automáticos'] = $inicio

    $arranque = [ordered]@{}
    $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    foreach ($n in 'Shell', 'Userinit', 'Taskman', 'AppSetup', 'GinaDLL') { if ($wl.$n) { $arranque["Winlogon\$n"] = "$($wl.$n)" } }
    $ifeo = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options'
    foreach ($k in @(Get-ChildItem $ifeo -ErrorAction SilentlyContinue)) {
        $dv = (Get-ItemProperty $k.PSPath -ErrorAction SilentlyContinue).Debugger
        if ($dv) { $arranque["IFEO\$($k.PSChildName)\Debugger"] = "$dv" }
    }
    foreach ($par in @(
            @('HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows', 'AppInit_DLLs'),
            @('HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows NT\CurrentVersion\Windows', 'AppInit_DLLs'),
            @('HKLM:\SYSTEM\CurrentControlSet\Control\Lsa', 'Security Packages'),
            @('HKLM:\SYSTEM\CurrentControlSet\Control\Lsa', 'Authentication Packages'),
            @('HKLM:\SYSTEM\CurrentControlSet\Control\Lsa', 'Notification Packages'))) {
        $v = (Get-ItemProperty -LiteralPath $par[0] -Name $par[1] -ErrorAction SilentlyContinue).($par[1])
        if ($v) { $arranque[($par[0] -replace '.*\\', '') + "\$($par[1])"] = ((@($v) -join ', ')) }
    }
    $r['Arranque e segurança (Winlogon, IFEO, LSA)'] = $arranque

    $wmi = [ordered]@{}
    foreach ($f in @(Get-CimInstance -Namespace root\subscription -ClassName __EventFilter -ErrorAction SilentlyContinue)) { $wmi["Gatilho: $($f.Name)"] = "$($f.Query)" }
    foreach ($co in @(Get-CimInstance -Namespace root\subscription -ClassName __EventConsumer -ErrorAction SilentlyContinue)) {
        $det = "$($co.CommandLineTemplate)$($co.ExecutablePath)$($co.ScriptText)$($co.ScriptFileName)"
        if (-not $det) { $det = "(apenas registra no log: $($co.SourceName))" }
        $wmi["Ação: $($co.Name)"] = "$($co.CimClass.CimClassName): $det"
    }
    $r['Assinaturas do WMI'] = $wmi

    $pastasIni = [ordered]@{}
    foreach ($pi in @("$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup", "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup")) {
        foreach ($a in @(Get-ChildItem -LiteralPath $pi -File -Force -ErrorAction SilentlyContinue)) {
            $alvo = ''
            if ($a.Extension -eq '.lnk') { try { $alvo = ' -> ' + (New-Object -ComObject WScript.Shell).CreateShortcut($a.FullName).TargetPath } catch {} }
            $pastasIni[$a.FullName] = "$($a.Length) bytes$alvo"
        }
    }
    $r['Pastas de inicialização'] = $pastasIni

    return $r
}

# =====================================================================
Write-Host ''
Write-Host '  LINHA DE BASE — foto dos pontos onde algo pode rodar sozinho (não muda nada)' -ForegroundColor White
Write-Host ("  {0:dd/MM/yyyy HH:mm} | usuário {1} | {2}" -f $inicio, $env:USERNAME, $(if ($admin) { 'como administrador' } else { 'sem administrador (alguns itens ficam de fora)' })) -ForegroundColor DarkGray

$atual = Coletar

if ($Ver) {
    foreach ($cat in $atual.Keys) {
        Secao $cat
        if ($atual[$cat].Count -eq 0) { Linha '[vazio]' DarkGray 'nenhum item' }
        foreach ($k in $atual[$cat].Keys) { Linha '  •' Gray ("{0}  =>  {1}" -f $k, $atual[$cat][$k]) }
    }
    Fim; exit 0
}

$raizBackup = Join-Path $env:ProgramData 'Blindagem'
$arqBase = Join-Path $raizBackup 'linha-base.json'

function GravarBase($dados) {
    if (-not (Test-Path -LiteralPath $raizBackup)) {
        $null = New-Item -ItemType Directory -Path $raizBackup -Force -ErrorAction Stop
        $null = icacls $raizBackup /setowner '*S-1-5-32-544'
        $null = icacls $raizBackup /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX'
    }
    $env = [ordered]@{ Criado = (Get-Date).ToString('o'); PC = $env:COMPUTERNAME; Usuario = $env:USERNAME; ComoAdmin = $admin; Categorias = $dados }
    ConvertTo-Json -InputObject $env -Depth 6 | Set-Content -LiteralPath $arqBase -Encoding UTF8 -ErrorAction Stop
}

# ---------- salvar nova foto ----------
if ($Salvar -or -not (Test-Path -LiteralPath $arqBase)) {
    if (-not $Salvar) { Write-Host ''; Linha '[1ª VEZ]' Yellow 'Ainda não havia foto guardada; vou tirar a primeira agora.' }
    try {
        if (Test-Path -LiteralPath $arqBase) { Copy-Item -LiteralPath $arqBase -Destination ("$arqBase.{0:yyyyMMdd_HHmmss}.bak" -f $inicio) -Force -ErrorAction SilentlyContinue }
        GravarBase $atual
        $total = ($atual.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum
        Secao 'Pronto'
        Linha '[FOTO]' Green "Guardei $total item(ns) como o estado normal."
        Linha '[ONDE]' Gray $arqBase
        if (-not $admin) { Linha '[AVISO]' Yellow 'Foi tirada SEM administrador: serviços e drivers ficaram sem caminho. Rode como administrador para uma foto completa.' }
        Linha '[DICA]' Gray 'Rode "linha-base.ps1" de vez em quando: ele vai comparar com esta foto e avisar o que mudou.'
    } catch { Secao 'Erro'; Linha '[ERRO]' Red "Não consegui guardar a foto ($($_.Exception.Message))" }
    Fim; exit 0
}

# ---------- comparar com a foto guardada ----------
$base = $null
try { $base = Get-Content -LiteralPath $arqBase -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Secao 'Erro'; Linha '[ERRO]' Red "Não consegui ler a foto guardada ($($_.Exception.Message)). Use -Salvar para refazer."; Fim; exit 1 }
Write-Host ("  Comparando com a foto de {0:dd/MM/yyyy HH:mm}" -f ([datetime]$base.Criado)) -ForegroundColor DarkGray

$novos = 0; $mudados = 0; $sumidos = 0
foreach ($cat in $atual.Keys) {
    $antes = @{}
    if ($base.Categorias.$cat) {
        foreach ($pr in $base.Categorias.$cat.PSObject.Properties) {
            # A foto pode ser de antes desta regra: aplica a mesma troca de código nos serviços guardados.
            $k = if ($cat -eq 'Serviços') { ChaveServico $pr.Name $antes } else { $pr.Name }
            $antes[$k] = "$($pr.Value)"
        }
    }
    $agora = $atual[$cat]
    $linhasCat = New-Object System.Collections.Generic.List[object]
    foreach ($k in $agora.Keys) {
        if (-not $antes.ContainsKey($k)) { $linhasCat.Add(@('[NOVO]', 'Red', "$k`n                roda: $($agora[$k])")); $novos++ }
        elseif ($antes[$k] -ne "$($agora[$k])") { $linhasCat.Add(@('[MUDOU]', 'Yellow', "$k`n                antes: $($antes[$k])`n                agora: $($agora[$k])")); $mudados++ }
    }
    foreach ($k in $antes.Keys) { if (-not $agora.Contains($k)) { $linhasCat.Add(@('[SUMIU]', 'DarkGray', "$k")); $sumidos++ } }
    if ($linhasCat.Count -gt 0) {
        Secao $cat
        foreach ($l in $linhasCat) { Linha $l[0] $l[1] $l[2] }
    }
}

Secao 'Resumo'
if ($novos -eq 0 -and $mudados -eq 0) {
    Linha '[LIMPO]' Green 'Nada novo nem alterado desde a última foto. O PC continua como o normal guardado.'
    if ($sumidos -gt 0) { Linha '[INFO]' Gray "$sumidos item(ns) deixaram de existir (normal após desinstalar algo)." }
} else {
    Linha '[OLHE]' Yellow "NOVOS: $novos   ALTERADOS: $mudados   (sumidos: $sumidos)"
    Linha '[INFO]' Gray 'NOVO/ALTERADO em tarefa, serviço, início automático ou WMI é o que merece atenção.'
    Linha '[INFO]' Gray 'Reconhece a mudança (instalou um programa)? Rode "linha-base.ps1 -Salvar" para virar o novo normal.'
    Linha '[INFO]' Gray 'Não reconhece? Investigue o programa apontado antes de apagar; o seguranca.ps1 ajuda a resolver.'
}
Fim
exit $(if ($novos -or $mudados) { 2 } else { 0 })
