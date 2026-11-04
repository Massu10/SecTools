"""Gera o ícone do atalho "Kali Linux" (a máscara verde do tema) a partir de mascara-mapa.txt.

Uso: python gerar-icone.py [pasta de saída]  ->  kali-mascara.ico (16 a 256 px) e kali-mascara-previa.png
Sem bibliotecas: desenha numa grade de 768x768 e tira a média de cada bloco para cada tamanho (fica liso nos
pequenos e com os quadradinhos certos no de 256); o PNG e o ICO são montados aqui mesmo.
"""
import math
import os
import struct
import sys
import zlib

AQUI = os.path.dirname(os.path.abspath(__file__))
SAIDA = sys.argv[1] if len(sys.argv) > 1 else AQUI
METADE = 19
M = 768                                       # divisível por todos os tamanhos
TAMANHOS = (256, 128, 64, 48, 32, 24, 16)
CELULA = 15                                   # cada quadradinho do mapa: 15 px aqui = 5 px no ícone de 256
CORES = {'.': 194, ':': 157, '-': 120, '=': 77, '#': 34, 'l': 34, 'X': 16, 'o': 46, 'p': 217}   # as do terminal
NIVEIS = [0, 95, 135, 175, 215, 255]

linhas = open(os.path.join(AQUI, 'mascara-mapa.txt'), encoding='utf-8').read().split('\n')
linhas = [l.ljust(METADE)[:METADE] for l in linhas if l.strip() or len(l) >= METADE]
mapa = [l + l[::-1] for l in linhas]
ALT, LARG = len(mapa), len(mapa[0])
X0, Y0 = (M - LARG * CELULA) // 2, (M - ALT * CELULA) // 2


def rgb256(n):
    k = n - 16
    return NIVEIS[k // 36], NIVEIS[(k // 6) % 6], NIVEIS[k % 6]


def mistura(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def pixel(x, y):
    """Cor (r, g, b, a) de um ponto da grade: placa escura de cantos redondos, borda verde e a máscara por cima."""
    meio, pad, raio, borda = M / 2, M * 0.02, M * 0.2, M * 0.022
    qx, qy = abs(x + 0.5 - meio) - (meio - pad - raio), abs(y + 0.5 - meio) - (meio - pad - raio)
    d = math.hypot(max(qx, 0), max(qy, 0)) + min(max(qx, qy), 0) - raio      # < 0 dentro da placa
    if d > 0:
        return 0, 0, 0, 0
    mx, my = (x - X0) // CELULA, (y - Y0) // CELULA
    if 0 <= mx < LARG and 0 <= my < ALT and mapa[my][mx] in CORES:
        return rgb256(CORES[mapa[my][mx]]) + (255,)
    if d > -borda:
        return (40, 168, 82, 255)
    t = min(1.0, math.hypot(x - meio, y - meio * 0.92) / (M * 0.62))          # brilho verde no meio
    return mistura((12, 46, 24), (2, 9, 5), t) + (255,)


def reduz(grade, tam):
    f = M // tam
    out = []
    for by in range(tam):
        linha = []
        for bx in range(tam):
            r = g = b = a = 0
            for y in range(by * f, by * f + f):
                row = grade[y]
                for x in range(bx * f, bx * f + f):
                    pr, pg, pb, pa = row[x]
                    r += pr * pa
                    g += pg * pa
                    b += pb * pa
                    a += pa
            if a:
                linha.append((round(r / a), round(g / a), round(b / a), round(a / (f * f))))
            else:
                linha.append((0, 0, 0, 0))
        out.append(linha)
    return out


def png(img):
    alt, larg = len(img), len(img[0])
    cru = b''.join(b'\0' + bytes(c for p in linha for c in p) for linha in img)

    def bloco(tipo, dados):
        return struct.pack('>I', len(dados)) + tipo + dados + struct.pack('>I', zlib.crc32(tipo + dados))

    return (b'\x89PNG\r\n\x1a\n' + bloco(b'IHDR', struct.pack('>IIBBBBB', larg, alt, 8, 6, 0, 0, 0))
            + bloco(b'IDAT', zlib.compress(cru, 9)) + bloco(b'IEND', b''))


grade = [[pixel(x, y) for x in range(M)] for y in range(M)]
imagens = {t: reduz(grade, t) for t in TAMANHOS}
pngs = [png(imagens[t]) for t in TAMANHOS]
cab = struct.pack('<HHH', 0, 1, len(TAMANHOS))
pos = 6 + 16 * len(TAMANHOS)
entradas = b''
for t, dados in zip(TAMANHOS, pngs):
    entradas += struct.pack('<BBBBHHII', t % 256, t % 256, 0, 0, 1, 32, len(dados), pos)
    pos += len(dados)
with open(os.path.join(SAIDA, 'kali-mascara.ico'), 'wb') as f:
    f.write(cab + entradas + b''.join(pngs))

# prévia: os tamanhos lado a lado, em fundo escuro e claro
fundos = ((24, 24, 24), (236, 236, 236))
larg_previa = sum(TAMANHOS) + 10 * (len(TAMANHOS) + 1)
previa = []
for fundo in fundos:
    faixa = [[fundo + (255,)] * larg_previa for _ in range(276)]
    x = 10
    for t in TAMANHOS:
        for y in range(t):
            for i in range(t):
                r, g, b, a = imagens[t][y][i]
                faixa[10 + y][x + i] = mistura(fundo, (r, g, b), a / 255) + (255,)
        x += t + 10
    previa += faixa
with open(os.path.join(SAIDA, 'kali-mascara-previa.png'), 'wb') as f:
    f.write(png(previa))
print('ok: kali-mascara.ico com', ', '.join(map(str, TAMANHOS)), 'px')
