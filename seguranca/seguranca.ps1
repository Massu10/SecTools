<#
  Verificar segurança — relatório do PC.
  Primeiro só lê configurações, processos, portas e registros. No final, oferece resolver
  o que der por aqui mesmo, perguntando item por item; nada muda sem você responder S.
  Uso: dois cliques no atalho "Verificar segurança" da área de trabalho.
       Para ver mais (logins pela rede, exclusões do antivírus) e resolver tudo: botão direito no atalho > Executar como administrador.
  -Resolver: pula a pergunta "Quer resolver agora?" e vai direto para os itens (usado ao reabrir como administrador).
  Cópia de cada relatório: %LOCALAPPDATA%\Blindagem\relatorios (fora de Documentos, onde o anti-ransomware barra o PowerShell).
#>
param([switch]$Pausar, [switch]$Resolver)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

$inicio = Get-Date
$pasta = Split-Path -Parent $MyInvocation.MyCommand.Path
# Fora de Documentos: lá o Acesso controlado a pastas (anti-ransomware) barra o PowerShell e a cópia não era salva.
$pastaRel = Join-Path $env:LOCALAPPDATA 'Blindagem\relatorios'
$null = New-Item -ItemType Directory -Force -Path $pastaRel
$arquivoRel = Join-Path $pastaRel ('seguranca-{0:yyyy-MM-dd_HHmm}.txt' -f $inicio)
$transcrevendo = $false
try { Start-Transcript -Path $arquivoRel -Force | Out-Null; $transcrevendo = $true } catch {}

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$eu = $env:USERNAME

# ---------- saída ----------
$script:achados = New-Object System.Collections.Generic.List[object]
$script:n = @{ OK = 0; ATENCAO = 0; PERIGO = 0 }

function Secao([string]$t) { Write-Host ''; Write-Host ("== $t ").PadRight(78, '=') -ForegroundColor Cyan }
# Uma linha só por item: a cópia em .txt (Start-Transcript) ignora -NoNewline e quebraria o rótulo do texto.
function Linha([string]$rotulo, [ConsoleColor]$cor, [string]$texto) { Write-Host ('  ' + $rotulo.PadRight(11) + $texto) -ForegroundColor $cor }
function Det([string]$t) { Write-Host ('             ' + $t) -ForegroundColor DarkGray }
function ComoResolver([string]$r) { if ($r) { Write-Host ('             Como resolver: ' + $r) -ForegroundColor DarkYellow } }
function Ok([string]$t) { $script:n.OK++; Linha '[OK]' Green $t }
function Info([string]$t) { Linha '[INFO]' Gray $t }
# $c: correção opcional (feita com Conserto). Só roda no final, se a pessoa confirmar.
function Atencao([string]$t, [string]$r, $c) {
    $script:n.ATENCAO++; $script:achados.Add([pscustomobject]@{ Nivel = 'ATENÇÃO'; Texto = $t; Resolver = $r; Consertos = @(@($c) | Where-Object { $_ }) })
    Linha '[ATENÇÃO]' Yellow $t; ComoResolver $r
}
function Perigo([string]$t, [string]$r, $c) {
    $script:n.PERIGO++; $script:achados.Add([pscustomobject]@{ Nivel = 'PERIGO'; Texto = $t; Resolver = $r; Consertos = @(@($c) | Where-Object { $_ }) })
    Linha '[PERIGO]' Red $t; ComoResolver $r
}
# Uma correção: o que vai ser feito (texto), o código, e os dados que ele recebe.
# -SemAdmin: funciona sem administrador. -Reinicia: só vale depois de reiniciar. -PorUltimo: roda depois das outras (ex.: reiniciar o PC).
function Conserto([string]$Acao, [scriptblock]$Fazer, $Dados, [string]$Aviso, [switch]$SemAdmin, [switch]$Reinicia, [switch]$PorUltimo) {
    return [pscustomobject]@{ Acao = $Acao; Fazer = $Fazer; Dados = $Dados; Aviso = $Aviso; Admin = -not $SemAdmin; Reinicia = [bool]$Reinicia; PorUltimo = [bool]$PorUltimo }
}
function AbrirTela([string]$acao, [string]$endereco) {
    return Conserto $acao { param($d) Start-Process $d -ErrorAction Stop } $endereco -SemAdmin
}
# Só pergunta quando há alguém olhando a janela (não quando o script roda por outro programa).
$podePerguntar = [Environment]::UserInteractive -and -not [Console]::IsInputRedirected -and
    -not ([Environment]::GetCommandLineArgs() | Where-Object { $_ -match '^-noni' })
function Falhou([string]$oque, $erro) {
    $m = "$erro"; if ($erro -is [System.Management.Automation.ErrorRecord]) { $m = $erro.Exception.Message }
    Linha '[?]' Magenta "Não consegui ler $oque ($m)"
}

# ---------- utilidades ----------
$script:cacheAss = @{}
function Assinatura([string]$caminho) {
    if (-not $caminho) { return [pscustomobject]@{ Ok = $null; Quem = 'caminho não visível sem admin' } }
    $k = $caminho.ToLower()
    if ($script:cacheAss.ContainsKey($k)) { return $script:cacheAss[$k] }
    $r = $null
    if (-not (Test-Path -LiteralPath $caminho)) { $r = [pscustomobject]@{ Ok = $false; Quem = 'arquivo não existe mais' } }
    else {
        try {
            $s = Get-AuthenticodeSignature -LiteralPath $caminho -ErrorAction Stop
            $quem = ''; if ($s.SignerCertificate) { $quem = $s.SignerCertificate.GetNameInfo('SimpleName', $false) }
            if ($s.Status -eq 'Valid') { $r = [pscustomobject]@{ Ok = $true; Quem = $quem } }
            elseif ($caminho -match '\\WindowsApps\\') { $r = [pscustomobject]@{ Ok = $true; Quem = 'pacote da Microsoft Store' } }
            else { $r = [pscustomobject]@{ Ok = $false; Quem = "sem assinatura válida ($($s.Status))" } }
        } catch { $r = [pscustomobject]@{ Ok = $null; Quem = 'não consegui verificar a assinatura' } }
    }
    $script:cacheAss[$k] = $r
    return $r
}
function PastaSuspeita([string]$c, $ass) {
    if (-not $c) { return $false }
    if ($c -match '\\AppData\\Local\\Temp\\|\\Windows\\Temp\\|\\Downloads\\|^C:\\Users\\Public\\|\\\$Recycle\.Bin\\|^C:\\ProgramData\\[^\\]+$') { return $true }
    if ($c -match '\\AppData\\Roaming\\' -and -not ($ass -and $ass.Ok)) { return $true }
    return $false
}
function CaminhoExe([string]$cmd) {
    if (-not $cmd) { return $null }
    $c = [Environment]::ExpandEnvironmentVariables($cmd.Trim())
    if ($c.StartsWith('"')) { $fim = $c.IndexOf('"', 1); if ($fim -gt 1) { return $c.Substring(1, $fim - 1) } }
    if ($c -match '^(.+?\.(exe|com|bat|cmd|ps1|vbs|js|scr|sys|dll))(\s|$)') { return $matches[1] }
    return ($c -split '\s+')[0]
}
# Texto que manda baixar e rodar código, ou esconder a janela/o comando (em tarefas, skills e perfis do PowerShell).
$padraoBaixar = '(?i)(Invoke-WebRequest|\biwr\b|Invoke-RestMethod|\birm\b|curl(\.exe)?\s|wget\s|DownloadString|DownloadFile|Start-BitsTransfer)[^\r\n]{0,150}\|\s*(iex|Invoke-Expression|sh|bash|powershell|pwsh|cmd)\b|FromBase64String|-EncodedCommand\b|powershell[^\r\n]{0,60}-w(indowstyle)?\s+h(idden)?\b|certutil[^\r\n]{0,40}-urlcache|bitsadmin\s+/transfer'
# Programa (ou DLL) registrado para um CLSID do COM. Se existir no seu usuário (HKCU), é ele que vale para o que roda como você:
# truque conhecido para sequestrar uma tarefa do Windows sem mexer nela.
function DllCom([string]$clsid) {
    $id = '{' + $clsid.Trim('{}') + '}'
    foreach ($base in "Registry::HKEY_CURRENT_USER\Software\Classes\CLSID\$id", "Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Classes\CLSID\$id") {
        foreach ($tipo in 'InprocServer32', 'LocalServer32') {
            $k = "$base\$tipo"
            if (-not (Test-Path -LiteralPath $k)) { continue }
            $v = "$((Get-Item -LiteralPath $k).GetValue(''))"
            if ($v) { return [pscustomobject]@{ Caminho = (CaminhoExe $v); DoUsuario = ($base -like '*HKEY_CURRENT_USER*') } }
        }
    }
    return $null
}
# Campos de um evento do Windows (nome -> valor).
function DadosEvento($e) { $h = @{}; foreach ($d in ([xml]$e.ToXml()).Event.EventData.Data) { $h["$($d.Name)"] = "$($d.'#text')" }; return $h }
# Caminho de serviço/driver como o Windows grava (\SystemRoot\..., \??\C:\..., System32\drivers\...) virando caminho normal.
function CaminhoServico([string]$p) {
    if (-not $p) { return $null }
    $p = $p.Trim() -replace '^\\\?\?\\', '' -replace '^(?i)\\SystemRoot', $env:windir
    if ($p -match '^(?i)(System32|SysWOW64)\\') { $p = Join-Path $env:windir $p }
    return CaminhoExe $p
}
function Loopback([string]$a) { return ($a -match '^127\.' -or $a -eq '::1') }
function EnderecoPrivado([string]$a) {
    $a = $a -replace '^::ffff:', ''
    return ($a -match '^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.|0\.0\.0\.0$|::1?$|fe80:|f[cd][0-9a-f]{2}:)')
}

# ---------- dados compartilhados ----------
$sistemaWin = @('system', 'registry', 'smss.exe', 'csrss.exe', 'wininit.exe', 'services.exe', 'lsass.exe', 'svchost.exe', 'winlogon.exe',
    'spoolsv.exe', 'fontdrvhost.exe', 'dwm.exe', 'lsaiso.exe', 'vmms.exe', 'vmcompute.exe', 'memory compression', 'secure system', 'system idle process')
$script:procs = @{}
try {
    foreach ($p in Get-CimInstance Win32_Process -ErrorAction Stop) {
        $cam = $p.ExecutablePath
        if (-not $cam -and $sistemaWin -contains "$($p.Name)".ToLower() -and $p.Name -like '*.exe') { $cam = Join-Path $env:windir "System32\$($p.Name)" }
        $script:procs[[int]$p.ProcessId] = [pscustomobject]@{ Nome = $p.Name; Caminho = $cam; Mem = [double]$p.WorkingSetSize }
    }
} catch {}
function NomeProc($id) { $p = $script:procs[[int]$id]; if ($p) { return $p.Nome }; return "PID $id" }

$script:servPorPid = @{}
$servicos = @()
try {
    $servicos = @(Get-CimInstance Win32_Service -ErrorAction Stop)
    foreach ($s in $servicos) {
        if ($s.ProcessId) {
            $k = [int]$s.ProcessId
            if (-not $script:servPorPid.ContainsKey($k)) { $script:servPorPid[$k] = New-Object System.Collections.Generic.List[string] }
            $script:servPorPid[$k].Add($s.Name)
        }
    }
} catch {}

Write-Host ''
Write-Host '  VERIFICAR SEGURANÇA — primeiro só lê; no final pergunta antes de resolver qualquer coisa' -ForegroundColor White
Write-Host ("  {0:dd/MM/yyyy HH:mm} | usuário {1} | {2}" -f $inicio, $eu, $(if ($admin) { 'como administrador' } else { 'sem administrador (algumas verificações ficam de fora)' })) -ForegroundColor DarkGray

# =====================================================================
Secao 'Firewall'
$script:fwOk = $false
$script:regrasEntrada = @()
$mascaraAtiva = 0
try {
    foreach ($r in @(Get-NetConnectionProfile -ErrorAction Stop)) {
        switch ("$($r.NetworkCategory)") {
            'Public' { $mascaraAtiva = $mascaraAtiva -bor 4; Ok "Rede '$($r.Name)' ($($r.InterfaceAlias)) está como Pública: o firewall fica mais restrito" }
            'Private' { $mascaraAtiva = $mascaraAtiva -bor 2; Info "Rede '$($r.Name)' ($($r.InterfaceAlias)) está como Privada: ok em casa; em café, hotel ou trabalho, mude para Pública" }
            default { $mascaraAtiva = $mascaraAtiva -bor 1; Info "Rede '$($r.Name)' ($($r.InterfaceAlias)) é de domínio (empresa)" }
        }
    }
} catch { Falhou 'o tipo da rede' $_ }
if ($mascaraAtiva -eq 0) { $mascaraAtiva = 4 }

# Bloqueio total (AllowInboundRules = False): o Windows ignora TODAS as regras que liberam entrada.
$script:bloqueioTotal = $false
try {
    $nomesPerfil = @{ Domain = 'Domínio'; Private = 'Privado'; Public = 'Público' }
    $bitPerfil = @{ Domain = 1; Private = 2; Public = 4 }
    $mascaraTotal = 0
    # ActiveStore = o que está valendo agora (inclui políticas), não só o que foi salvo.
    foreach ($p in Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop) {
        $nome = $nomesPerfil["$($p.Name)"]
        if ("$($p.Enabled)" -ne 'True') {
            Perigo "Firewall do perfil $nome está DESLIGADO" 'Segurança do Windows > Firewall e proteção de rede > clique no perfil e ligue o Firewall' `
            (Conserto "Ligar o firewall do perfil $nome" { param($d) Set-NetFirewallProfile -Name $d -Enabled True -ErrorAction Stop } "$($p.Name)")
        }
        elseif ("$($p.DefaultInboundAction)" -eq 'Allow') {
            Perigo "Perfil $nome aceita qualquer conexão de entrada por padrão" "Num terminal de administrador: Set-NetFirewallProfile -Name $($p.Name) -DefaultInboundAction Block" `
            (Conserto "Bloquear por padrão as conexões de entrada no perfil $nome" { param($d) Set-NetFirewallProfile -Name $d -DefaultInboundAction Block -ErrorAction Stop } "$($p.Name)")
        }
        elseif ("$($p.AllowInboundRules)" -eq 'False') {
            $mascaraTotal = $mascaraTotal -bor $bitPerfil["$($p.Name)"]
            Ok "Firewall ligado no perfil $nome com bloqueio TOTAL de entrada (nem programas liberados recebem conexões)"
        }
        else { Ok "Firewall ligado no perfil $nome (entrada bloqueada por padrão)" }
    }
    $script:bloqueioTotal = (($mascaraAtiva -band $mascaraTotal) -eq $mascaraAtiva)
} catch { Falhou 'o firewall' $_ }

try {
    $todas = @(Get-NetFirewallRule -Direction Inbound -Action Allow -Enabled True -ErrorAction Stop)
    $script:regrasEntrada = @($todas | Where-Object { $pf = [int]$_.Profile; $pf -eq 0 -or ($pf -band $mascaraAtiva) })
    # Ler todos os filtros de uma vez é rápido, mas sem admin o Windows nega; aí lê regra por regra.
    function LerFiltros([string]$cmd) {
        $h = @{}
        foreach ($f in @(& $cmd -All -ErrorAction SilentlyContinue)) { $h[$f.InstanceID] = $f }
        if ($h.Count -eq 0) { foreach ($f in @($todas | & $cmd -ErrorAction SilentlyContinue)) { $h[$f.InstanceID] = $f } }
        return $h
    }
    $script:filtroPorta = LerFiltros 'Get-NetFirewallPortFilter'
    $script:filtroApp = LerFiltros 'Get-NetFirewallApplicationFilter'
    $script:filtroEnd = LerFiltros 'Get-NetFirewallAddressFilter'
    $script:filtroServ = LerFiltros 'Get-NetFirewallServiceFilter'
    # O registro mostra a condição "TTK" (porta dinâmica especial) que o PowerShell e o netsh escondem.
    $script:regraTTK = @{}
    try {
        $bruto = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\SharedAccess\Parameters\FirewallPolicy\FirewallRules' -ErrorAction Stop
        foreach ($pr in $bruto.PSObject.Properties) { if ("$($pr.Value)" -match '\|TTK2?(_\d+)?=') { $script:regraTTK[$pr.Name] = $true } }
    } catch {}
    $script:fwOk = ($script:filtroPorta.Count -gt 0)
    if (-not $script:fwOk) { Info 'Não consegui ler as portas das regras do firewall; a exposição das portas fica sem verificar' }

    # Apaga todas as regras (entrada e saída, liberar e bloquear) que apontam para o programa. O programa em si não é tocado.
    $apagarRegrasDoPrograma = {
        param($prog)
        $regras = @(Get-NetFirewallApplicationFilter -All -ErrorAction Stop |
            Where-Object { "$($_.Program)" -ne 'Any' -and [Environment]::ExpandEnvironmentVariables("$($_.Program)") -ieq $prog } | Get-NetFirewallRule -ErrorAction Stop)
        if ($regras.Count -gt 0) { $regras | Remove-NetFirewallRule -ErrorAction Stop }
        Det "$($regras.Count) regra(s) apagada(s)"
    }
    $terceiros = @($todas | Where-Object { -not $_.Group -and -not $_.Owner })
    if ($terceiros.Count -eq 0) { Ok 'Nenhuma regra de entrada criada por programas de fora do Windows' }
    else {
        Info 'Regras de entrada criadas por programas instalados:'
        $vistos = @{}; $progsAvisados = @{}
        foreach ($r in $terceiros) {
            $prog = 'qualquer programa'; $a = $script:filtroApp[$r.Name]
            if ($a -and "$($a.Program)" -ne 'Any') { $prog = [Environment]::ExpandEnvironmentVariables("$($a.Program)") }
            $chave = "$($r.DisplayName)|$prog"; if ($vistos.ContainsKey($chave)) { continue }; $vistos[$chave] = $true
            $f = $script:filtroPorta[$r.Name]; $portas = ''; if ($f) { $portas = " | $($f.Protocol) $(@($f.LocalPort) -join ',')" }
            $vale = if (([int]$r.Profile -eq 0) -or ([int]$r.Profile -band $mascaraAtiva)) { 'vale na rede atual' } else { 'não vale na rede atual' }
            if ($prog -ne 'qualquer programa' -and -not (Test-Path -LiteralPath $prog)) {
                if ($progsAvisados.ContainsKey($prog.ToLower())) { continue }; $progsAvisados[$prog.ToLower()] = $true
                Atencao "Regra '$($r.DisplayName)' libera um programa que não existe mais ($prog)" 'Firewall do Windows com Segurança Avançada (wf.msc) > Regras de Entrada > apague a regra' `
                (Conserto 'Apagar as regras do firewall que apontam para esse programa (ele já foi apagado, então não fazem falta)' $apagarRegrasDoPrograma $prog)
            } elseif (PastaSuspeita $prog (Assinatura $prog)) {
                if ($progsAvisados.ContainsKey($prog.ToLower())) { continue }; $progsAvisados[$prog.ToLower()] = $true
                Atencao "Regra '$($r.DisplayName)' libera um programa em pasta incomum ($prog)" 'Se não reconhece: wf.msc > Regras de Entrada > apague a regra e investigue o programa' `
                (Conserto 'Apagar as regras do firewall que liberam esse programa (o programa não é apagado)' $apagarRegrasDoPrograma $prog -Aviso 'Se você reconhece e usa esse programa, responda N: ele pode parar de funcionar pela rede.')
            } else {
                $obs = if ($r.DisplayName -match '^HNS Container Networking') { ' — rede interna do WSL/Docker' } else { '' }
                Det "$($r.DisplayName) -> $prog$portas ($vale)$obs"
            }
        }
        if ($script:bloqueioTotal) { Info 'Com o bloqueio total de entrada ligado, nenhuma dessas regras vale na rede atual' }
    }
} catch { Falhou 'as regras do firewall' $_ }

# =====================================================================
Secao 'Antivírus'
try {
    $avs = @(Get-CimInstance -Namespace root/SecurityCenter2 -ClassName AntivirusProduct -ErrorAction Stop)
    $ativos = @($avs | Where-Object { ([int]$_.productState -band 0x1000) })
    foreach ($a in $avs) {
        $st = [int]$a.productState
        $lig = if ($st -band 0x1000) { 'ligado' } else { 'desligado' }
        $atu = if ($st -band 0x10) { 'DESATUALIZADO' } else { 'atualizado' }
        if (($st -band 0x1000) -and -not ($st -band 0x10)) { Ok "$($a.displayName): $lig e $atu" }
        elseif ($ativos.Count -eq 0 -or ($st -band 0x10)) { Atencao "$($a.displayName): $lig, $atu" 'Abra o antivírus e atualize/ligue a proteção' }
        else { Info "$($a.displayName): $lig (outro antivírus está ativo)" }
    }
    if ($ativos.Count -eq 0) { Perigo 'Nenhum antivírus ligado' 'Segurança do Windows > Proteção contra vírus e ameaças > ligue a proteção em tempo real' }
    if ($ativos.Count -gt 1) { Atencao "Mais de um antivírus ligado ($(($ativos | ForEach-Object displayName) -join ', ')): costuma deixar o PC lento e um atrapalha o outro" 'Deixe só um (o Defender já basta para uso normal)' }
} catch { Falhou 'a lista de antivírus' $_ }

try {
    $mp = Get-CimInstance -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpComputerStatus -ErrorAction Stop
    if ("$($mp.AMRunningMode)" -match 'Passive|SxS') { Info "Microsoft Defender em modo passivo (outro antivírus é o principal)" }
    else {
        # A proteção contra alterações pode impedir mudanças por script; por isso confere depois e, se não pegou, abre a tela.
        $ligarDefender = {
            param($d)
            $p = @{ ($d.Opcao) = $false }; Set-MpPreference @p -ErrorAction Stop
            $agora = Get-CimInstance -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpComputerStatus -ErrorAction Stop
            if (-not $agora.($d.Status)) { Start-Process 'windowsdefender://threatsettings'; throw 'o Windows não deixou mudar por script; abri a tela do Defender para você ligar lá' }
        }
        $quickScan = Conserto 'Fazer uma verificação rápida agora' { Start-MpScan -ScanType QuickScan -ErrorAction Stop } -Aviso 'Leva alguns minutos; a janela fica parada até terminar.'
        if ($mp.RealTimeProtectionEnabled) { Ok 'Defender: proteção em tempo real ligada' }
        else {
            Perigo 'Defender: proteção em tempo real DESLIGADA' 'Segurança do Windows > Proteção contra vírus e ameaças > Gerenciar configurações > ligue Proteção em tempo real' `
            (Conserto 'Ligar a proteção em tempo real do Defender' $ligarDefender @{ Opcao = 'DisableRealtimeMonitoring'; Status = 'RealTimeProtectionEnabled' })
        }
        if ($mp.BehaviorMonitorEnabled) { Ok 'Defender: monitoramento de comportamento ligado' }
        else {
            Atencao 'Defender: monitoramento de comportamento desligado' 'Segurança do Windows > Proteção contra vírus e ameaças > Gerenciar configurações' `
            (Conserto 'Ligar o monitoramento de comportamento do Defender' $ligarDefender @{ Opcao = 'DisableBehaviorMonitoring'; Status = 'BehaviorMonitorEnabled' })
        }
        if ($mp.IsTamperProtected) { Ok 'Defender: proteção contra alterações ligada (vírus não conseguem desligar o antivírus)' }
        else {
            # O Windows não deixa ligar isso por script (de propósito); dá para abrir a tela certa.
            Atencao 'Defender: proteção contra alterações desligada' 'Segurança do Windows > Proteção contra vírus e ameaças > Gerenciar configurações > ligue Proteção contra Adulteração' `
            (AbrirTela 'Abrir a tela do Defender onde se liga a Proteção contra Adulteração (o Windows não deixa ligar por script)' 'windowsdefender://threatsettings')
        }
        $idade = [int64]$mp.AntivirusSignatureAge
        if ($idade -le 2) { Ok ("Defender: definições de vírus atualizadas ({0:dd/MM HH:mm})" -f $mp.AntivirusSignatureLastUpdated) }
        else {
            Atencao "Defender: definições de vírus com $idade dias" 'Segurança do Windows > Proteção contra vírus e ameaças > Atualizações de proteção > Verificar atualizações' `
            (Conserto 'Baixar as definições de vírus mais novas' { Update-MpSignature -ErrorAction Stop })
        }
        $rap = [int64]$mp.QuickScanAge
        if ($rap -eq 4294967295) { Atencao 'Defender: nunca fez verificação rápida' 'Segurança do Windows > Proteção contra vírus e ameaças > Verificação rápida' $quickScan }
        elseif ($rap -gt 7) { Atencao "Defender: última verificação rápida há $rap dias" 'Segurança do Windows > Proteção contra vírus e ameaças > Verificação rápida' $quickScan }
        else { Ok "Defender: verificação rápida em dia (há $rap dia(s))" }
        $comp = [int64]$mp.FullScanAge
        if ($comp -eq 4294967295) {
            Atencao 'Defender: nunca fez uma verificação completa' 'Segurança do Windows > Proteção contra vírus e ameaças > Opções de verificação > Verificação completa > Verificar agora (demora; dá para usar o PC)' `
            (Conserto 'Começar uma verificação completa numa janela separada (minimizada)' {
                Start-Process -FilePath "$env:ProgramFiles\Windows Defender\MpCmdRun.exe" -ArgumentList '-Scan', '-ScanType', '2' -WindowStyle Minimized -ErrorAction Stop
            } -Aviso 'Demora (pode passar de uma hora), mas dá para usar o PC normalmente. Não feche a janela minimizada.')
        }
        else { Info "Defender: última verificação completa há $comp dia(s)" }
    }
} catch { Falhou 'o estado do Defender' $_ }

try {
    $nomesAmeaca = @{}
    foreach ($t in @(Get-CimInstance -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpThreat -ErrorAction SilentlyContinue)) { $nomesAmeaca["$($t.ThreatID)"] = $t.ThreatName }
    $det = @(Get-CimInstance -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpThreatDetection -ErrorAction Stop | Where-Object { $_.InitialDetectionTime -gt (Get-Date).AddDays(-30) })
    if ($det.Count -eq 0) { Ok 'Nenhuma ameaça encontrada nos últimos 30 dias' }
    foreach ($d in $det) {
        $nome = $nomesAmeaca["$($d.ThreatID)"]; if (-not $nome) { $nome = "ameaça $($d.ThreatID)" }
        $onde = (@($d.Resources) | Select-Object -First 1) -replace '^file:_', ''
        if ($d.ActionSuccess) { Info ("Ameaça {0} em {1:dd/MM HH:mm} foi resolvida pelo Defender ({2})" -f $nome, $d.InitialDetectionTime, $onde) }
        else {
            Perigo ("Ameaça {0} em {1:dd/MM HH:mm} NÃO foi resolvida ({2})" -f $nome, $d.InitialDetectionTime, $onde) 'Segurança do Windows > Proteção contra vírus e ameaças > Ameaças atuais > Iniciar ações' `
            (Conserto 'Mandar o Defender remover as ameaças pendentes' { Remove-MpThreat -ErrorAction Stop })
        }
    }
} catch { Falhou 'o histórico de ameaças' $_ }

# =====================================================================
Secao 'Usuários'
try {
    $desativarConta = { param($d) Disable-LocalUser -SID $d -ErrorAction Stop }
    foreach ($u in Get-LocalUser -ErrorAction Stop) {
        $sid = "$($u.SID)"
        if ($sid -match '-501$') {
            if ($u.Enabled) {
                Perigo "Conta Convidado ($($u.Name)) está ATIVA: qualquer um entra sem senha" 'Num terminal de administrador: net user Convidado /active:no' `
                (Conserto "Desativar a conta Convidado ($($u.Name))" $desativarConta $sid)
            }
            continue
        }
        if ($sid -match '-500$') {
            if (-not $u.Enabled) { Ok "Conta Administrador interna ($($u.Name)) desativada" }
            else {
                # Nunca desativa a conta que está rodando o script (a pessoa ficaria sem acesso).
                $c = $null; if ($u.Name -ine $eu) { $c = Conserto "Desativar a conta Administrador interna ($($u.Name))" $desativarConta $sid -Aviso 'Nada é apagado; dá para reativar depois em lusrmgr.msc.' }
                Atencao "Conta Administrador interna ($($u.Name)) está ativa" 'Num terminal de administrador: net user Administrador /active:no (use a sua conta)' $c
            }
            continue
        }
        if ($sid -match '-50[34]$') { continue }
        if (-not $u.Enabled) { Info "Conta '$($u.Name)' existe, mas está desativada"; continue }
        $ult = if ($u.LastLogon) { '{0:dd/MM/yyyy HH:mm}' -f $u.LastLogon } else { 'nunca' }
        if ($u.Name -ieq $eu) { Ok "Conta '$($u.Name)' ativa (você; último login $ult)" }
        else {
            Atencao "Conta '$($u.Name)' está ativa (último login $ult). Foi você que criou?" 'Configurações > Contas > Outros usuários > se não reconhece, remova' `
            (Conserto "Desativar a conta '$($u.Name)'" $desativarConta $sid -Aviso 'Nada é apagado; dá para reativar em lusrmgr.msc. Se é de alguém da casa que usa o PC, responda N.')
        }
        if (-not $u.PasswordRequired) {
            Atencao "Conta '$($u.Name)' está marcada como 'senha não requerida' (aceitaria senha em branco)" "Num terminal de administrador: net user $($u.Name) /passwordreq:yes" `
            (Conserto "Marcar a conta '$($u.Name)' como 'senha obrigatória'" {
                param($d) $null = net user $d /passwordreq:yes; if ($LASTEXITCODE -ne 0) { throw "net user terminou com código $LASTEXITCODE" }
            } "$($u.Name)")
        }
    }
} catch { Falhou 'os usuários locais' $_ }

function MembrosGrupo([string]$sidGrupo) {
    try { return @(Get-LocalGroupMember -SID $sidGrupo -ErrorAction Stop) }
    catch {
        $nome = (New-Object Security.Principal.SecurityIdentifier $sidGrupo).Translate([Security.Principal.NTAccount]).Value -replace '^.*\\', ''
        $g = [ADSI]"WinNT://./$nome,group"
        return @($g.psbase.Invoke('Members') | ForEach-Object { [pscustomobject]@{ Name = $_.GetType().InvokeMember('Name', 'GetProperty', $null, $_, $null); SID = $null } })
    }
}
try {
    # Dados: grupo e membro (SID quando o Windows informa; senão o nome).
    $tirarDoGrupo = { param($d) Remove-LocalGroupMember -SID $d.Grupo -Member $d.Membro -ErrorAction Stop }
    foreach ($m in MembrosGrupo 'S-1-5-32-544') {
        $curto = "$($m.Name)" -replace '^.*\\', ''
        $membro = if ($m.SID) { "$($m.SID)" } else { "$($m.Name)" }
        if ($curto -ieq $eu) { Ok "Administradores: '$curto' (você)" }
        elseif ("$($m.SID)" -match '-500$') { Info "Administradores: '$curto' (conta interna do Windows)" }
        else {
            Atencao "Administradores: '$($m.Name)' também é administrador" 'Win+R > lusrmgr.msc > Grupos > Administradores > remova quem você não reconhece' `
            (Conserto "Tirar '$($m.Name)' do grupo Administradores (a conta continua existindo)" $tirarDoGrupo @{ Grupo = 'S-1-5-32-544'; Membro = $membro } -Aviso 'Se é alguém da casa que precisa instalar programas, responda N.')
        }
    }
    $rdp = @(MembrosGrupo 'S-1-5-32-555')
    if ($rdp.Count -eq 0) { Ok 'Ninguém no grupo de acesso pela Área de Trabalho Remota' }
    foreach ($m in $rdp) {
        $membro = if ($m.SID) { "$($m.SID)" } else { "$($m.Name)" }
        Atencao "Pode entrar pela Área de Trabalho Remota: '$($m.Name)'" 'Win+R > lusrmgr.msc > Grupos > Usuários da área de trabalho remota > remova' `
        (Conserto "Tirar '$($m.Name)' do grupo de acesso pela Área de Trabalho Remota" $tirarDoGrupo @{ Grupo = 'S-1-5-32-555'; Membro = $membro })
    }
} catch { Falhou 'os grupos de administradores' $_ }

# =====================================================================
Secao 'Portas abertas'
$portasWin = @{
    135  = 'RPC do Windows (conversa entre serviços). Necessária dentro do PC, não aberta para a rede'
    139  = 'NetBIOS (compartilhamento de arquivos antigo). Dispensável se você não compartilha pastas na rede'
    445  = 'SMB (compartilhamento de arquivos e impressoras). Dispensável se você não compartilha pastas na rede'
    2179 = 'Hyper-V (ver a tela de máquinas virtuais a partir de outro computador; o WSL/Docker não usa)'
    5040 = 'Dispositivos conectados do Windows (continuar no PC, compartilhar por proximidade)'
    5357 = 'Descoberta de dispositivos na rede (WSD)'
    7680 = 'Otimização de Entrega (Windows Update compartilhando atualizações com outros PCs)'
}
$portasRisco = @{ 21 = 'FTP'; 22 = 'SSH (acesso remoto por terminal)'; 23 = 'Telnet'; 3389 = 'Área de Trabalho Remota'; 5900 = 'VNC (acesso remoto à tela)'; 5985 = 'WinRM (controle remoto do PowerShell)'; 5986 = 'WinRM (controle remoto do PowerShell, HTTPS)' }

$ipInterface = @{}
try { foreach ($i in Get-NetIPAddress -ErrorAction Stop) { $ipInterface[$i.IPAddress] = $i.InterfaceAlias } } catch {}
function Interna([string]$a) { $al = $ipInterface[$a]; return ($al -and $al -match 'vEthernet|WSL|Loopback') }

function PortaCasa($lista, [int]$porta) {
    foreach ($item in @($lista)) {
        $t = "$item"
        if ($t -eq 'Any') { return $true }
        if ($t -eq 'RPC' -and $porta -ge 49152) { return $true }
        if ($t -eq 'RPCEPMap' -and $porta -eq 135) { return $true }
        if ($t -match '^(\d+)-(\d+)$') { if ($porta -ge [int]$matches[1] -and $porta -le [int]$matches[2]) { return $true } }
        elseif ($t -match '^\d+$' -and [int]$t -eq $porta) { return $true }
    }
    return $false
}
function ProtoCasa([string]$p, [string]$proto) { return ($p -eq 'Any' -or $p -eq $proto -or ($proto -eq 'TCP' -and $p -eq '6') -or ($proto -eq 'UDP' -and $p -eq '17')) }
function Exposicao([int]$porta, [string]$proto, [string]$caminho, [int]$idp) {
    if ($script:bloqueioTotal) { return $null }
    $melhor = $null; $certas = New-Object System.Collections.Generic.List[object]
    foreach ($r in $script:regrasEntrada) {
        # Regras com porta dinâmica especial (Wi-Fi Direct, Teredo): o PowerShell mostra "Any", mas não valem para portas comuns.
        if ($script:regraTTK.ContainsKey($r.Name)) { continue }
        # Regra com dono (Owner) é de um app da Loja: só vale para os processos daquele app, nunca para svchost/lsass.
        if ($r.Owner) { continue }
        $f = $script:filtroPorta[$r.Name]; if (-not $f) { continue }
        if (-not (ProtoCasa "$($f.Protocol)" $proto)) { continue }
        if (-not (PortaCasa $f.LocalPort $porta)) { continue }
        $a = $script:filtroApp[$r.Name]; $prog = 'Any'; if ($a) { $prog = "$($a.Program)" }
        $talvez = $false
        if ($prog -ne 'Any') {
            $exp = [Environment]::ExpandEnvironmentVariables($prog).ToLower()
            if ($exp -eq 'system') { if ($idp -ne 4) { continue } }
            elseif ($idp -eq 4) { continue }
            elseif (-not $caminho) { $talvez = $true }
            elseif ($exp -ne $caminho.ToLower()) { continue }
        }
        # Regra presa a um serviço (ex.: só o WMI) não vale para outros serviços do mesmo svchost.
        $sf = $script:filtroServ[$r.Name]
        if ($sf -and "$($sf.Service)" -ne 'Any') {
            $hospedados = @(); if ($script:servPorPid.ContainsKey($idp)) { $hospedados = @($script:servPorPid[$idp]) }
            if (-not ($hospedados | Where-Object { $_ -ieq "$($sf.Service)" })) { continue }
        }
        $ad = $script:filtroEnd[$r.Name]; $remoto = 'Any'; if ($ad) { $remoto = (@($ad.RemoteAddress) -join ',') }
        $escopo = if ($remoto -eq 'Any') { 'qualquer endereço' } elseif ($remoto -match 'LocalSubnet') { 'só a rede local' } else { "só $remoto" }
        $novo = [pscustomobject]@{ Regra = $r.DisplayName; Escopo = $escopo; Talvez = $talvez; Regras = $null }
        if (-not $talvez) { $certas.Add($r) }
        if (-not $melhor -or ($melhor.Talvez -and -not $talvez) -or ($escopo -eq 'qualquer endereço' -and -not $talvez)) { $melhor = $novo }
    }
    # Todas as regras que com certeza liberam a porta (para desativar, se a pessoa pedir).
    if ($melhor) { $melhor.Regras = $certas.ToArray() }
    return $melhor
}
# Correção para porta liberada: desativa (não apaga) as regras que liberam. Dá para religar em wf.msc.
function ConsertoPorta($e, [string]$oque, [string]$aviso) {
    if (-not $e -or $e.Talvez -or @($e.Regras).Count -eq 0) { return $null }
    $nomes = (@($e.Regras | ForEach-Object { $_.DisplayName } | Select-Object -Unique) | ForEach-Object { "'$_'" }) -join ', '
    return Conserto "Fechar $oque no firewall: desativar a(s) regra(s) $nomes (dá para religar em wf.msc)" {
        param($d) $d | Disable-NetFirewallRule -ErrorAction Stop
    } $e.Regras -Aviso $aviso
}
function TextoExposicao($e) {
    if ($script:bloqueioTotal) { return 'bloqueada pelo firewall (bloqueio total de entrada)' }
    if (-not $script:fwOk) { return 'firewall não verificado' }
    if (-not $e) { return 'bloqueada pelo firewall na rede atual' }
    if ($e.Talvez) { return "talvez liberada no firewall (regra '$($e.Regra)')" }
    return "liberada no firewall para $($e.Escopo) (regra '$($e.Regra)')"
}

try {
    $tcp = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { -not (Loopback $_.LocalAddress) })
    $locais = @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object { Loopback $_.LocalAddress } | Select-Object -ExpandProperty LocalPort -Unique)
    Info "$($locais.Count) porta(s) só para o próprio PC (127.0.0.1), invisíveis na rede: não entram na lista"
    $grupos = $tcp | Group-Object { "$($_.LocalPort)|$($_.OwningProcess)" } | Sort-Object { [int]$_.Group[0].LocalPort }
    foreach ($g in $grupos) {
        $porta = [int]$g.Group[0].LocalPort; $idp = [int]$g.Group[0].OwningProcess
        $ends = @($g.Group | ForEach-Object { "$($_.LocalAddress)" } | Select-Object -Unique)
        $p = $script:procs[$idp]; $nomeP = NomeProc $idp; $np = "$nomeP".ToLower()
        $serv = @(); if ($script:servPorPid.ContainsKey($idp)) { $serv = @($script:servPorPid[$idp]) }
        $quem = $nomeP; if ($serv.Count -gt 0 -and $serv.Count -le 3) { $quem = "$nomeP [$($serv -join ', ')]" }
        if (@($ends | Where-Object { -not (Interna $_) }).Count -eq 0) { Info "Porta $porta — ${quem}: só na rede interna do WSL/Docker ($($ends -join ', '))"; continue }
        $caminho = if ($p) { $p.Caminho } else { $null }
        $e = $null; if ($script:fwOk) { $e = Exposicao $porta 'TCP' $caminho $idp }
        $txt = TextoExposicao $e

        if ($portasRisco.ContainsKey($porta)) {
            $d = $portasRisco[$porta]
            if ($e -and $e.Escopo -eq 'qualquer endereço' -and -not $e.Talvez) { Perigo "Porta $porta ($d) aberta por $quem e $txt" 'Se você não usa esse acesso remoto, desligue o serviço/programa' }
            else { Atencao "Porta $porta ($d) ligada por $quem; $txt" 'Se você não usa esse acesso remoto, desligue o serviço/programa' }
        } elseif ($portasWin.ContainsKey($porta)) {
            $d = $portasWin[$porta]
            if (-not $e) { Ok "Porta $porta — ${d}: $txt" }
            elseif ($porta -eq 139 -or $porta -eq 445) {
                Atencao "Porta $porta — ${d}: $txt" 'Se não compartilha pastas: Configurações > Rede e Internet > Configurações de rede avançadas > Configurações de compartilhamento avançadas > desligue Compartilhamento de arquivos e impressoras' `
                (ConsertoPorta $e "a porta $porta" 'Se você compartilha pastas ou impressora com outros PCs da casa, responda N.')
            }
            elseif ($porta -eq 135 -or $porta -eq 2179) {
                Atencao "Porta $porta — ${d}: $txt" 'O Docker/WSL não precisa disso aberto para a rede; só serve para controlar o Hyper-V de outro computador' `
                (ConsertoPorta $e "a porta $porta" 'Se você controla máquinas virtuais deste PC a partir de outro computador, responda N.')
            }
            else { Info "Porta $porta — ${d}: $txt" }
            if ($porta -eq 7680) { Det 'Para desligar: Configurações > Windows Update > Opções avançadas > Otimização de Entrega > desligue "Permitir downloads de outros PCs"' }
        } elseif ($np -match '^com\.docker|^docker|^wslrelay|^vpnkit') {
            Info "Porta $porta — Docker (projeto local): $txt"
        } elseif ($porta -ge 49152 -and @('lsass.exe', 'wininit.exe', 'services.exe', 'spoolsv.exe', 'svchost.exe') -contains $np) {
            $extra = if ($np -eq 'spoolsv.exe') { ', impressão' } else { '' }
            if ($e) { Info "Porta $porta — RPC dinâmica do Windows ($quem$extra): $txt" } else { Ok "Porta $porta — RPC dinâmica do Windows ($quem$extra): $txt" }
        } elseif ($np -eq 'svchost.exe' -or $np -eq 'system') {
            if ($e) { Info "Porta $porta — serviço do Windows ($quem): $txt" } else { Ok "Porta $porta — serviço do Windows ($quem): $txt" }
        } else {
            $ass = Assinatura $caminho
            if ($e -and -not $ass.Ok) {
                Atencao "Porta $porta aberta por $quem ($($ass.Quem)) e $txt" 'Se não reconhece o programa, feche-o e apague a regra em wf.msc > Regras de Entrada' `
                (ConsertoPorta $e "a porta $porta" 'Se você reconhece e usa esse programa pela rede, responda N.')
            }
            elseif ($e) { Info "Porta $porta — $quem ($($ass.Quem)): $txt" }
            else { Ok "Porta $porta — $quem ($($ass.Quem)): $txt" }
        }
    }
} catch { Falhou 'as portas TCP' $_ }

try {
    $udp = @(Get-NetUDPEndpoint -ErrorAction Stop | Where-Object { -not (Loopback $_.LocalAddress) })
    $deFora = @($udp | Where-Object { $p = $script:procs[[int]$_.OwningProcess]; -not ($p -and $p.Caminho -and $p.Caminho -like "$env:windir\*") -and -not ($sistemaWin -contains "$(NomeProc $_.OwningProcess)".ToLower()) })
    $grupos = $deFora | Group-Object { "$($_.LocalPort)|$($_.OwningProcess)" } | Sort-Object { [int]$_.Group[0].LocalPort }
    if (@($grupos).Count -eq 0) { Ok 'Nenhuma porta UDP aberta por programas de fora do Windows' }
    foreach ($g in $grupos) {
        $porta = [int]$g.Group[0].LocalPort; $idp = [int]$g.Group[0].OwningProcess
        if (@($g.Group | Where-Object { -not (Interna "$($_.LocalAddress)") }).Count -eq 0) { continue }
        $p = $script:procs[$idp]; $caminho = if ($p) { $p.Caminho } else { $null }
        $ass = Assinatura $caminho
        $e = $null; if ($script:fwOk) { $e = Exposicao $porta 'UDP' $caminho $idp }
        $txt = TextoExposicao $e
        $d = if ($porta -eq 5353) { ' (mDNS, descoberta de aparelhos na rede)' } elseif ($porta -eq 5355) { ' (LLMNR)' } elseif ($porta -eq 1900) { ' (SSDP/UPnP)' } else { '' }
        if ($e -and -not $ass.Ok) {
            Atencao "UDP $porta$d aberta por $(NomeProc $idp) ($($ass.Quem)) e $txt" 'Se não reconhece o programa, feche-o e apague a regra em wf.msc > Regras de Entrada' `
            (ConsertoPorta $e "a porta UDP $porta" 'Se você reconhece e usa esse programa pela rede, responda N.')
        }
        else { Info "UDP $porta$d — $(NomeProc $idp) ($($ass.Quem)): $txt" }
    }
} catch { Falhou 'as portas UDP' $_ }

# =====================================================================
Secao 'Acesso remoto'
try {
    $ts = Get-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -ErrorAction Stop
    if ($ts.fDenyTSConnections -eq 0) {
        Atencao 'Área de Trabalho Remota LIGADA: dá para entrar neste PC pela rede' 'Configurações > Sistema > Área de Trabalho Remota > desligue, se não usa' `
        (Conserto 'Desligar a Área de Trabalho Remota e fechar as regras dela no firewall' {
            Set-ItemProperty 'HKLM:\System\CurrentControlSet\Control\Terminal Server' -Name fDenyTSConnections -Value 1 -Type DWord -ErrorAction Stop
            Get-NetFirewallRule -Group '@FirewallAPI.dll,-28752' -ErrorAction SilentlyContinue | Disable-NetFirewallRule -ErrorAction SilentlyContinue
        } -Aviso 'Se você entra neste PC de outro computador (Área de Trabalho Remota), responda N.')
    }
    else { Ok 'Área de Trabalho Remota desligada' }
    $ra = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' -ErrorAction SilentlyContinue
    if ($ra -and $ra.fAllowToGetHelp -eq 1) { Info 'Assistência Remota permitida (só funciona com convite seu). Para desligar: Win+R > SystemPropertiesRemote > desmarque "Permitir conexões de Assistência Remota"' }
    else { Ok 'Assistência Remota desligada' }
} catch { Falhou 'a Área de Trabalho Remota' $_ }

# Para o serviço agora e marca como Desativado (não desinstala nada; dá para voltar em services.msc).
$pararServico = {
    param($nome)
    Set-Service -Name $nome -StartupType Disabled -ErrorAction Stop
    Stop-Service -Name $nome -Force -ErrorAction Stop
}
try {
    $remotos = @{ WinRM = 'WinRM (controle remoto do PowerShell)'; sshd = 'Servidor SSH'; RemoteRegistry = 'Registro Remoto'; ftpsvc = 'Servidor FTP'; TlntSvr = 'Telnet'; SNMP = 'SNMP' }
    $algum = $false
    foreach ($nome in $remotos.Keys) {
        $s = $servicos | Where-Object { $_.Name -eq $nome } | Select-Object -First 1
        if (-not $s) { continue }
        if ($s.State -eq 'Running') {
            $algum = $true
            Atencao "Serviço $($remotos[$nome]) está rodando" "Se não usa: Win+R > services.msc > $nome > Parar e Tipo de inicialização Desativado" `
            (Conserto "Parar o serviço $($remotos[$nome]) e impedir que ele inicie com o Windows" $pararServico $nome -Aviso 'Se você usa esse acesso remoto, responda N.')
        }
        elseif ($s.StartMode -eq 'Auto') { $algum = $true; Info "Serviço $($remotos[$nome]) inicia com o Windows, mas está parado" }
    }
    if (-not $algum) { Ok 'Nenhum serviço de acesso remoto (WinRM, SSH, Registro Remoto, FTP, Telnet) rodando' }
} catch { Falhou 'os serviços de acesso remoto' $_ }

try {
    $smb1 = $false
    $drv = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\mrxsmb10' -ErrorAction SilentlyContinue
    if ($drv -and $drv.Start -ne 4) { $smb1 = $true }
    $par = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters' -ErrorAction SilentlyContinue
    if ($par -and $par.SMB1 -eq 1) { $smb1 = $true }
    if ($smb1) {
        Atencao 'SMB1 ligado (protocolo antigo usado pelo vírus WannaCry)' 'Win+R > optionalfeatures > desmarque "Suporte para Compartilhamento de Arquivos SMB 1.0/CIFS"' `
        (Conserto 'Desligar o SMB1' {
            Disable-WindowsOptionalFeature -Online -FeatureName SMB1Protocol -NoRestart -ErrorAction Stop | Out-Null
            Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force -ErrorAction SilentlyContinue
        } -Aviso 'Só atrapalha se você usa um aparelho muito antigo na rede (HD de rede ou impressora de mais de 10 anos).' -Reinicia)
    }
    else { Ok 'SMB1 (protocolo antigo, usado pelo WannaCry) desligado' }
} catch { Falhou 'o SMB1' $_ }

try {
    $padraoRemoto = 'anydesk|teamviewer|rustdesk|ultraviewer|screenconnect|connectwise|splashtop|radmin|vnc|remoting_host|ammyy|supremo|dwagent|getscreen|meshagent|zohoassist|logmein|parsec|nomachine|remotepc|aeroadmin'
    $achouRem = @($script:procs.Values | Where-Object { "$($_.Nome)" -match $padraoRemoto } | Select-Object -ExpandProperty Nome -Unique)
    $achouSrv = @($servicos | Where-Object { $_.Name -match $padraoRemoto -or $_.DisplayName -match $padraoRemoto } | Sort-Object Name -Unique)
    if ($achouRem.Count + $achouSrv.Count -eq 0) { Ok 'Nenhum programa de acesso remoto (AnyDesk, TeamViewer, RustDesk...) instalado como serviço ou rodando' }
    foreach ($x in $achouRem) {
        Atencao "Programa de acesso remoto rodando: $x" 'Se não foi você que abriu, desconecte a internet e investigue: alguém pode estar controlando o PC' `
        (Conserto "Fechar o $x agora (não desinstala)" {
            param($d) Get-Process -Name ([IO.Path]::GetFileNameWithoutExtension($d)) -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction Stop
        } $x -Aviso 'Se é você (ou alguém de confiança) usando esse acesso agora, responda N.')
    }
    foreach ($s in $achouSrv) {
        Atencao "Serviço de acesso remoto instalado: $($s.DisplayName)" 'Se não usa, desinstale em Configurações > Aplicativos' `
        (Conserto "Parar o serviço '$($s.DisplayName)' e impedir que ele inicie com o Windows (para tirar de vez, desinstale em Configurações > Aplicativos)" $pararServico $s.Name -Aviso 'Se você usa esse programa para acessar este PC de longe, responda N.')
    }
} catch { Falhou 'os programas de acesso remoto' $_ }

try {
    $extras = @(Get-CimInstance Win32_Share -ErrorAction Stop | Where-Object { $_.Name -notmatch '^(ADMIN\$|IPC\$|print\$|[A-Z]\$)$' })
    if ($extras.Count -eq 0) { Ok 'Só os compartilhamentos padrão do Windows (ADMIN$, C$, IPC$)' }
    foreach ($s in $extras) {
        Atencao "Pasta compartilhada na rede: '$($s.Name)' -> $($s.Path)" 'Explorador de Arquivos > botão direito na pasta > Propriedades > Compartilhamento > pare de compartilhar, se não precisa' `
        (Conserto "Parar de compartilhar '$($s.Name)' (a pasta e os arquivos continuam onde estão)" { param($d) Remove-SmbShare -Name $d -Force -ErrorAction Stop } "$($s.Name)" -Aviso 'Se outro PC ou a TV da casa abre essa pasta, responda N.')
    }
} catch { Falhou 'os compartilhamentos' $_ }

# =====================================================================
Secao 'Processos'
$descricoes = @{
    'code.exe' = 'VS Code (um processo por janela, extensão e terminal)'; 'claude.exe' = 'Claude Code (um por sessão aberta)'
    'svchost.exe' = 'Serviços do Windows'; 'vmmemwsl' = 'Linux do WSL (é a memória do Docker)'; 'vmmem' = 'Máquina virtual (WSL/Docker)'
    'wsl.exe' = 'WSL (Linux no Windows, usado pelo Docker)'; 'wslhost.exe' = 'WSL (Linux no Windows, usado pelo Docker)'; 'wslservice.exe' = 'WSL (Linux no Windows, usado pelo Docker)'; 'wslrelay.exe' = 'WSL (Linux no Windows, usado pelo Docker)'
    'msrdc.exe' = 'Janelas Linux do WSL (WSLg); não é acesso remoto'; 'docker desktop.exe' = 'Docker Desktop'; 'com.docker.backend.exe' = 'Docker Desktop'; 'com.docker.build.exe' = 'Docker Desktop'
    'docker-agent.exe' = 'IA do Docker (Gordon)'; 'msedgewebview2.exe' = 'Componente do Edge usado por apps (Widgets, Teams...)'; 'msedge.exe' = 'Microsoft Edge'; 'chrome.exe' = 'Google Chrome'
    'conhost.exe' = 'Janela de console de algum terminal ou comando'; 'openconsole.exe' = 'Terminal do VS Code'; 'powershell.exe' = 'PowerShell (terminais do VS Code, scripts e este relatório)'; 'pwsh.exe' = 'PowerShell 7'; 'cmd.exe' = 'Prompt de comando'
    'copilot-runtime.exe' = 'GitHub Copilot do VS Code'; 'msmpeng.exe' = 'Microsoft Defender (antivírus)'; 'nissrv.exe' = 'Microsoft Defender (rede)'; 'mpdefendercoreservice.exe' = 'Microsoft Defender'
    'explorer.exe' = 'Área de trabalho e Explorador de Arquivos'; 'dwm.exe' = 'Desenho das janelas do Windows'; 'node.exe' = 'Node.js (ferramentas como Vite)'; 'python.exe' = 'Python'
    'vmcompute.exe' = 'Hyper-V (base do WSL/Docker)'; 'vmms.exe' = 'Hyper-V (base do WSL/Docker)'; 'vmwp.exe' = 'Hyper-V (base do WSL/Docker)'
    'searchhost.exe' = 'Pesquisa do Windows'; 'startmenuexperiencehost.exe' = 'Menu Iniciar'; 'widgetboard.exe' = 'Widgets do Windows'; 'runtimebroker.exe' = 'Permissões de apps do Windows'; 'dllhost.exe' = 'Componentes do Windows'
    'memory compression' = 'Memória comprimida do Windows'; 'secure system' = 'Proteção de memória do Windows'; 'registry' = 'Registro do Windows'
}
try {
    Info 'Programas que mais aparecem (quantidade e memória):'
    $grupos = $script:procs.Values | Group-Object { "$($_.Nome)".ToLower() } | ForEach-Object {
        [pscustomobject]@{ Nome = $_.Group[0].Nome; Qtde = $_.Count; MB = [math]::Round((($_.Group | Measure-Object Mem -Sum).Sum) / 1MB); Caminho = ($_.Group | Where-Object Caminho | Select-Object -First 1).Caminho }
    } | Sort-Object MB -Descending
    foreach ($g in ($grupos | Where-Object { $_.Qtde -ge 3 -or $_.MB -ge 150 } | Select-Object -First 18)) {
        $d = $descricoes["$($g.Nome)".ToLower()]
        if (-not $d) { $d = (Assinatura $g.Caminho).Quem }
        Det ("{0,-28} x{1,-3} {2,6} MB  {3}" -f $g.Nome, $g.Qtde, $g.MB, $d)
    }
    Info "Total: $($script:procs.Count) processos. Muitos 'svchost', 'Code' e 'conhost' é normal."

    $semCaminho = 0; $problemas = 0
    $porCaminho = $script:procs.Values | Where-Object { $_.Caminho } | Group-Object { $_.Caminho.ToLower() }
    $semCaminho = @($script:procs.Values | Where-Object { -not $_.Caminho }).Count
    foreach ($g in $porCaminho) {
        $c = $g.Group[0].Caminho; $ass = Assinatura $c
        if (PastaSuspeita $c $ass) { $problemas++; Atencao "Processo rodando de pasta incomum: $($g.Group[0].Nome) ($c; $($ass.Quem))" 'Se não reconhece, feche-o no Gerenciador de Tarefas e rode uma verificação completa do Defender' }
        elseif ($ass.Ok -eq $false) { $problemas++; Atencao "Processo sem assinatura digital: $($g.Group[0].Nome) ($c)" 'Se não reconhece, pesquise o nome do arquivo e rode uma verificação completa do Defender' }
    }
    if ($problemas -eq 0) { Ok "Todos os $(@($porCaminho).Count) programas em execução estão em pastas normais e assinados" }
    if ($semCaminho -gt 0 -and -not $admin) { Info "$semCaminho processo(s) do sistema não mostram o caminho sem administrador" }
} catch { Falhou 'os processos' $_ }

# =====================================================================
Secao 'Inicialização com o Windows'
# $conserto: como desativar esse item, caso ele seja suspeito.
function ChecarItem([string]$rotulo, [string]$caminho, $conserto) {
    if (-not $caminho) { Det "$rotulo (sem programa: ação interna do Windows)"; return }
    $ass = Assinatura $caminho
    if ($ass.Quem -eq 'arquivo não existe mais') { Atencao "$rotulo aponta para um programa que não existe mais: $caminho" 'Normalmente é sobra de programa desinstalado (ou atualização em andamento). Se continuar aparecendo e você não reconhece: Gerenciador de Tarefas > Inicializar (ou Agendador de Tarefas / services.msc) > desative' $conserto }
    elseif (PastaSuspeita $caminho $ass) { Atencao "$rotulo inicia de pasta incomum: $caminho ($($ass.Quem))" 'Se não reconhece: Gerenciador de Tarefas > Inicializar (ou Agendador de Tarefas) > desative e investigue' $conserto }
    elseif ($ass.Ok -eq $false) { Atencao "$rotulo sem assinatura válida: $caminho ($($ass.Quem))" 'Se não reconhece: Gerenciador de Tarefas > Inicializar (ou Agendador de Tarefas) > desative' $conserto }
    else { Det "$rotulo -> $caminho ($($ass.Quem))" }
}
# O Gerenciador de Tarefas guarda "desativado" em StartupApproved: 1º byte ímpar = desativado.
function InicioDesativado([string]$aprov, [string]$nome) {
    # Confere antes de ler: erro dentro de try ainda sujaria a cópia .txt do relatório.
    if (-not $aprov -or -not (Test-Path -LiteralPath $aprov)) { return $false }
    try {
        $k = Get-Item -LiteralPath $aprov -ErrorAction Stop
        if (@($k.GetValueNames()) -notcontains $nome) { return $false }
        $v = $k.GetValue($nome); return ($v -and $v.Length -gt 0 -and ($v[0] -band 1))
    } catch { return $false }
}
# Desativa do mesmo jeito que o Gerenciador de Tarefas (dá para religar lá, na aba Inicializar).
$desativarInicio = {
    param($d)
    if (-not (Test-Path -LiteralPath $d.Aprov)) { $null = New-Item -Path $d.Aprov -Force -ErrorAction Stop }
    $bytes = [byte[]](@(3, 0, 0, 0) + [BitConverter]::GetBytes([DateTime]::Now.ToFileTime()))
    $null = New-ItemProperty -LiteralPath $d.Aprov -Name $d.Nome -Value $bytes -PropertyType Binary -Force -ErrorAction Stop
}
try {
    Info 'Programas que abrem sozinhos (registro e pasta Inicializar):'
    $baseAprov = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    $fontes = @(
        @{ Chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'; Aprov = "HKCU:\$baseAprov\Run" }
        @{ Chave = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Aprov = $null }
        @{ Chave = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'; Aprov = "HKLM:\$baseAprov\Run" }
        @{ Chave = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'; Aprov = $null }
        @{ Chave = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Aprov = "HKLM:\$baseAprov\Run32" }
    )
    foreach ($fo in $fontes) {
        $k = $fo.Chave
        if (-not (Test-Path $k)) { continue }
        foreach ($pr in (Get-ItemProperty $k).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }) {
            if (InicioDesativado $fo.Aprov $pr.Name) { Det "$($pr.Name) (desativado no Gerenciador de Tarefas)"; continue }
            $semAdmin = $k -like 'HKCU:*'
            $c = if ($fo.Aprov) {
                Conserto "Desativar '$($pr.Name)' na inicialização (igual ao Gerenciador de Tarefas; dá para religar lá)" $desativarInicio @{ Aprov = $fo.Aprov; Nome = $pr.Name } -SemAdmin:$semAdmin
            } else {
                Conserto "Tirar '$($pr.Name)' da lista de execução única (RunOnce)" { param($d) Remove-ItemProperty -LiteralPath $d.Chave -Name $d.Nome -ErrorAction Stop } @{ Chave = $k; Nome = $pr.Name } -SemAdmin:$semAdmin
            }
            ChecarItem $pr.Name (CaminhoExe "$($pr.Value)") $c
        }
    }
    $wsh = New-Object -ComObject WScript.Shell
    $pastas = @(
        @{ Pasta = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"; Aprov = "HKCU:\$baseAprov\StartupFolder"; SemAdmin = $true }
        @{ Pasta = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"; Aprov = "HKLM:\$baseAprov\StartupFolder"; SemAdmin = $false }
    )
    foreach ($pa in $pastas) {
        foreach ($f in Get-ChildItem $pa.Pasta -File -ErrorAction SilentlyContinue | Where-Object Name -ne 'desktop.ini') {
            if (InicioDesativado $pa.Aprov $f.Name) { Det "Inicializar: $($f.Name) (desativado no Gerenciador de Tarefas)"; continue }
            $alvo = $f.FullName; if ($f.Extension -eq '.lnk') { $alvo = $wsh.CreateShortcut($f.FullName).TargetPath }
            $c = Conserto "Desativar '$($f.Name)' na inicialização (igual ao Gerenciador de Tarefas; o arquivo fica onde está)" $desativarInicio @{ Aprov = $pa.Aprov; Nome = $f.Name } -SemAdmin:($pa.SemAdmin)
            ChecarItem "Inicializar: $($f.Name)" $alvo $c
        }
    }
} catch { Falhou 'os programas da inicialização' $_ }

try {
    Info 'Tarefas agendadas de fora do Windows:'
    $tarefas = @(Get-ScheduledTask -ErrorAction Stop | Where-Object { $_.TaskPath -notlike '\Microsoft\*' -and $_.State -ne 'Disabled' })
    if ($tarefas.Count -eq 0) { Det '(nenhuma)' }
    $desativarTarefa = { param($d) $null = Disable-ScheduledTask -TaskPath $d.Pasta -TaskName $d.Nome -ErrorAction Stop }
    foreach ($t in $tarefas) {
        $c = Conserto "Desativar a tarefa agendada '$($t.TaskName)' (não apaga; dá para religar no Agendador de Tarefas)" $desativarTarefa @{ Pasta = $t.TaskPath; Nome = $t.TaskName }
        $algum = $false
        foreach ($a in @($t.Actions)) {
            if ($a.Execute) { $algum = $true; ChecarItem "Tarefa $($t.TaskName)" (CaminhoExe "$($a.Execute)") $c }
            elseif ($a.ClassId) { $com = DllCom "$($a.ClassId)"; if ($com) { $algum = $true; ChecarItem "Tarefa $($t.TaskName) (DLL)" $com.Caminho $c } }
        }
        if (-not $algum) { Det "$($t.TaskPath)$($t.TaskName) (ação interna, normal em tarefas do Windows)" }
    }
} catch { Falhou 'as tarefas agendadas' $_ }

try {
    # Vírus se escondem com nome de tarefa da Microsoft: confere o programa (ou a DLL) de cada uma e só mostra as estranhas.
    $ms = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.TaskPath -like '\Microsoft\*' -and $_.State -ne 'Disabled' })
    $ruinsMs = 0
    foreach ($t in $ms) {
        $nomeT = "$($t.TaskPath)$($t.TaskName)"
        foreach ($a in @($t.Actions)) {
            $cam = $null; $doUsuario = $false
            if ($a.Execute) {
                $cam = CaminhoExe "$($a.Execute)"
                if ($cam -and -not [IO.Path]::IsPathRooted($cam)) { $cam = (Get-Command $cam -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }
                $argsT = [Environment]::ExpandEnvironmentVariables("$($a.Arguments)")
                if ($cam -match '\\(rundll32|regsvr32)\.exe$' -and $argsT -match '^\s*"?([A-Za-z]:\\[^",]+\.(dll|ocx|cpl))') { $cam = $matches[1] }
                elseif ($argsT -match $padraoBaixar) {
                    $ruinsMs++
                    Atencao "Tarefa com nome da Microsoft roda um comando que baixa ou esconde código: $nomeT -> $($a.Execute) $argsT" 'Truque comum de vírus. Win+R > taskschd.msc > procure a tarefa > Desativar; depois rode a Verificação Offline do Defender' `
                    (Conserto "Desativar a tarefa '$($t.TaskName)' (não apaga; dá para religar no Agendador de Tarefas)" $desativarTarefa @{ Pasta = $t.TaskPath; Nome = $t.TaskName })
                    continue
                }
            } elseif ($a.ClassId) {
                $com = DllCom "$($a.ClassId)"; if ($com) { $cam = $com.Caminho; $doUsuario = $com.DoUsuario }
            }
            if (-not $cam) { continue }
            $ass = Assinatura $cam
            if ($ass.Quem -eq 'arquivo não existe mais') { continue }
            if ($doUsuario -or $ass.Ok -eq $false -or (PastaSuspeita $cam $ass) -or ($ass.Ok -and $ass.Quem -notmatch 'Microsoft')) {
                $ruinsMs++
                $porque = if ($doUsuario) { 'teve a DLL trocada só no seu usuário (sequestro de COM)' } else { "roda programa que não é da Microsoft ($($ass.Quem))" }
                Atencao "Tarefa com nome da Microsoft $porque`: $nomeT -> $cam" 'Truque comum de vírus para se esconder. Win+R > taskschd.msc > procure a tarefa > Desativar; depois rode a Verificação Offline do Defender' `
                (Conserto "Desativar a tarefa '$($t.TaskName)' (não apaga; dá para religar no Agendador de Tarefas)" $desativarTarefa @{ Pasta = $t.TaskPath; Nome = $t.TaskName })
            }
        }
    }
    if ($ruinsMs -eq 0) { Ok "As $($ms.Count) tarefas do próprio Windows rodam só programas assinados pela Microsoft" }
} catch { Falhou 'as tarefas do Windows' $_ }

try {
    Info 'Serviços automáticos de fora do Windows:'
    $fora = @($servicos | Where-Object { $_.StartMode -eq 'Auto' -and $_.PathName } | Where-Object { $c = CaminhoExe $_.PathName; $c -and $c -notlike "$env:windir\*" })
    if ($fora.Count -eq 0) { Det '(nenhum)' }
    foreach ($s in $fora) {
        $c = Conserto "Parar o serviço '$($s.DisplayName)' e impedir que ele inicie com o Windows (dá para voltar em services.msc)" $pararServico $s.Name -Aviso 'Se é de um programa que você usa, ele pode parar de funcionar.'
        ChecarItem "Serviço $($s.DisplayName)" (CaminhoExe $s.PathName) $c
    }
} catch { Falhou 'os serviços' $_ }

# =====================================================================
Secao 'Conexões com a internet agora'
$dominios = @{
    'api.anthropic.com' = 'Anthropic'; 'claude.ai' = 'Anthropic'; 'console.anthropic.com' = 'Anthropic'; 'mcp-proxy.anthropic.com' = 'Anthropic'; 'statsig.anthropic.com' = 'Anthropic'
    'http-intake.logs.us5.datadoghq.com' = 'Datadog, registros de erro do Claude Code'; 'github.com' = 'GitHub'; 'api.github.com' = 'GitHub'; 'api.githubcopilot.com' = 'GitHub Copilot'
    'copilot-proxy.githubusercontent.com' = 'GitHub Copilot'; 'marketplace.visualstudio.com' = 'Microsoft (VS Code)'; 'update.code.visualstudio.com' = 'Microsoft (VS Code)'
    'default.exp-tas.com' = 'Microsoft (VS Code)'; 'mobile.events.data.microsoft.com' = 'Microsoft (telemetria)'; 'settings-win.data.microsoft.com' = 'Microsoft (Windows)'
    'login.microsoftonline.com' = 'Microsoft (login)'; 'hub.docker.com' = 'Docker'; 'registry-1.docker.io' = 'Docker'; 'desktop.docker.com' = 'Docker'; 'ai-backend-service.docker.com' = 'Docker (IA)'
    'www.google.com' = 'Google'; 'www.bing.com' = 'Microsoft (Bing)'
}
$donosPtr = [ordered]@{ '1e100\.net$' = 'Google'; 'googleusercontent\.com$' = 'nuvem do Google'; 'amazonaws\.com$' = 'nuvem da Amazon'; 'cloudfront\.net$' = 'Amazon CloudFront'; 'akamai' = 'Akamai (CDN)'; 'msedge\.net$|microsoft\.com$|azure|windows\.net$' = 'Microsoft'; 'github' = 'GitHub'; 'cloudflare' = 'Cloudflare' }
try {
    $mapaIp = @{}
    foreach ($d in $dominios.Keys) {
        foreach ($r in @(Resolve-DnsName -Name $d -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue)) { if ($r.IPAddress -and -not $mapaIp.ContainsKey($r.IPAddress)) { $mapaIp[$r.IPAddress] = "$d ($($dominios[$d]))" } }
    }
    # Sem nenhuma conexão (ex.: PC offline) o Windows dá erro em vez de lista vazia; isso não é falha de leitura.
    $con = @(Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue | Where-Object { -not (EnderecoPrivado "$($_.RemoteAddress)") })
    if ($con.Count -eq 0) { Info 'Nenhuma conexão externa aberta agora' }
    foreach ($g in ($con | Group-Object { "$($_.RemoteAddress)|$($_.OwningProcess)" } | Sort-Object { NomeProc $_.Group[0].OwningProcess })) {
        $ip = "$($g.Group[0].RemoteAddress)" -replace '^::ffff:', ''; $idp = [int]$g.Group[0].OwningProcess
        $p = $script:procs[$idp]; $caminho = if ($p) { $p.Caminho } else { $null }
        $ass = Assinatura $caminho
        $nome = $mapaIp[$ip]
        if (-not $nome) {
            $ptr = (@(Resolve-DnsName -Name $ip -Type PTR -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue) | Where-Object NameHost | Select-Object -First 1).NameHost
            if ($ptr) { $dono = ''; foreach ($k in $donosPtr.Keys) { if ($ptr -match $k) { $dono = " ($($donosPtr[$k]))"; break } }; $nome = "$ptr$dono" } else { $nome = 'sem nome conhecido' }
        }
        $linha = "$(NomeProc $idp) ($($ass.Quem)) -> $ip = $nome  [$($g.Count) conexão(ões)]"
        if ($ass.Ok -eq $false -or (PastaSuspeita $caminho $ass)) { Atencao "Conexão de programa não confiável: $linha" 'Se não reconhece o programa, desconecte a internet, feche-o e rode uma verificação completa do Defender' }
        else { Det $linha }
    }
    Info 'Programa assinado (Microsoft, Anthropic, Docker...) falando com servidor sem nome conhecido é normal: muitos servidores de nuvem não têm nome reverso.'
} catch { Falhou 'as conexões' $_ }

# =====================================================================
Secao 'Hosts, DNS e proxy'
try {
    $esperadas = 'host\.docker\.internal|gateway\.docker\.internal|kubernetes\.docker\.internal'
    $linhas = @(Get-Content "$env:windir\System32\drivers\etc\hosts" -ErrorAction Stop | Where-Object { $_ -notmatch '^\s*(#|$)' })
    $estranhas = @($linhas | Where-Object { $_ -notmatch $esperadas })
    if ($estranhas.Count -eq 0) {
        $doDocker = if (@($linhas).Count -gt 0) { " ($(@($linhas).Count) linha(s) do Docker, esperadas)" } else { '' }
        Ok "Arquivo hosts sem redirecionamentos estranhos$doDocker"
    }
    foreach ($l in $estranhas) {
        Atencao "Linha no arquivo hosts: '$($l.Trim())' (pode desviar um site para outro endereço)" 'Se não foi você: abra o Bloco de Notas como administrador, edite C:\Windows\System32\drivers\etc\hosts e apague a linha' `
        (Conserto 'Desativar essa linha do arquivo hosts (vira comentário; antes guardo uma cópia do arquivo ao lado dele)' {
            param($linha)
            $arq = "$env:windir\System32\drivers\etc\hosts"
            $todas = @(Get-Content -LiteralPath $arq -ErrorAction Stop)
            Copy-Item -LiteralPath $arq -Destination ('{0}.copia-{1:yyyyMMdd-HHmmss}' -f $arq, (Get-Date)) -ErrorAction Stop
            $marca = '# desativada por seguranca.ps1 em ' + (Get-Date -Format 'dd/MM/yyyy') + ': '
            $novas = [string[]]@($todas | ForEach-Object { if ($_ -ceq $linha) { $marca + $_ } else { $_ } })
            [IO.File]::WriteAllLines($arq, $novas, (New-Object Text.UTF8Encoding $false))
        } $l)
    }
} catch { Falhou 'o arquivo hosts' $_ }

try {
    $publicos = @('1.1.1.1', '1.0.0.1', '1.1.1.2', '1.0.0.2', '1.1.1.3', '1.0.0.3', '8.8.8.8', '8.8.4.4', '9.9.9.9', '149.112.112.112', '208.67.222.222', '208.67.220.220', '94.140.14.14', '94.140.15.15', '185.228.168.9', '185.228.169.9')
    foreach ($c in @(Get-NetIPConfiguration -ErrorAction Stop | Where-Object { $_.IPv4DefaultGateway -and "$($_.NetAdapter.Status)" -eq 'Up' })) {
        $gw = "$(@($c.IPv4DefaultGateway)[0].NextHop)"
        $v4 = @($c.DNSServer | Where-Object { $_.AddressFamily -eq 2 } | ForEach-Object { $_.ServerAddresses })
        $v6 = @($c.DNSServer | Where-Object { $_.AddressFamily -eq 23 } | ForEach-Object { $_.ServerAddresses })
        foreach ($d in $v4) {
            if ($d -eq $gw) { Ok "DNS ($($c.InterfaceAlias)): $d, o seu roteador" }
            elseif ($publicos -contains $d) { Ok "DNS ($($c.InterfaceAlias)): $d, DNS público conhecido" }
            elseif (EnderecoPrivado $d) { Info "DNS ($($c.InterfaceAlias)): $d, na rede local (normal se for o roteador ou um bloqueador como Pi-hole)" }
            else {
                Atencao "DNS ($($c.InterfaceAlias)): $d, endereço desconhecido (pode desviar sites)" 'Se não foi você: Configurações > Rede e Internet > Ethernet/Wi-Fi > Atribuição de servidor DNS > Editar > Automático (DHCP)' `
                (Conserto "Voltar o DNS de '$($c.InterfaceAlias)' para automático (o do roteador)" { param($a) Set-DnsClientServerAddress -InterfaceAlias $a -ResetServerAddresses -ErrorAction Stop } "$($c.InterfaceAlias)" -Aviso 'Se foi você que escolheu esse DNS (VPN, bloqueador de anúncios), responda N.')
            }
        }
        if ($v6.Count -gt 0) { Info "DNS IPv6 ($($c.InterfaceAlias)): $($v6 -join ', ') (normalmente do roteador ou do provedor)" }
    }
} catch { Falhou 'o DNS' $_ }

try {
    $is = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' -ErrorAction Stop
    $temProxy = $false
    $chaveIS = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $avisoProxy = 'Se você usa VPN, proxy da empresa ou um programa que precisa disso, responda N.'
    if ($is.ProxyEnable -eq 1) {
        $temProxy = $true
        Atencao "Proxy ligado no Windows: $($is.ProxyServer) (todo o tráfego do navegador passa por ele)" 'Se não foi você: Configurações > Rede e Internet > Proxy > desligue' `
        (Conserto 'Desligar o proxy do Windows' { Set-ItemProperty $chaveIS -Name ProxyEnable -Value 0 -Type DWord -ErrorAction Stop } -Aviso $avisoProxy -SemAdmin)
    }
    if ($is.AutoConfigURL) {
        $temProxy = $true
        Atencao "Script de proxy automático: $($is.AutoConfigURL)" 'Se não foi você: Configurações > Rede e Internet > Proxy > desligue "Usar script de instalação"' `
        (Conserto 'Desligar o script de proxy automático' { Remove-ItemProperty $chaveIS -Name AutoConfigURL -ErrorAction Stop } -Aviso $avisoProxy -SemAdmin)
    }
    if (-not $temProxy) { Ok 'Sem proxy no Windows/navegador' }
    $wh = (@(netsh winhttp show proxy) -join ' ')
    if ($wh -match 'Direct access|Acesso direto') { Ok 'Sem proxy do sistema (WinHTTP)' }
    elseif ($wh) {
        Atencao "Proxy do sistema (WinHTTP) configurado: $(($wh -replace '\s+', ' ').Trim())" 'Se não foi você, num terminal de administrador: netsh winhttp reset proxy' `
        (Conserto 'Tirar o proxy do sistema (WinHTTP)' { $null = netsh winhttp reset proxy; if ($LASTEXITCODE -ne 0) { throw "netsh terminou com código $LASTEXITCODE" } } -Aviso $avisoProxy)
    }
} catch { Falhou 'o proxy' $_ }

# =====================================================================
Secao 'Extensões do navegador'
function NomeExtensao($m, [string]$dir) {
    $n = "$($m.name)"
    if ($n -match '^__MSG_(.+)__$') {
        $chave = $matches[1]
        foreach ($loc in @('pt_BR', 'pt_PT', 'pt', "$($m.default_locale)", 'en', 'en_US')) {
            if (-not $loc) { continue }
            $arq = Join-Path $dir "_locales\$loc\messages.json"
            if (-not (Test-Path -LiteralPath $arq)) { continue }
            try {
                $msgs = Get-Content -Raw -Encoding UTF8 -LiteralPath $arq | ConvertFrom-Json
                $prop = $msgs.PSObject.Properties | Where-Object { $_.Name -ieq $chave } | Select-Object -First 1
                if ($prop -and $prop.Value.message) { return $prop.Value.message }
            } catch {}
        }
    }
    return $n
}
$navs = [ordered]@{
    'Edge'    = @{ Pasta = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"; Pagina = 'edge://extensions' }
    'Chrome'  = @{ Pasta = "$env:LOCALAPPDATA\Google\Chrome\User Data"; Pagina = 'chrome://extensions' }
    'Brave'   = @{ Pasta = "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"; Pagina = 'brave://extensions' }
    'Vivaldi' = @{ Pasta = "$env:LOCALAPPDATA\Vivaldi\User Data"; Pagina = 'vivaldi://extensions' }
}
try {
    $algumNav = $false
    foreach ($nav in $navs.Keys) {
        $base = $navs[$nav].Pasta; if (-not (Test-Path -LiteralPath $base)) { continue }
        $algumNav = $true; $qtde = 0
        foreach ($perfil in Get-ChildItem -LiteralPath $base -Directory | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'Preferences') }) {
            # Sites com permissão de notificação: é daí que vêm os avisos falsos de "vírus" e as propagandas no canto da tela.
            try {
                $pj = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $perfil.FullName 'Preferences') | ConvertFrom-Json
                $notif = $pj.profile.content_settings.exceptions.notifications
                $sites = @(if ($notif) { $notif.PSObject.Properties | Where-Object { "$($_.Value.setting)" -eq '1' } | ForEach-Object { $_.Name -replace ',\*$', '' } })
                if ($sites.Count -gt 0) {
                    Atencao "$nav ($($perfil.Name)): $($sites.Count) site(s) podem mostrar notificações: $(($sites | Select-Object -First 5) -join ', ')" "Avisos falsos de vírus e propagandas costumam vir daqui. Se não reconhece, tire em $($navs[$nav].Pagina -replace 'extensions$', 'settings/content/notifications')"
                }
            } catch {}
            $pastaExt = Join-Path $perfil.FullName 'Extensions'; if (-not (Test-Path -LiteralPath $pastaExt)) { continue }
            foreach ($ext in Get-ChildItem -LiteralPath $pastaExt -Directory) {
                $ver = Get-ChildItem -LiteralPath $ext.FullName -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
                if (-not $ver) { continue }
                $mf = Join-Path $ver.FullName 'manifest.json'; if (-not (Test-Path -LiteralPath $mf)) { continue }
                try { $m = Get-Content -Raw -Encoding UTF8 -LiteralPath $mf | ConvertFrom-Json } catch { continue }
                $qtde++
                $nome = NomeExtensao $m $ver.FullName
                $perms = @($m.permissions) + @($m.host_permissions) + @(@($m.content_scripts) | Where-Object { $_ } | ForEach-Object { $_.matches })
                $todos = @($perms | Where-Object { "$_" -match '<all_urls>|^\*://\*/|^https?://\*/' }).Count -gt 0
                $rot = "$nav ($($perfil.Name)): '$nome' v$($m.version)"
                if ($todos) { Atencao "$rot pode ler e alterar todos os sites que você abre" "Tudo bem se você instalou e confia (bloqueador de anúncios, gerenciador de senhas). Se não reconhece, remova em $($navs[$nav].Pagina)" }
                else { Ok "$rot (sem acesso a todos os sites)" }
            }
        }
        if ($qtde -eq 0) { Ok "$($nav): nenhuma extensão instalada" }
    }
    # Políticas forçadas: é assim que programas indesejados trocam a página inicial e a busca ou instalam extensões que não saem.
    foreach ($k in 'HKLM:\SOFTWARE\Policies\Google\Chrome', 'HKCU:\SOFTWARE\Policies\Google\Chrome', 'HKLM:\SOFTWARE\Policies\Microsoft\Edge', 'HKCU:\SOFTWARE\Policies\Microsoft\Edge', 'HKLM:\SOFTWARE\Policies\BraveSoftware\Brave', 'HKCU:\SOFTWARE\Policies\BraveSoftware\Brave') {
        if (-not (Test-Path -LiteralPath $k)) { continue }
        $vals = @(@((Get-Item -LiteralPath $k).GetValueNames()) + @(Get-ChildItem -LiteralPath $k -ErrorAction SilentlyContinue | ForEach-Object { $_.PSChildName }) | Where-Object { $_ })
        $ruinsPol = @($vals | Where-Object { $_ -match 'ExtensionInstallForcelist|ExtensionSettings|HomepageLocation|RestoreOnStartupURLs|NewTabPageLocation|DefaultSearchProvider|Proxy' })
        if ($ruinsPol.Count -gt 0) { Atencao "Configuração forçada no navegador ($k): $($ruinsPol -join ', ')" 'Se não foi você (nem a empresa): programas indesejados usam isso para trocar a página inicial e a busca ou instalar extensões que não saem. Apague a chave no regedit e rode a verificação completa do Defender' }
        else { Info "Ajustes por política no navegador ($k): $($vals -join ', ')" }
    }
    if (-not $algumNav) { Info 'Nenhum navegador Chromium (Edge, Chrome, Brave, Vivaldi) encontrado' }
    if (Test-Path "$env:APPDATA\Mozilla\Firefox\Profiles") { Info 'Firefox instalado: confira as extensões em about:addons (este relatório não lê o Firefox)' }
} catch { Falhou 'as extensões do navegador' $_ }

# =====================================================================
Secao 'Certificados raiz'
try {
    $maq = @(Get-ChildItem Cert:\LocalMachine\Root -ErrorAction Stop)
    $maqT = @{}; foreach ($c in $maq) { $maqT[$c.Thumbprint] = $true }
    $soUsu = @(Get-ChildItem Cert:\CurrentUser\Root -ErrorAction Stop | Where-Object { -not $maqT.ContainsKey($_.Thumbprint) })
    $sst = Join-Path $env:TEMP ('seguranca-raizes-{0}.sst' -f $PID)
    $oficiais = @{}
    try {
        # A saída vai para uma variável: comando externo escrevendo direto na tela deixa uma linha em branco na cópia .txt.
        $null = cmd /c "certutil -generateSSTFromWU `"$sst`" 2>&1"
        if (Test-Path -LiteralPath $sst) {
            $col = New-Object Security.Cryptography.X509Certificates.X509Certificate2Collection
            $col.Import($sst)
            foreach ($c in $col) { $oficiais[$c.Thumbprint] = $true }
        }
    } catch {} finally { if (Test-Path -LiteralPath $sst) { Remove-Item -LiteralPath $sst -Force -ErrorAction SilentlyContinue } }

    function DescreverCert($c) { return ('{0} (válido até {1:dd/MM/yyyy})' -f $c.GetNameInfo('SimpleName', $false), $c.NotAfter) }
    # O risco depende do uso gravado no certificado (EKU).
    function RiscoCert($c) {
        $usos = @($c.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId })
        if ($usos.Count -eq 0) { return 'vale para tudo: pode ler conexões HTTPS e fazer programas parecerem confiáveis' }
        if ($usos -contains '1.3.6.1.5.5.7.3.1') { return 'pode ler conexões HTTPS' }
        if ($usos -contains '1.3.6.1.5.5.7.3.3') { return 'faz o PC aceitar como confiáveis programas e drivers assinados por ele' }
        return "uso: $((@($c.EnhancedKeyUsageList | ForEach-Object { $_.FriendlyName })) -join ', ')"
    }
    function TextoCert($c) {
        $tipo = if ($c.Subject -match 'libwdi|libusbK') { 'Certificado de driver USB (libwdi/libusbK, de ferramentas de celular)' } else { 'Certificado raiz fora da lista oficial da Microsoft' }
        return ('{0}: {1}, criado em {2:dd/MM/yyyy} — {3}' -f $tipo, (DescreverCert $c), $c.NotBefore, (RiscoCert $c))
    }
    $resolverCert = 'Se não reconhece ou não usa mais o programa que o instalou: Win+R > certlm.msc (máquina) ou certmgr.msc (usuário) > Autoridades de Certificação Raiz Confiáveis (e Editores Confiáveis) > apague-o. Antivírus e programas de empresa às vezes instalam o seu de propósito.'
    # Tira o certificado das listas de confiança da máquina e do usuário (Raiz e Editores Confiáveis).
    $apagarCert = {
        param($t)
        foreach ($loja in 'LocalMachine\Root', 'LocalMachine\TrustedPublisher', 'CurrentUser\Root', 'CurrentUser\TrustedPublisher') {
            $c = "Cert:\$loja\$t"
            if (Test-Path -LiteralPath $c) { Remove-Item -LiteralPath $c -Force -ErrorAction Stop }
        }
        if ((Test-Path -LiteralPath "Cert:\LocalMachine\Root\$t") -or (Test-Path -LiteralPath "Cert:\CurrentUser\Root\$t")) { throw 'o certificado continua instalado' }
    }
    function ConsertoCert($c) {
        $aviso = 'Antivírus e programas de empresa às vezes instalam o seu de propósito: se reconhece, responda N.'
        if ($c.Subject -match 'libwdi|libusbK') { $aviso = 'Só faz falta se você ainda usa ferramenta de celular (desbloqueio de Xiaomi, restaurar iPhone em modo DFU); nesse caso o programa reinstala o driver quando precisar.' }
        # Certificado só do usuário não precisa de administrador (o Windows mostra uma confirmação própria).
        return Conserto "Apagar o certificado '$($c.GetNameInfo('SimpleName', $false))' das listas de confiança do Windows" $apagarCert $c.Thumbprint -Aviso $aviso -SemAdmin:(-not $maqT.ContainsKey($c.Thumbprint))
    }
    if ($oficiais.Count -gt 0) {
        $estranhos = @(($maq + $soUsu) | Where-Object { -not $oficiais.ContainsKey($_.Thumbprint) } | Sort-Object Thumbprint -Unique)
        $ruins = 0
        foreach ($c in $estranhos) {
            if ($c.Subject -match 'mkcert') { Info "Certificado do mkcert (HTTPS local do projeto): $(DescreverCert $c)" }
            elseif ($c.Subject -match 'Microsoft' -and $c.Subject -eq $c.Issuer) { Det "Raiz da própria Microsoft: $(DescreverCert $c)" }
            elseif ($c.Subject -eq "CN=$env:COMPUTERNAME" -and $c.Issuer -eq $c.Subject -and (Get-Service vmms -ErrorAction SilentlyContinue) -and
                (@($c.EnhancedKeyUsageList | ForEach-Object { $_.ObjectId }) -join ',') -eq '1.3.6.1.5.5.7.3.1') {
                # O Hyper-V (base do WSL/Docker) cria um certificado com o nome do PC, só para autenticar servidor.
                Info "Certificado com o nome do PC (provavelmente do Hyper-V, base do WSL/Docker): esperado. Sem proxy no PC, ele não intercepta nada"
            }
            else { $ruins++; Atencao (TextoCert $c) $resolverCert (ConsertoCert $c) }
        }
        if ($ruins -eq 0) { Ok "Nenhum certificado raiz suspeito entre os $($maq.Count + $soUsu.Count) instalados ($($oficiais.Count) raízes oficiais da Microsoft conferidas)" }
    } else {
        Info 'Não consegui baixar a lista oficial da Microsoft; confiro só os certificados instalados pelo usuário'
        if ($soUsu.Count -eq 0) { Ok 'Nenhum certificado raiz instalado só para o seu usuário' }
        foreach ($c in $soUsu) {
            if ($c.Subject -match 'mkcert') { Info "Certificado do mkcert (HTTPS local do projeto): $(DescreverCert $c)" }
            else { Atencao "Instalado só no seu usuário. $(TextoCert $c)" $resolverCert (ConsertoCert $c) }
        }
    }
} catch { Falhou 'os certificados raiz' $_ }

# =====================================================================
Secao 'Persistência escondida (WMI)'
try {
    $conhecidos = 'SCM Event Log (Filter|Consumer)|BVTFilter|BVTConsumer|TSLogonEvents|TSLogonFilter|RmAssistEventFilter|KernCap|NTEventLogConsumer'
    $filtros = @(Get-CimInstance -Namespace root/subscription -ClassName __EventFilter -ErrorAction Stop)
    $consumidores = @(Get-CimInstance -Namespace root/subscription -ClassName __EventConsumer -ErrorAction Stop)
    $ruins = 0
    foreach ($c in $consumidores) {
        $classe = $c.CimClass.CimClassName
        if ($classe -eq 'CommandLineEventConsumer' -or $classe -eq 'ActiveScriptEventConsumer') {
            $ruins++
            $o = "$($c.CommandLineTemplate)$($c.ScriptText)$($c.ScriptFileName)"; if ($o.Length -gt 140) { $o = $o.Substring(0, 140) + '...' }
            Perigo "Tarefa escondida no WMI '$($c.Name)' roda um comando sozinha: $o" 'Truque comum de vírus. Rode a verificação completa e a "Verificação Offline do Microsoft Defender" em Segurança do Windows > Opções de verificação' `
            (Conserto "Apagar a tarefa escondida '$($c.Name)' do WMI (e a ligação dela com o gatilho)" {
                param($nome)
                Get-CimInstance -Namespace root/subscription -ClassName __FilterToConsumerBinding -ErrorAction Stop |
                    Where-Object { "$($_.Consumer.Name)" -eq $nome } | Remove-CimInstance -ErrorAction Stop
                Get-CimInstance -Namespace root/subscription -ClassName __EventConsumer -ErrorAction Stop |
                    Where-Object { "$($_.Name)" -eq $nome } | Remove-CimInstance -ErrorAction Stop
            } "$($c.Name)" -Aviso 'Depois rode também a Verificação Offline do Defender: quem colocou isso pode ter deixado outras coisas.')
        } elseif ("$($c.Name)" -notmatch $conhecidos) { $ruins++; Atencao "Assinatura WMI desconhecida: '$($c.Name)' ($classe)" 'Pesquise o nome; se não for de um programa seu, rode a Verificação Offline do Defender' }
    }
    foreach ($f in $filtros) { if ("$($f.Name)" -notmatch $conhecidos -and $ruins -eq 0) { Det "Filtro WMI '$($f.Name)' (sem ação perigosa ligada)" } }
    if ($ruins -eq 0) { Ok 'Nenhuma tarefa escondida no WMI' }
} catch { if ($admin) { Falhou 'as assinaturas do WMI' $_ } else { Info 'Assinaturas do WMI exigem administrador: rode o atalho como administrador para conferir' } }

# =====================================================================
Secao 'Proteções do Windows'
try {
    $pol = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' -ErrorAction Stop
    $uacRes = 'Win+R > UserAccountControlSettings > volte para o nível padrão (e reinicie)'
    # Nível padrão do Windows: pede confirmação na tela escurecida.
    $uacPadrao = {
        $k = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
        Set-ItemProperty $k -Name EnableLUA -Value 1 -Type DWord -ErrorAction Stop
        Set-ItemProperty $k -Name ConsentPromptBehaviorAdmin -Value 5 -Type DWord -ErrorAction Stop
        Set-ItemProperty $k -Name PromptOnSecureDesktop -Value 1 -Type DWord -ErrorAction Stop
    }
    if ($pol.EnableLUA -eq 0) { Perigo 'Controle de Conta de Usuário (UAC) DESLIGADO: qualquer programa vira administrador' $uacRes (Conserto 'Ligar o UAC no nível padrão do Windows' $uacPadrao -Reinicia) }
    elseif ($pol.ConsentPromptBehaviorAdmin -eq 0) { Atencao 'UAC nunca avisa: programas viram administrador sem perguntar' $uacRes (Conserto 'Voltar o UAC para o nível padrão (pergunta antes de um programa virar administrador)' $uacPadrao) }
    else { Ok 'UAC ligado: pede confirmação antes de um programa virar administrador' }
} catch { Falhou 'o UAC' $_ }

try {
    $ss = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -ErrorAction SilentlyContinue).SmartScreenEnabled
    $ssPol = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -ErrorAction SilentlyContinue).EnableSmartScreen
    if ("$ss" -eq 'Off' -or "$ssPol" -eq '0') {
        Atencao 'SmartScreen desligado: não avisa sobre programas baixados perigosos' 'Segurança do Windows > Controle de aplicativos e do navegador > Proteção baseada em reputação > ligue tudo' `
        (Conserto 'Ligar o SmartScreen para programas e arquivos baixados' {
            Set-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer' -Name SmartScreenEnabled -Value 'Warn' -Type String -ErrorAction Stop
            Remove-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name EnableSmartScreen -ErrorAction SilentlyContinue
        })
    }
    else { Ok 'SmartScreen ligado (avisa sobre programas e sites perigosos)' }
    $sac = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy' -ErrorAction SilentlyContinue).VerifiedAndReputablePolicyState
    if ("$sac" -eq '1') { Info 'Controle Inteligente de Aplicativos ligado' } elseif ("$sac" -eq '2') { Info 'Controle Inteligente de Aplicativos em avaliação' } else { Info 'Controle Inteligente de Aplicativos desligado (normal em PC de desenvolvimento)' }
} catch { Falhou 'o SmartScreen' $_ }

try {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard -ErrorAction Stop
    $rodando = @($dg.SecurityServicesRunning)
    if ($rodando -contains 2) { Ok 'Integridade de memória ligada (impede drivers maliciosos)' }
    else {
        # Ligar por script pularia a checagem de drivers incompatíveis que a tela faz; por isso só abre a tela.
        Atencao 'Integridade de memória desligada' 'Segurança do Windows > Segurança do dispositivo > Detalhes do isolamento de núcleo > ligue Integridade de memória (pede reiniciar; driver antigo pode impedir)' `
        (AbrirTela 'Abrir a tela do Isolamento de núcleo (lá você liga a Integridade de memória; ela confere os drivers antes)' 'windowsdefender://coreisolation')
    }
    if ($rodando -contains 1) { Info 'Credential Guard ligado (protege senhas guardadas na memória)' }
} catch { Falhou 'a integridade de memória' $_ }

$secureBootDesligado = $false
try {
    $sb = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\SecureBoot\State' -ErrorAction SilentlyContinue
    if (-not $sb) { Info 'Secure Boot não disponível (PC com BIOS antiga)' }
    elseif ($sb.UEFISecureBootEnabled -eq 1) { Ok 'Secure Boot ligado (impede vírus de inicialização)' }
    else {
        $secureBootDesligado = $true
        # O Windows não liga o Secure Boot sozinho (é configuração da placa-mãe); o máximo é reiniciar direto na tela do BIOS.
        Atencao 'Secure Boot desligado' 'Ligue no BIOS/UEFI do PC (geralmente F2 ou Del ao ligar > Boot > Secure Boot). Peça ajuda se nunca mexeu no BIOS' `
        (Conserto 'Reiniciar o PC direto na tela do BIOS/UEFI, onde você liga o Secure Boot' {
            $null = shutdown.exe /r /fw /t 60 /c 'Verificar seguranca: reiniciando na tela do BIOS para ligar o Secure Boot'
            if ($LASTEXITCODE -ne 0) { throw "o Windows não conseguiu (código $LASTEXITCODE); reinicie e aperte F2 ou Del ao ligar" }
            Det 'O PC reinicia em 1 minuto. Para cancelar: Win+R > shutdown /a'
        } -PorUltimo -Aviso ('Salve e feche tudo antes: o PC reinicia em 1 minuto. No BIOS, procure "Secure Boot" (fica em Boot ou Security), coloque Enabled e salve com F10. ' +
            'Se estiver bloqueado, procure "Install default Secure Boot keys" ou "OS Type: Windows UEFI". Se o Windows não ligar depois, volte no BIOS e desligue de novo.'))
    }
} catch { Falhou 'o Secure Boot' $_ }

try {
    $pref = Get-CimInstance -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpPreference -ErrorAction Stop
    switch ("$($pref.EnableControlledFolderAccess)") {
        '1' { Info 'Proteção contra ransomware (Acesso controlado a pastas) ligada. Se git/npm falharem em Documentos, libere o programa em Segurança do Windows' }
        '2' { Info 'Proteção contra ransomware em modo auditoria' }
        default { Info 'Proteção contra ransomware (Acesso controlado a pastas) desligada: opcional; se ligar, libere git, node e Docker para não travar o projeto em Documentos' }
    }
    if ($admin) {
        $exc = @(foreach ($tipo in 'Path', 'Process', 'Extension') {
                foreach ($v in @($pref."Exclusion$tipo")) { if ($v -and "$v" -notmatch 'N/A') { [pscustomobject]@{ Tipo = $tipo; Valor = "$v" } } }
            })
        if ($exc.Count -eq 0) { Ok 'Antivírus sem exclusões (nenhuma pasta ou programa escondido dele)' }
        foreach ($x in $exc) {
            Atencao "Exclusão no antivírus: $($x.Valor) (o Defender não examina isso)" 'Se não foi você: Segurança do Windows > Proteção contra vírus > Gerenciar configurações > Exclusões > remova' `
            (Conserto "Tirar '$($x.Valor)' das exclusões do Defender (ele volta a examinar)" {
                param($d) $p = @{ ("Exclusion$($d.Tipo)") = $d.Valor }; Remove-MpPreference @p -ErrorAction Stop
            } $x -Aviso 'Se foi você que colocou (para acelerar uma pasta de projeto, por exemplo), responda N.')
        }
    }
} catch { Falhou 'as preferências do Defender' $_ }

try {
    $lsa = (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue).RunAsPPL
    if ("$lsa" -match '^[12]$') { Info 'Proteção da autoridade de segurança local (LSA) ligada' } else { Info 'Proteção da LSA não configurada (opcional: Segurança do Windows > Segurança do dispositivo > Isolamento de núcleo)' }
} catch {}

try {
    $bl = (New-Object -ComObject Shell.Application).NameSpace('C:\').Self.ExtendedProperty('System.Volume.BitLockerProtection')
    switch ("$bl") {
        '1' { Ok 'Disco C: criptografado (BitLocker): se o PC for roubado, não leem seus arquivos' }
        '3' { Info 'Disco C: sendo criptografado agora (BitLocker)' }
        '6' { Ok 'Disco C: criptografado (BitLocker)' }
        '2' {
            $resBL = 'Configurações > Privacidade e segurança > Criptografia do dispositivo (ou Painel de Controle > Criptografia de Unidade de Disco BitLocker). Guarde a chave de recuperação!'
            if ($secureBootDesligado) {
                # Ligar o Secure Boot depois do BitLocker faz o PC pedir a chave de recuperação na inicialização.
                Atencao 'Disco C: sem criptografia: se o PC for roubado, dá para ler seus arquivos' ('Ligue o Secure Boot ANTES (senão o BitLocker pede a chave de recuperação quando você ligar). Depois: ' + $resBL)
            } else {
                # O assistente obriga a guardar a chave de recuperação (na conta Microsoft, num arquivo fora do C: ou impressa); por isso abre a tela em vez de ligar direto.
                $telaBL = if (Test-Path "$env:windir\System32\BitLockerWizardElev.exe") { 'control.exe' } else { 'ms-settings:deviceencryption' }
                Atencao 'Disco C: sem criptografia: se o PC for roubado, dá para ler seus arquivos' $resBL `
                (Conserto 'Abrir a tela do BitLocker (lá clique em "Ativar o BitLocker" no C: e guarde a chave na sua conta Microsoft)' {
                    param($d) if ($d -eq 'control.exe') { Start-Process control.exe '/name Microsoft.BitLockerDriveEncryption' -ErrorAction Stop } else { Start-Process $d -ErrorAction Stop }
                } $telaBL -SemAdmin -Aviso 'Guarde a chave de recuperação fora deste PC: sem ela, se algo der errado, os arquivos ficam presos.')
            }
        }
        '5' {
            Atencao 'BitLocker do disco C: está suspenso' 'Painel de Controle > Criptografia de Unidade de Disco BitLocker > Retomar proteção' `
            (Conserto 'Retomar a proteção do BitLocker no C:' { $null = Resume-BitLocker -MountPoint 'C:' -ErrorAction Stop })
        }
        '8' {
            Atencao 'Criptografia do disco C: esperando ativação' 'Configurações > Privacidade e segurança > Criptografia do dispositivo > ligue' `
            (AbrirTela 'Abrir a tela de Criptografia do dispositivo (lá você liga)' 'ms-settings:deviceencryption')
        }
        default { Info "Criptografia do disco C: estado desconhecido ($bl)" }
    }
} catch { Falhou 'a criptografia do disco' $_ }

# =====================================================================
Secao 'Atualizações'
try {
    $ult = $null
    try {
        $busca = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
        $tot = $busca.GetTotalHistoryCount()
        if ($tot -gt 0) { foreach ($h in $busca.QueryHistory(0, [Math]::Min(50, $tot))) { if ($h.ResultCode -eq 2 -and $h.Operation -eq 1 -and (-not $ult -or $h.Date -gt $ult)) { $ult = $h.Date } } }
    } catch {}
    if (-not $ult) { $hf = Get-HotFix -ErrorAction SilentlyContinue | Where-Object InstalledOn | Sort-Object InstalledOn -Descending | Select-Object -First 1; if ($hf) { $ult = $hf.InstalledOn } }
    if (-not $ult) { Info 'Não consegui ver a data da última atualização do Windows' }
    else {
        $dias = [int]((Get-Date) - $ult).TotalDays
        if ($dias -gt 45) {
            Atencao "Windows Update: última atualização instalada há $dias dias" 'Configurações > Windows Update > Verificar se há atualizações' `
            (AbrirTela 'Abrir o Windows Update e procurar atualizações' 'ms-settings:windowsupdate-action')
        }
        else { Ok ("Windows Update: última atualização instalada em {0:dd/MM/yyyy} (há {1} dia(s))" -f $ult.ToLocalTime(), $dias) }
    }
} catch { Falhou 'o Windows Update' $_ }

try {
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { Info 'winget não encontrado: pulei a lista de programas desatualizados' }
    else {
        Write-Host '             Consultando o winget (pode levar alguns segundos)...' -ForegroundColor DarkGray
        $antes = [Console]::OutputEncoding
        try { [Console]::OutputEncoding = [Text.Encoding]::UTF8; $saida = @(winget upgrade --accept-source-agreements --disable-interactivity) } finally { [Console]::OutputEncoding = $antes }
        $linhas = @($saida | ForEach-Object { ("$_" -split "`r")[-1] } | Where-Object { $_.Trim() })
        $iSep = -1; for ($i = 0; $i -lt $linhas.Count; $i++) { if ($linhas[$i] -match '^-{10,}') { $iSep = $i; break } }
        if ($iSep -lt 1) { Ok 'Nenhum programa com atualização pendente (winget)' }
        else {
            $itens = @($linhas[($iSep + 1)..($linhas.Count - 1)] | Where-Object { $_ -notmatch '(?i)^\d+\s+(atualiza|upgrade|pacote|package)|include-unknown|--include' })
            if ($itens.Count -eq 0) { Ok 'Nenhum programa com atualização pendente (winget)' }
            else {
                # As colunas são alinhadas: o ID começa onde começa "ID" no cabeçalho.
                $cab = $linhas[$iSep - 1]; $posId = -1
                if ($cab -match '(?i)^(.*?\s)ID\s') { $posId = $matches[1].Length }
                $atualizar = {
                    param($d)
                    # Python instalado para todos (C:\Program Files\Python3XX): o pacote dele fica registrado no HKCU, o winget acha que
                    # é "só deste usuário" e atualizaria com InstallAllUsers=0, criando outra cópia em AppData. Aqui vão as opções certas.
                    $opcoesPy = @()
                    if ($d -match '^Python\.Python\.(3\.\d+)$') {
                        $verPy = $Matches[1]
                        $chavePy = "HKLM:\SOFTWARE\Python\PythonCore\$verPy\InstallPath"
                        $dirPy = ''
                        if (Test-Path -LiteralPath $chavePy) { $dirPy = "$((Get-ItemProperty -LiteralPath $chavePy).'(default)')".TrimEnd('\') }
                        if ($dirPy) {
                            if ($dirPy -ne (Join-Path $env:ProgramFiles ('Python' + ($verPy -replace '\.', '')))) {
                                throw "o Python $verPy está em $dirPy, fora da pasta padrão: atualize pelo instalador do python.org (botão Upgrade Now)"
                            }
                            $noPath = @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_.TrimEnd('\') -eq $dirPy }).Count -gt 0
                            $opcoesPy = @('--override', "/quiet /norestart InstallAllUsers=1 PrependPath=$([int]$noPath)")
                            Det "Python para todos os usuários ($dirPy): atualizando no mesmo lugar, sem criar outra cópia"
                        }
                    }
                    $antes = [Console]::OutputEncoding
                    try {
                        [Console]::OutputEncoding = [Text.Encoding]::UTF8
                        winget upgrade --id $d --exact @opcoesPy --accept-source-agreements --accept-package-agreements --disable-interactivity |
                            ForEach-Object { $x = ("$_" -split "`r")[-1]; if ($x.Trim() -and $x -notmatch '^\s*[-\\|/]\s*$|[█▒]') { Det $x.Trim() } }
                        $cod = $LASTEXITCODE
                    } finally { [Console]::OutputEncoding = $antes }
                    if ($cod -ne 0) { throw "o winget terminou com código $cod" }
                }
                $cs = @(foreach ($l in $itens) {
                        if ($posId -lt 1 -or $l.Length -le $posId) { continue }
                        $id = ($l.Substring($posId).Trim() -split '\s+')[0]
                        if ($id -notmatch '^[\w.+-]+$') { continue }
                        $nomeProg = $l.Substring(0, $posId).Trim()
                        # O winget às vezes confunde o programa com a versão de testes (o Chrome normal aparece como Google.Chrome.Beta):
                        # atualizar por ele trocaria o programa pela versão Beta. Esses ficam para o próprio programa atualizar.
                        if ($id -match '(?i)\.(Beta|Dev|Canary|Nightly|Preview|Insiders?)(\.|$)' -and $nomeProg -notmatch '(?i)Beta|Dev|Canary|Nightly|Preview|Insider') { continue }
                        Conserto "Atualizar $nomeProg ($id) pelo winget" $atualizar $id -SemAdmin -Aviso 'Feche o programa antes. O instalador dele pode abrir uma janela ou pedir permissão.'
                    })
                Atencao "$($itens.Count) programa(s) com atualização disponível" 'Atualize pelo próprio programa ou responda S abaixo, um por vez (evite winget upgrade --all: ele às vezes troca um programa pela versão de testes)' $cs
                Det $cab
                foreach ($l in $itens) { Det $l }
            }
        }
    }
} catch { Falhou 'o winget' $_ }

# =====================================================================
Secao 'Logins e tentativas pela rede (últimos 7 dias)'
if (-not $admin) { Info 'Precisa de administrador: botão direito no atalho > Executar como administrador para ver logins pela rede, tentativas de senha errada e quem tentou entrar pelo firewall' }
else {
    try {
        $xp = "*[System[(EventID=4624) and TimeCreated[timediff(@SystemTime) <= 604800000]] and EventData[Data[@Name='LogonType']='3' or Data[@Name='LogonType']='10']]"
        $ev = @(Get-WinEvent -LogName Security -FilterXPath $xp -MaxEvents 3000 -ErrorAction SilentlyContinue)
        $deFora = @($ev | ForEach-Object { DadosEvento $_ } | Where-Object { $_.IpAddress -and $_.IpAddress -notmatch '^(-|127\.0\.0\.1|::1|)$' })
        if ($deFora.Count -eq 0) { Ok 'Ninguém entrou neste PC pela rede' }
        foreach ($g in ($deFora | Group-Object { "$($_.IpAddress)|$($_.TargetUserName)|$($_.LogonType)" })) {
            $x = $g.Group[0]; $tipo = if ($x.LogonType -eq '10') { 'Área de Trabalho Remota' } else { 'rede (pastas/serviços)' }
            if (EnderecoPrivado $x.IpAddress) { Atencao "Login por $tipo vindo de $($x.IpAddress) (rede local) como '$($x.TargetUserName)' — $($g.Count) vez(es)" 'Se não reconhece o aparelho, troque a senha do Windows e desligue o compartilhamento' }
            else { Perigo "Login por $tipo vindo da INTERNET ($($x.IpAddress)) como '$($x.TargetUserName)' — $($g.Count) vez(es)" 'Troque a senha do Windows agora, desligue a Área de Trabalho Remota e o compartilhamento' }
        }
    } catch { Falhou 'os logins pela rede' $_ }
    try {
        $xp = '*[System[(EventID=4625) and TimeCreated[timediff(@SystemTime) <= 604800000]]]'
        $ev = @(Get-WinEvent -LogName Security -FilterXPath $xp -MaxEvents 3000 -ErrorAction SilentlyContinue)
        if ($ev.Count -eq 0) { Ok 'Nenhuma tentativa de senha errada' }
        else {
            $porIp = $ev | ForEach-Object { DadosEvento $_ } | Group-Object { if ($_.IpAddress -and $_.IpAddress -notmatch '^(-|127\.0\.0\.1|::1)$') { $_.IpAddress } else { 'LOCAL' } } | Sort-Object Count -Descending
            foreach ($g in $porIp) {
                if ($g.Name -eq 'LOCAL') {
                    $t = "$($g.Count) tentativa(s) de senha errada feitas neste PC (não vieram da rede)"
                    if ($g.Count -ge 20) { Atencao $t "Veja abaixo como a senha foi usada: 'no teclado' ou 'desbloqueio da tela' = alguém digitou aqui; 'tarefa', 'serviço' ou 'senha guardada' = um programa ainda usa uma senha antiga, atualize nele" }
                    else { Info $t }
                    foreach ($s in ($g.Group | Group-Object { "$($_.LogonType)|$($_.TargetUserName)|$($_.ProcessName)" } | Sort-Object Count -Descending | Select-Object -First 5)) {
                        $x = $s.Group[0]
                        $como = switch ($x.LogonType) { '2' { 'no teclado' } '7' { 'desbloqueio da tela' } '11' { 'senha guardada' } '4' { 'tarefa' } '5' { 'serviço' } default { "tipo $($x.LogonType)" } }
                        $prog = if ($x.ProcessName -and $x.ProcessName -ne '-') { $x.ProcessName } else { 'Windows' }
                        Det ("{0}x  conta '{1}' | {2} | programa: {3}" -f $s.Count, $x.TargetUserName, $como, $prog)
                    }
                }
                elseif ($g.Count -ge 20) { Atencao "$($g.Count) tentativas de senha errada vindas de $($g.Name)" 'Muitas tentativas = alguém tentando adivinhar a senha. Use uma senha forte e desligue acessos remotos que não usa' }
                else { Info "$($g.Count) tentativa(s) de senha errada vindas de $($g.Name)" }
            }
        }
    } catch { Falhou 'as tentativas de senha errada' $_ }
    try {
        # Log do firewall (a blindagem liga o registro do que é bloqueado): pedidos de conexão nova vindos da internet.
        $arqFw = @(Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { "$($_.LogBlocked)" -eq 'True' } |
            ForEach-Object { [Environment]::ExpandEnvironmentVariables("$($_.LogFileName)") } | Select-Object -Unique)
        if ($arqFw.Count -eq 0) { Info 'O firewall não está anotando o que bloqueia: sem isso não dá para ver quem tentou entrar (a blindagem liga)' }
        foreach ($a in $arqFw) {
            if (-not (Test-Path -LiteralPath $a)) { continue }
            # Campos: data hora ação protocolo origem destino porta-origem porta-destino tamanho flags ... sentido pid
            $linhasFw = @(Get-Content -LiteralPath $a -ErrorAction SilentlyContinue | Where-Object { $_ -and $_ -notmatch '^#' })
            $tent = @(foreach ($l in $linhasFw) {
                    $c = $l.Trim([char]0, ' ') -split '\s+'
                    if ($c.Count -lt 17 -or $c[2] -ne 'DROP' -or $c[16] -ne 'RECEIVE' -or $c[3] -ne 'TCP' -or $c[9] -ne 'S') { continue }
                    if (EnderecoPrivado $c[4]) { continue }
                    [pscustomobject]@{ Quando = "$($c[0]) $($c[1])"; De = $c[4]; Porta = $c[7] }
                })
            $periodo = ''
            $datas = @($linhasFw | ForEach-Object { ($_.Trim([char]0, ' ') -split '\s+')[0] } | Where-Object { $_ -match '^\d{4}-\d\d-\d\d$' })
            if ($datas.Count) { $periodo = " (log de $(([datetime]$datas[0]).ToString('dd/MM')) a $(([datetime]$datas[-1]).ToString('dd/MM')))" }
            if ($tent.Count -eq 0) { Ok "Ninguém da internet tentou abrir conexão com este PC$periodo" }
            else {
                $porIp = @($tent | Group-Object De | Sort-Object Count -Descending)
                Atencao "$($tent.Count) tentativa(s) de conexão vindas da internet, de $($porIp.Count) endereço(s), bloqueadas pelo firewall$periodo" 'O firewall barrou, mas o PC está alcançável de fora. No roteador: desligue o UPnP e apague qualquer redirecionamento de porta para este PC'
                foreach ($g in ($porIp | Select-Object -First 8)) {
                    $portasG = (@($g.Group | ForEach-Object Porta | Select-Object -Unique | Select-Object -First 6)) -join ', '
                    Det ("{0,4}x de {1} para a(s) porta(s) {2} (última {3})" -f $g.Count, $g.Name, $portasG, ($g.Group[-1]).Quando)
                }
            }
        }
    } catch { Falhou 'o log do firewall' $_ }
}

# =====================================================================
Secao 'Inicialização profunda (boot, login e drivers)'
try {
    # Opções do boot atual (dá para ler sem administrador, ao contrário do bcdedit).
    $opc = "$((Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control' -ErrorAction Stop).SystemStartOptions)"
    $flags = @()
    if ($opc -match 'TESTSIGNING') { $flags += 'modo de teste (aceita drivers sem assinatura)' }
    if ($opc -match 'NOINTEGRITYCHECKS|DISABLE_INTEGRITY_CHECKS') { $flags += 'checagem de assinatura dos drivers desligada' }
    if ($opc -match '(^|\s)DEBUG(\s|=|$)') { $flags += 'depuração do núcleo ligada (outro computador pode controlar o Windows)' }
    if ($flags.Count -eq 0) { Ok 'Boot normal: sem modo de teste, sem depuração e com assinatura de drivers exigida' }
    else {
        Perigo "Boot com proteção desligada: $($flags -join '; ')" 'Se não foi você (nem uma ferramenta de desenvolvimento de drivers): num terminal de administrador rode bcdedit /set testsigning off, bcdedit /set nointegritychecks off e bcdedit /debug off; depois reinicie' `
        (Conserto 'Religar as proteções do boot (tira o modo de teste e a depuração, volta a exigir assinatura de drivers)' {
            foreach ($a in '/set {current} testsigning off', '/set {current} nointegritychecks off', '/debug {current} off') { $null = cmd /c "bcdedit $a" }
        } -Reinicia)
    }

    # Pontos clássicos onde vírus se penduram no boot e no login.
    $desvios = New-Object System.Collections.Generic.List[string]
    $sm = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -ErrorAction SilentlyContinue
    $be = (@($sm.BootExecute) | Where-Object { $_ }) -join ' | '
    if ($be -and $be -notmatch '^autocheck autochk \*$') { $desvios.Add("roda antes do Windows abrir (BootExecute): $be") }
    $wl = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    if ("$($wl.Shell)".Trim() -notmatch '^(?i)(explorer\.exe)?$') { $desvios.Add("Winlogon Shell = $($wl.Shell)") }
    if ("$($wl.Userinit)".Trim().TrimEnd(',') -notmatch '^(?i)(C:\\Windows\\system32\\)?userinit\.exe$') { $desvios.Add("Winlogon Userinit = $($wl.Userinit)") }
    foreach ($k in 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Windows', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows NT\CurrentVersion\Windows') {
        $p = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
        if ($p -and "$($p.AppInit_DLLs)".Trim() -and "$($p.LoadAppInit_DLLs)" -eq '1') { $desvios.Add("AppInit_DLLs (carrega em todo programa) = $($p.AppInit_DLLs)") }
    }
    foreach ($k in @(Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options' -ErrorAction SilentlyContinue)) {
        $dv = (Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue).Debugger
        if ($dv) { $desvios.Add("quando $($k.PSChildName) abre, roda no lugar: $dv") }
    }
    $lsaP = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa' -ErrorAction SilentlyContinue
    foreach ($x in @(@($lsaP.'Authentication Packages') + @($lsaP.'Notification Packages') + @($lsaP.'Security Packages'))) {
        $x = "$x".Trim([char[]]'" ')
        if ($x -and $x -notmatch '^(?i)(msv1_0|scecli|kerberos|schannel|wdigest|tspkg|pku2u|cloudap|negoexts|livessp|rassfm)$') { $desvios.Add("pacote de login no LSA (vê as senhas): $x") }
    }
    if ($desvios.Count -eq 0) { Ok 'Login sem desvios (BootExecute, Winlogon, AppInit, IFEO e LSA normais)' }
    foreach ($x in $desvios) { Atencao "Desvio na inicialização: $x" 'Truque comum de vírus para rodar junto com o Windows. Se não reconhece, rode a Verificação Offline do Defender e peça ajuda antes de apagar' }

    # Drivers que sobem com o Windows: sem assinatura válida aqui é o sinal mais forte de rootkit.
    $nDrv = 0; $ruinsDrv = 0
    foreach ($d in @(Get-CimInstance Win32_SystemDriver -ErrorAction Stop | Where-Object { $_.StartMode -in 'Boot', 'System', 'Auto' })) {
        $cam = CaminhoServico "$($d.PathName)"; if (-not $cam) { continue }
        $nDrv++; $ass = Assinatura $cam
        if ($ass.Quem -eq 'arquivo não existe mais') { Det "Driver $($d.Name) aponta para arquivo que não existe ($cam): sobra de programa desinstalado" }
        elseif ($ass.Ok -eq $false) { $ruinsDrv++; Perigo "Driver que sobe com o Windows sem assinatura válida: $($d.Name) ($cam; $($ass.Quem))" 'Sinal forte de rootkit (ou driver muito antigo). Rode a Verificação Offline do Defender e peça ajuda antes de mexer' }
        elseif ($ass.Ok -and $ass.Quem -notmatch '^Microsoft') { Det "Driver de fora da Microsoft: $($d.Name) -> $cam ($($ass.Quem))" }
    }
    if ($ruinsDrv -eq 0) { Ok "Todos os $nDrv drivers que sobem com o Windows têm assinatura válida" }
} catch { Falhou 'a inicialização profunda' $_ }

# =====================================================================
Secao 'Eventos suspeitos (últimos 7 dias)'
$desde = (Get-Date).AddDays(-7)
try {
    $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 7045; StartTime = $desde } -MaxEvents 300 -ErrorAction SilentlyContinue)
    if ($ev.Count -eq 0) { Ok 'Nenhum serviço ou driver novo instalado' }
    else {
        Info 'Serviços/drivers instalados (normal depois de atualizar o Windows ou instalar programas):'
        $vistos = @{}; $mostrados = 0
        foreach ($e in $ev) {
            $x = DadosEvento $e; $nomeS = $x['ServiceName']
            if ($vistos.ContainsKey($nomeS)) { continue }; $vistos[$nomeS] = $true
            $cam = CaminhoServico $x['ImagePath']; $ass = Assinatura $cam
            $t = '{0:dd/MM HH:mm} {1} -> {2} ({3})' -f $e.TimeCreated, $nomeS, $cam, $ass.Quem
            # Arquivo que já sumiu é normal (o Defender e instaladores criam serviços temporários).
            if ($ass.Quem -ne 'arquivo não existe mais' -and ($ass.Ok -eq $false -or (PastaSuspeita $cam $ass))) {
                Atencao "Serviço novo não confiável: $t" 'Se não reconhece: Win+R > services.msc > pare e desative; depois rode a verificação completa do Defender'
            } else { $mostrados++; if ($mostrados -le 15) { Det $t } }
        }
        if ($mostrados -gt 15) { Det "... e mais $($mostrados - 15) (todos assinados)" }
    }

    $limpos = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 104; StartTime = $desde } -MaxEvents 20 -ErrorAction SilentlyContinue)
    if ($admin) { $limpos += @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 1102; StartTime = $desde } -MaxEvents 20 -ErrorAction SilentlyContinue) }
    if ($limpos.Count -eq 0) { Ok 'Nenhum histórico do Windows foi apagado' }
    foreach ($e in $limpos) {
        $canal = ''; try { $canal = "$(([xml]$e.ToXml()).Event.UserData.LogFileCleared.Channel)" } catch {}
        if (-not $canal -and $e.Id -eq 1102) { $canal = 'Security' }
        Atencao ('Histórico "{0}" do Windows apagado em {1:dd/MM HH:mm}' -f $canal, $e.TimeCreated) 'Quem invade costuma apagar o histórico para esconder o que fez. Se não foi você (nem um programa de limpeza), troque a senha e rode a Verificação Offline do Defender'
    }

    # O que as regras extras do Defender (ASR, ligadas pelo blindagem.ps1) bloquearam ou só anotaram.
    $nomesAsr = @{
        '56a863a9-875e-4185-98a7-b882c64b5ce5' = 'drivers com falha conhecida'; '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = 'roubo de senhas da memória (LSASS)'
        'e6db77e5-3df2-4cf1-b95a-636979351e5b' = 'esconder-se no WMI'; 'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = 'executável vindo de e-mail'
        'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = 'Office abrindo programas'; '3b576869-a4ec-4529-8536-b80a7769e899' = 'Office criando executáveis'
        '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = 'Office injetando código'; '26190899-1602-49e8-8b27-eb1d0a1ce869' = 'Outlook abrindo programas'
        '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = 'macro chamando o Windows'; '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = 'Adobe Reader abrindo programas'
        'd3e037e1-3eb8-44c8-a917-57927947596d' = 'JavaScript/VBScript rodando baixados'; 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = 'programa sem assinatura no pendrive'
        'c1db55ab-c21a-4637-bb3f-a12568109d35' = 'comportamento de ransomware'; '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = 'script ofuscado'
        'd1e49aac-8f56-4280-b9ba-993a6d77406c' = 'programa aberto por PsExec/WMI'; '01443614-cd74-433a-b99e-2ecdc07bfc25' = 'executável raro ou novo'
    }
    $asrEv = @(Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Windows Defender/Operational'; Id = 1121, 1122; StartTime = $desde } -MaxEvents 500 -ErrorAction SilentlyContinue)
    if ($asrEv.Count -eq 0) { Info 'Regras extras do Defender (ASR): nada bloqueado nem anotado' }
    $linhasAsr = @($asrEv | ForEach-Object { $x = DadosEvento $_; [pscustomobject]@{ Bloqueou = ($_.Id -eq 1121); Regra = "$($x['ID'])".ToLower(); Quem = "$($x['Path'])"; Alvo = "$($x['Process Name'])"; Quando = $_.TimeCreated } })
    foreach ($g in @($linhasAsr | Group-Object Bloqueou, Regra, Quem)) {
        $x = $g.Group[0]; $nomeR = $nomesAsr[$x.Regra]; if (-not $nomeR) { $nomeR = $x.Regra }
        $ass = Assinatura $x.Quem
        $ult = ($g.Group | Sort-Object Quando | Select-Object -Last 1).Quando
        $t = "Defender {0} {1}x pela regra '{2}': {3} (com {4}; último {5:dd/MM HH:mm})" -f $(if ($x.Bloqueou) { 'bloqueou' } else { 'só anotou' }), $g.Count, $nomeR, $x.Quem, $x.Alvo, $ult
        # Serviço do Windows (ex.: SysMain) encostando no lsass é falso positivo conhecido dessa regra.
        if ($x.Regra -eq '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' -and $ass.Ok -and $x.Quem -like "$env:windir\*") { Info "$t — normal: serviço do próprio Windows; o Defender só impede" }
        elseif ($ass.Ok -eq $false -or (PastaSuspeita $x.Quem $ass)) { Atencao "$t — programa não confiável" 'Se não reconhece o programa, rode a verificação completa do Defender' }
        else { Info $t }
    }

    if ($admin) {
        # A instalação do Windows cria contas internas (defaultuser0, WDAGUtilityAccount...) usando a conta do próprio PC (nome terminando em $).
        $instalado = $null; try { $instalado = (Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).InstallDate } catch {}
        $daInstalacao = { param($ev, $dados) "$($dados['SubjectUserName'])" -match '\$$' -and $instalado -and $ev.TimeCreated -le $instalado.AddHours(2) }
        foreach ($e in @(Get-WinEvent -FilterHashtable @{ LogName = 'Security'; Id = 4720, 4732; StartTime = $desde } -MaxEvents 100 -ErrorAction SilentlyContinue)) {
            $x = DadosEvento $e
            if ($e.Id -eq 4720) {
                $t = "Conta nova criada em {0:dd/MM HH:mm}: '{1}' (por '{2}')" -f $e.TimeCreated, $x['TargetUserName'], $x['SubjectUserName']
                if ($x['TargetUserName'] -ieq $eu) { Info "$t — é a sua conta" }
                elseif ($x['TargetUserName'] -match '^(defaultuser\d+|WDAGUtilityAccount)$' -or "$($x['TargetSid'])" -match '-50[0-4]$' -or (& $daInstalacao $e $x)) { Info "$t — conta interna, criada pela instalação do Windows" }
                else { Atencao $t 'Se não foi você: Configurações > Contas > Outros usuários > remova' }
            } elseif ($x['TargetSid'] -eq 'S-1-5-32-544') {
                $quemAdm = $x['MemberSid']; $existe = $true
                try { $quemAdm = (New-Object Security.Principal.SecurityIdentifier $x['MemberSid']).Translate([Security.Principal.NTAccount]).Value } catch { $existe = $false }
                $t = "Virou administrador em {0:dd/MM HH:mm}: '{1}' (por '{2}')" -f $e.TimeCreated, $quemAdm, $x['SubjectUserName']
                if (($quemAdm -replace '^.*\\', '') -ieq $eu) { Info "$t — é você" }
                elseif (($quemAdm -replace '^.*\\', '') -match '^defaultuser\d+$' -or (& $daInstalacao $e $x)) { Info "$t — conta temporária da instalação do Windows" }
                elseif (-not $existe) { Info "$t — essa conta já foi apagada" }
                else { Atencao $t 'Se não foi você: Win+R > lusrmgr.msc > Grupos > Administradores > remova' }
            }
        }
    }
} catch { Falhou 'os eventos suspeitos' $_ }

# =====================================================================
Secao 'Brechas para um programa virar administrador'
try {
    $aie = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer', 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer' | Where-Object { "$((Get-ItemProperty -LiteralPath $_ -ErrorAction SilentlyContinue).AlwaysInstallElevated)" -eq '1' })
    if ($aie.Count -eq 2) {
        Perigo 'Qualquer instalador (.msi) vira administrador sem perguntar (AlwaysInstallElevated)' 'Num terminal de administrador apague o valor AlwaysInstallElevated em HKLM e HKCU \SOFTWARE\Policies\Microsoft\Windows\Installer' `
        (Conserto 'Desligar o AlwaysInstallElevated (instaladores voltam a pedir permissão)' {
            foreach ($k in 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Installer', 'HKCU:\SOFTWARE\Policies\Microsoft\Windows\Installer') { Remove-ItemProperty -LiteralPath $k -Name AlwaysInstallElevated -ErrorAction SilentlyContinue }
        })
    } else { Ok 'Instaladores (.msi) não viram administrador sozinhos' }

    $wl2 = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -ErrorAction SilentlyContinue
    if ($wl2 -and $wl2.DefaultPassword) {
        Perigo "A senha da conta '$($wl2.DefaultUserName)' está guardada sem criptografia no registro (login automático)" 'Win+R > netplwiz > marque "Os usuários devem digitar um nome de usuário e uma senha"; depois troque a senha' `
        (Conserto 'Apagar a senha guardada no registro e desligar o login automático' {
            $k = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
            Remove-ItemProperty -LiteralPath $k -Name DefaultPassword -ErrorAction Stop
            Set-ItemProperty -LiteralPath $k -Name AutoAdminLogon -Value '0' -ErrorAction Stop
        } -Aviso 'O PC vai pedir a senha ao ligar. Troque a senha depois: ela ficou exposta.')
    }
    elseif ($wl2 -and "$($wl2.AutoAdminLogon)" -eq '1') { Info "Login automático ligado (conta '$($wl2.DefaultUserName)'): quem ligar o PC entra direto" }
    else { Ok 'Sem senha guardada para login automático' }

    # Caminho com espaço e sem aspas: o Windows tenta C:\Program.exe antes do programa certo.
    $semAspas = @($servicos | Where-Object {
            $pn = "$($_.PathName)".Trim()
            $pn -and -not $pn.StartsWith('"') -and $pn -match '^[A-Za-z]:\\' -and ((CaminhoExe $pn) -match ' ') -and $_.StartMode -ne 'Disabled'
        })
    if ($semAspas.Count -eq 0) { Ok 'Nenhum serviço com caminho sem aspas' }
    foreach ($s in $semAspas) {
        Atencao "Serviço '$($s.DisplayName)' com caminho sem aspas: $($s.PathName)" 'Um programa posto em C:\Program.exe rodaria como sistema. Corrija pondo o caminho entre aspas (regedit > HKLM\SYSTEM\CurrentControlSet\Services\<serviço> > ImagePath)' `
        (Conserto "Pôr aspas no caminho do serviço '$($s.DisplayName)' (ele continua rodando o mesmo programa)" {
            param($nome)
            $k = "HKLM:\SYSTEM\CurrentControlSet\Services\$nome"
            $chave = Get-Item -LiteralPath $k -ErrorAction Stop
            $atual = "$($chave.GetValue('ImagePath', $null, 'DoNotExpandEnvironmentNames'))"; $tipo = $chave.GetValueKind('ImagePath')
            if ($atual.TrimStart().StartsWith('"')) { return }
            if ($atual -notmatch '^(?i)(.+?\.exe)(\s.*)?$') { throw 'não achei o .exe no caminho' }
            $novo = '"' + $matches[1] + '"' + $matches[2]
            Set-ItemProperty -LiteralPath $k -Name ImagePath -Value $novo -Type $tipo -ErrorAction Stop
            Det "ImagePath agora: $novo"
        } $s.Name)
    }

    # Pasta do PATH do sistema em que qualquer usuário grava: um programa comum planta ali uma DLL que algo com administrador carrega.
    $fracos = 'S-1-1-0', 'S-1-5-11', 'S-1-5-32-545', 'S-1-5-4'
    $dirs = @([Environment]::GetEnvironmentVariable('Path', 'Machine') -split ';' | Where-Object { $_.Trim() } | ForEach-Object { [Environment]::ExpandEnvironmentVariables($_.Trim()).TrimEnd('\') } | Select-Object -Unique)
    $abertas = 0
    foreach ($dir in $dirs) {
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        $acl = $null; try { $acl = Get-Acl -LiteralPath $dir } catch {}; if (-not $acl) { continue }
        $grava = @($acl.Access | Where-Object {
                $_.AccessControlType -eq 'Allow' -and -not ($_.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -and
                (([int64]$_.FileSystemRights) -band 0x50000002) -and
                ($(try { $_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value } catch { '' }) -in $fracos)
            })
        if ($grava.Count -gt 0) { $abertas++; Atencao "Pasta do PATH do sistema em que qualquer usuário grava: $dir" 'Tire a permissão de gravação de "Usuários"/"Todos" (botão direito > Propriedades > Segurança) ou reinstale o programa em C:\Program Files' }
    }
    if ($abertas -eq 0) { Ok "Nenhuma pasta do PATH do sistema aceita gravação de usuários comuns ($($dirs.Count) conferidas)" }
} catch { Falhou 'as brechas de administrador' $_ }

# =====================================================================
Secao 'Assistentes de IA e terminais (Claude Code, Codex, PowerShell)'
# Um vírus pode mudar a configuração desses assistentes para rodar comandos sozinho (ganchos), abrir programas
# (servidores MCP), desviar as conversas para outro servidor (variáveis de ambiente) ou plantar instruções (skills).
try {
    $casa = $env:USERPROFILE
    $dirClaude = Join-Path $casa '.claude'; $dirCodex = Join-Path $casa '.codex'
    $problemasIA = 0
    # Variáveis que mudam para onde o assistente (e o Node, o git, o npm) manda os dados, ou injetam código nele.
    $padraoEnv = '^(ANTHROPIC_BASE_URL|ANTHROPIC_BEDROCK_BASE_URL|ANTHROPIC_VERTEX_BASE_URL|CLAUDE_CONFIG_DIR|CLAUDE_CODE_SHELL|CLAUDE_CODE_SHELL_PREFIX|CLAUDE_CODE_GIT_BASH_PATH|OPENAI_BASE_URL|CODEX_HOME|NODE_OPTIONS|NODE_EXTRA_CA_CERTS|NODE_TLS_REJECT_UNAUTHORIZED|ELECTRON_RUN_AS_NODE|HTTPS?_PROXY|ALL_PROXY)$'

    foreach ($esc in 'User', 'Machine') {
        $vars = [Environment]::GetEnvironmentVariables($esc)
        foreach ($nome in @($vars.Keys | Where-Object { "$_" -match $padraoEnv } | Sort-Object)) {
            $problemasIA++
            $onde = if ($esc -eq 'User') { 'do seu usuário' } else { 'do sistema' }
            Atencao "Variável de ambiente $nome = '$($vars[$nome])' ($onde): muda para onde o Claude Code, o Codex ou o Node mandam os dados" 'Se não foi você: Win+R > sysdm.cpl > Avançado > Variáveis de Ambiente > apague' `
            (Conserto "Apagar a variável $nome ($onde; o valor fica anotado neste relatório)" { param($d) [Environment]::SetEnvironmentVariable($d.Nome, $null, $d.Escopo) } @{ Nome = "$nome"; Escopo = $esc } `
                -SemAdmin:($esc -eq 'User') -Aviso 'Se foi você (proxy da empresa, VPN, ferramenta de desenvolvimento), responda N. Depois feche e abra o VS Code.')
        }
    }

    if (-not (Test-Path -LiteralPath $dirClaude) -and -not (Test-Path -LiteralPath $dirCodex)) { Info 'Claude Code e Codex não estão instalados neste usuário' }
    else {
        # Arquivos de configuração do Claude Code: do usuário, da empresa (managed) e dos projetos (até 4 pastas abaixo).
        $arqsConfig = New-Object System.Collections.Generic.List[string]
        $arqsMcp = New-Object System.Collections.Generic.List[string]
        foreach ($a in (Join-Path $dirClaude 'settings.json'), (Join-Path $dirClaude 'settings.local.json'), "$env:ProgramFiles\ClaudeCode\managed-settings.json", "$env:ProgramData\ClaudeCode\managed-settings.json") {
            if (Test-Path -LiteralPath $a) { $arqsConfig.Add($a) }
        }
        foreach ($raiz in @([Environment]::GetFolderPath('MyDocuments'), [Environment]::GetFolderPath('Desktop'), (Join-Path $casa 'source'), (Join-Path $casa 'Projects')) | Select-Object -Unique) {
            if (-not $raiz -or -not (Test-Path -LiteralPath $raiz)) { continue }
            foreach ($d in @(Get-ChildItem -LiteralPath $raiz -Directory -Recurse -Depth 4 -Force -Filter '.claude' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' })) {
                foreach ($nomeArq in 'settings.json', 'settings.local.json') { $a = Join-Path $d.FullName $nomeArq; if (Test-Path -LiteralPath $a) { $arqsConfig.Add($a) } }
            }
            foreach ($f in @(Get-ChildItem -LiteralPath $raiz -File -Recurse -Depth 4 -Force -Filter '.mcp.json' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\node_modules\\' })) { $arqsMcp.Add($f.FullName) }
        }
        $chavesComando = 'hooks', 'statusLine', 'apiKeyHelper', 'awsCredentialExport', 'awsAuthRefresh', 'otelHeadersHelper'
        # Guarda uma cópia ao lado e tira do arquivo só as chaves que rodam comandos.
        $tirarComandos = {
            param($arq)
            Copy-Item -LiteralPath $arq -Destination ('{0}.copia-{1:yyyyMMdd-HHmmss}' -f $arq, (Get-Date)) -ErrorAction Stop
            $j = Get-Content -LiteralPath $arq -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in 'hooks', 'statusLine', 'apiKeyHelper', 'awsCredentialExport', 'awsAuthRefresh', 'otelHeadersHelper') { $j.PSObject.Properties.Remove($k) }
            [IO.File]::WriteAllText($arq, ($j | ConvertTo-Json -Depth 30), (New-Object Text.UTF8Encoding $false))
        }
        foreach ($a in @($arqsConfig | Select-Object -Unique)) {
            $curto = $a.Replace($casa, '~')
            $j = $null; try { $j = Get-Content -LiteralPath $a -Raw -Encoding UTF8 | ConvertFrom-Json } catch { Info "Não consegui ler $curto (não é um JSON válido)"; continue }
            if (-not $j) { continue }
            $cmds = New-Object System.Collections.Generic.List[string]
            if ($j.hooks) {
                foreach ($evt in $j.hooks.PSObject.Properties) {
                    foreach ($m in @($evt.Value)) {
                        foreach ($h in @($m.hooks)) {
                            if ($h.command) { $cmds.Add("gancho $($evt.Name): $($h.command)") }
                            elseif ($h.url) { $cmds.Add("gancho $($evt.Name) chama o site $($h.url)") }
                        }
                    }
                }
            }
            if ($j.statusLine -and $j.statusLine.command) { $cmds.Add("barra de status: $($j.statusLine.command)") }
            foreach ($k in ($chavesComando | Select-Object -Skip 2)) { if ($j.$k) { $cmds.Add("${k}: $($j.$k)") } }
            if ($cmds.Count -gt 0) {
                $problemasIA++
                $mais = if ($cmds.Count -gt 1) { " (e mais $($cmds.Count - 1))" } else { '' }
                Atencao "O Claude Code roda comandos sozinho, configurados em ${curto}: $($cmds[0])$mais" 'Se não foi você: apague o bloco "hooks" (e "statusLine"/"apiKeyHelper") desse arquivo, ou use /hooks dentro do Claude Code' `
                (Conserto "Guardar uma cópia de $curto e tirar dele os comandos automáticos (hooks, statusLine, apiKeyHelper)" $tirarComandos $a -SemAdmin:($a -like "$casa\*") `
                    -Aviso 'Se foi você que configurou esses comandos (formatar código, barra de status), responda N.')
                foreach ($x in $cmds) { Det $x }
            }
            if ($j.env) {
                foreach ($pr in @($j.env.PSObject.Properties | Where-Object { $_.Name -match $padraoEnv })) {
                    $problemasIA++
                    Atencao "$curto define $($pr.Name) = '$($pr.Value)' para o Claude Code" 'Se não foi você: apague essa linha do bloco "env" do arquivo'
                }
            }
            if ("$($j.permissions.defaultMode)" -eq 'bypassPermissions' -or $j.skipDangerousModePermissionPrompt) {
                $problemasIA++
                Atencao "$curto deixa o Claude Code rodar qualquer comando sem pedir licença (bypassPermissions)" 'Se não foi você: apague "defaultMode" do bloco "permissions" (e "skipDangerousModePermissionPrompt")'
            }
            if ($j.extraKnownMarketplaces) {
                foreach ($mk in @($j.extraKnownMarketplaces.PSObject.Properties)) {
                    $problemasIA++
                    Atencao "$curto adiciona uma loja de plugins extra: '$($mk.Name)' ($($mk.Value.source | ConvertTo-Json -Compress))" 'Se não foi você: apague "extraKnownMarketplaces" desse arquivo e confira /plugin dentro do Claude Code'
                }
            }
        }

        # Servidores MCP: programas que o assistente abre (ou sites que ele chama) para ganhar ferramentas novas.
        $mcp = New-Object System.Collections.Generic.List[object]
        $cj = Join-Path $casa '.claude.json'
        if (Test-Path -LiteralPath $cj) {
            try {
                $j = Get-Content -LiteralPath $cj -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($j.mcpServers) { foreach ($s in $j.mcpServers.PSObject.Properties) { $mcp.Add([pscustomobject]@{ Nome = $s.Name; Onde = '~\.claude.json (todos os projetos)'; S = $s.Value }) } }
                if ($j.projects) {
                    foreach ($p in $j.projects.PSObject.Properties) {
                        if ($p.Value.mcpServers) { foreach ($s in $p.Value.mcpServers.PSObject.Properties) { $mcp.Add([pscustomobject]@{ Nome = $s.Name; Onde = "~\.claude.json (projeto $($p.Name))"; S = $s.Value }) } }
                    }
                }
            } catch { Info 'Não consegui ler ~\.claude.json' }
        }
        foreach ($a in $arqsMcp) {
            try {
                $j = Get-Content -LiteralPath $a -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($j.mcpServers) { foreach ($s in $j.mcpServers.PSObject.Properties) { $mcp.Add([pscustomobject]@{ Nome = $s.Name; Onde = $a.Replace($casa, '~'); S = $s.Value }) } }
            } catch { Info "Não consegui ler $($a.Replace($casa, '~'))" }
        }
        $toml = Join-Path $dirCodex 'config.toml'
        if (Test-Path -LiteralPath $toml) {
            $atual = $null
            foreach ($l in @(Get-Content -LiteralPath $toml -Encoding UTF8)) {
                if ($l -match '^\s*\[mcp_servers\.("?)([^\]".]+)\1\]') {
                    $atual = [pscustomobject]@{ Nome = $matches[2]; Onde = '~\.codex\config.toml'; S = [pscustomobject]@{ command = ''; args = ''; url = '' } }
                    $mcp.Add($atual); continue
                }
                if ($l -match '^\s*\[') { $atual = $null; continue }
                if ($atual -and $l -match '^\s*(command|url)\s*=\s*"(.*)"') { $atual.S.($matches[1]) = $matches[2] -replace '\\\\', '\' }
                elseif ($atual -and $l -match '^\s*args\s*=\s*\[(.*)\]') { $atual.S.args = $matches[1] -replace '"', '' -replace '\\\\', '\' }
                elseif ($l -match '^\s*notify\s*=\s*(.+)$') {
                    $problemasIA++
                    Atencao "O Codex roda um comando depois de cada resposta: notify = $($matches[1].Trim())" 'Se não foi você: apague a linha notify de ~\.codex\config.toml'
                } elseif ($l -match '^\s*(openai_base_url|chatgpt_base_url|base_url)\s*=\s*"(.*)"') {
                    $url = $matches[2]
                    if ($url -notmatch '^https://([a-z0-9-]+\.)*(openai\.com|chatgpt\.com)(/|$)') {
                        $problemasIA++
                        Atencao "O Codex manda as conversas para $url (~\.codex\config.toml)" 'Se não foi você: apague essa linha do config.toml'
                    }
                }
            }
        }
        foreach ($m in $mcp) {
            $url = "$($m.S.url)"; $argsTxt = (@($m.S.args) | ForEach-Object { "$_" }) -join ' '
            $o = if ($url) { "chama o site $url" } else { "abre: $($m.S.command) $argsTxt".Trim() }
            $problemasIA++
            $como = if ($m.Onde -like '*config.toml') { "apague o bloco [mcp_servers.$($m.Nome)] do ~\.codex\config.toml" }
            elseif ($m.Onde -like '*.mcp.json') { "apague o bloco `"$($m.Nome)`" do arquivo $($m.Onde)" }
            else { "num terminal, rode: claude mcp remove `"$($m.Nome)`"" }
            Atencao "Servidor MCP '$($m.Nome)' em $($m.Onde) $o. Foi você que adicionou?" "Se não reconhece: $como"
        }

        # Instruções que o assistente segue: skills, agentes, comandos e os arquivos globais (CLAUDE.md, AGENTS.md).
        foreach ($a in (Join-Path $dirClaude 'CLAUDE.md'), (Join-Path $dirCodex 'AGENTS.md'), (Join-Path $dirCodex 'AGENTS.override.md')) {
            if (Test-Path -LiteralPath $a) { Info ("Instruções que o assistente segue em toda conversa: {0} (alterado em {1:dd/MM/yyyy HH:mm})" -f $a.Replace($casa, '~'), (Get-Item -LiteralPath $a).LastWriteTime) }
        }
        $minhas = @(Get-ChildItem -LiteralPath (Join-Path $dirClaude 'skills') -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin 'synced', '.trash' })
        foreach ($s in $minhas) {
            $md = Join-Path $s.FullName 'SKILL.md'; $quando = if (Test-Path -LiteralPath $md) { (Get-Item -LiteralPath $md).LastWriteTime } else { $s.LastWriteTime }
            Det ("Skill instalada à mão: {0} (alterada em {1:dd/MM/yyyy HH:mm}; se mudou sem você pedir, confira o conteúdo)" -f $s.Name, $quando)
        }
        $pastasTexto = @((Join-Path $dirClaude 'skills'), (Join-Path $dirClaude 'agents'), (Join-Path $dirClaude 'commands'), (Join-Path $dirCodex 'skills'), (Join-Path $dirCodex 'prompts')) | Where-Object { Test-Path -LiteralPath $_ }
        $textos = @()
        if ($pastasTexto) { $textos = @(Get-ChildItem -LiteralPath $pastasTexto -Recurse -File -Force -Include '*.md' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\\.trash\\' }) }
        foreach ($a in (Join-Path $dirClaude 'CLAUDE.md'), (Join-Path $dirCodex 'AGENTS.md'), (Join-Path $dirCodex 'AGENTS.override.md')) { if (Test-Path -LiteralPath $a) { $textos += Get-Item -LiteralPath $a } }
        foreach ($f in $textos) {
            $t = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
            if (-not $t) { continue }
            $porque = @()
            if ($t -match $padraoBaixar) { $trecho = $matches[0].Trim(); if ($trecho.Length -gt 90) { $trecho = $trecho.Substring(0, 90) + '...' }; $porque += "manda baixar e rodar código ('$trecho')" }
            if ($t -match '[​-‏‪-‮⁠-⁤]|\uDB40[\uDC00-\uDC7F]') { $porque += 'tem caracteres invisíveis (truque para esconder instruções)' }
            if ($porque.Count -gt 0) {
                $problemasIA++
                Atencao "Instrução para o assistente em $($f.FullName.Replace($casa, '~')): $($porque -join ' e ')" 'Abra o arquivo e confira. Se não foi você (nem uma skill oficial), apague a pasta da skill e rode a verificação completa do Defender'
            }
        }

        # Os programas dos assistentes têm de estar assinados pelo fabricante (senão podem ter sido trocados).
        $exes = @()
        $exes += @(Get-ChildItem -LiteralPath "$casa\.vscode\extensions" -Directory -Filter 'anthropic.claude-code-*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'resources\native-binary\claude.exe' })
        $exes += @(Get-ChildItem -LiteralPath "$casa\.vscode\extensions" -Directory -Filter 'openai.chatgpt-*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'bin\windows-x86_64\codex.exe' })
        $exes += "$casa\.local\bin\claude.exe"
        $nExe = 0; $ruinsExe = 0
        foreach ($e in @($exes | Where-Object { Test-Path -LiteralPath $_ })) {
            $nExe++; $ass = Assinatura $e
            if ($ass.Ok -eq $false -or ($ass.Ok -and $ass.Quem -notmatch 'Anthropic|OpenAI')) {
                $ruinsExe++
                Perigo "Programa do assistente sem a assinatura do fabricante: $($e.Replace($casa, '~')) ($($ass.Quem))" 'Pode ter sido trocado. No VS Code, desinstale a extensão, apague a pasta dela em %USERPROFILE%\.vscode\extensions e instale de novo pela loja'
            } elseif ($null -eq $ass.Ok) { Info "Não consegui conferir a assinatura de $($e.Replace($casa, '~'))" }
        }
        if ($nExe -gt 0 -and $ruinsExe -eq 0) { Ok "Programas do Claude Code e do Codex com a assinatura do fabricante ($nExe conferido(s))" }
    }

    # Terminais: o que roda sozinho toda vez que um PowerShell ou um cmd abre (o Claude Code, o git e o npm abrem vários).
    $docs = [Environment]::GetFolderPath('MyDocuments')
    $perfis = @("$docs\WindowsPowerShell\profile.ps1", "$docs\WindowsPowerShell\Microsoft.PowerShell_profile.ps1", "$docs\WindowsPowerShell\Microsoft.VSCode_profile.ps1",
        "$docs\PowerShell\profile.ps1", "$docs\PowerShell\Microsoft.PowerShell_profile.ps1", "$docs\PowerShell\Microsoft.VSCode_profile.ps1",
        "$env:windir\System32\WindowsPowerShell\v1.0\profile.ps1", "$env:windir\System32\WindowsPowerShell\v1.0\Microsoft.PowerShell_profile.ps1",
        "$env:windir\SysWOW64\WindowsPowerShell\v1.0\profile.ps1", "$env:ProgramFiles\PowerShell\7\profile.ps1", "$env:ProgramFiles\PowerShell\7\Microsoft.PowerShell_profile.ps1")
    foreach ($p in $perfis) {
        if (-not (Test-Path -LiteralPath $p)) { continue }
        $problemasIA++
        $t = Get-Content -LiteralPath $p -Raw -ErrorAction SilentlyContinue
        $extra = if ("$t" -match $padraoBaixar) { ' e TEM comando que baixa ou esconde código' } else { '' }
        Atencao ("Perfil do PowerShell (roda sozinho sempre que um PowerShell abre): {0}, alterado em {1:dd/MM/yyyy HH:mm}{2}" -f $p, (Get-Item -LiteralPath $p).LastWriteTime, $extra) 'Se não foi você (oh-my-posh, atalhos): renomeie o arquivo e rode a verificação completa do Defender' `
        (Conserto 'Desativar o perfil (renomeio para .desativado; dá para voltar o nome)' { param($a) Rename-Item -LiteralPath $a -NewName ((Split-Path $a -Leaf) + '.desativado') -ErrorAction Stop } $p -SemAdmin:($p -like "$casa\*"))
    }
    foreach ($k in 'HKCU:\Software\Microsoft\Command Processor', 'HKLM:\Software\Microsoft\Command Processor', 'HKLM:\Software\WOW6432Node\Microsoft\Command Processor') {
        $v = "$((Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue).AutoRun)".Trim()
        if (-not $v) { continue }
        $problemasIA++
        Atencao "Todo Prompt de Comando (cmd) roda antes: $v ($k\AutoRun)" 'Truque usado por vírus (o Claude Code e o git abrem o cmd). Se não foi você, apague o valor AutoRun no regedit' `
        (Conserto "Apagar o AutoRun do cmd (o valor era: $v)" { param($d) Remove-ItemProperty -LiteralPath $d -Name AutoRun -ErrorAction Stop } $k -SemAdmin:($k -like 'HKCU:*'))
    }
    if ($problemasIA -eq 0) { Ok 'Nada mexido no Claude Code, no Codex nem nos terminais (sem ganchos, servidores MCP, desvios de rede, perfis do PowerShell ou AutoRun do cmd)' }
} catch { Falhou 'a configuração dos assistentes de IA' $_ }

# =====================================================================
Secao 'Blindagem (continua valendo?)'
try {
    $pastaBlind = Join-Path $env:ProgramData 'Blindagem'
    $aplicada = @(Get-ChildItem -LiteralPath $pastaBlind -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'mudancas.json') }).Count -gt 0
    function ValorReg([string]$k, [string]$n) {
        if (-not (Test-Path -LiteralPath $k)) { return $null }
        try { $c = Get-Item -LiteralPath $k -ErrorAction Stop; if (@($c.GetValueNames()) -notcontains $n) { return $null }; return $c.GetValue($n) } catch { return $null }
    }
    # O mesmo que o blindagem.ps1 liga (o essencial). Atualizações do Windows e programas às vezes voltam isso ao padrão.
    $itensB = @(
        @('LLMNR desligado', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient', 'EnableMulticast', 0),
        @('mDNS desligado', 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters', 'EnableMDNS', 0),
        @('WDigest (senha legível na memória) desligado', 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest', 'UseLogonCredential', 0),
        @('Só NTLMv2', 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa', 'LmCompatibilityLevel', 5),
        @('Pastas de rede só com assinatura', 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters', 'RequireSecuritySignature', 1),
        @('Área de Trabalho Remota travada por política', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services', 'fDenyTSConnections', 1),
        @('Túnel Teredo desligado', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition', 'Teredo_State', 'Disabled'),
        @('WPAD (proxy automático da rede) desligado', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp', 'DisableWpad', 1),
        @('Arquivos .vbs/.js não rodam com dois cliques', 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings', 'Enabled', 0),
        @('Linha de comando dos programas anotada', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit', 'ProcessCreationIncludeCmdLine_Enabled', 1),
        @('Código dos scripts de PowerShell anotado', 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging', 'EnableScriptBlockLogging', 1),
        @('Inicialização Rápida desligada (nada da memória fica no SSD entre um boot e outro)', 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power', 'HiberbootEnabled', 0),
        @('Hibernação desligada', 'HKLM:\SYSTEM\CurrentControlSet\Control\Power', 'HibernateEnabled', 0)
    )
    $faltando = New-Object System.Collections.Generic.List[string]
    foreach ($i in $itensB) { if ("$(ValorReg $i[1] $i[2])" -ne "$($i[3])") { $faltando.Add($i[0]) } }
    if (-not $script:bloqueioTotal) { $faltando.Add('Bloqueio total de entrada no firewall') }
    try {
        $mpP = Get-CimInstance -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpPreference -ErrorAction Stop
        if ("$($mpP.EnableNetworkProtection)" -ne '1' -and "$(ValorReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection' 'EnableNetworkProtection')" -ne '1') { $faltando.Add('Proteção de rede do Defender') }
        if ("$($mpP.PUAProtection)" -ne '1' -and "$(ValorReg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender' 'PUAProtection')" -ne '1') { $faltando.Add('Bloqueio de programas indesejados (PUA)') }
        # As regras podem estar no Defender (comando) ou na política do Windows (plano B do blindagem.ps1).
        $nAsr = @($mpP.AttackSurfaceReductionRules_Ids | Where-Object { $_ -and "$_" -notmatch 'N/A' }).Count
        $polAsr = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR\Rules'
        if (Test-Path -LiteralPath $polAsr) { $nAsr = [Math]::Max($nAsr, @((Get-Item -LiteralPath $polAsr).GetValueNames() | Where-Object { $_ }).Count) }
        if ($nAsr -lt 16) { $faltando.Add("Regras extras do Defender (ASR): $nAsr de 16") }
    } catch {}
    $arqBlind = Join-Path $pasta 'blindagem.ps1'
    $cB = $null
    if (Test-Path -LiteralPath $arqBlind) {
        $cB = Conserto 'Rodar a blindagem agora (ela guarda como estava antes de mudar e pede administrador)' {
            param($a) $p = Start-Process powershell.exe -ArgumentList '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$a`"", '-SemPausa' -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "a blindagem terminou com código $($p.ExitCode); veja o relatório dela em $env:LOCALAPPDATA\Blindagem\relatorios" }
        } $arqBlind -SemAdmin
    }
    if ($faltando.Count -eq 0) { Ok 'Blindagem valendo: todas as proteções extras continuam ligadas' }
    elseif ($aplicada) {
        Atencao "$($faltando.Count) proteção(ões) da blindagem não estão valendo (são novas ou voltaram ao padrão)" 'Rode o blindagem.ps1 de novo (blindagem.ps1 -Simular mostra antes o que muda, sem mudar nada)' $cB
        foreach ($f in $faltando) { Det "- $f" }
    } else {
        Info "A blindagem nunca foi aplicada neste PC ($($faltando.Count) proteções extras desligadas). Para ver o que ela muda, sem mudar nada: blindagem.ps1 -Simular"
        foreach ($f in $faltando) { Det "- $f" }
    }
    $lb = Join-Path $pastaBlind 'linha-base.json'
    if (Test-Path -LiteralPath $lb) { Info ('Foto da linha de base de {0:dd/MM/yyyy}: rode linha-base.ps1 para ver o que passou a rodar sozinho desde então' -f (Get-Item -LiteralPath $lb).LastWriteTime) }
    else { Info 'Sem foto da linha de base: com o PC limpo, rode linha-base.ps1 -Salvar (depois ele avisa tudo de novo que passar a rodar sozinho)' }
} catch { Falhou 'a blindagem' $_ }

# =====================================================================
Secao 'Resumo'
$dur = [int]((Get-Date) - $inicio).TotalSeconds
Write-Host ("  OK: {0}   ATENÇÃO: {1}   PERIGO: {2}   (levou {3} s)" -f $script:n.OK, $script:n.ATENCAO, $script:n.PERIGO, $dur) -ForegroundColor White
$ordenados = @($script:achados | Where-Object Nivel -eq 'PERIGO') + @($script:achados | Where-Object Nivel -ne 'PERIGO')
if ($script:achados.Count -eq 0) { Write-Host '  Nada a resolver.' -ForegroundColor Green }
else {
    Write-Host '  O que vale resolver:' -ForegroundColor White
    foreach ($a in $ordenados) {
        $cor = if ($a.Nivel -eq 'PERIGO') { 'Red' } else { 'Yellow' }
        Linha "[$($a.Nivel)]" $cor $a.Texto
        ComoResolver $a.Resolver
        if ($a.Consertos.Count -gt 0) { Write-Host '             -> dá para resolver por aqui (veja abaixo)' -ForegroundColor DarkCyan }
    }
}

# =====================================================================
# Resolver: só roda o que a pessoa confirmar, um item por vez.
$feitos = New-Object System.Collections.Generic.List[string]
$precisaReiniciar = $false
$fila = @(foreach ($a in $ordenados) { foreach ($c in $a.Consertos) { [pscustomobject]@{ Achado = $a; C = $c } } })
$fila = @($fila | Where-Object { -not $_.C.PorUltimo }) + @($fila | Where-Object { $_.C.PorUltimo })
if ($fila.Count -gt 0) {
    Secao 'Resolver agora'
    $qAdmin = @($fila | Where-Object { $_.C.Admin }).Count
    if (-not $podePerguntar) {
        Info "$($fila.Count) item(ns) dá para resolver por este script: abra pelo atalho 'Verificar segurança' (botão direito > Executar como administrador) e responda S no final"
        $fila = @()
    }
    elseif (-not $admin -and $qAdmin -gt 0) {
        Info "$qAdmin de $($fila.Count) item(ns) precisam de administrador."
        $r = "$(Read-Host '  Abrir de novo como administrador para resolver tudo? (S/N)')".Trim()
        if ($r -match '^(s|sim|y)$') {
            try {
                Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -Verb RunAs -ErrorAction Stop `
                    -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Pausar -Resolver"
                Info 'Abri uma janela nova como administrador: continue por lá (ela refaz o relatório e depois pergunta item por item).'
                $fila = @()
            } catch { Info 'O pedido de administrador foi cancelado; sigo só com o que dá para fazer sem ele.'; $fila = @($fila | Where-Object { -not $_.C.Admin }) }
        } else { $fila = @($fila | Where-Object { -not $_.C.Admin }) }
    }
    if ($fila.Count -gt 0 -and -not $Resolver) {
        $r = "$(Read-Host "  Quer resolver agora? Pergunto um item por vez ($($fila.Count) no total) (S/N)")".Trim()
        if ($r -notmatch '^(s|sim|y)$') { $fila = @() }
    }
    $i = 0
    foreach ($item in $fila) {
        $i++; $c = $item.C
        Write-Host ''
        $cor = if ($item.Achado.Nivel -eq 'PERIGO') { 'Red' } else { 'Yellow' }
        Write-Host ("  [$i/$($fila.Count)] " + $item.Achado.Texto) -ForegroundColor $cor
        Write-Host ('        O que vou fazer: ' + $c.Acao) -ForegroundColor White
        if ($c.Aviso) { Write-Host ('        Antes de responder: ' + $c.Aviso) -ForegroundColor DarkYellow }
        $r = "$(Read-Host '        Fazer? (S = sim, N = pular, P = parar aqui)')".Trim().ToLower()
        if ($r -match '^p') { Info 'Parei aqui; o resto ficou como estava.'; break }
        if ($r -notmatch '^(s|sim|y)$') { Det 'Pulei.'; continue }
        try {
            & $c.Fazer $c.Dados
            $feitos.Add($c.Acao)
            if ($c.Reinicia) { $precisaReiniciar = $true }
            Ok ('Feito: ' + $c.Acao)
        } catch {
            $m = "$_"; if ($_.Exception) { $m = $_.Exception.Message }
            Linha '[ERRO]' Red "Não consegui: $m"
        }
    }
    if ($feitos.Count -gt 0) {
        Write-Host ''
        Info "$($feitos.Count) item(ns) resolvido(s). Rode o 'Verificar segurança' de novo para conferir."
        if ($precisaReiniciar) { Info 'Algumas mudanças só valem depois de reiniciar o PC.' }
    }
}

Write-Host ''
Write-Host '  Fora do PC (confira você mesmo):' -ForegroundColor White
Det '- Roteador: troque a senha padrão de administrador e desligue o UPnP.'
Det '- Ative a verificação em duas etapas no Google, no GitHub e na conta Microsoft.'
Write-Host ''
if ($feitos.Count -eq 0) { Write-Host '  Este relatório não mudou nada no computador.' -ForegroundColor DarkGray }
else { Write-Host "  Mudanças feitas agora: $($feitos -join '; ')" -ForegroundColor DarkGray }
# Confere se a cópia existe mesmo: o Start-Transcript não avisa quando o Windows barra a gravação.
if ($transcrevendo) { try { Stop-Transcript | Out-Null } catch {} }
if (Test-Path -LiteralPath $arquivoRel) { Write-Host "  Cópia salva em: $arquivoRel" -ForegroundColor DarkGray }
else { Write-Host "  Não consegui salvar a cópia do relatório em $arquivoRel" -ForegroundColor Yellow }
if ($Pausar) { Write-Host ''; Read-Host '  Pressione Enter para fechar' | Out-Null }
