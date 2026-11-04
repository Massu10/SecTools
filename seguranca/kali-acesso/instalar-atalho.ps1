<#
Instala o "Kali Linux" de um clique: copia o abrir-kali.ps1 e o ícone da máscara para C:\ProgramData\Blindagem\kali
(só administradores alteram essa pasta, porque o atalho roda como administrador) e cria o atalho no menu Iniciar,
marcado para pedir administrador. O atalho liga a máquina, abre a janela direto nela, aperta o Enter do login do
xrdp e fecha a janela quando a máquina desliga.

Uso (PowerShell, na pasta deste arquivo):  .\instalar-atalho.ps1  [-Maquina Kali] [-Nome "Kali Linux"]
Pede administrador uma vez (para a pasta do ProgramData). Se o Acesso controlado a pastas (anti-ransomware) estiver
ligado, ele não deixa script nenhum gravar na Área de Trabalho: o atalho fica pronto numa pasta e é só arrastar.
#>
param(
    [string]$Maquina = 'Kali',
    [string]$Nome = 'Kali Linux',
    [switch]$SoCopiar          # interno: a parte que roda como administrador
)
$ErrorActionPreference = 'Stop'
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$destino = 'C:\ProgramData\Blindagem\kali'
$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

function Copiar {
    if (-not (Test-Path $destino)) {
        $null = New-Item -ItemType Directory -Force -Path $destino
        # administradores e o sistema alteram; os usuários só leem e executam (SIDs: vale em qualquer idioma)
        & icacls.exe $destino /inheritance:r /grant:r '*S-1-5-32-544:(OI)(CI)F' '*S-1-5-18:(OI)(CI)F' '*S-1-5-32-545:(OI)(CI)RX' | Out-Null
    }
    $arq = Join-Path $destino 'abrir-kali.ps1'
    if ((Test-Path $arq) -and -not (Test-Path "$arq.antes")) { Copy-Item $arq "$arq.antes" }
    # UTF-8 com BOM e CRLF: o PowerShell 5.1 lê os acentos errado sem o BOM
    $texto = [IO.File]::ReadAllText((Join-Path $aqui 'abrir-kali.ps1'), [Text.Encoding]::UTF8).TrimStart([char]0xFEFF)
    [IO.File]::WriteAllText($arq, $texto.Replace("`r`n", "`n").Replace("`n", "`r`n"), (New-Object Text.UTF8Encoding $true))
    $icone = Join-Path $aqui '..\kali-visual\kali-mascara.ico'
    if (Test-Path $icone) { Copy-Item $icone (Join-Path $destino 'kali-mascara.ico') -Force }
    "copiado para $destino"
}

if ($SoCopiar) { Copiar; exit 0 }

if ($admin) { Copiar }
else {
    'pedindo administrador para copiar para C:\ProgramData\Blindagem\kali...'
    try {
        $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"", '-SoCopiar')
    } catch { throw "precisa de administrador e o pedido foi recusado ($($_.Exception.Message))" }
    if ($p.ExitCode -ne 0 -or -not (Test-Path (Join-Path $destino 'abrir-kali.ps1'))) { throw 'a cópia como administrador não deu certo' }
}

# atalho no menu Iniciar do usuário, marcado para pedir administrador
$sh = New-Object -ComObject WScript.Shell
$lnk = Join-Path ([Environment]::GetFolderPath('Programs')) "$Nome.lnk"
$l = $sh.CreateShortcut($lnk)
$l.TargetPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$l.Arguments = "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$destino\abrir-kali.ps1`" -Maquina `"$Maquina`""
$l.WorkingDirectory = $destino
$l.Description = "Abre o $Maquina (liga, entra direto e faz o login sozinho)"
if (Test-Path (Join-Path $destino 'kali-mascara.ico')) { $l.IconLocation = "$destino\kali-mascara.ico,0" }
$l.Save()
$b = [IO.File]::ReadAllBytes($lnk)
$b[0x15] = $b[0x15] -bor 0x20          # LinkFlags RunAsUser: "executar como administrador"
[IO.File]::WriteAllBytes($lnk, $b)
"atalho no menu Iniciar: $lnk"

# área de trabalho: direto, ou pronto numa pasta se o anti-ransomware estiver protegendo a Área de Trabalho
$cfa = 1
try { $cfa = [int](Get-MpPreference).EnableControlledFolderAccess } catch { }
$mesa = [Environment]::GetFolderPath('Desktop')
if ($cfa -eq 0) {
    Copy-Item $lnk (Join-Path $mesa "$Nome.lnk") -Force
    "atalho na área de trabalho: $mesa\$Nome.lnk"
} else {
    $pronto = Join-Path $env:LOCALAPPDATA 'Blindagem\atalhos'
    $null = New-Item -ItemType Directory -Force -Path $pronto
    Copy-Item $lnk (Join-Path $pronto "$Nome.lnk") -Force
    "O Acesso controlado a pastas não deixa scripts gravarem na Área de Trabalho."
    "Arraste o atalho da pasta que vai abrir para a área de trabalho (se já houver um, escolha Substituir)."
    Start-Process explorer.exe -ArgumentList "/select,`"$pronto\$Nome.lnk`""
}
& (Join-Path $env:SystemRoot 'System32\ie4uinit.exe') -show
