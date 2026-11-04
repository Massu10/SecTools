<#
Aplica um script (aplicar-*.sh) no disco do Kali sem precisar entrar nele: desliga a maquina virtual (pergunta antes,
se ela estiver ligada), monta o disco no Linux do WSL, roda o script como root, solta o disco e liga o Kali de novo
se ele estava ligado. Pede administrador sozinho. Registro em %LOCALAPPDATA%\Blindagem\relatorios.

Uso (PowerShell, na pasta deste arquivo):
  .\aplicar-no-kali.ps1 -Script .\aplicar-boot-rapido.sh
  .\aplicar-no-kali.ps1 -Script .\aplicar-sair-facil.sh
  .\aplicar-no-kali.ps1 -Script ..\kali-visual\aplicar-mascara.sh -Pasta <pasta com os arquivos do tema>
Opcoes:
  -Maquina Kali    nome da maquina virtual no Hyper-V
  -Usuario kali    usuario do Kali (chega aos scripts como USUARIO_KALI)
  -Distro Ubuntu   o Linux do WSL que monta o disco (padrao: o principal do WSL)
  -SemPerguntar    desliga o Kali sem perguntar
  -Simular         so mostra o que faria (nao pede administrador)
Precisa: Windows com Hyper-V e WSL 2 com um Linux (ex.: wsl --install -d Ubuntu).
O disco certo e o atual da maquina (com pontos de restauracao, e o .avhdx mais novo; nunca o .vhdx base).
#>
param(
    [Parameter(Mandatory = $true)][string]$Script,
    [string]$Pasta,
    [string]$Maquina = 'Kali',
    [string]$Usuario = 'kali',
    [string]$Distro,
    [switch]$SemPerguntar,
    [switch]$Simular
)
$ErrorActionPreference = 'Stop'
$Script = (Resolve-Path -LiteralPath $Script).Path
if ($Pasta) { $Pasta = (Resolve-Path -LiteralPath $Pasta).Path }
if ($Usuario -notmatch '^[a-z_][a-z0-9_-]*$') { throw "nome de usuario do Kali estranho: $Usuario" }
$wsl = Join-Path $env:SystemRoot 'System32\wsl.exe'
$noWsl = @(); if ($Distro) { $noWsl = @('-d', $Distro) }
$rel = Join-Path $env:LOCALAPPDATA 'Blindagem\relatorios'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

function CaminhoWsl([string]$caminho) {
    # wslpath sem passar pelo shell do Linux (-e), para as barras invertidas chegarem inteiras
    $r = & $wsl @noWsl -e wslpath -a $caminho
    if ($LASTEXITCODE -ne 0 -or -not $r) { throw "o WSL nao converteu o caminho $caminho (o WSL esta instalado?)" }
    return "$r".Trim()
}
# texto entre aspas simples para o bash (o PowerShell 5.1 estraga aspas duplas dentro de argumentos)
function Aspas([string]$s) { "'" + ($s -replace "'", "'\''") + "'" }

if ($Simular) {
    "script:  $Script  ->  $(CaminhoWsl $Script)"
    if ($Pasta) { "pasta:   $Pasta  ->  $(CaminhoWsl $Pasta)" }
    "maquina: $Maquina | usuario do Kali: $Usuario | WSL: $(if ($Distro) { $Distro } else { 'o principal' })"
    'faria: desligar a maquina (perguntando, se ligada), montar o disco atual no WSL, rodar o script como root,'
    '       soltar o disco e ligar de novo se ela estava ligada'
    exit 0
}

if (-not $admin) {
    # roda de novo como administrador, com os mesmos parametros, e mostra o registro no fim
    $p = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-Script', "`"$Script`"",
        '-Maquina', "`"$Maquina`"", '-Usuario', $Usuario)
    if ($Pasta) { $p += '-Pasta', "`"$Pasta`"" }
    if ($Distro) { $p += '-Distro', "`"$Distro`"" }
    if ($SemPerguntar) { $p += '-SemPerguntar' }
    $inicio = Get-Date
    try { $proc = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -ArgumentList $p }
    catch { throw "precisa de administrador e o pedido foi recusado ($($_.Exception.Message))" }
    $ultimo = Get-ChildItem $rel -Filter 'aplicar-no-kali-*.txt' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $inicio.AddSeconds(-5) -and $_.Name -notlike '*-kali.txt' } |
        Sort-Object LastWriteTime | Select-Object -Last 1
    if ($ultimo) {
        Get-Content $ultimo.FullName -Encoding UTF8 | Where-Object { $_ -notmatch '^\*{10}|^(Hora|In.cio|Fim|Nome|Executar|Computador|Aplicativo|ID do|PS|Build|CLR|WSMan|Serial)' }
        $kali = $ultimo.FullName -replace '\.txt$', '-kali.txt'
        if (Test-Path $kali) { '--- no Kali:'; Get-Content $kali -Encoding UTF8 }
    }
    exit $proc.ExitCode
}

$null = New-Item -ItemType Directory -Force -Path $rel
$base = Join-Path $rel ('aplicar-no-kali-{0}-{1:yyyy-MM-dd_HHmmss}' -f [IO.Path]::GetFileNameWithoutExtension($Script), (Get-Date))
Start-Transcript -Path "$base.txt" -Force | Out-Null
$codigo = 1
try {
    $env:PSModulePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
    Import-Module Hyper-V
    $scriptWsl = CaminhoWsl $Script
    $pastaWsl = if ($Pasta) { CaminhoWsl $Pasta } else { '' }
    $logWsl = CaminhoWsl "$base-kali.txt"
    $estava = "$((Get-VM -Name $Maquina).State)"
    "maquina $Maquina estava: $estava"
    if ($estava -in 'Saved', 'Paused') { throw "a maquina esta $estava; ligue e desligue normalmente antes" }
    if ($estava -ne 'Off') {
        if (-not $SemPerguntar) {
            $r = Read-Host "O $Maquina esta ligado. Desligar agora? Os programas abertos nele fecham. (s/N)"
            if ($r -notmatch '^[sS]') { throw 'cancelado: o Kali continua ligado' }
        }
        'desligando (como pelo menu; os programas abertos tem ate 5 minutos para fechar)'
        Stop-VM -Name $Maquina -Force
    }
    $t = 0
    while ("$((Get-VM -Name $Maquina).State)" -ne 'Off' -and $t -lt 300) { Start-Sleep -Seconds 2; $t += 2 }
    if ("$((Get-VM -Name $Maquina).State)" -ne 'Off') { throw 'a maquina nao desligou' }
    $disco = @(Get-VMHardDiskDrive -VMName $Maquina | Where-Object { $_.Path } | ForEach-Object { $_.Path })[0]
    if (-not $disco) { throw "a maquina $Maquina nao tem disco" }
    "disco atual: $disco"
    if ((Get-VHD -Path $disco).Attached) { throw 'o disco ja esta conectado em outro lugar (wsl --shutdown resolve, se for o WSL)' }
    & $wsl --mount --vhd $disco --bare
    if ($LASTEXITCODE -ne 0) { throw "wsl --mount falhou (codigo $LASTEXITCODE)" }
    try {
        $comando = "USUARIO_KALI=$(Aspas $Usuario) bash $(Aspas $scriptWsl)"
        if ($pastaWsl) { $comando += ' ' + (Aspas $pastaWsl) }
        & $wsl @noWsl -u root -e bash -c "$comando > $(Aspas $logWsl) 2>&1"
        $codigo = $LASTEXITCODE
        "script terminou com codigo $codigo"
    } finally {
        & $wsl --unmount $disco
        if ($LASTEXITCODE -ne 0 -or (Get-VHD -Path $disco).Attached) {
            'o wsl --unmount nao soltou o disco: wsl --shutdown'
            & $wsl --shutdown
            Start-Sleep -Seconds 3
        }
        "disco ainda conectado: $((Get-VHD -Path $disco).Attached)"
    }
    if ($codigo -ne 0) { throw "o script deu erro (codigo $codigo); veja $base-kali.txt" }
    if ($estava -eq 'Running' -and -not (Get-VHD -Path $disco).Attached) {
        $abrir = 'C:\ProgramData\Blindagem\kali\abrir-kali.ps1'
        if (Test-Path $abrir) {
            'abrindo o Kali de novo'
            Start-Process powershell.exe -ArgumentList '-NoProfile', '-WindowStyle', 'Hidden', '-ExecutionPolicy', 'Bypass', '-File', "`"$abrir`"", '-Maquina', "`"$Maquina`""
        } else {
            'ligando o Kali de novo'
            Start-VM -Name $Maquina
        }
    }
    'PRONTO'
} catch {
    "ERRO: $($_.Exception.Message)"
    $codigo = 1
} finally {
    Stop-Transcript | Out-Null
}
exit $codigo
