# Recuperar celular Xiaomi, Redmi ou POCO

Reinstala a ROM oficial pelo modo MIAssistant do recovery, com o bootloader bloqueado, e apaga os vírus.

Serve para os celulares Xiaomi, Redmi e POCO cujo recovery tem a opção **Connect with MIAssistant**. Testado no
Redmi 15 4G / POCO M7 (`creek`), Redmi 12 (`fire`), Redmi 12 5G / POCO M6 Pro 5G (`sky`) e Redmi Note 12 4G (`tapas`;
`topaz` é o com NFC); os outros modelos usam o mesmo caminho. O script lê o codinome do aparelho, o servidor da Xiaomi
manda a ROM certa para ele e o recovery ainda confere a ROM antes de instalar.

Funciona em qualquer PC com Windows e o [Python](https://www.python.org/downloads/) 3.9 ou mais novo (marque "Add
python.exe to PATH" ao instalar): basta copiar esta pasta. Na primeira vez o `RECUPERAR.cmd` cria o `.venv` e instala o
miasst 1.4.4. As ROMs (cerca de 5 GB cada) ficam na pasta `rom` e não vão para o git.

## Antes de começar

- Bateria acima de 50%.
- Tenha a senha da conta Google que está no celular (e da Mi Account, se houver): depois de apagar tudo, o celular pede
  essa conta para liberar o uso (proteção contra roubo).
- Fotos e arquivos que não estão na nuvem serão perdidos.
- Feche o Mi PC Suite / Mi Assistant, se estiverem abertos.
- Internet boa: a ROM tem cerca de 5 GB.

## Passo a passo

1. No celular: desligue, segure **Power + Volume para cima** até abrir o menu do recovery e escolha
   **Connect with MIAssistant**. Ligue o cabo USB no PC.
2. No PC: dois cliques em **RECUPERAR.cmd**.
3. Escolha **1** para conferir se o celular aparece e qual modelo o script reconheceu. Conecte um celular por vez. As
   ROMs baixadas ficam juntas na pasta `rom`; na hora de instalar, o script usa a do modelo conectado.
4. Escolha **7** (passo a passo completo): baixa a ROM oficial, apaga tudo, instala e reinicia. Ou faça um por um:
   3 (baixar), 5 (apagar), 4 (instalar), 6 (reiniciar). Os passos que apagam ou instalam pedem para você digitar
   INSTALAR ou APAGAR.

Pela linha de comando: `RECUPERAR.cmd info | roms | baixar | instalar [arquivo.zip] | apagar | reiniciar`.

## Se der "falta o driver USB"

O script abre o Gerenciador de Dispositivos e mostra o que fazer: instalar o driver **WinUsb Device** no celular (ou
usar o programa [Zadig](https://zadig.akeo.ie)). É uma vez só.

## Se a instalação falhar ou o celular reiniciar no meio

- Não é o vírus: no modo recovery o Android e os apps não rodam.
- `Installation_aborted`: o celular recebeu e conferiu a ROM, mas recusou instalar, sem gravar nada. O motivo mais comum
  é a ROM não ser mais nova que a versão do celular: o recovery só instala versão mais nova. O script avisa isso antes
  de enviar. Para tirar o vírus não precisa reinstalar: opção 5 e depois opção 6.
- Não dá para instalar uma ROM mais antiga com o bootloader bloqueado: a Xiaomi só aprova a mesma versão ou uma mais nova.
- Apague tudo (opção 5) e tente instalar de novo (opção 4), com bateria acima de 50%, o cabo original e uma porta USB
  direto no PC.
- O registro da tentativa fica em `instalacao.log` (só números técnicos, sem dados pessoais).

## O que o script faz (e o que não faz)

- Usa o mesmo protocolo do programa oficial da Xiaomi (MIAssistant), pela ferramenta
  [miasst 1.4.4](https://github.com/MiForge/MiAssistantTool) (Apache-2.0).
- Só instala ROM oficial que o servidor da Xiaomi aprova para **este** aparelho.
- Não desbloqueia o bootloader e não contorna a conta Google nem a Mi Account.
- Deixa de fora as opções perigosas do miasst (por exemplo, "Wipe EFS" apaga o IMEI).

## Depois que o celular ligar

- Configure como celular novo; não restaure apps de backup (o vírus volta junto).
- Instale apps só pela Play Store.
- De outro aparelho, troque as senhas usadas no celular infectado (Google, banco, redes sociais) e ative a verificação
  em duas etapas.

## Sem PC

Só restaurar de fábrica já remove quase todo vírus: recovery (Power + Volume para cima) > Wipe Data > Wipe All Data >
confirmar.
