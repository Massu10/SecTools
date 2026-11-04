"""Recupera celulares Xiaomi, Redmi e POCO pelo modo MIAssistant do recovery (testado no Redmi 15 4G,
Redmi 12 e Redmi Note 12 globais; os outros modelos com esse modo usam o mesmo caminho).

Usa o miasst 1.4.4 (github.com/MiForge/MiAssistantTool, licença Apache-2.0), que fala
o mesmo protocolo do programa oficial da Xiaomi: o servidor da Xiaomi aprova a ROM para
este aparelho e o recovery confere essa aprovação antes de instalar. Funciona com o
bootloader bloqueado e só instala ROM oficial aceita pelo aparelho.

Uso: RECUPERAR.cmd             (menu)
     RECUPERAR.cmd info | roms | baixar | instalar [arquivo.zip] | apagar | reiniciar
"""

from __future__ import annotations

import hashlib
import os
import re
import subprocess
import sys
import time
import zipfile
from functools import cache
from pathlib import Path

import requests
import usb.core
from miassistant import core, deps

PASTA_ROM = Path(__file__).resolve().parent / "rom"
LOG_INSTALACAO = PASTA_ROM.parent / "instalacao.log"
# Nomes de alguns modelos, pelo codinome, só para mostrar. Qualquer Xiaomi/Redmi/POCO com o modo MIAssistant é
# aceito: o servidor da Xiaomi escolhe a ROM certa de cada aparelho e o recovery confere antes de instalar.
APARELHOS = {
    "creek": "Redmi 15 4G / POCO M7",
    "fire": "Redmi 12",
    "sky": "Redmi 12 5G / POCO M6 Pro 5G",
    "tapas": "Redmi Note 12 4G",
    "topaz": "Redmi Note 12 4G NFC",
}
INTERFACE_MIASSISTANT = (
    0xFF,
    0x42,
    0x01,
)  # interface ADB que o recovery abre nesse modo
ESPERA_CELULAR_S = 300

COMO_ENTRAR = """\
Coloque o celular no modo MIAssistant:
  1. Desligue o celular (se travar, segure o botão Power por uns 15 segundos).
  2. Segure Power + Volume para cima até abrir o menu do recovery.
  3. Escolha "Connect with MIAssistant" (o volume move, o Power confirma).
  4. Ligue o cabo USB no PC (de preferência o cabo original, numa porta direto no PC).
Deixe só este celular conectado e feche o Mi PC Suite / Mi Assistant, se estiver aberto."""

DRIVER = """\
Falta o driver USB "WinUSB" para o celular nesse modo. Para instalar (uma vez só):
  1. Vou abrir o Gerenciador de Dispositivos.
  2. Ache o celular: costuma aparecer com triângulo amarelo em "Outros dispositivos",
     ou como "ADB Interface"/"Android" (some e volta quando você tira e põe o cabo).
  3. Botão direito > Atualizar driver > Procurar drivers no meu computador >
     Permitir que eu escolha em uma lista de drivers disponíveis.
  4. Categoria "Universal Serial Bus devices" (Dispositivos de barramento serial universal) >
     fabricante "WinUsb Device" > modelo "WinUsb Device" (ou "ADB Device") > Avançar > Sim.
  5. Rode a opção de novo.
Alternativa: o programa Zadig (https://zadig.akeo.ie): Options > List All Devices,
escolha o celular, selecione WinUSB e clique em Install Driver / Replace Driver."""

AVISO_APAGAR = """\
Isto apaga TUDO do celular: apps (inclusive os vírus), fotos, conversas, contas e arquivos.
Antes de continuar:
  - tenha a senha da conta Google que está no celular: depois de apagar, ele pede essa
    conta para liberar o uso (proteção contra roubo);
  - se a Mi Account estiver no celular com "Encontrar dispositivo", tenha a senha dela também.
Fotos e arquivos que não estão na nuvem serão perdidos."""


def titulo(texto: str) -> None:
    print(f"\n=== {texto} ===\n")


def confirmar(palavra: str) -> bool:
    resposta = input(f"\nDigite {palavra} para continuar (ou só Enter para cancelar): ")
    return resposta.strip().upper() == palavra


_ultimo_progresso = 0.0


def progresso(rotulo: str, feito: int, total: int, extra: str = "") -> None:
    global _ultimo_progresso
    agora = time.monotonic()
    if total and (agora - _ultimo_progresso > 0.5 or feito >= total):
        _ultimo_progresso = agora
        gb = 2**30
        print(
            f"\r{rotulo}: {feito / gb:.2f} de {total / gb:.2f} GB ({feito * 100 // total}%){extra}   ",
            end="",
            flush=True,
        )


def hashes(caminho: Path) -> tuple[str, str]:
    """MD5 e SHA1 do arquivo (a Xiaomi aprova a ROM por esses dois)."""
    md5, sha1 = hashlib.md5(), hashlib.sha1()
    total, feito = caminho.stat().st_size, 0
    with open(caminho, "rb") as arquivo:
        while bloco := arquivo.read(8 * 2**20):
            md5.update(bloco)
            sha1.update(bloco)
            feito += len(bloco)
            progresso("Conferindo o arquivo", feito, total)
    print()
    return md5.hexdigest(), sha1.hexdigest()


# ---------------------------------------------------------------- conexão USB


def procurar_celular() -> bool:
    """Só olha os descritores USB; não abre o aparelho."""
    try:
        aparelhos = list(usb.core.find(find_all=True, backend=core._BACKEND))
    except usb.core.USBError:
        return False
    for aparelho in aparelhos:
        try:
            for config in aparelho:
                for interface in config:
                    trio = (
                        interface.bInterfaceClass,
                        interface.bInterfaceSubClass,
                        interface.bInterfaceProtocol,
                    )
                    if trio == INTERFACE_MIASSISTANT:
                        return True
        except (usb.core.USBError, NotImplementedError, ValueError):
            continue
    return False


def conectar():
    deps.ensure_libusb()
    if sys.platform == "win32" and core._BACKEND is None:
        sys.exit(
            "Não consegui carregar o libusb. Rode no terminal desta pasta:\n"
            "  .venv\\Scripts\\python -m pip install --force-reinstall libusb_package"
        )
    inicio, avisou = time.monotonic(), False
    while not procurar_celular():
        if not avisou:
            print(COMO_ENTRAR)
            print("\nAguardando o celular (até 5 minutos)...", flush=True)
            avisou = True
        if time.monotonic() - inicio > ESPERA_CELULAR_S:
            sys.exit(
                "\nO celular não apareceu no modo MIAssistant. "
                "Confira a tela do celular, o cabo e a porta USB e tente de novo."
            )
        time.sleep(2)
    try:
        return core.get_transport()
    except (NotImplementedError, usb.core.USBError) as erro:
        print(f"\nO Windows achou o celular, mas não liberou a conexão USB ({erro}).\n")
        print(DRIVER)
        if sys.platform == "win32":
            os.startfile("devmgmt.msc")
        sys.exit(1)


def mostrar_info(info: dict) -> None:
    titulo("Celular conectado")
    campos = (
        ("Aparelho", "device"),
        ("Versão instalada", "version"),
        ("Região", "region"),
        ("Zona da ROM", "romzone"),
        ("Canal", "branch"),
        ("Android (codebase)", "codebase"),
        ("Recovery", "recoveryversion"),
    )
    for rotulo, chave in campos:
        print(f"  {rotulo:<20} {info.get(chave, '')}")


def modelo_reconhecido(info: dict) -> str | None:
    """Codinome aceito que o celular informa (ex.: "creek" em "creek_global")."""
    partes = re.split(r"[^a-z0-9]+", info.get("device", "").lower())
    return next((codigo for codigo in APARELHOS if codigo in partes), None)


def codinome(info: dict) -> str:
    """Codinome do celular, mesmo que não esteja na lista (primeira parte do nome)."""
    partes = re.split(r"[^a-z0-9]+", info.get("device", "").lower())
    return modelo_reconhecido(info) or partes[0]


def confere_codinome(info: dict) -> bool:
    codigo = modelo_reconhecido(info)
    if codigo:
        print(f"\n  Modelo: {APARELHOS[codigo]} ({codigo})")
        return True
    if not info.get("device"):
        print("\nO celular não informou o modelo; confira se ele está no modo MIAssistant.")
        return False
    print(
        f"\n  Modelo: {codinome(info)} (pelo codinome que o celular informa: '{info.get('device')}').\n"
        "  O servidor da Xiaomi escolhe a ROM deste aparelho e o recovery confere antes de instalar."
    )
    return True


def celular_conferido() -> dict | None:
    conectar()
    info = core.get_info()
    mostrar_info(info)
    return info if confere_codinome(info) else None


# ------------------------------------------------------- servidor da Xiaomi


def consultar_xiaomi(info: dict, md5: str = "") -> dict:
    try:
        resposta = core._validate_request(info, md5)
    except Exception as erro:  # rede fora ou resposta inesperada
        sys.exit(
            f"\nNão consegui consultar o servidor da Xiaomi ({erro}). Confira a internet."
        )
    return resposta if isinstance(resposta, dict) else {}


def roms_oficiais(info: dict) -> tuple[list[dict], dict]:
    """ROMs que o servidor da Xiaomi libera para este celular (com o token de cada uma)."""
    resposta = consultar_xiaomi(info)
    achadas: dict[str, dict] = {}

    def andar(obj, origem=None):
        if isinstance(obj, dict):
            if origem and obj.get("Validate") and obj.get("md5"):
                md5 = str(obj["md5"]).lower()
                achadas.setdefault(
                    md5,
                    {
                        "origem": origem,
                        "md5": md5,
                        "validate": obj["Validate"],
                        "arquivo": obj.get("filename") or "",
                        "versao": obj.get("version") or "",
                    },
                )
            for chave, valor in obj.items():
                andar(valor, chave)
        elif isinstance(obj, list):
            for item in obj:
                andar(item, origem)

    andar(resposta)
    roms = sorted(achadas.values(), key=lambda rom: rom["origem"] != "LatestRom")
    for rom in roms:
        if not (rom["arquivo"] and rom["versao"]):
            pacote = consultar_xiaomi(info, rom["md5"]).get("PkgRom") or {}
            rom["arquivo"] = rom["arquivo"] or pacote.get("filename") or ""
            rom["versao"] = rom["versao"] or pacote.get("version") or ""
    return roms, resposta


def link(rom: dict) -> str:
    return f"https://bigota.d.miui.com/{rom['versao']}/{rom['arquivo']}"


def nome_local(rom: dict) -> str:
    """Nome no disco, sem o código de acesso (?t=...&s=...) que a Xiaomi põe no link."""
    nome = rom["arquivo"].split("?", 1)[0].rsplit("/", 1)[-1]
    return re.sub(r'[<>:"/\\|?*]', "_", nome)


def listar(roms: list[dict], resposta: dict) -> None:
    if not roms:
        print("\nO servidor da Xiaomi não liberou nenhuma ROM para este celular.")
        if resposta.get("Code"):
            print(f"Resposta do servidor: {resposta['Code']}")
        return
    titulo("ROMs oficiais aceitas por este celular")
    for numero, rom in enumerate(roms, 1):
        print(f"  [{numero}] {rom['versao'] or '?'}  ({rom['origem']})")
        print(f"      arquivo: {nome_local(rom) or '?'}")
        print(f"      md5:     {rom['md5']}")
        if rom["arquivo"] and rom["versao"]:
            print(f"      link:    {links(rom)[0]}")


def sha1_do_token(token: str) -> str:
    try:
        return str(core.validate_decrypt(token).get("SHA1", "")).lower()
    except Exception:  # token ilegível = não serve para este arquivo
        return ""


MESMA_VERSAO = """
O celular já está na versão {instalada}, e esta ROM é a {rom}: não é mais nova.
O recovery da Xiaomi só instala uma versão MAIS NOVA que a do celular. Com a mesma
versão, ele recebe o arquivo, confere e cancela ("Installation_aborted"), sem gravar nada.
Para tirar o vírus não precisa reinstalar: opção 5 (apagar tudo) e opção 6 (reiniciar).
Quando a Xiaomi lançar uma versão nova para este celular, as opções 3 e 4 vão funcionar."""


def aprovacao_da_xiaomi(
    info: dict, md5: str, sha1: str, versao_rom: str
) -> tuple[str | None, bool | None, str]:
    """Token da Xiaomi que libera este arquivo neste celular, se apaga os dados, e a origem."""
    pacote = consultar_xiaomi(info, md5).get("PkgRom") or {}
    if pacote.get("Validate"):
        if sha1_do_token(pacote["Validate"]) != sha1:
            print(
                "\nO arquivo não é idêntico ao que a Xiaomi aprovou (SHA1 diferente). Baixe de novo."
            )
            return None, None, "PkgRom com SHA1 diferente"
        erase = pacote.get("Erase")
        return pacote["Validate"], str(erase) == "1", f"PkgRom (Erase={erase})"
    # Sem aprovação direta (PkgRom). Se a ROM não é mais nova que a do celular, o recovery
    # cancela depois de receber tudo: avisa antes, em vez de mandar 5 GB à toa.
    instalada, nova = numero_versao(info.get("version", "")), numero_versao(versao_rom)
    if instalada and nova and nova <= instalada:
        print(MESMA_VERSAO.format(instalada=info.get("version"), rom=versao_rom))
        return None, None, "sem PkgRom; ROM não é mais nova que a instalada"
    # O miasst 1.4.4 sai sem instalar nesse caso (issue #13); o token da mesma ROM vem
    # na lista geral e o recovery confere a assinatura dele.
    roms, resposta = roms_oficiais(info)
    for rom in roms:
        if sha1_do_token(rom["validate"]) == sha1:
            return (
                rom["validate"],
                None,
                f"sem PkgRom; token da lista ({rom['origem']})",
            )
    print(
        "\nA Xiaomi não aprovou este arquivo para este celular "
        "(região diferente, ROM fastboot em vez de recovery, ou versão mais antiga que a instalada)."
    )
    listar(roms, resposta)
    return None, None, "não aprovada"


# ------------------------------------------------------------------ download


# Servidores oficiais da Xiaomi com a mesma ROM. O bigota (o do link que o servidor manda)
# pode ficar lentíssimo em algumas redes; o MD5 no final garante que o arquivo é o certo.
ESPELHOS = (
    "cdnorg.d.miui.com",
    "bn.d.miui.com",
    "bkt-sgp-miui-ota-update-alisgp.oss-ap-southeast-1.aliyuncs.com",
    "hugeota.d.miui.com",
)
JANELA_S = 45  # a cada período assim, confere se o servidor não ficou lento demais
TROCAS_MAX = 50


class Lento(Exception):
    pass


def links(rom: dict) -> list[str]:
    caminho = f"{rom['versao']}/{nome_local(rom)}"
    return [f"https://{espelho}/{caminho}" for espelho in ESPELHOS] + [link(rom)]


def servidor(url: str) -> str:
    return url.split("/")[2]


def medir(url: str, segundos: float = 4.0) -> float:
    """Velocidade (bytes/s) baixando o começo do arquivo por alguns segundos; 0 se falhar."""
    inicio, recebido = time.monotonic(), 0
    try:
        with requests.get(
            url, headers={"Accept-Encoding": "identity"}, stream=True, timeout=(8, 8)
        ) as resposta:
            resposta.raise_for_status()
            for bloco in resposta.iter_content(chunk_size=64 * 1024):
                if not recebido and not bloco.startswith(b"PK"):
                    return 0.0  # não veio um .zip
                recebido += len(bloco)
                if time.monotonic() - inicio >= segundos:
                    break
    except requests.RequestException:
        pass
    return recebido / max(time.monotonic() - inicio, 0.001)


def baixar_parte(url: str, parcial: Path, minimo: float) -> None:
    """Baixa ou continua o arquivo; levanta Lento se a velocidade cair abaixo de `minimo`."""
    feito = parcial.stat().st_size if parcial.exists() else 0
    # Sem compressão: o Range precisa contar os bytes do arquivo como ele é gravado.
    cabecalho = {"Accept-Encoding": "identity"}
    if feito:
        cabecalho["Range"] = f"bytes={feito}-"
    with requests.get(
        url, headers=cabecalho, stream=True, timeout=(10, 30)
    ) as resposta:
        if resposta.status_code == 416:  # já estava completo
            return
        resposta.raise_for_status()
        if resposta.status_code != 206:  # servidor ignorou o Range: recomeça do zero
            feito = 0
        total = feito + int(resposta.headers.get("Content-Length") or 0)
        janela, na_janela, velocidade = time.monotonic(), 0, ""
        with open(parcial, "ab" if feito else "wb") as arquivo:
            for bloco in resposta.iter_content(chunk_size=256 * 1024):
                arquivo.write(bloco)
                feito += len(bloco)
                na_janela += len(bloco)
                decorrido = time.monotonic() - janela
                if decorrido >= 1:
                    velocidade = f" a {na_janela / decorrido / 2**20:.1f} MB/s"
                progresso("Baixando", feito, total, velocidade)
                if decorrido >= JANELA_S:
                    if na_janela / decorrido < minimo:
                        raise Lento
                    janela, na_janela = time.monotonic(), 0
    print()


def baixar(urls: list[str], destino: Path, md5_esperado: str) -> bool:
    PASTA_ROM.mkdir(exist_ok=True)
    if destino.exists():
        print(f"\nJá baixada: {destino.name}")
        if hashes(destino)[0] == md5_esperado:
            print("MD5 confere.")
            return True
        print("MD5 não confere; vou baixar de novo.")
        destino.unlink()
    parcial = destino.with_name(destino.name + ".parcial")
    print("\nTestando a velocidade dos servidores oficiais da Xiaomi...")
    opcoes = []
    for url in urls:
        velocidade = medir(url)
        print(f"  {servidor(url):<64} {velocidade / 2**20:6.2f} MB/s")
        if velocidade > 0:
            opcoes.append((velocidade, url))
    opcoes.sort(reverse=True)
    trocas = 0
    while opcoes and trocas < TROCAS_MAX:
        velocidade, url = opcoes[0]
        print(f"\nBaixando de {servidor(url)}")
        try:
            baixar_parte(url, parcial, minimo=velocidade / 10)
            break
        except Lento:
            print(f"\n{servidor(url)} ficou lento; trocando de servidor...")
        except requests.RequestException as erro:
            codigo = getattr(erro.response, "status_code", 0) or 0
            print(
                f"\nFalha em {servidor(url)} ({codigo or erro}); trocando de servidor..."
            )
            if (
                400 <= codigo < 500
            ):  # link recusado: não adianta insistir neste servidor
                opcoes.pop(0)
                continue
            time.sleep(3)
        opcoes.append(opcoes.pop(0))  # este servidor vai para o fim da fila
        trocas += 1
    else:
        print(
            "\nNão terminei o download. Confira a internet e rode a opção de novo:"
            " ele continua de onde parou."
        )
        return False
    if hashes(parcial)[0] != md5_esperado:
        parcial.unlink()
        print(
            "O arquivo veio corrompido (MD5 diferente) e foi apagado. Rode a opção de novo."
        )
        return False
    parcial.replace(destino)
    print(f"ROM pronta e conferida: {destino}")
    return True


def escolher(roms: list[dict]) -> dict:
    if len(roms) == 1:
        return roms[0]
    while True:
        escolha = input(f"\nQual ROM? [1-{len(roms)}, Enter = 1]: ").strip() or "1"
        if escolha.isdigit() and 1 <= int(escolha) <= len(roms):
            return roms[int(escolha) - 1]


@cache
def metadados_da_rom(caminho: str) -> dict[str, str]:
    """Ficha do pacote (META-INF/com/android/metadata), que o recovery confere antes de instalar."""
    try:
        with zipfile.ZipFile(caminho) as pacote:
            texto = pacote.read("META-INF/com/android/metadata").decode(errors="ignore")
    except (OSError, KeyError, zipfile.BadZipFile):
        return {}
    pares = (linha.split("=", 1) for linha in texto.splitlines() if "=" in linha)
    return {chave.strip(): valor.strip() for chave, valor in pares}


def versao_da_rom(arquivo: Path) -> str:
    versao = metadados_da_rom(str(arquivo)).get("post-build-incremental", "")
    if versao:
        return versao
    achado = re.search(r"(?:OS|V)\d+(?:\.\d+){3}\.[A-Z]+", arquivo.name)
    return achado.group() if achado else ""


def numero_versao(texto: str) -> tuple[int, ...] | None:
    """OS3.0.305.0.WBOMIXM -> (1, 3, 0, 305, 0); V14.0.6.0.TMXMIXM -> (0, 14, 0, 6, 0)."""
    achado = re.match(r"\s*(OS|V)(\d+)\.(\d+)\.(\d+)\.(\d+)", texto, re.IGNORECASE)
    if not achado:
        return None
    serie = 1 if achado.group(1).upper() == "OS" else 0  # HyperOS veio depois do MIUI
    return (serie, *(int(parte) for parte in achado.groups()[1:]))


def rom_do_modelo(arquivo: Path, codigo: str) -> bool:
    """A ficha da ROM diz para quais aparelhos ela serve (pre-device); sem ficha, o nome."""
    aparelhos = metadados_da_rom(str(arquivo)).get("pre-device", "")
    if aparelhos:
        return codigo in [item.strip().lower() for item in aparelhos.split(",")]
    nome = arquivo.name.lower()
    return nome.startswith(f"{codigo}_") or f"_{codigo}global_" in nome


def escolher_arquivo(caminho: str | None, codigo: str | None) -> Path | None:
    """ROM a instalar: a informada, ou a da pasta rom que é deste modelo de celular."""
    if caminho:
        arquivo = Path(caminho.strip().strip('"'))
    else:
        zips = sorted(
            PASTA_ROM.glob("*.zip"), key=lambda p: p.stat().st_mtime, reverse=True
        )
        if codigo:
            zips = [item for item in zips if rom_do_modelo(item, codigo)]
        if len(zips) == 1:
            arquivo = zips[0]
        elif zips:
            for numero, item in enumerate(zips, 1):
                print(f"  [{numero}] {item.name}")
            arquivo = escolher([{"caminho": item} for item in zips])["caminho"]
        else:
            print(
                "\nNão há ROM deste celular na pasta rom. Use antes a opção 3 (baixar)."
            )
            texto = input(
                "Ou informe o caminho do .zip (a ROM de recovery) e aperte Enter: "
            )
            if not texto.strip():
                return None
            arquivo = Path(texto.strip().strip('"'))
    if not arquivo.is_file() or arquivo.suffix.lower() != ".zip":
        print(f"\nNão achei o arquivo .zip: {arquivo}")
        print(
            "A ROM certa é a de recovery (.zip, cerca de 5 GB), não a fastboot (.tgz)."
        )
        return None
    return arquivo


# ---------------------------------------------------------------- instalação

FIM_OK, FIM_FALHA = "DONEDONE", "FAILFAIL"  # fim do sideload no protocolo do Android
DESCONECTOU = "DESCONECTOU"
SILENCIO_S = 15  # sem resposta por esse tempo: confere se o celular ainda está no USB

REINICIOU = """\
O celular reiniciou (ou o cabo soltou) no meio da instalação, sem confirmar.
Isso não é o vírus: no modo recovery o Android e os apps não rodam.
Em geral o celular volta a ligar na versão que já estava instalada. Se não ligar,
o recovery continua lá: Power + Volume para cima > Connect with MIAssistant.
Próximo passo recomendado: opção 5 (apagar tudo) e depois opção 4 (instalar de novo),
com bateria acima de 50%, o cabo original e uma porta USB direto no PC (sem hub)."""

CANCELOU = """\
O celular recebeu a ROM inteira, conferiu e cancelou a instalação antes de gravar
qualquer coisa ("Installation_aborted"). Nada foi alterado no sistema.
O motivo mais comum: a ROM não é mais nova que a versão que já está no celular.
Para tirar o vírus não precisa reinstalar: opção 5 (apagar tudo) e opção 6 (reiniciar)."""


def registrar(texto: str, novo: bool = False) -> None:
    """Registro da instalação (instalacao.log): só dados técnicos, sem número de série."""
    with open(LOG_INSTALACAO, "w" if novo else "a", encoding="utf-8") as log:
        log.write(f"{time.strftime('%d/%m %H:%M:%S')} {texto}\n")


def ainda_conectado(transporte: dict) -> bool:
    """O celular desta conexão continua no USB? Some quando ele reinicia."""
    ponto = transporte.get("out_ep")
    if ponto is None:
        return True
    aparelho = ponto.device
    try:
        achados = usb.core.find(
            find_all=True,
            backend=core._BACKEND,
            custom_match=lambda d: (
                (d.bus, d.address) == (aparelho.bus, aparelho.address)
            ),
        )
        return any(True for _ in achados)
    except usb.core.USBError:
        return True  # na dúvida, continua esperando


def sideload(transporte: dict, arquivo: Path, token: str) -> str:
    """Envia a ROM ao celular com o mesmo protocolo do core.start_sideload do miasst 1.4.4.

    Diferenças: mostra o progresso real (o celular lê o pacote ~2 vezes: confere e depois
    instala), desiste se o celular sumir do USB em vez de esperar para sempre, e grava
    em instalacao.log só os números de bloco pedidos e a mensagem final.
    """
    tamanho = arquivo.stat().st_size
    bloco_tam = core.ADB_SIDELOAD_CHUNK_SIZE
    pedido = f"sideload-host:{tamanho}:{bloco_tam}:{token}:0".encode()
    core.send_packet(transporte, core.ADB_OPEN, 1, 0, pedido)
    enviado, anterior, linhas, silencio = 0, -1, 0, time.monotonic()
    with open(arquivo, "rb") as rom:
        registrar(f"início do envio: {arquivo.name} ({tamanho} bytes)")
        while True:
            comeco = time.monotonic()
            try:
                cmd, arg0, arg1, dados = core.read_packet(transporte)
            except (core.DeviceTimeout, core.DeviceWriteError):
                if time.monotonic() - comeco < 1:
                    time.sleep(0.5)  # erro na hora: o celular pode ter saído do USB
                if time.monotonic() - silencio > SILENCIO_S and not ainda_conectado(
                    transporte
                ):
                    registrar(
                        f"celular sumiu do USB; enviado {enviado / tamanho:.2f}x o arquivo"
                    )
                    print()
                    return DESCONECTOU
                continue
            silencio = time.monotonic()
            texto = dados.decode(errors="ignore")
            if len(dados) > 8 or texto in (FIM_OK, FIM_FALHA):
                registrar(
                    f"mensagem final: {texto!r}; enviado {enviado / tamanho:.2f}x"
                )
                print(f"\n\nMensagem do celular: {texto}\n")
                return texto
            if cmd == core.ADB_OKAY:
                core.send_packet(transporte, core.ADB_OKAY, arg1, arg0)
            if cmd != core.ADB_WRTE:
                continue
            numero = re.match(r"\d+", texto)
            bloco = int(numero.group()) if numero else 0
            deslocamento = bloco * bloco_tam
            if deslocamento > tamanho:
                registrar(f"pedido do bloco {bloco}, além do fim do arquivo")
                print()
                return "BLOCO_INVALIDO"
            if bloco != anterior + 1 and linhas < 5000:
                registrar(
                    f"bloco {anterior} -> {bloco} (enviado {enviado / tamanho:.2f}x)"
                )
                linhas += 1
            anterior = bloco
            rom.seek(deslocamento)
            pedaco = rom.read(min(bloco_tam, tamanho - deslocamento))
            try:
                core.send_packet(transporte, core.ADB_WRTE, arg1, arg0, pedaco)
                core.send_packet(transporte, core.ADB_OKAY, arg1, arg0)
            except core.DeviceWriteError:
                continue
            enviado += len(pedaco)
            # Mesma conta do "adb sideload" oficial: 100% quando enviou ~2,13x o arquivo.
            pct = min(99, enviado * 47 // tamanho)
            print(f"\rEnviando ao celular: ~{pct}%   ", end="", flush=True)


# -------------------------------------------------------------------- ações


def acao_info() -> int:
    return 0 if celular_conferido() else 1


def acao_roms() -> int:
    info = celular_conferido()
    if not info:
        return 1
    roms, resposta = roms_oficiais(info)
    listar(roms, resposta)
    return 0 if roms else 1


def acao_baixar() -> int:
    info = celular_conferido()
    if not info:
        return 1
    roms, resposta = roms_oficiais(info)
    roms = [rom for rom in roms if rom["arquivo"] and rom["versao"]]
    listar(roms, resposta)
    if not roms:
        return 1
    rom = escolher(roms)
    return 0 if baixar(links(rom), PASTA_ROM / nome_local(rom), rom["md5"]) else 1


def acao_instalar(caminho: str | None = None) -> int:
    transporte = conectar()
    info = core.get_info()
    mostrar_info(info)
    if not confere_codinome(info):
        return 1
    arquivo = escolher_arquivo(caminho, codinome(info))
    if not arquivo:
        return 1
    versao_rom = versao_da_rom(arquivo)
    print(f"\nROM escolhida: {arquivo}\nVersão da ROM: {versao_rom or '?'}")
    registrar(
        f"aparelho={info.get('device')} instalada={info.get('version')} "
        f"rom={versao_rom} arquivo={arquivo.name}",
        novo=True,
    )
    md5, sha1 = hashes(arquivo)
    token, apaga, origem = aprovacao_da_xiaomi(info, md5, sha1, versao_rom)
    registrar(f"aprovação: {origem}")
    if not token:
        print(f"\nRegistro desta tentativa: {LOG_INSTALACAO}")
        return 1
    titulo("Instalar a ROM oficial")
    print("A Xiaomi aprovou esta ROM para este celular.")
    if apaga:
        print("ATENÇÃO: esta instalação APAGA os dados do celular.")
    elif apaga is None:
        print("Esta instalação pode apagar os dados do celular.")
    print(
        "Leva de 10 a 30 minutos. O celular primeiro confere o pacote inteiro (até ~47%)\n"
        "e depois instala (até 100%). A porcentagem pode parar um tempo: é normal.\n"
        "Bateria acima de 50%. Não tire o cabo, não feche esta janela e não mexa no celular."
    )
    if not confirmar("INSTALAR"):
        print("Cancelado.")
        return 1
    mensagem = sideload(transporte, arquivo, token)
    minusculo = mensagem.lower()
    falhou = mensagem == FIM_FALHA or any(
        palavra in minusculo for palavra in ("fail", "error", "abort")
    )
    if not falhou and (
        mensagem == FIM_OK or "complete" in minusculo or "success" in minusculo
    ):
        print("Instalação concluída.")
        return 0
    if mensagem == DESCONECTOU:
        print(REINICIOU)
    elif "abort" in minusculo:
        print(CANCELOU)
    else:
        print(
            "O celular não confirmou a instalação (veja a mensagem acima e a tela do celular)."
        )
    print(f"\nRegistro desta tentativa: {LOG_INSTALACAO}")
    return 1


def acao_apagar() -> int:
    if not celular_conferido():
        return 1
    titulo("Apagar tudo (restaurar de fábrica)")
    print(AVISO_APAGAR)
    if not confirmar("APAGAR"):
        print("Cancelado.")
        return 1
    try:
        resposta = core.adb_cmd(core.get_transport(), "format-data:")
    except core.DeviceTimeout:
        resposta = "(sem resposta)"
    print(f"\nResposta do celular: {resposta}")
    print(
        "Confira a tela do celular. Se não apagou, faça pelo próprio recovery:\n"
        "volte ao menu > Wipe Data > Wipe All Data > confirme."
    )
    return 0


def acao_reiniciar() -> int:
    conectar()
    try:
        core.adb_cmd(core.get_transport(), "reboot:")
    except core.DeviceTimeout:
        pass  # o celular desconecta ao reiniciar
    print("\nCelular reiniciando. A primeira inicialização pode levar alguns minutos.")
    return 0


ACOES = {
    "info": acao_info,
    "roms": acao_roms,
    "baixar": acao_baixar,
    "instalar": acao_instalar,
    "apagar": acao_apagar,
    "reiniciar": acao_reiniciar,
}

MENU = (
    ("1", "Ver dados do celular", ["info"]),
    ("2", "Ver as ROMs oficiais aceitas por este celular", ["roms"]),
    ("3", "Baixar a ROM oficial (cerca de 5 GB; continua de onde parou)", ["baixar"]),
    ("4", "Instalar a ROM oficial", ["instalar"]),
    ("5", "Apagar tudo (restaurar de fábrica)", ["apagar"]),
    ("6", "Reiniciar o celular", ["reiniciar"]),
    (
        "7",
        "Passo a passo completo: baixar, apagar tudo, instalar e reiniciar",
        ["baixar", "apagar", "instalar", "reiniciar"],
    ),
)


def rodar(acao: str) -> int:
    """Cada passo roda num processo novo, com a conexão USB do zero (o celular pode reconectar)."""
    return subprocess.call([sys.executable, "-I", str(Path(__file__).resolve()), acao])


def menu() -> int:
    while True:
        titulo("Recuperar celular Xiaomi / Redmi / POCO (modo MIAssistant)")
        for numero, texto, _ in MENU:
            print(f"  {numero}  {texto}")
        print("  0  Sair")
        escolha = input("\nOpção: ").strip()
        if escolha == "0":
            return 0
        passos = next((passos for numero, _, passos in MENU if numero == escolha), None)
        for indice, passo in enumerate(passos or []):
            if indice:
                input(
                    "\nSe o celular saiu do modo MIAssistant, entre de novo "
                    "(Power + Volume para cima > Connect with MIAssistant).\n"
                    "Aperte Enter para o próximo passo..."
                )
            if rodar(passo) != 0:
                print("\nEste passo não terminou; parei aqui.")
                break


def main() -> int:
    if len(sys.argv) == 1:
        return menu()
    nome = sys.argv[1].lower()
    if nome not in ACOES:
        print(__doc__)
        return 2
    if nome == "instalar":
        return acao_instalar(sys.argv[2] if len(sys.argv) > 2 else None)
    return ACOES[nome]()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\nCancelado.")
        sys.exit(130)
