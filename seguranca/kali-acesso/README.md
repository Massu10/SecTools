# Kali Linux no Hyper-V

Montar o Kali como máquina virtual do Hyper-V (para cursos e labs de cibersegurança), abrir com um clique e entrar
sem paradas, e mexer no disco dele pelo Windows quando for preciso.

## Montar o Kali (uma vez)

1. Ligue os recursos do Windows (PowerShell como administrador) e reinicie:
   ```powershell
   Enable-WindowsOptionalFeature -Online -All -FeatureName Microsoft-Hyper-V-All, VirtualMachinePlatform, Microsoft-Windows-Subsystem-Linux
   ```
   Um Linux no WSL serve para mexer no disco do Kali pelo Windows (veja `aplicar-no-kali.ps1`): `wsl --install -d Ubuntu`.
2. Baixe de `https://cdimage.kali.org/kali-<versão>/` o `kali-linux-<versão>-hyperv-amd64.7z`, o `SHA256SUMS`, o
   `SHA256SUMS.gpg` e a chave `https://archive.kali.org/archive-key.asc`.
3. Confira antes de abrir: `gpg --verify SHA256SUMS.gpg SHA256SUMS` tem de dizer **Good signature** com a chave do Kali
   (Kali Linux Archive Automatic Signing Key) e o SHA256 do `.7z` tem de ser o da lista assinada. Não confie em códigos
   copiados de páginas ou resumos: vale a lista assinada.
4. Extraia com o `tar.exe` do Windows (abre `.7z`): `tar -xf kali-...-hyperv-amd64.7z -C C:\VMs\Kali`. Leia o
   `create-vm.ps1` que vem dentro antes de rodar qualquer coisa.
5. Crie a máquina (Gerenciador do Hyper-V ou com base no `create-vm.ps1` oficial): geração 2, Secure Boot desligado,
   sessão aprimorada (`Set-VM -EnhancedSessionTransportType HvSocket`), memória **fixa** (dinâmica deixa o Linux lento no
   Hyper-V), uma placa na rede **KaliNAT** (internet) e, para os labs, outra na rede privada **Lab** (só entre VMs).
6. Rede **KaliNAT** (internet por NAT, sem depender do "Default Switch"; o Kali não alcança o Windows):
   ```powershell
   New-VMSwitch -Name KaliNAT -SwitchType Internal
   New-NetIPAddress -InterfaceAlias 'vEthernet (KaliNAT)' -IPAddress 192.168.150.1 -PrefixLength 24
   New-NetNat -Name KaliNAT -InternalIPInterfaceAddressPrefix 192.168.150.0/24
   New-VMSwitch -Name Lab -SwitchType Private          # rede dos labs, sem internet
   ```
   Desfazer: `Remove-NetNat KaliNAT; Remove-VMSwitch KaliNAT`.
7. Dentro do Kali (usuário `kali`, senha `kali`; colar no terminal com Ctrl+Shift+V):
   ```bash
   sudo nmcli con add type ethernet con-name Internet ifname "*" ethernet.mac-address <MAC da placa KaliNAT> \
     ipv4.method manual ipv4.addresses 192.168.150.10/24 ipv4.gateway 192.168.150.1 ipv4.dns "1.1.1.1 8.8.8.8" \
     ipv6.method disabled connection.autoconnect-priority 10 && sudo nmcli con up Internet && ping -c 3 kali.org
   passwd                                          # troque a senha padrão
   sudo apt update && sudo apt full-upgrade -y
   ```
   O MAC da placa aparece em Configurações da máquina > placa de rede > Recursos avançados (deixe o MAC estático).
8. Crie um ponto de restauração ("Kali limpo") depois de atualizar.

## Abrir com um clique: `instalar-atalho.ps1`

```powershell
.\instalar-atalho.ps1                    # máquina "Kali"; outra: -Maquina "Nome" -Nome "Nome do atalho"
```

Copia o [abrir-kali.ps1](abrir-kali.ps1) e o ícone para `C:\ProgramData\Blindagem\kali` (só administradores alteram,
porque o atalho roda como administrador) e cria o atalho **Kali Linux** no menu Iniciar, marcado para pedir
administrador. Com o Acesso controlado a pastas (anti-ransomware) ligado, nenhum script grava na Área de Trabalho: o
atalho fica pronto numa pasta que abre sozinha, e é só arrastar.

O atalho liga a máquina, abre a janela direto nela (sem a tela de escolher a máquina) e fecha a janela quando o Kali
desliga; se você fechar a janela com ele ligado, pergunta se desliga. Também aperta sozinho o **Enter** da tela de login
do xrdp (veja abaixo). O único clique que sobra é o "Sim" do administrador: tirar esse pedido (tarefa agendada ou o grupo
"Administradores do Hyper-V") daria a qualquer programa um jeito de virar administrador sem pedir.

## Mudar o Kali pelo Windows: `aplicar-no-kali.ps1`

```powershell
.\aplicar-no-kali.ps1 -Script .\aplicar-boot-rapido.sh
.\aplicar-no-kali.ps1 -Script .\aplicar-sair-facil.sh
.\aplicar-no-kali.ps1 -Script ..\kali-visual\aplicar-autologin.sh
.\aplicar-no-kali.ps1 -Script .\aplicar-boot-rapido.sh -Simular      # só mostra o que faria
```

Pede administrador, desliga o Kali (pergunta antes, se estiver ligado), monta o disco atual no Linux do WSL
(`wsl --mount --bare`), roda o script como root, solta o disco e liga o Kali de novo se ele estava ligado. Opções:
`-Maquina`, `-Usuario` (o usuário do Kali; chega aos scripts como `USUARIO_KALI`), `-Distro` (o Linux do WSL),
`-Pasta` (arquivos que o script usa), `-SemPerguntar`. Registro em `%LOCALAPPDATA%\Blindagem\relatorios`.

Os scripts `aplicar-*.sh` também rodam direto num Linux com o disco do Kali conectado: `sudo bash aplicar-x.sh`.

| Script | O que muda no Kali |
|---|---|
| [aplicar-boot-rapido.sh](aplicar-boot-rapido.sh) | O GRUB entra direto (1 s com o menu escondido; Esc abre o menu). Depois de um boot que falhou, o menu aparece por 30 s |
| [aplicar-sair-facil.sh](aplicar-sair-facil.sh) | Só o seu usuário desliga e reinicia sem senha (regra do polkit [49-kali-desligar-sem-senha.rules](49-kali-desligar-sem-senha.rules)); sudo e root continuam pedindo |
| [../kali-visual/aplicar-autologin.sh](../kali-visual/aplicar-autologin.sh) | Login do xrdp já preenchido para o seu usuário, xrdp escutando só pelo Hyper-V (vsock, nunca pela rede), XFCE sem efeitos pesados |

Cada script guarda uma cópia dos arquivos que muda (`.antes`, `.antes-rapido`...).

## Por que ainda aparece a tela do xrdp ("Xorg")

O xrdp só pula a tela de login quando o programa que conecta manda usuário e senha, e a janela do Hyper-V não manda.
Com o `aplicar-autologin.sh` a tela já vem preenchida, e o `abrir-kali.ps1` espera o Hyper-V avisar que o xrdp está
pronto (`Msvm_ComputerSystem.EnhancedSessionModeState` = 2), mais 5 s, e aperta o Enter uma vez, só se a janela do
Kali estiver na frente (nunca manda tecla para outro programa).

## Tela cheia

No arquivo `%APPDATA%\Microsoft\Windows\Hyper-V\Client\1.0\vmconnect.rdp.<ID da máquina>.config`: `FullScreen` = `True`
e `DesktopSize` = a resolução do monitor, com a janela do Kali fechada. Na hora: **Ctrl+Alt+Break**.
