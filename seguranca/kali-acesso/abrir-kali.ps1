# Abre o Kali com um clique (atalho "Kali Linux", que pede permissão de administrador):
# liga a VM se estiver desligada, abre a janela já no Kali, aperta o Enter da tela de login do xrdp ("Xorg", usuário
# e senha já preenchidos) quando ela aparece e fecha a janela sozinha quando o Kali desligar.
# Se a janela for fechada com o Kali ligado, pergunta se quer desligar o Kali também (sem senha).
# Instalação: instalar-atalho.ps1 (copia para C:\ProgramData\Blindagem\kali, que só administradores alteram, e cria o
# atalho). Máquina virtual com outro nome: -Maquina "Nome". Gravado em UTF-8 COM BOM (o PowerShell 5.1 lê os acentos
# errado sem o BOM).
param([string]$Maquina = 'Kali')
$ErrorActionPreference = 'Stop'
# só módulos do Windows (nada da pasta do usuário roda como administrador)
$env:PSModulePath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\Modules"
Import-Module Hyper-V
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
$nome = $Maquina

function Aviso([string]$texto, [string]$botoes = 'OK', [string]$icone = 'Information') {
  [System.Windows.Forms.MessageBox]::Show($texto, 'Kali Linux', $botoes, $icone, 'Button1',
    [System.Windows.Forms.MessageBoxOptions]::DefaultDesktopOnly)
}

# O xrdp do Kali só entra sozinho se o programa que conecta mandar usuário e senha, e a janela do Hyper-V não manda.
# O Hyper-V avisa quando o xrdp fica pronto (sessão aprimorada disponível = 2); a janela troca para ele e mostra o
# login já preenchido. Daí o Enter vai uma vez só, e só se a janela do Kali estiver na frente.
function XrdpPronto {
  try {
    $vmc = Get-CimInstance -Namespace root\virtualization\v2 -ClassName Msvm_ComputerSystem -Filter "ElementName='$nome'"
    return @($vmc)[0].EnhancedSessionModeState -eq 2
  } catch { return $false }
}
function NaFrente([int]$id) {
  try { return [System.Windows.Automation.AutomationElement]::FocusedElement.Current.ProcessId -eq $id } catch { return $false }
}

try {
  $vm = Get-VM -Name $nome
  switch ($vm.State) {
    'Paused' { Resume-VM -Name $nome }
    'Off'    { Start-VM -Name $nome }
    'Saved'  { Start-VM -Name $nome }
  }

  # janela do Kali já aberta: só traz para a frente
  $aberta = Get-Process vmconnect -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "$nome *" }
  if ($aberta) { [void](New-Object -ComObject WScript.Shell).AppActivate($aberta[0].Id); exit 0 }

  $janela = Start-Process "$env:SystemRoot\System32\vmconnect.exe" -ArgumentList 'localhost', $nome -PassThru
  $prontoEm, $enterFeito, $volta = $null, $false, 0
  while (-not $janela.HasExited) {
    Start-Sleep -Milliseconds 500
    if (-not $enterFeito) {
      if ($null -eq $prontoEm) {
        if (XrdpPronto) { $prontoEm = Get-Date }
      } elseif (((Get-Date) - $prontoEm).TotalSeconds -ge 5) {      # tempo da janela trocar e o login aparecer
        $enterFeito = $true
        if (NaFrente $janela.Id) { [System.Windows.Forms.SendKeys]::SendWait('{ENTER}') }
      }
    }
    if ((++$volta % 4) -ne 0) { continue }                           # o estado da VM, a cada 2 s
    if ((Get-VM -Name $nome).State -eq 'Off') {
      # o Kali foi desligado por dentro: fecha a janela
      Start-Sleep -Seconds 1
      if (-not $janela.HasExited) {
        [void]$janela.CloseMainWindow()
        if (-not $janela.WaitForExit(5000)) { $janela.Kill() }
      }
      exit 0
    }
  }

  # a janela foi fechada com o Kali ainda ligado
  if ((Get-VM -Name $nome).State -eq 'Running') {
    $r = Aviso ("Você fechou a janela, mas o Kali continua ligado (usando 8 GB de memória).`n`n" +
      "Desligar o Kali agora?`n(Salve o que estiver aberto nele antes de clicar em Sim.)") 'YesNo' 'Question'
    if ($r -eq 'Yes') { Stop-VM -Name $nome -Force }
  }
} catch {
  [void](Aviso "Não consegui abrir o Kali:`n`n$($_.Exception.Message)" 'OK' 'Error')
  exit 1
}
