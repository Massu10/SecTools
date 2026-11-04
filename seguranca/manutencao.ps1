<#
  Manutenção — a rotina inteira numa ordem só. Pede administrador (janela do UAC).

  manutencao.ps1            CONFERIR (não apaga nada):
                              0. confere os códigos SHA256 dos scripts (codigos-sha256.txt); se algum não bater, PARA
                              1. blindagem: simula e, se algo saiu do lugar, reaplica (sem derrubar a internet)
                              2. relatório de segurança (seguranca.ps1 como administrador)
                              3. linha de base: compara o que roda sozinho com a foto guardada
  manutencao.ps1 -Concluir  DEPOIS de conferir (todo NOVO/MUDOU da linha de base precisa ter explicação):
                              4. salva a foto nova da linha de base (a anterior vai para C:\ProgramData\Blindagem)
                              5. apaga os nossos relatórios e as sobras de instaladores (os históricos do Windows ficam)
                              6. backup completo do Windows na parte BACKUP e só então apaga as versões anteriores

  manutencao.ps1 -GerarCodigos   grava o codigos-sha256.txt com os scripts de agora (faça só depois de conferir
                                 que eles são os originais; guarde uma cópia fora do PC, ex.: num pendrive)
  Opções: -SemConferir (pula o passo 0), -SemBackup (pula o passo 6), -Backup <rótulo> (padrão: BACKUP, o nome da
          unidade onde o backup é guardado).

  Resumo da última execução: %LOCALAPPDATA%\Blindagem\relatorios\ultima-manutencao.txt
#>
param([switch]$Concluir, [switch]$SemPausa, [switch]$GerarCodigos, [switch]$SemConferir, [switch]$SemBackup,
      [string]$Backup = 'BACKUP')

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$esteArquivo = $MyInvocation.MyCommand.Path
$pasta = Split-Path -Parent $esteArquivo
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($GerarCodigos) {
    $lista = Join-Path $pasta 'codigos-sha256.txt'
    Get-ChildItem -LiteralPath $pasta -Filter '*.ps1' | Sort-Object Name | ForEach-Object {
        '{0}  seguranca\{1}' -f (Get-FileHash -LiteralPath $_.FullName).Hash, $_.Name
    } | Set-Content -LiteralPath $lista -Encoding ASCII
    Write-Host "  Códigos gravados em $lista. Guarde uma cópia fora do PC." -ForegroundColor Green
    exit 0
}

if (-not $admin) {
    $argumentos = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$esteArquivo`"")
    if ($Concluir) { $argumentos += '-Concluir' }
    if ($SemPausa) { $argumentos += '-SemPausa' }
    if ($SemConferir) { $argumentos += '-SemConferir' }
    if ($SemBackup) { $argumentos += '-SemBackup' }
    if ($Backup -ne 'BACKUP') { $argumentos += '-Backup', "`"$Backup`"" }
    try { $p = Start-Process powershell.exe -Verb RunAs -ArgumentList $argumentos -Wait -PassThru -ErrorAction Stop; exit $p.ExitCode }
    catch { Write-Host '  Precisa de administrador e o pedido do UAC foi recusado. Nada foi feito.' -ForegroundColor Red; exit 1 }
}

$ps = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
$pastaRel = Join-Path $env:LOCALAPPDATA 'Blindagem\relatorios'   # fora de Documentos: lá o anti-ransomware barra o PowerShell
$null = New-Item -ItemType Directory -Force -Path $pastaRel
$resumo = Join-Path $pastaRel 'ultima-manutencao.txt'
$inicio = Get-Date
$linhas = New-Object System.Collections.Generic.List[string]
$script:problemas = 0
function Passo([string]$t) { Write-Host ''; Write-Host $t -ForegroundColor Cyan; $linhas.Add(''); $linhas.Add($t) }
function Nota([string]$t, [string]$cor = 'Gray') { Write-Host "  $t" -ForegroundColor $cor; $linhas.Add("  $t") }
function Problema([string]$t) { $script:problemas++; Nota "[PROBLEMA] $t" 'Red' }
function Fim {
    $linhas.Insert(0, ('Manutenção {0} em {1:dd/MM/yyyy HH:mm} ({2:N0} min) | problemas: {3}' -f $(if ($Concluir) { 'CONCLUIR' } else { 'CONFERIR' }), $inicio, ((Get-Date) - $inicio).TotalMinutes, $script:problemas))
    $linhas | Set-Content -LiteralPath $resumo -Encoding UTF8
    Write-Host ''
    Write-Host "  Resumo salvo em $resumo" -ForegroundColor Yellow
    if (-not $SemPausa -and [Environment]::UserInteractive) { Write-Host ''; $null = Read-Host '  Aperte Enter para fechar' }
    exit $script:problemas
}

# 0. Códigos dos scripts
Passo '0. Conferindo os códigos SHA256 dos scripts'
$lista = Join-Path $pasta 'codigos-sha256.txt'
if ($SemConferir) { Nota 'pulado (-SemConferir)' 'Yellow' }
elseif (-not (Test-Path -LiteralPath $lista)) {
    Problema 'codigos-sha256.txt não encontrado; não dá para conferir os scripts'
    Nota 'Primeira vez: confira os scripts, rode "manutencao.ps1 -GerarCodigos" e guarde uma cópia da lista fora do PC.'
    Nota 'Ou rode com -SemConferir (sem essa proteção).'
    Fim
}
$conferidos = 0
if ($SemConferir) { $lista = $null }
foreach ($l in @(if ($lista) { Get-Content -LiteralPath $lista })) {
    if ($l -match '^([0-9A-Fa-f]{64})\s+seguranca\\(.+\.ps1)\s*$') {
        $arq = Join-Path $pasta $Matches[2]; $esperado = $Matches[1].ToUpper()
        if (-not (Test-Path -LiteralPath $arq)) { Problema "$($Matches[2]) não existe"; continue }
        $atual = (Get-FileHash -LiteralPath $arq).Hash
        if ($atual -eq $esperado) { $conferidos++; Nota "$($Matches[2]): bate" } else { Problema "$($Matches[2]) NÃO bate com o código guardado (pode ter sido alterado)" }
    }
}
if ($script:problemas) { Problema 'parei aqui: com um script alterado, nada do que ele disser é confiável'; Fim }
if (-not $SemConferir) { Nota "$conferidos script(s) conferido(s)" 'Green' }

if (-not $Concluir) {
    # 1. Blindagem
    Passo '1. Blindagem: simulando'
    $sim = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pasta 'blindagem.ps1') -Simular -SemPausa 2>&1 | ForEach-Object { "$_" }
    $mudar = @($sim | Where-Object { $_ -match '\[VAI MUDAR\]' })
    if ($mudar.Count -eq 0) { Nota 'tudo continua aplicado' 'Green' }
    else {
        $mudar | ForEach-Object { Nota $_.Trim() }
        Passo "1b. Blindagem: reaplicando $($mudar.Count) item(ns) (sem derrubar a internet)"
        $apl = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pasta 'blindagem.ps1') -Online -SemPausa 2>&1 | ForEach-Object { "$_" }
        $cod = $LASTEXITCODE
        $apl | Where-Object { $_ -match '\[(FEITO|ERRO)\]' } | Select-Object -Last 15 | ForEach-Object { Nota $_.Trim() $(if ($_ -match 'ERRO') { 'Red' } else { 'Green' }) }
        if ($apl -match '\[ERRO\]') { Problema 'a blindagem teve erro em algum item (veja acima)' }
        if ($cod -ne 0) { Problema "blindagem terminou com código $cod" }
    }

    # 2. Relatório de segurança
    Passo '2. Relatório de segurança (como administrador)'
    $rel = & $ps -NoProfile -NonInteractive -ExecutionPolicy Bypass -File (Join-Path $pasta 'seguranca.ps1') 2>&1 | ForEach-Object { "$_" }
    $rel | Where-Object { $_ -match '\[(PERIGO|ATENÇÃO)\]' } | Select-Object -Unique | ForEach-Object { Nota $_.Trim() $(if ($_ -match 'PERIGO') { 'Red' } else { 'Yellow' }) }
    $placar = $rel | Where-Object { $_ -match 'OK: \d+\s+ATENÇÃO: \d+\s+PERIGO: \d+' } | Select-Object -Last 1
    Nota "$placar".Trim()
    if ("$placar" -match 'PERIGO: ([1-9]\d*)') { Problema "o relatório tem $($Matches[1]) PERIGO; não conclua antes de resolver" }

    # 3. Linha de base
    Passo '3. Linha de base: o que mudou desde a foto'
    $lb = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pasta 'linha-base.ps1') -SemPausa 2>&1 | ForEach-Object { "$_" }
    $codLb = $LASTEXITCODE
    $lb | Where-Object { $_ -match '\[(NOVO|MUDOU|SUMIU)\]|antes:|agora:' } | ForEach-Object { Nota $_.Trim() }
    if ($codLb -eq 0) { Nota 'nada mudou desde a foto' 'Green' }
    else { Nota 'há novidades: confira se cada uma tem explicação (atualização, driver, programa que você instalou)' 'Yellow' }

    Passo 'Próximo passo'
    Nota 'Se não houver PERIGO e toda novidade tiver explicação: rode "manutencao.ps1 -Concluir" (foto nova, limpa os logs e faz o backup).'
    Fim
}

# ===== -Concluir =====
# 4. Foto nova
Passo '4. Foto nova da linha de base'
$foto = 'C:\ProgramData\Blindagem\linha-base.json'
if (Test-Path -LiteralPath $foto) {
    $copiaFoto = 'C:\ProgramData\Blindagem\{0:yyyy-MM-dd_HHmm}-linha-base-antiga.json' -f (Get-Date)
    Copy-Item -LiteralPath $foto -Destination $copiaFoto -Force
    Nota "cópia da foto anterior: $copiaFoto"
}
$antes = if (Test-Path -LiteralPath $foto) { (Get-Item -LiteralPath $foto).LastWriteTime } else { [datetime]::MinValue }
$null = & $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $pasta 'linha-base.ps1') -Salvar -SemPausa 2>&1
if ((Test-Path -LiteralPath $foto) -and (Get-Item -LiteralPath $foto).LastWriteTime -gt $antes) { Nota ('foto nova salva às {0:HH:mm:ss}' -f (Get-Item -LiteralPath $foto).LastWriteTime) 'Green' }
else { Problema 'a foto nova não foi salva' }

# 5. Logs
Passo '5. Apagando os nossos relatórios e as sobras de instaladores (históricos do Windows ficam)'
$apagados = 0; $bytes = 0
$alvos = @(Get-ChildItem -LiteralPath $pastaRel -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -ne $resumo })
if (Test-Path -LiteralPath 'C:\AMD') { $alvos += Get-Item -LiteralPath 'C:\AMD' }
$alvos += @(Get-ChildItem -LiteralPath $env:TEMP -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^(dd_vcredist.*|AMD.*|Docker.*install.*)\.log$' })
foreach ($a in $alvos) {
    $tam = if ($a.PSIsContainer) { (Get-ChildItem -LiteralPath $a.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum } else { $a.Length }
    Remove-Item -LiteralPath $a.FullName -Recurse -Force -ErrorAction SilentlyContinue
    if (-not (Test-Path -LiteralPath $a.FullName)) { $apagados++; $bytes += [int64]$tam } else { Nota "não consegui apagar: $($a.FullName)" 'Yellow' }
}
Nota ('{0} item(ns) apagado(s), {1:N1} MB' -f $apagados, ($bytes / 1MB)) 'Green'

# 6. Backup substituindo o anterior
if ($SemBackup) { Passo '6. Backup: pulado (-SemBackup)'; Fim }
Passo "6. Backup completo do Windows na unidade $Backup (uns minutos)"
$volB = Get-Volume | Where-Object { $_.FileSystemLabel -eq $Backup } | Select-Object -First 1
if (-not $volB) { Problema "unidade com o nome $Backup não encontrada (use -Backup <nome da unidade> ou -SemBackup)"; Fim }
$wb = "$env:SystemRoot\System32\wbadmin.exe"
$null = & $wb start backup "-backupTarget:$($volB.Path)" -allCritical -quiet 2>&1
$codWb = $LASTEXITCODE
if ($codWb -ne 0) { Problema "o backup falhou (wbadmin $codWb); as versões anteriores NÃO foram apagadas"; Fim }
Nota 'backup novo concluído' 'Green'
# Cada versão do backup é uma cópia de sombra da parte BACKUP: apaga só as antigas, fica a mais nova.
$sombras = @(Get-CimInstance Win32_ShadowCopy | Where-Object { $_.VolumeName -eq $volB.Path } | Sort-Object InstallDate)
if ($sombras.Count -gt 1) { $sombras | Select-Object -First ($sombras.Count - 1) | ForEach-Object { Remove-CimInstance -InputObject $_ -ErrorAction SilentlyContinue } }
Nota ("versões antigas apagadas: {0}" -f [Math]::Max(0, $sombras.Count - 1))
$vers = @(& $wb get versions "-backupTarget:$($volB.Path)" 2>&1 | Where-Object { "$_" -match 'Hora do backup|Backup time' } | ForEach-Object { "$_".Trim() })
$vers | ForEach-Object { Nota "guardado: $_" }
if ($vers.Count -ne 1) { Problema "esperava 1 versão guardada e encontrei $($vers.Count)" }
$volB = Get-Volume | Where-Object { $_.FileSystemLabel -eq $Backup } | Select-Object -First 1
Nota ('unidade {0}: {1:N1} de {2:N1} GB usados' -f $Backup, (($volB.Size - $volB.SizeRemaining) / 1GB), ($volB.Size / 1GB))
Fim
