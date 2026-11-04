# Segurança do Windows

Quatro scripts PowerShell que trabalham juntos. Rodam no PowerShell 5.1 que já vem no Windows 10/11, não baixam nada e
não precisam de instalação: basta a pasta.

| Script | O que faz | Muda algo? |
|---|---|---|
| [seguranca.ps1](seguranca.ps1) | **Verificar segurança**: relatório do PC (veja abaixo) | Só se você pedir, item por item |
| [blindagem.ps1](blindagem.ps1) | **Blindagem**: fecha portas, protocolos e brechas; liga proteções e registros | Sim, guardando como estava (`-Desfazer`) |
| [linha-base.ps1](linha-base.ps1) | **Linha de base**: "foto" de tudo que roda sozinho; depois mostra só o que mudou | Não |
| [manutencao.ps1](manutencao.ps1) | **Manutenção**: roda os três numa ordem só e faz o backup | Sim (backup e limpeza) |

## Como rodar

Crie um atalho para cada um (botão direito na área de trabalho > Novo > Atalho) com:

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\caminho\seguranca\seguranca.ps1" -Pausar
```

Para ver tudo e poder resolver: botão direito no atalho > **Executar como administrador**. A blindagem, a linha de base
e a manutenção pedem administrador sozinhas (janela do UAC).

Se baixou o ZIP do GitHub, desbloqueie os arquivos uma vez: `Get-ChildItem -Recurse | Unblock-File` na pasta.

## seguranca.ps1: o relatório

Primeiro só lê. Confere: firewall, antivírus (Defender), usuários, portas abertas, acesso remoto, processos,
inicialização com o Windows, conexões com a internet agora, hosts/DNS/proxy, extensões do navegador, certificados raiz,
persistência escondida (WMI), proteções do Windows, atualizações (winget), logins pela rede, inicialização profunda
(boot, login e drivers), eventos suspeitos, brechas para um programa virar administrador, configurações de assistentes de
IA e terminais (Claude Code, Codex, PowerShell) e se a blindagem continua valendo.

Cada item sai como **OK**, **ATENÇÃO** ou **PERIGO**. No fim, oferece resolver o que der, perguntando item por item;
nada muda sem você responder S. Parâmetros: `-Pausar` (espera um Enter no fim), `-Resolver` (vai direto aos itens).

## blindagem.ps1: endurecer o Windows

```
blindagem.ps1 -Simular    mostra o que mudaria, sem mudar nada (não precisa de administrador)
blindagem.ps1             aplica; desliga a rede só enquanto aplica e religa no fim
blindagem.ps1 -Online     aplica sem desligar a rede
blindagem.ps1 -Desfazer   volta tudo como era (ou só um backup: -Backup <pasta>)
```

Mexe em: rede e firewall, acesso remoto (travado desligado), portas e protocolos da rede local que vazam senha, senhas e
contas, memória entre desligamentos, reprodução automática de pendrive, scripts perigosos (.vbs/.js com dois cliques),
proteções extras do Defender e registros do Windows (para saber depois o que aconteceu no PC). Antes de mudar cada item,
guarda como estava em `C:\ProgramData\Blindagem` (só administradores alteram). Continua funcionando: internet, Docker
Desktop, WSL, VS Code, git e impressão em PDF.

## linha-base.ps1: o que mudou

```
linha-base.ps1            compara com a foto guardada (ou tira a primeira, se não houver)
linha-base.ps1 -Salvar    tira uma foto nova (faça só com o PC limpo)
linha-base.ps1 -Ver       só mostra o estado de agora
```

Foto em `C:\ProgramData\Blindagem\linha-base.json`. Tarefas agendadas, serviços, drivers, inícios automáticos, Winlogon,
WMI e pastas de inicialização: qualquer coisa nova aparece como **NOVO**, **MUDOU** ou **SUMIU**.

## manutencao.ps1: a rotina

```
manutencao.ps1                  CONFERIR: códigos dos scripts, blindagem (reaplica se algo saiu do lugar), relatório e linha de base
manutencao.ps1 -Concluir        depois de conferir: foto nova da linha de base, limpa os relatórios e faz o backup do Windows
manutencao.ps1 -GerarCodigos    grava o codigos-sha256.txt com os scripts de agora (guarde uma cópia fora do PC)
```

O passo 0 confere os códigos SHA256 dos scripts com o `codigos-sha256.txt` e **para** se algum não bater (um script
alterado não é confiável). Na primeira vez, confira os scripts e gere a lista com `-GerarCodigos`. Outras opções:
`-SemConferir`, `-SemBackup` e `-Backup <nome da unidade>` (padrão: uma unidade chamada `BACKUP`, onde o `wbadmin`
guarda o backup completo e apaga as versões antigas).

## Onde ficam as coisas

- Relatórios de cada execução: `%LOCALAPPDATA%\Blindagem\relatorios` (fora de Documentos: com o Acesso controlado a
  pastas ligado, o anti-ransomware barra o PowerShell de gravar lá).
- Backups da blindagem e a linha de base: `C:\ProgramData\Blindagem` (só administradores alteram).
- Os relatórios têm dados do PC: não vão para o git (`.gitignore`).
