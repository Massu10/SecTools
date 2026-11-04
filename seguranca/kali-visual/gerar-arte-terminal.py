"""Gera a máscara do terminal (meio-blocos) a partir de mascara-mapa.txt (metade esquerda, espelhada).

Uso: python gerar-arte-terminal.py [pasta de saída]  ->  mascara-kali.ans e mascara-root.ans (tema verde, 256 cores),
     mascara-real.ans e mascara-real-root.ans (cores de verdade, para o "cores original"; 24 bits) e previa-arte.html
Mapa: ' ' fundo | . : - = # tons da pele (claro -> escuro) | X traço preto | o olho | p bochecha | l lábios
"""
import math
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))
SAIDA = sys.argv[1] if len(sys.argv) > 1 else AQUI
METADE = 19

linhas = open(os.path.join(AQUI, 'mascara-mapa.txt'), encoding='utf-8').read().split('\n')
linhas = [l.ljust(METADE)[:METADE] for l in linhas if l.strip() or len(l) >= METADE]
if len(linhas) % 2:
    linhas.append(' ' * METADE)
mapa = [l + l[::-1] for l in linhas]

# tema verde (256 cores); os lábios ficam no tom da borda, como sempre foram
VERDE_KALI = {'.': 194, ':': 157, '-': 120, '=': 77, '#': 34, 'l': 34, 'X': 16, 'o': 46, 'p': 217}
VERDE_ROOT = {'.': 157, ':': 120, '-': 77, '=': 34, '#': 28, 'l': 28, 'X': 16, 'o': 196, 'p': 157}
# a máscara de verdade: porcelana marfim, bochechas rosadas, bigode, cavanhaque e sobrancelhas pretos, lábios vinho
REAL = {'.': (247, 242, 231), ':': (231, 223, 207), '-': (206, 196, 178), '=': (167, 155, 138), '#': (113, 102, 90),
        'l': (142, 44, 56), 'X': (22, 19, 18), 'o': (34, 28, 26), 'p': (231, 140, 146)}
REAL_ROOT = dict(REAL, o=(226, 28, 40))   # root: olhos vermelhos acesos
VARIANTES = {
    'mascara-kali': (VERDE_KALI, '#020904'),
    'mascara-root': (VERDE_ROOT, '#090304'),
    'mascara-real': (REAL, '#23252e'),
    'mascara-real-root': (REAL_ROOT, '#23252e'),
}
NIVEIS = [0, 95, 135, 175, 215, 255]
BOCHECHAS = [(y, x) for y, l in enumerate(mapa) for x, ch in enumerate(l) if ch == 'p']


def rgb256(n):
    k = n - 16
    return NIVEIS[k // 36], NIVEIS[(k // 6) % 6], NIVEIS[k % 6]


def css(cor):
    return '#%02x%02x%02x' % (rgb256(cor) if isinstance(cor, int) else cor)


def cor_da(cores, y, x):
    """Cor de uma célula do mapa (None = fundo). Nas cores de verdade a pele em volta da bochecha fica rosada."""
    ch = mapa[y][x]
    cor = cores.get(ch)
    if cor is None or isinstance(cor, int) or ch not in '.:-=' or not BOCHECHAS:
        return cor
    d = min(math.hypot(y - by, x - bx) for by, bx in BOCHECHAS)
    t = max(0.0, 1 - d / 3.2) * 0.6
    return tuple(round(a + (b - a) * t) for a, b in zip(cor, cores['p']))


def sgr(cor, fundo=False):
    if isinstance(cor, int):
        return '\x1b[%d;5;%dm' % (48 if fundo else 38, cor)
    return '\x1b[%d;2;%d;%d;%dm' % ((48 if fundo else 38,) + tuple(cor))


def gera(cores):
    ans, htm = [], []
    for r in range(0, len(mapa), 2):
        s, h = [], []
        fg_at, bg_at = None, 'início'          # cada linha começa dizendo o fundo
        for x in range(len(mapa[r])):
            t, b = cor_da(cores, r, x), cor_da(cores, r + 1, x)
            if t is None and b is None:
                c, fg, bg = ' ', None, None
            elif b is None:
                c, fg, bg = '▀', t, None
            elif t is None:
                c, fg, bg = '▄', b, None
            elif t == b:
                c, fg, bg = '█', t, None
            else:
                c, fg, bg = '▀', t, b
            if bg != bg_at:
                s.append('\x1b[49m' if bg is None else sgr(bg, True))
                bg_at = bg
            if fg is not None and fg != fg_at:
                s.append(sgr(fg))
                fg_at = fg
            s.append(c)
            ct = css(t) if t is not None else 'transparent'
            cb = css(b) if b is not None else 'transparent'
            h.append(f"<i style='background:linear-gradient({ct} 50%,{cb} 50%)'></i>")
        s.append('\x1b[0m')
        ans.append(''.join(s))
        htm.append(''.join(h))
    return '\n'.join(ans) + '\n', '<br>'.join(htm)


previas = []
for nome, (cores, fundo) in VARIANTES.items():
    a, h = gera(cores)
    with open(os.path.join(SAIDA, nome + '.ans'), 'w', encoding='utf-8', newline='\n') as f:
        f.write(a)
    previas.append(f"<div class='m' style='background:{fundo}'>{h}</div>")

css_previa = "body{background:#111;margin:0;padding:20px}.m{display:inline-block;margin-right:20px;padding:20px;line-height:0}i{display:inline-block;width:10px;height:20px}"
with open(os.path.join(SAIDA, 'previa-arte.html'), 'w', encoding='utf-8') as f:
    f.write(f"<!doctype html><meta charset='utf-8'><style>{css_previa}</style>{''.join(previas)}")
print('ok', len(mapa[0]), 'colunas x', len(mapa) // 2, 'linhas')
