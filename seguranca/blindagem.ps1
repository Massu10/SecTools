<#
  Blindagem — desliga o que ainda escuta na rede, os protocolos da rede local que vazam senha,
  liga proteções extras do Defender e deixa o Windows registrando o que acontece no PC.
  Complementa o seguranca.ps1, que só verifica.

  Antes de mudar cada item, guarda como ele estava; -Desfazer volta tudo.
  Continua funcionando: internet, Docker Desktop, WSL, VS Code, git, Claude Code e "Microsoft Print to PDF".
  Deixa de funcionar de propósito: arquivos .vbs/.js com dois cliques (se um instalador antigo reclamar, use -Desfazer).
  Se o Defender recusar uma mudança por comando, aplica a mesma coisa pela política do Windows (plano B).

  Uso:
    blindagem.ps1 -Simular    mostra o que mudaria, sem mudar nada (não precisa de administrador)
    blindagem.ps1             aplica (pede administrador); desliga a rede só enquanto aplica e religa no fim
    blindagem.ps1 -Online     aplica sem desligar a rede
    blindagem.ps1 -Desfazer   volta tudo como era antes (ou só um backup, com -Backup <pasta>)
  Backups: C:\ProgramData\Blindagem (só administradores alteram). Registro de cada execução: %LOCALAPPDATA%\Blindagem\relatorios.
#>
param([switch]$Simular, [switch]$Online, [switch]$Desfazer, [string]$Backup, [switch]$SemPausa)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$esteArquivo = $MyInvocation.MyCommand.Path
$pasta = Split-Path -Parent $esteArquivo
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Sem administrador: abre de novo pedindo permissão (janela do UAC) e espera terminar.
if (-not $admin -and -not $Simular) {
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$esteArquivo`"")
    if ($Online) { $argumentos += '-Online' }
    if ($Desfazer) { $argumentos += '-Desfazer' }
    if ($Backup) { $argumentos += '-Backup', "`"$Backup`"" }
    if ($SemPausa) { $argumentos += '-SemPausa' }
    try { $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argumentos -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode }
    catch { Write-Host '  Precisa de administrador e o pedido do UAC foi recusado. Nada foi mudado.' -ForegroundColor Red; exit 1 }
}

$inicio = Get-Date
$transcrevendo = $false
if (-not $Simular) {
    $pastaRel = Join-Path $env:LOCALAPPDATA 'Blindagem\relatorios'   # fora de Documentos: lá o anti-ransomware barra o PowerShell
    $null = New-Item -ItemType Directory -Force -Path $pastaRel
    $nomeRel = if ($Desfazer) { 'blindagem-desfazer-{0:yyyy-MM-dd_HHmm}.txt' } else { 'blindagem-{0:yyyy-MM-dd_HHmm}.txt' }
    try { Start-Transcript -Path (Join-Path $pastaRel ($nomeRel -f $inicio)) -Force | Out-Null; $transcrevendo = $true } catch {}
}

# ---------- saída ----------
$script:n = @{ Feito = 0; Ja = 0; Muda = 0; Erro = 0 }
function Secao([string]$t) { Write-Host ''; Write-Host ("== $t ").PadRight(78, '=') -ForegroundColor Cyan }
function Linha([string]$rotulo, [ConsoleColor]$cor, [string]$texto) { Write-Host ('  ' + $rotulo.PadRight(13) + $texto) -ForegroundColor $cor }
function Feito([string]$t) { $script:n.Feito++; Linha '[FEITO]' Green $t }
function Ja([string]$t) { $script:n.Ja++; Linha '[JÁ ESTAVA]' DarkGreen $t }
function Muda([string]$t) { $script:n.Muda++; Linha '[VAI MUDAR]' Yellow $t }
function Info([string]$t) { Linha '[INFO]' Gray $t }
function Erro([string]$t, $e) {
    $script:n.Erro++
    $m = if ($e -is [System.Management.Automation.ErrorRecord]) { $e.Exception.Message } else { "$e" }
    Linha '[ERRO]' Red "$t ($m)"
}
function Fim {
    if ($transcrevendo) { try { Stop-Transcript | Out-Null } catch {} }
    if (-not $SemPausa -and -not $Simular -and [Environment]::UserInteractive) { Write-Host ''; $null = Read-Host '  Aperte Enter para fechar' }
}

# ---------- backup ----------
$raizBackup = Join-Path $env:ProgramData 'Blindagem'
$script:itens = New-Object System.Collections.Generic.List[object]
$script:arqItens = $null
# Anota como o item estava ANTES de mudar. O arquivo é regravado a cada item, para valer mesmo se o script parar no meio.
function Guardar([string]$item, [hashtable]$dados) {
    $dados['Item'] = $item
    $script:itens.Add([pscustomobject]$dados)
    ConvertTo-Json -InputObject $script:itens.ToArray() -Depth 5 | Set-Content -LiteralPath $script:arqItens -Encoding UTF8 -ErrorAction Stop
}

# ---------- como mudar cada tipo de item ----------
function Reg([string]$chave, [string]$nome, $valor, [string]$porque, [string]$tipo = 'DWord') {
    $existia = $false; $atual = $null; $tipoAtual = $null
    try {
        # Test-Path antes: erro dentro de try ainda sujaria a cópia .txt do relatório.
        $k = $null; if (Test-Path -LiteralPath $chave) { $k = Get-Item -LiteralPath $chave -ErrorAction Stop }
        if ($k -and @($k.GetValueNames()) -contains $nome) {
            $existia = $true
            $atual = $k.GetValue($nome, $null, 'DoNotExpandEnvironmentNames')
            $tipoAtual = "$($k.GetValueKind($nome))"
        }
    } catch {}
    if ($existia -and "$atual" -eq "$valor") { Ja $porque; return }
    if ($Simular) { $antes = if ($existia) { "$atual" } else { 'sem valor' }; Muda "$porque  [${nome}: $antes -> $valor]"; return }
    try {
        Guardar 'reg' @{ Chave = $chave; Nome = $nome; Existia = $existia; Valor = $atual; TipoValor = $tipoAtual }
        if (-not (Test-Path -LiteralPath $chave)) { $null = New-Item -Path $chave -Force -ErrorAction Stop }
        $null = New-ItemProperty -LiteralPath $chave -Name $nome -Value $valor -PropertyType $tipo -Force -ErrorAction Stop
        Feito $porque
    } catch { Erro $porque $_ }
}

# Para o serviço e marca como Desativado (não desinstala nada).
function Servico([string]$nome, [string]$porque) {
    $s = Get-Service -Name $nome -ErrorAction SilentlyContinue
    if (-not $s) { Ja "$porque (não instalado)"; return }
    if ("$($s.StartType)" -eq 'Disabled' -and "$($s.Status)" -eq 'Stopped') { Ja $porque; return }
    if ($Simular) { Muda "$porque  [${nome}: $($s.StartType), $($s.Status) -> desativado e parado]"; return }
    try {
        Guardar 'servico' @{ Nome = $nome; Inicio = "$($s.StartType)"; Rodando = ("$($s.Status)" -eq 'Running') }
        Set-Service -Name $nome -StartupType Disabled -ErrorAction Stop
        if ("$($s.Status)" -ne 'Stopped') { Stop-Service -Name $nome -Force -ErrorAction Stop }
        Feito $porque
    } catch { Erro $porque $_ }
}

function MpLer { Get-CimInstance -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpPreference -ErrorAction Stop }
# Chama o Defender direto (o Set-MpPreference às vezes não carrega no PowerShell 5.1); se falhar, tenta o comando normal.
# Nunca para o script: devolve o erro (ou nada). O Defender às vezes dá erro e muda assim mesmo (e vice-versa),
# então quem chama decide RELENDO o estado; se não mudou de verdade, usa a política do Windows (plano B).
function MpMudar([string]$metodo, [hashtable]$h) {
    $erro = $null
    try { $null = Invoke-CimMethod -Namespace root/Microsoft/Windows/Defender -ClassName MSFT_MpPreference -MethodName $metodo -Arguments $h -ErrorAction Stop; return $null } catch { $erro = $_ }
    $cmd = @{ Set = 'Set-MpPreference'; Add = 'Add-MpPreference'; Remove = 'Remove-MpPreference' }[$metodo]
    try { & $cmd @h -ErrorAction Stop; return $null } catch { if (-not $erro) { $erro = $_ } }
    return $erro
}
# Lê um valor do registro sem gerar erro (nem sujar o relatório).
function LerReg([string]$chave, [string]$nome) {
    if (-not (Test-Path -LiteralPath $chave)) { return $null }
    try { $k = Get-Item -LiteralPath $chave -ErrorAction Stop; if (@($k.GetValueNames()) -contains $nome) { return $k.GetValue($nome) } } catch {}
    return $null
}

function Log([string]$nome, [int64]$mb, [string]$porque, [switch]$Ligar) {
    try { $l = Get-WinEvent -ListLog $nome -ErrorAction Stop }
    catch { if ($Simular) { Info "${porque}: só dá para ler como administrador" } else { Info "${porque}: não existe neste Windows" }; return }
    $bytes = $mb * 1MB
    $ligar = $Ligar -and -not $l.IsEnabled
    if ($l.MaximumSizeInBytes -ge $bytes -and -not $ligar) { Ja $porque; return }
    if ($Simular) { Muda ("$porque  [{0} MB{1} -> $mb MB]" -f [math]::Round($l.MaximumSizeInBytes / 1MB), $(if ($ligar) { ', desligado' } else { '' })); return }
    try {
        Guardar 'log' @{ Nome = $nome; Tamanho = $l.MaximumSizeInBytes; Ligado = $l.IsEnabled }
        if ($l.MaximumSizeInBytes -lt $bytes) { $l.MaximumSizeInBytes = $bytes }
        if ($ligar) { $l.IsEnabled = $true }
        $l.SaveChanges()
        Feito $porque
    } catch { Erro $porque $_ }
}

function PortasEscutando {
    Secao 'Portas que ainda escutam na rede'
    $nomes = @{}; foreach ($pr in Get-Process -ErrorAction SilentlyContinue) { $nomes[[int]$pr.Id] = $pr.ProcessName }
    $grupos = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { "$($_.LocalAddress)" -notmatch '^(127\.|::1$)' } |
        Group-Object LocalPort | Sort-Object { [int]$_.Name })
    foreach ($g in $grupos) { Info ('TCP {0,-6} {1}' -f $g.Name, ((@($g.Group | ForEach-Object { $nomes[[int]$_.OwningProcess] }) | Select-Object -Unique) -join ', ')) }
    Info 'Mesmo essas ficam fechadas para a rede: o firewall está no bloqueio total de entrada.'
    Info 'A 135 e as 4966x são do próprio Windows (conversa interna entre serviços) e não dá para desligar.'
}

# =====================================================================
Write-Host ''
if ($Simular) { Write-Host '  BLINDAGEM — SIMULAÇÃO: só mostra o que mudaria; nada é mudado' -ForegroundColor White }
elseif ($Desfazer) { Write-Host '  BLINDAGEM — DESFAZER: voltando as configurações como eram antes' -ForegroundColor White }
else { Write-Host '  BLINDAGEM — aplicando (cada item é guardado antes de mudar)' -ForegroundColor White }
Write-Host ("  {0:dd/MM/yyyy HH:mm} | usuário {1} | {2}" -f $inicio, $env:USERNAME, $(if ($admin) { 'como administrador' } else { 'sem administrador' })) -ForegroundColor DarkGray

# =====================================================================
if ($Desfazer) {
    Secao 'Desfazer'
    $pastas = @()
    if ($Backup) { $pastas = @(Get-Item -LiteralPath $Backup -ErrorAction SilentlyContinue) }
    else { $pastas = @(Get-ChildItem -LiteralPath $raizBackup -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'desfeito' } | Sort-Object Name -Descending) }
    $pastas = @($pastas | Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $_.FullName 'mudancas.json')) })
    if ($pastas.Count -eq 0) { Erro 'Não achei backup para voltar' "procurei em $raizBackup"; Fim; exit 1 }
    # Do mais novo para o mais antigo, e dentro de cada um, do último item para o primeiro.
    foreach ($pb in $pastas) {
        Info "Voltando ao estado guardado em $($pb.FullName)"
        $errosAntes = $script:n.Erro
        $lista = Get-Content -LiteralPath (Join-Path $pb.FullName 'mudancas.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $lista = @($lista)
        [array]::Reverse($lista)
        foreach ($i in $lista) {
            try {
                switch ($i.Item) {
                    'reg' {
                        if ($i.Existia) {
                            $v = $i.Valor
                            if ($i.TipoValor -eq 'Binary') { $v = [byte[]]@($v) } elseif ($i.TipoValor -eq 'MultiString') { $v = [string[]]@($v) }
                            $null = New-ItemProperty -LiteralPath $i.Chave -Name $i.Nome -Value $v -PropertyType $i.TipoValor -Force -ErrorAction Stop
                        } else { Remove-ItemProperty -LiteralPath $i.Chave -Name $i.Nome -ErrorAction SilentlyContinue }
                        Feito "Registro $($i.Nome) ($($i.Chave -replace '^.*::', ''))"
                    }
                    'servico' {
                        Set-Service -Name $i.Nome -StartupType $i.Inicio -ErrorAction Stop
                        if ($i.Rodando) { Start-Service -Name $i.Nome -ErrorAction SilentlyContinue }
                        Feito "Serviço $($i.Nome) de volta para $($i.Inicio)"
                    }
                    'firewall' {
                        $h = @{ Name = $i.Perfil; ($i.Opcao) = $i.Valor }
                        Set-NetFirewallProfile @h -ErrorAction Stop
                        Feito "Firewall $($i.Perfil): $($i.Opcao) = $($i.Valor)"
                    }
                    'defender' {
                        $v = if ($null -eq $i.Valor) { 0 } else { $i.Valor }
                        $null = MpMudar 'Set' @{ ($i.Opcao) = [byte]$v }
                        Feito "Defender: $($i.Opcao) = $v"
                    }
                    'asr' {
                        if ($i.Existia) { $null = MpMudar 'Add' @{ AttackSurfaceReductionRules_Ids = [string[]]@($i.Id); AttackSurfaceReductionRules_Actions = [byte[]]@([byte]$i.Acao) } }
                        else { $null = MpMudar 'Remove' @{ AttackSurfaceReductionRules_Ids = [string[]]@($i.Id) } }
                        Feito "Regra do Defender $($i.Id) de volta"
                    }
                    'log' {
                        $l = Get-WinEvent -ListLog $i.Nome -ErrorAction Stop
                        $l.MaximumSizeInBytes = [int64]$i.Tamanho; $l.IsEnabled = [bool]$i.Ligado; $l.SaveChanges()
                        Feito "Registro de eventos $($i.Nome) de volta"
                    }
                    'recurso' {
                        $null = Enable-WindowsOptionalFeature -Online -FeatureName $i.Nome -NoRestart -All -ErrorAction Stop
                        Feito "Recurso $($i.Nome) religado"
                    }
                }
            } catch { Erro "Não consegui voltar $($i.Item) $($i.Nome)$($i.Opcao)$($i.Id)" $_ }
        }
        $aud = Join-Path $pb.FullName 'auditoria.csv'
        if (Test-Path -LiteralPath $aud) {
            $null = auditpol /restore /file:"$aud"
            if ($LASTEXITCODE -eq 0) { Feito 'Auditoria do Windows de volta como estava' } else { Erro 'Não consegui voltar a auditoria' "auditpol terminou com código $LASTEXITCODE" }
        }
        if ($script:n.Erro -eq $errosAntes) { try { Rename-Item -LiteralPath $pb.FullName -NewName ($pb.Name + '-desfeito') -ErrorAction Stop } catch {} }
    }
    Secao 'Resumo'
    Write-Host ("  Voltou: {0}   Erros: {1}" -f $script:n.Feito, $script:n.Erro) -ForegroundColor White
    Info 'Reinicie o PC para tudo voltar a valer.'
    Fim
    exit $(if ($script:n.Erro) { 2 } else { 0 })
}

# =====================================================================
if (-not $Simular) {
    try {
        if (-not (Test-Path -LiteralPath $raizBackup)) { $null = New-Item -ItemType Directory -Path $raizBackup -Force -ErrorAction Stop }
        # Só administradores e o sistema alteram os backups (um programa comum não consegue forjar um "desfazer").
        $null = icacls $raizBackup /setowner '*S-1-5-32-544'
        $null = icacls $raizBackup /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX'
        $pastaBackup = Join-Path $raizBackup ('{0:yyyy-MM-dd_HHmmss}' -f $inicio)
        $null = New-Item -ItemType Directory -Path $pastaBackup -Force -ErrorAction Stop
        $script:arqItens = Join-Path $pastaBackup 'mudancas.json'
        Set-Content -LiteralPath $script:arqItens -Value '[]' -Encoding UTF8 -ErrorAction Stop
    } catch { Erro 'Não consegui criar a pasta de backup; parei sem mudar nada' $_; Fim; exit 1 }
}

# ---------- modo offline ----------
$script:desligados = @()
$tarefa = 'Blindagem - religar a rede'
if (-not $Simular -and -not $Online) {
    Secao 'Rede'
    $mpcmd = Join-Path $env:ProgramFiles 'Windows Defender\MpCmdRun.exe'
    if (Test-Path -LiteralPath $mpcmd) {
        Info 'Atualizando o antivírus antes de desligar a rede...'
        $null = & $mpcmd -SignatureUpdate
        if ($LASTEXITCODE -eq 0) { Feito 'Antivírus atualizado' } else { Info "Não consegui atualizar o antivírus agora (código $LASTEXITCODE); sigo assim mesmo" }
    }
    try {
        $fisicos = @(Get-NetAdapter -Physical -ErrorAction Stop | Where-Object { "$($_.Status)" -eq 'Up' })
        if ($fisicos.Count -eq 0) { Info 'Nenhuma placa de rede ligada; já está offline' }
        else {
            $nomesAd = @($fisicos | ForEach-Object { $_.Name })
            # Rede de segurança: se esta janela fechar no meio, uma tarefa do sistema religa a rede em 10 minutos ou ao ligar o PC.
            $lista = ($nomesAd | ForEach-Object { "'" + ($_ -replace "'", "''") + "'" }) -join ','
            $cmd = "Enable-NetAdapter -Name $lista -Confirm:`$false; Unregister-ScheduledTask -TaskName '$tarefa' -Confirm:`$false"
            $sistema = (New-Object Security.Principal.SecurityIdentifier 'S-1-5-18').Translate([Security.Principal.NTAccount]).Value
            $null = Register-ScheduledTask -TaskName $tarefa -Force -ErrorAction Stop `
                -Action (New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -Command `"$cmd`"") `
                -Trigger @((New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(10)), (New-ScheduledTaskTrigger -AtStartup)) `
                -Principal (New-ScheduledTaskPrincipal -UserId $sistema -LogonType ServiceAccount -RunLevel Highest) `
                -Settings (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable)
            $script:desligados = $nomesAd
            Disable-NetAdapter -Name $nomesAd -Confirm:$false -ErrorAction Stop
            Feito "Rede desligada enquanto aplico ($($nomesAd -join ', ')); ela volta sozinha no fim"
        }
    } catch { Erro 'Não consegui desligar a rede; sigo com ela ligada' $_ }
}

try {
    # =====================================================================
    Secao 'Firewall'
    $quero = [ordered]@{ Enabled = 'True'; DefaultInboundAction = 'Block'; AllowInboundRules = 'False'; LogBlocked = 'True'; NotifyOnListen = 'True'; LogMaxSizeKilobytes = '16384' }
    $textos = @{
        Enabled              = 'firewall ligado'
        DefaultInboundAction = 'conexões de entrada bloqueadas por padrão'
        AllowInboundRules    = 'bloqueio TOTAL de entrada (nem programas liberados recebem conexões)'
        LogBlocked           = 'anotar as tentativas de conexão bloqueadas (System32\LogFiles\Firewall\pfirewall.log)'
        NotifyOnListen       = 'avisar quando um programa for impedido de receber conexões'
        LogMaxSizeKilobytes  = 'histórico do firewall maior (16 MB; o padrão de 4 MB dura poucos dias)'
    }
    try {
        # Cópia extra das regras, só por garantia (o -Desfazer usa o arquivo mudancas.json).
        if (-not $Simular) { $null = netsh advfirewall export (Join-Path $pastaBackup 'firewall.wfw') }
        $efetivo = @{}; foreach ($a in Get-NetFirewallProfile -PolicyStore ActiveStore -ErrorAction Stop) { $efetivo["$($a.Name)"] = $a }
        foreach ($p in Get-NetFirewallProfile -PolicyStore PersistentStore -ErrorAction Stop) {
            foreach ($k in $quero.Keys) {
                $txt = "Perfil $($p.Name): $($textos[$k])"
                $agora = "$($efetivo["$($p.Name)"].$k)"
                if ($agora -eq $quero[$k]) { Ja $txt; continue }
                if ($Simular) { Muda "$txt  [$agora -> $($quero[$k])]"; continue }
                try {
                    Guardar 'firewall' @{ Perfil = "$($p.Name)"; Opcao = $k; Valor = "$($p.$k)" }
                    $h = @{ Name = $p.Name; $k = $quero[$k] }
                    Set-NetFirewallProfile @h -ErrorAction Stop
                    Feito $txt
                } catch { Erro $txt $_ }
            }
        }
    } catch { Erro 'Não consegui ler o firewall' $_ }

    # =====================================================================
    Secao 'Acesso remoto (travado desligado)'
    $ts = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'
    Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' 'fDenyTSConnections' 1 'Área de Trabalho Remota desligada'
    Reg $ts 'fDenyTSConnections' 1 'Área de Trabalho Remota travada por política (não liga nem pela tela de Configurações)'
    Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Remote Assistance' 'fAllowToGetHelp' 0 'Assistência Remota desligada'
    Reg $ts 'fAllowToGetHelp' 0 'Assistência Remota travada por política'
    Reg $ts 'fAllowUnsolicited' 0 'Ajuda remota sem convite travada'
    Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service' 'AllowAutoConfig' 0 'Controle remoto do PowerShell (WinRM) travado por política'
    Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WinRM\Service\WinRS' 'AllowRemoteShellAccess' 0 'Terminal remoto (WinRS) travado por política'
    Servico 'WinRM' 'Serviço de controle remoto do PowerShell (WinRM, portas 5985/5986)'
    Servico 'TermService' 'Serviço da Área de Trabalho Remota (porta 3389)'
    Servico 'UmRdpService' 'Redirecionador de portas da Área de Trabalho Remota'
    Servico 'RemoteRegistry' 'Registro Remoto'
    Servico 'RemoteAccess' 'Roteamento e acesso remoto'
    Servico 'sshd' 'Servidor SSH (porta 22)'

    # =====================================================================
    Secao 'Portas e rede local'
    # O Docker Desktop exige o serviço Servidor: com ele instalado, o serviço fica ligado.
    # A porta 445 continua fechada pelo firewall (bloqueio total de entrada) e sem C$/ADMIN$ (AutoShareWks=0, abaixo).
    if (Test-Path -LiteralPath "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe") { Info 'Serviço Servidor (SMB) fica ligado porque o Docker Desktop exige; a porta 445 segue fechada pelo firewall e sem compartilhamentos administrativos' }
    else { Servico 'LanmanServer' 'Compartilhamento de arquivos (SMB, porta 445): não há pastas compartilhadas' }
    Servico 'lmhosts' 'Auxiliar NetBIOS'
    Servico 'SSDPSRV' 'Descoberta SSDP/UPnP (porta 1900)'
    Servico 'upnphost' 'Host de dispositivos UPnP'
    Servico 'FDResPub' 'Anúncio deste PC para outros aparelhos da rede (porta 5357)'

    $nomesInterface = @{}
    foreach ($a in Get-NetAdapter -IncludeHidden -ErrorAction SilentlyContinue) { $nomesInterface[("Tcpip_$($a.InterfaceGuid)").ToLower()] = $a.Name }
    $mudouNetbios = $script:n.Feito
    foreach ($k in Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces' -ErrorAction SilentlyContinue) {
        $ni = $nomesInterface[$k.PSChildName.ToLower()]; if (-not $ni) { $ni = 'placa de rede antiga ou oculta' }
        Reg $k.PSPath 'NetbiosOptions' 2 "NetBIOS desligado em '$ni' (portas 137-139)"
    }
    if (-not $Simular -and $script:n.Feito -gt $mudouNetbios) {
        # Vale na hora para as placas ativas; as outras pegam ao reiniciar.
        try { Get-CimInstance Win32_NetworkAdapterConfiguration -Filter 'IPEnabled=TRUE' -ErrorAction Stop | Invoke-CimMethod -MethodName SetTcpipNetbios -Arguments @{ TcpipNetbiosOptions = [uint32]2 } -ErrorAction SilentlyContinue | Out-Null } catch {}
    }
    Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient' 'EnableMulticast' 0 'LLMNR desligado (impede que alguém na mesma rede se passe por outro PC para pegar sua senha)'
    Reg 'HKLM:\SYSTEM\CurrentControlSet\Services\Dnscache\Parameters' 'EnableMDNS' 0 'mDNS desligado (o PC para de se anunciar na rede local, porta 5353)'
    Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization' 'DODownloadMode' 0 'Windows Update baixa só da Microsoft, sem trocar arquivos com outros PCs (porta 7680)'
    Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Internet Settings\WinHttp' 'DisableWpad' 1 'Descoberta automática de proxy (WPAD) desligada: ninguém na rede se oferece como "proxy" para espiar o PC'
    $v6 = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\TCPIP\v6Transition'
    Reg $v6 'Teredo_State' 'Disabled' 'Túnel Teredo desligado (podia expor o PC direto na internet por IPv6)' 'String'
    Reg $v6 'ISATAP_State' 'Disabled' 'Túnel ISATAP desligado' 'String'
    Reg $v6 '6to4_State' 'Disabled' 'Túnel 6to4 desligado' 'String'
    $srv = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters'
    Reg $srv 'AutoShareWks' 0 'Sem compartilhamentos administrativos ocultos (C$, ADMIN$)'
    Reg $srv 'SMB1' 0 'SMB1 desligado no servidor'
    Reg $srv 'RequireSecuritySignature' 1 'Servidor SMB exige assinatura'
    Reg $srv 'RestrictNullSessAccess' 1 'Servidor SMB sem acesso anônimo'
    $cli = 'HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters'
    Reg $cli 'RequireSecuritySignature' 1 'Pastas de rede só com assinatura (ninguém altera os arquivos no caminho)'
    Reg $cli 'EnablePlainTextPassword' 0 'Pastas de rede: senha nunca vai sem criptografia'
    Reg $cli 'AllowInsecureGuestAuth' 0 'Pastas de rede: nada de entrar como convidado sem senha'
    $prn = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\Printers'
    Reg $prn 'RegisterSpoolerRemoteRpcEndPoint' 2 'Serviço de impressão não aceita conexões de outros PCs (o "Imprimir em PDF" continua)'
    Reg "$prn\PointAndPrint" 'RestrictDriverInstallationToAdministrators' 1 'Só administrador instala driver de impressora (falha PrintNightmare)'

    # =====================================================================
    Secao 'Senhas e contas'
    $lsa = 'HKLM:\SYSTEM\CurrentControlSet\Control\Lsa'
    Reg $lsa 'LmCompatibilityLevel' 5 'Só aceita NTLMv2 (recusa os formatos de senha antigos LM e NTLMv1)'
    Reg $lsa 'NoLMHash' 1 'Não guarda a senha no formato LM antigo (fácil de quebrar)'
    Reg $lsa 'RestrictAnonymous' 1 'Ninguém anônimo lista contas e pastas deste PC'
    Reg $lsa 'RestrictAnonymousSAM' 1 'Ninguém anônimo lista as contas'
    Reg $lsa 'EveryoneIncludesAnonymous' 0 'Anônimo não ganha as permissões de "Todos"'
    Reg "$lsa\MSV1_0" 'NTLMMinClientSec' 537395200 'Login de rede (saindo) só com NTLMv2 e criptografia de 128 bits'
    Reg "$lsa\MSV1_0" 'NTLMMinServerSec' 537395200 'Login de rede (entrando) só com NTLMv2 e criptografia de 128 bits'
    Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\SecurityProviders\WDigest' 'UseLogonCredential' 0 'Senha nunca fica legível na memória (WDigest)'
    $sys = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
    Reg $sys 'LocalAccountTokenFilterPolicy' 0 'Conta local não tem poder de administrador pela rede'
    Reg $sys 'EnableLUA' 1 'UAC ligado'
    Reg $sys 'ConsentPromptBehaviorAdmin' 2 'UAC pede confirmação para TUDO que precisa de administrador, inclusive mudanças nas configurações do Windows'
    Reg $sys 'PromptOnSecureDesktop' 1 'Confirmação do UAC na tela protegida (nenhum programa consegue clicar "Sim" por você)'

    # =====================================================================
    Secao 'Memória entre desligamentos'
    # Com a Inicialização Rápida, "Desligar" grava o núcleo do Windows (e os drivers carregados) no SSD e carrega de volta no
    # próximo boot. Desligada, cada boot começa do zero. O PC só demora uns segundos a mais para ligar.
    Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled' 0 'Inicialização Rápida desligada ("Desligar" apaga a memória de verdade)'
    Reg 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'HibernateEnabled' 0 'Hibernação desligada (a memória não fica gravada no SSD em hiberfil.sys)'
    if (-not $Simular) {
        $null = powercfg.exe /hibernate off
        if ($LASTEXITCODE -eq 0) { Feito 'Arquivo de hibernação (hiberfil.sys) apagado agora' } else { Erro 'Não consegui apagar o hiberfil.sys agora' "powercfg terminou com código $LASTEXITCODE (some no próximo reinício)" }
    }

    # =====================================================================
    Secao 'Pendrive e reprodução automática'
    $exp = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer'
    Reg $exp 'NoDriveTypeAutoRun' 255 'Nada roda sozinho ao conectar pendrive, CD ou HD externo'
    Reg $exp 'NoAutorun' 1 'Arquivo autorun.inf ignorado'
    Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' 'NoAutoplayfornonVolume' 1 'Sem reprodução automática para celular e câmera'

    # =====================================================================
    Secao 'Scripts perigosos'
    # .vbs/.js com dois cliques é um jeito comum de vírus chegar (e-mail, WhatsApp, "boleto"). Nada do Docker/WSL/VS Code/git usa isso.
    Reg 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'Enabled' 0 'Arquivos .vbs e .js não rodam com dois cliques (Windows Script Host desligado)'
    Reg 'HKLM:\SOFTWARE\Microsoft\Windows Script Host\Settings' 'IgnoreUserSettings' 1 'Um programa comum não consegue religar o Windows Script Host só para o usuário'

    # =====================================================================
    Secao 'Antivírus (Defender)'
    $mp = $null
    try { $mp = MpLer }
    catch { if ($Simular) { Info 'As configurações do Defender só podem ser lidas como administrador; elas entram na aplicação de verdade' } else { Erro 'Não consegui ler as configurações do Defender' $_ } }
    if ($mp) {
        $prefs = [ordered]@{
            PUAProtection           = @(1, 'Bloquear programas indesejados (adware, "otimizadores", mineradores)')
            EnableNetworkProtection = @(1, 'Proteção de rede: bloqueia sites e servidores maliciosos em qualquer programa, não só no navegador')
            MAPSReporting           = @(2, 'Proteção na nuvem completa')
            SubmitSamplesConsent    = @(1, 'Enviar à Microsoft só amostras seguras (nunca documentos pessoais)')
            CloudBlockLevel         = @(2, 'Nuvem mais rigorosa com arquivos desconhecidos')
        }
        # Plano B de cada opção: o mesmo ajuste pela política do Windows (o Defender lê em alguns minutos).
        $politicaMp = @{
            PUAProtection           = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender', 'PUAProtection')
            EnableNetworkProtection = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\Network Protection', 'EnableNetworkProtection')
            MAPSReporting           = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet', 'SpynetReporting')
            SubmitSamplesConsent    = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet', 'SubmitSamplesConsent')
            CloudBlockLevel         = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\MpEngine', 'MpCloudBlockLevel')
        }
        foreach ($k in $prefs.Keys) {
            $quer = $prefs[$k][0]; $txt = $prefs[$k][1]; $atual = $mp.$k; $pp = $politicaMp[$k]
            if ("$atual" -eq "$quer" -or "$(LerReg $pp[0] $pp[1])" -eq "$quer") { Ja $txt; continue }
            if ($Simular) { Muda "$txt  [$atual -> $quer]"; continue }
            try {
                Guardar 'defender' @{ Opcao = $k; Valor = $atual }
                $erroMp = MpMudar 'Set' @{ $k = [byte]$quer }
                if ("$((MpLer).$k)" -eq "$quer") { Feito $txt }
                else {
                    $motivo = if ($erroMp) { $erroMp.Exception.Message } else { 'a Proteção contra Adulteração pode ter barrado' }
                    Info "${txt}: não pegou pelo comando ($motivo); aplicando pela política do Windows"
                    Reg $pp[0] $pp[1] $quer "$txt (por política; o Defender passa a usar em alguns minutos)"
                }
            } catch { Erro $txt $_ }
        }

        # Regras ASR: 1 = bloquear, 2 = só registrar. As de "só registrar" travariam scripts e builds do projeto.
        $asr = [ordered]@{
            '56a863a9-875e-4185-98a7-b882c64b5ce5' = @(1, 'drivers legítimos com falha conhecida (usados para desligar o antivírus)')
            '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2' = @(1, 'roubo de senhas da memória do Windows (LSASS)')
            'e6db77e5-3df2-4cf1-b95a-636979351e5b' = @(1, 'programas que se escondem no WMI para voltar a cada reinício')
            'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550' = @(1, 'executáveis vindos de e-mail e webmail')
            'd4f940ab-401b-4efc-aadc-ad5f3c50688a' = @(1, 'Office abrindo outros programas')
            '3b576869-a4ec-4529-8536-b80a7769e899' = @(1, 'Office criando executáveis')
            '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84' = @(1, 'Office injetando código em outros programas')
            '26190899-1602-49e8-8b27-eb1d0a1ce869' = @(1, 'Outlook abrindo outros programas')
            '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b' = @(1, 'macros do Office chamando funções do Windows')
            '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c' = @(1, 'Adobe Reader abrindo outros programas')
            'd3e037e1-3eb8-44c8-a917-57927947596d' = @(1, 'JavaScript/VBScript rodando executáveis baixados')
            'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4' = @(1, 'programas sem assinatura rodando de pendrive')
            'c1db55ab-c21a-4637-bb3f-a12568109d35' = @(2, 'comportamento de ransomware')
            '5beb7efe-fd9a-4556-801d-275e5ffc04cc' = @(2, 'scripts ofuscados')
            'd1e49aac-8f56-4280-b9ba-993a6d77406c' = @(2, 'programas abertos pelo PsExec ou WMI')
            '01443614-cd74-433a-b99e-2ecdc07bfc25' = @(2, 'executáveis raros ou recém-criados')
        }
        $nomeAcao = @{ 0 = 'desligada'; 1 = 'bloquear'; 2 = 'só registrar'; 6 = 'avisar' }
        $ids = @($mp.AttackSurfaceReductionRules_Ids); $acoes = @($mp.AttackSurfaceReductionRules_Actions)
        $asrPol = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Windows Defender Exploit Guard\ASR'
        $pedidas = New-Object System.Collections.Generic.List[string]
        foreach ($id in $asr.Keys) {
            $quer = $asr[$id][0]
            $txt = "Regra do Defender ($($nomeAcao[$quer])): $($asr[$id][1])"
            $i = -1; for ($j = 0; $j -lt $ids.Count; $j++) { if ("$($ids[$j])" -ieq $id) { $i = $j; break } }
            $atual = if ($i -ge 0) { [int]$acoes[$i] } else { $null }
            if (($null -ne $atual -and $atual -eq $quer) -or "$(LerReg "$asrPol\Rules" $id)" -eq "$quer") { Ja $txt; continue }
            if ($Simular) { Muda "$txt  [$(if ($null -eq $atual) { 'não configurada' } else { $nomeAcao[$atual] }) -> $($nomeAcao[$quer])]"; continue }
            try {
                Guardar 'asr' @{ Id = $id; Existia = ($i -ge 0); Acao = $atual }
                $null = MpMudar 'Add' @{ AttackSurfaceReductionRules_Ids = [string[]]@($id); AttackSurfaceReductionRules_Actions = [byte[]]@([byte]$quer) }
                $pedidas.Add($id)
            } catch { Erro $txt $_ }
        }
        # Confere relendo cada regra pedida: só diz FEITO o que o Defender mostra como valendo.
        if ($pedidas.Count -gt 0) {
            $faltam = @($pedidas)
            try {
                $mp2 = MpLer; $ids2 = @($mp2.AttackSurfaceReductionRules_Ids); $ac2 = @($mp2.AttackSurfaceReductionRules_Actions)
                $faltam = @($pedidas | Where-Object { $r = $_; $ok = $false; for ($j = 0; $j -lt $ids2.Count; $j++) { if ("$($ids2[$j])" -ieq $r -and [int]$ac2[$j] -eq $asr[$r][0]) { $ok = $true } }; -not $ok })
            } catch {}
            foreach ($r in $pedidas) { if ($faltam -notcontains $r) { Feito "Regra do Defender ($($nomeAcao[$asr[$r][0]])): $($asr[$r][1])" } }
            if ($faltam.Count -gt 0) {
                # Plano B: política do Windows. Grava TODAS, porque com a política ligada o Defender usa só a lista dela.
                Info "$($faltam.Count) regra(s) não pegaram pelo comando; aplicando todas pela política do Windows"
                Reg $asrPol 'ExploitGuard_ASR_Rules' 1 'Regras extras do Defender ligadas por política'
                foreach ($r in $asr.Keys) { Reg "$asrPol\Rules" $r "$($asr[$r][0])" "Regra do Defender por política ($($nomeAcao[$asr[$r][0]])): $($asr[$r][1])" 'String' }
                Info 'O Defender passa a usar a política em alguns minutos; o seguranca.ps1 confere depois.'
            }
        }
    }

    # =====================================================================
    Secao 'Registros do Windows (para saber depois o que aconteceu no PC)'
    # Subcategorias pelo código (os nomes mudam com o idioma do Windows). $true = anota também as falhas.
    $auditoria = [ordered]@{
        '{0CCE923F-69AE-11D9-BED3-505054503030}' = @($true, 'senhas conferidas (certas e erradas)')
        '{0CCE9215-69AE-11D9-BED3-505054503030}' = @($true, 'logins')
        '{0CCE9216-69AE-11D9-BED3-505054503030}' = @($false, 'logoffs')
        '{0CCE9217-69AE-11D9-BED3-505054503030}' = @($true, 'conta bloqueada por senha errada')
        '{0CCE921B-69AE-11D9-BED3-505054503030}' = @($false, 'logins com poder de administrador')
        '{0CCE921C-69AE-11D9-BED3-505054503030}' = @($true, 'bloqueio e desbloqueio de tela')
        '{0CCE922B-69AE-11D9-BED3-505054503030}' = @($false, 'programas abertos')
        '{0CCE9235-69AE-11D9-BED3-505054503030}' = @($true, 'contas criadas, alteradas ou com senha trocada')
        '{0CCE9237-69AE-11D9-BED3-505054503030}' = @($true, 'mudanças em grupos (ex.: alguém virar administrador)')
        '{0CCE922F-69AE-11D9-BED3-505054503030}' = @($true, 'mudanças na própria auditoria')
        '{0CCE9230-69AE-11D9-BED3-505054503030}' = @($false, 'mudanças nas regras de login')
        '{0CCE9211-69AE-11D9-BED3-505054503030}' = @($true, 'serviços e drivers instalados')
        '{0CCE9210-69AE-11D9-BED3-505054503030}' = @($true, 'mudanças no estado da segurança')
        '{0CCE9212-69AE-11D9-BED3-505054503030}' = @($true, 'integridade do sistema')
        '{0CCE9227-69AE-11D9-BED3-505054503030}' = @($true, 'tarefas agendadas criadas ou alteradas')
        '{0CCE9248-69AE-11D9-BED3-505054503030}' = @($false, 'pendrives e aparelhos conectados')
    }
    if ($Simular) { Info "Auditoria (sem administrador não dá para conferir o que já está ligado; aplicando, liga): $((@($auditoria.Values | ForEach-Object { $_[1] })) -join '; ')" }
    else {
        $arqAud = Join-Path $pastaBackup 'auditoria.csv'
        $null = auditpol /backup /file:"$arqAud"
        if ($LASTEXITCODE -ne 0) { Erro 'Não consegui copiar a auditoria atual, então não mexi nela' "auditpol terminou com código $LASTEXITCODE" }
        else {
            foreach ($g in $auditoria.Keys) {
                $txt = "Anotar $($auditoria[$g][1])"
                # Só liga; nunca desliga o que já estava ligado.
                if ($auditoria[$g][0]) { $null = auditpol /set /subcategory:"$g" /success:enable /failure:enable }
                else { $null = auditpol /set /subcategory:"$g" /success:enable }
                if ($LASTEXITCODE -eq 0) { Feito $txt } else { Erro $txt "auditpol terminou com código $LASTEXITCODE" }
            }
        }
    }
    Reg 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System\Audit' 'ProcessCreationIncludeCmdLine_Enabled' 1 'Anotar a linha de comando de cada programa aberto'
    Reg 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\PowerShell\ScriptBlockLogging' 'EnableScriptBlockLogging' 1 'Anotar o código de todo script de PowerShell que roda (pega vírus que não deixa arquivo no disco)'
    Reg $lsa 'SCENoApplyLegacyAuditPolicy' 1 'Auditoria detalhada vale por cima da antiga'
    Log 'Security' 256 'Histórico de segurança maior (256 MB, alguns meses)'
    Log 'System' 64 'Histórico do sistema maior (64 MB)'
    Log 'Microsoft-Windows-PowerShell/Operational' 128 'Histórico dos comandos de PowerShell (128 MB)'
    Log 'Windows PowerShell' 32 'Histórico do PowerShell antigo (32 MB)'
    Log 'Microsoft-Windows-Windows Defender/Operational' 64 'Histórico do antivírus (64 MB; as atualizações do Defender às vezes voltam para 16 MB e aí ele refaz: normal)'
    Log 'Microsoft-Windows-Windows Firewall With Advanced Security/Firewall' 32 'Histórico de mudanças no firewall (32 MB)'
    Log 'Microsoft-Windows-TaskScheduler/Operational' 32 'Histórico das tarefas agendadas (vem desligado)' -Ligar
    Log 'Microsoft-Windows-DriverFrameworks-UserMode/Operational' 16 'Histórico de pendrives e aparelhos USB (vem desligado)' -Ligar
    Log 'Microsoft-Windows-DNS-Client/Operational' 32 'Histórico dos endereços de internet consultados pelo PC (vem desligado)' -Ligar

    # =====================================================================
    Secao 'Recursos antigos do Windows'
    foreach ($f in @(
            @('MicrosoftWindowsPowerShellV2Root', 'PowerShell 2.0 (versão antiga, usada para driblar os registros do PowerShell)'),
            @('SMB1Protocol', 'SMB1 (protocolo usado pelo WannaCry)'),
            @('TelnetClient', 'Cliente Telnet'),
            @('TFTP', 'Cliente TFTP'))) {
        $nomeRec = $f[0]; $txt = $f[1]
        $st = $null
        try { $st = Get-WindowsOptionalFeature -Online -FeatureName $nomeRec -ErrorAction Stop }
        catch { if ($Simular) { Info "${txt}: só dá para conferir como administrador" } else { Ja "${txt}: não existe neste Windows" }; continue }
        if (-not $st) { Ja "${txt}: não existe neste Windows"; continue }
        if ("$($st.State)" -ne 'Enabled') { Ja "$txt desligado"; continue }
        if ($Simular) { Muda "Desligar $txt"; continue }
        try {
            Guardar 'recurso' @{ Nome = $nomeRec }
            $null = Disable-WindowsOptionalFeature -Online -FeatureName $nomeRec -NoRestart -ErrorAction Stop
            Feito "Desligar $txt"
        } catch { Erro "Desligar $txt" $_ }
    }
} finally {
    if ($script:desligados.Count -gt 0) {
        Secao 'Rede'
        try {
            Enable-NetAdapter -Name $script:desligados -Confirm:$false -ErrorAction Stop
            Feito "Rede religada ($($script:desligados -join ', '))"
            try { Unregister-ScheduledTask -TaskName $tarefa -Confirm:$false -ErrorAction Stop } catch {}
            $limite = (Get-Date).AddSeconds(60)
            while ((Get-Date) -lt $limite -and -not @(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { "$($_.IPv4Connectivity)" -eq 'Internet' }).Count) { Start-Sleep -Seconds 2 }
            if (@(Get-NetConnectionProfile -ErrorAction SilentlyContinue | Where-Object { "$($_.IPv4Connectivity)" -eq 'Internet' }).Count) { Info 'Internet de volta' }
            else { Info 'A placa foi religada; a internet ainda está voltando' }
        } catch { Erro 'Não consegui religar a rede; ela volta sozinha em até 10 minutos (ou ao reiniciar)' $_ }
    }
}

PortasEscutando

# =====================================================================
Secao 'Resumo'
if ($Simular) {
    Write-Host ('  Vai mudar: {0}   Já estava certo: {1}' -f $script:n.Muda, $script:n.Ja) -ForegroundColor White
    Info 'Isto foi só uma simulação: nada foi mudado.'
} else {
    Write-Host ('  Feito: {0}   Já estava certo: {1}   Erros: {2}' -f $script:n.Feito, $script:n.Ja, $script:n.Erro) -ForegroundColor White
    Info "Como estava antes: $pastaBackup"
    Info 'Para voltar tudo: blindagem.ps1 -Desfazer'
    if ($script:n.Feito -gt 0) { Info 'Reinicie o PC para valer tudo (NetBIOS, mDNS, Teredo, impressão e regras de senha de rede só mudam depois de reiniciar).' }
    Info 'Se aparecer aviso do Defender dizendo "o administrador de TI bloqueou", é uma das regras ligadas aqui: o Windows usa esse texto padrão.'
}
Fim
exit $(if ($script:n.Erro) { 2 } else { 0 })
