<#
Instala no Kali o tema "Máscara verde": terminal verde do usuário e do root, desenho da máscara ao abrir o terminal,
chuva de código em todo resultado (comando chuva), cores original/verde e os dois papéis de parede.
Monta a pasta de arquivos em %LOCALAPPDATA%\Blindagem\kali-mascara (artes do terminal pelo Python, se houver; papéis
de parede pelo Edge ou pelo Chrome sem janela) e chama o ..\kali-acesso\aplicar-no-kali.ps1, que pede administrador,
desliga o Kali (pergunta antes) e aplica com o disco montado no WSL. Reaplicar volta tudo ao verde.

Uso (PowerShell, na pasta deste arquivo):  .\instalar-tema.ps1  [-Maquina Kali] [-Usuario kali] [-SemPapel] [-Simular]
#>
param(
    [string]$Maquina = 'Kali',
    [string]$Usuario = 'kali',
    [switch]$SemPapel,
    [switch]$Simular
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$pasta = Join-Path $env:LOCALAPPDATA 'Blindagem\kali-mascara'
$null = New-Item -ItemType Directory -Force -Path $pasta

# 1. arquivos do tema
foreach ($f in 'Mascara.colorscheme', 'MascaraRoot.colorscheme', 'mascara.zsh', 'matrix', 'aplicar-mascara.sh') {
    Copy-Item (Join-Path $aqui $f) $pasta -Force
}

# 2. artes do terminal (.ans): geradas do mascara-mapa.txt pelo Python; sem Python, as que vêm no repositório
$python = Get-Command python.exe, py.exe -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*WindowsApps*' } | Select-Object -First 1
if ($python) {
    & $python.Source -I (Join-Path $aqui 'gerar-arte-terminal.py') $pasta | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'o gerar-arte-terminal.py deu erro' }
    Remove-Item (Join-Path $pasta 'previa-arte.html') -ErrorAction SilentlyContinue
    'artes do terminal geradas'
} else {
    Copy-Item (Join-Path $aqui 'mascara-*.ans') $pasta -Force
    'artes do terminal: as do repositório (sem Python)'
}

# 3. papéis de parede (1920x1080): verde e o mesmo desenho nas cores originais do Kali
if (-not $SemPapel) {
    $navegador = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe", "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe", "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($navegador) {
        $url = 'file:///' + ((Join-Path $aqui 'papel-mascara.html') -replace '\\', '/' -replace ' ', '%20')
        $perfil = Join-Path $env:TEMP "papel-mascara-$PID"
        foreach ($v in @(@('verde', ''), @('original', '#original'))) {
            $png = Join-Path $pasta "kali-mascara-$($v[0]).png"
            Remove-Item $png -ErrorAction SilentlyContinue
            $p = Start-Process $navegador -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
                '--headless=new', '--disable-gpu', '--hide-scrollbars', '--force-device-scale-factor=1',
                '--window-size=1920,1080', "--user-data-dir=`"$perfil`"", "--screenshot=`"$png`"", "`"$url$($v[1])`"")
            if (Test-Path $png) { "papel de parede $($v[0]): ok" } else { "AVISO: o papel $($v[0]) não saiu (código $($p.ExitCode))" }
        }
        Remove-Item $perfil -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        'AVISO: sem Edge nem Chrome; os papéis de parede ficam como estão'
    }
} else {
    Remove-Item (Join-Path $pasta 'kali-mascara-*.png') -ErrorAction SilentlyContinue
    'papéis de parede: ficam como estão (-SemPapel)'
}

# 4. aplica no Kali
$aplicar = Join-Path $aqui '..\kali-acesso\aplicar-no-kali.ps1'
$parametros = @{ Script = (Join-Path $pasta 'aplicar-mascara.sh'); Pasta = $pasta; Maquina = $Maquina; Usuario = $Usuario }
if ($Simular) { $parametros.Simular = $true }
& $aplicar @parametros
