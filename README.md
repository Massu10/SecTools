# Ferramentas de segurança

Ferramentas para proteger e conferir o Windows, montar um laboratório Kali Linux no Hyper-V para estudar
cibersegurança e recuperar celulares Xiaomi infectados. Tudo em português, comentado, sem programas de terceiros
escondidos: scripts PowerShell, bash e Python que dá para ler antes de rodar.

| Pasta | O que é |
|---|---|
| [seguranca/](seguranca/) | **Windows**: relatório de segurança, blindagem (com desfazer), linha de base do que roda sozinho e rotina de manutenção |
| [seguranca/kali-acesso/](seguranca/kali-acesso/) | **Kali no Hyper-V**: como montar, abrir com um clique, entrar sem paradas e mudar o Kali pelo Windows |
| [seguranca/kali-visual/](seguranca/kali-visual/) | **Tema "Máscara verde"** para o terminal do Kali: chuva de código nos resultados, cores originais na hora, papéis de parede |
| [labs/](labs/) | **Labs** de John the Ripper, Hashcat, Hydra e Metasploit num laboratório isolado |
| [recuperar-redmi/](recuperar-redmi/) | **Celular**: reinstala a ROM oficial de Xiaomi/Redmi/POCO pelo modo MIAssistant e apaga os vírus |

Cada pasta tem o seu README com o passo a passo.

## Começo rápido

1. Baixe: `git clone <endereço deste repositório>` ou **Code > Download ZIP**. Se baixou o ZIP, desbloqueie os arquivos
   uma vez (PowerShell, dentro da pasta): `Get-ChildItem -Recurse | Unblock-File`.
2. Relatório de segurança do Windows (só lê; pergunta antes de mudar qualquer coisa):
   ```
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\seguranca\seguranca.ps1 -Pausar
   ```
3. Kali: monte a máquina como em [seguranca/kali-acesso/](seguranca/kali-acesso/) e depois:
   ```
   .\seguranca\kali-acesso\instalar-atalho.ps1      # "Kali Linux" de um clique
   .\seguranca\kali-visual\instalar-tema.ps1        # tema, chuva de código e cores
   ```

## Requisitos

- Windows 10 ou 11 com o PowerShell 5.1 (já vem). Os scripts pedem administrador sozinhos quando precisam.
- Para o Kali: Hyper-V e WSL 2 com um Linux (`wsl --install -d Ubuntu`). Os nomes padrão são a máquina `Kali` e o usuário
  `kali`; para outros, `-Maquina` e `-Usuario`.
- Python 3.9 ou mais novo para o recuperador de celular (e, opcional, para gerar as artes do tema).
- Edge ou Chrome para gerar os papéis de parede do tema (todo Windows tem o Edge).

## Onde as ferramentas guardam coisas

- `%LOCALAPPDATA%\Blindagem\relatorios`: relatórios e registros de cada execução (têm dados do PC; não vão para o git).
- `C:\ProgramData\Blindagem`: backups da blindagem, linha de base e o lançador do Kali (só administradores alteram).

## Uso responsável

Os labs e as ferramentas de teste de invasão são para o **seu** laboratório: hashes que você mesmo gerou e alvos que
você mesmo montou, numa rede isolada. Usar essas técnicas em sistemas de terceiros sem autorização por escrito é crime
(no Brasil, art. 154-A do Código Penal). Em curso, CTF ou pentest, guarde o escopo por escrito antes de qualquer teste.
O recuperador de celular só instala ROM oficial aprovada pela Xiaomi e não contorna bloqueios de conta.
