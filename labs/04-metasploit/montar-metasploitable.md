# Montar a Metasploitable 2 no Hyper-V (rede privada Lab)

A **Metasploitable 2** é uma VM Linux **propositalmente vulnerável**, feita pela Rapid7
justamente para treinar exploração. É o alvo padrão de curso. Como ela é cheia de
buracos, a regra é só uma: **ela nunca toca a internet** — fica presa na rede privada
**Lab** do Hyper-V, isolada (como montar: [../../seguranca/kali-acesso/README.md](../../seguranca/kali-acesso/README.md)).

> Ela vem como imagem **VMware (.vmdk)**. No Hyper-V a gente converte para **.vhdx** e cria
> uma VM **Geração 1** (é um Linux antigo, BIOS).

## 1. Baixar

- Página oficial (Rapid7): procure por **"Metasploitable 2 download"** → repositório no
  SourceForge (`metasploitable`). Baixe o `metasploitable-linux-2.0.0.zip`.
- Confira o SHA/assinatura como você faz com tudo. Descompacte num lugar fora dos
  Documentos (ex. `C:\VMs\Metasploitable`). Dentro vem `Metasploitable.vmdk`.

## 2. Converter .vmdk → .vhdx

Pelo `qemu-img` (dentro do Kali, com `qemu-utils` instalado — ou a versão Windows):
```bash
qemu-img convert -f vmdk -O vhdx Metasploitable.vmdk Metasploitable.vhdx
```
Alternativa com janela, no Windows: **StarWind V2V Converter** (grátis) converte
VMDK→VHDX apontando e clicando. Ponha o `.vhdx` final em `C:\VMs\Metasploitable`.

## 3. Criar a VM (PowerShell como administrador)

```powershell
New-VM -Name Metasploitable -Generation 1 -MemoryStartupBytes 1GB `
  -VHDPath 'C:\VMs\Metasploitable\Metasploitable.vhdx' -SwitchName Lab
Set-VM -Name Metasploitable -ProcessorCount 2 -AutomaticCheckpointsEnabled $false
```
- **Geração 1** (BIOS). **Só a placa na rede `Lab`** — nenhuma placa na KaliNAT/internet.
- Se o switch `Lab` ainda não existe: `New-VMSwitch -Name Lab -SwitchType Private`.

```powershell
Start-VM Metasploitable
vmconnect localhost Metasploitable
```

## 4. IP fixo nos dois lados (a rede Lab não tem DHCP)

Switch **privado** não entrega IP. Defina na mão.

No **Kali** (placa Lab):
```bash
sudo nmcli con add type ethernet con-name Lab ifname <placa-lab> \
  ipv4.method manual ipv4.addresses 10.10.10.10/24
sudo nmcli con up Lab
```
(descubra `<placa-lab>` com `ip link`; costuma ser `eth1` — a segunda placa.)

Na **Metasploitable** (login `msfadmin` / `msfadmin`):
```bash
sudo ifconfig eth0 10.10.10.20 netmask 255.255.255.0
```
Para fixar entre reinícios, edite `/etc/network/interfaces` (`iface eth0 inet static`,
`address 10.10.10.20`, `netmask 255.255.255.0`).

## 5. Conferir o isolamento

Do Kali:
```bash
ping -c 2 10.10.10.20        # deve responder
```
Da Metasploitable:
```bash
ping -c 2 8.8.8.8            # deve FALHAR — é o isolamento certo
```
Se o alvo não alcança a internet e alcança o Kali, está perfeito. Tire um **ponto de
verificação** no Hyper-V ("Metasploitable limpa") para voltar fácil depois de bagunçar.

Pronto — volte para o [README do Lab 4](README.md).
