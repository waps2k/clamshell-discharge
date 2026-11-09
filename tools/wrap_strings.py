#!/usr/bin/env python3
"""Swift 소스의 한글 문자열 리터럴을 tr(...) 로 감싸고, 번역 키 목록을 출력한다.

- 문자열 보간 \\( ... ) 안의 중첩 문자열도 처리 (재귀)
- 주석(//), enum raw value(case x = "..."), 이미 tr( 로 감싼 것은 건너뜀
- 키: 보간 부분을 %@ 로 바꾼 문자열

사용: wrap_strings.py --list FILE...   키만 출력
      wrap_strings.py --apply FILE...  파일을 직접 수정
"""
import re
import sys

HANGUL = re.compile(r'[가-힣]')


def scan_string(src, i):
    """src[i] == '"' 인 위치에서 문자열 리터럴 끝까지 읽음.
    반환: (끝 인덱스(닫는 따옴표 다음), 파츠 리스트)
    파츠: ('lit', text) | ('interp', expr_source_transformed, raw_expr)
    """
    assert src[i] == '"'
    j = i + 1
    parts = []
    buf = []
    while j < len(src):
        c = src[j]
        if c == '\\':
            if src[j + 1] == '(':
                if buf:
                    parts.append(('lit', ''.join(buf)))
                    buf = []
                # 보간식: 괄호 짝 맞추며 중첩 문자열 처리
                k = j + 2
                depth = 1
                expr_start = k
                while depth:
                    ch = src[k]
                    if ch == '"':
                        k, _ = scan_string(src, k)
                        continue
                    if ch == '(':
                        depth += 1
                    elif ch == ')':
                        depth -= 1
                    k += 1
                raw = src[expr_start:k - 1]
                parts.append(('interp', transform(raw), raw))
                j = k
                continue
            buf.append(src[j:j + 2])
            j += 2
            continue
        if c == '"':
            if buf:
                parts.append(('lit', ''.join(buf)))
            return j + 1, parts
        if c == '\n':
            raise ValueError('multiline string not supported')
        buf.append(c)
        j += 1
    raise ValueError('unterminated string')


KEYS = []


def literal_text(parts):
    return ''.join(p[1] for p in parts if p[0] == 'lit')


def rebuild(parts):
    out = ['"']
    for p in parts:
        if p[0] == 'lit':
            out.append(p[1])
        else:
            out.append('\\(' + p[1] + ')')
    out.append('"')
    return ''.join(out)


def key_of(parts):
    k = []
    for p in parts:
        k.append(p[1] if p[0] == 'lit' else '%@')
    return ''.join(k)


def transform(src):
    """src 안의 한글 문자열 리터럴을 tr(...) 로 감싼 소스를 돌려줌"""
    out = []
    i = 0
    n = len(src)
    while i < n:
        c = src[i]
        # 주석
        if src.startswith('//', i):
            e = src.find('\n', i)
            e = n if e < 0 else e
            out.append(src[i:e])
            i = e
            continue
        if src.startswith('/*', i):
            e = src.find('*/', i) + 2
            out.append(src[i:e])
            i = e
            continue
        if c == '"':
            # 여러 줄 문자열(""") 은 그대로
            if src.startswith('"""', i):
                e = src.find('"""', i + 3) + 3
                out.append(src[i:e])
                i = e
                continue
            end, parts = scan_string(src, i)
            lit = rebuild(parts)
            line_start = src.rfind('\n', 0, i) + 1
            before = src[line_start:i]
            already = src[max(0, i - 3):i] == 'tr('
            # enum raw value 줄 (case a = "..", b = "..") 은 통째로 건너뜀
            is_raw_case = re.match(r'\s*case\s+\w+\s*=', before) is not None
            skip_line = 'do shell script' in src[line_start:src.find('\n', i)]
            if HANGUL.search(literal_text(parts)) and not is_raw_case and not skip_line:
                KEYS.append(key_of(parts))   # 이미 tr( 로 감싼 것도 키 목록에는 포함 (번역 누락 검사용)
            if HANGUL.search(literal_text(parts)) and not already and not is_raw_case and not skip_line:
                out.append('tr(' + lit + ')')
            else:
                out.append(lit)
            i = end
            continue
        out.append(c)
        i += 1
    return ''.join(out)


def main():
    mode = sys.argv[1]
    for path in sys.argv[2:]:
        src = open(path, encoding='utf-8').read()
        new = transform(src)
        if mode == '--apply' and new != src:
            open(path, 'w', encoding='utf-8').write(new)
    seen = []
    for k in KEYS:
        if k not in seen:
            seen.append(k)
    for k in seen:
        print(k)


if __name__ == '__main__':
    main()
