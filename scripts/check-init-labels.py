import re, glob, sys

core = {}
for p in glob.glob('FieldwatchCore/Sources/FieldwatchCore/*.swift'):
    s = open(p, encoding='utf-8').read()
    # public struct/class X ... ثم أول public init
    for m in re.finditer(r'public (?:struct|final class|class) (\w+)', s):
        name = m.group(1)
        rest = s[m.end():]
        im = re.search(r'public init\s*\(', rest)
        if not im: continue
        # استخرج المعاملات حتى القوس المطابق
        i = im.end(); depth = 1; buf = ''
        while i < len(rest) and depth > 0:
            c = rest[i]
            if c == '(': depth += 1
            if c == ')': depth -= 1
            if depth > 0: buf += c
            i += 1
        labels = []
        d = 0; cur = ''
        for ch in buf:
            if ch in '([{<': d += 1
            elif ch in ')]}>': d -= 1
            if ch == ',' and d == 0:
                labels.append(cur); cur = ''
            else: cur += ch
        labels.append(cur)
        out = []
        for chunk in labels:
            lm = re.match(r'\s*(\w+)\s*:', chunk)
            if lm: out.append(lm.group(1))
            elif chunk.strip(): out.append('_')
        core[name] = out

def calls(text, name):
    res = []
    for m in re.finditer(r'(?<![\w.])' + re.escape(name) + r'\s*\(', text):
        i = m.end(); depth = 1; buf = ''
        while i < len(text) and depth > 0:
            c = text[i]
            if c in '([{': depth += 1
            elif c in ')]}': depth -= 1
            if depth > 0: buf += c
            i += 1
        res.append((m.start(), buf))
    return res

problems = []
for p in glob.glob('FieldwatchApp/Sources/*.swift'):
    s = open(p, encoding='utf-8').read()
    for name, decl in core.items():
        if not decl: continue
        for pos, buf in calls(s, name):
            if buf.strip().startswith(')'): continue
            # اقسم على المستوى الأعلى
            d = 0; chunks = []; cur = ''
            for ch in buf:
                if ch in '([{': d += 1
                elif ch in ')]}': d -= 1
                if ch == ',' and d == 0: chunks.append(cur); cur = ''
                else: cur += ch
            chunks.append(cur)
            got = []
            for ch in chunks:
                lm = re.match(r'\s*(\w+)\s*:', ch)
                got.append(lm.group(1) if lm else ('_' if ch.strip() else None))
            got = [g for g in got if g]
            if not got: continue
            unknown = [g for g in got if g not in decl and g != '_']
            order_ok = True
            idx = -1
            for g in got:
                if g == '_': continue
                j = decl.index(g) if g in decl else -1
                if j < idx: order_ok = False
                idx = max(idx, j)
            line = s[:pos].count('\n') + 1
            if unknown:
                problems.append(f'{p}:{line}  {name}(…)  وسائط غير موجودة: {unknown}')
            elif not order_ok:
                problems.append(f'{p}:{line}  {name}(…)  ترتيب مخالف للتعريف: {got}  |  التعريف: {decl}')

print(f'أنواع النواة المفهرسة: {len(core)}')
if problems:
    print(f'⚠️ {len(problems)} مشكلة:')
    for x in problems: print('  ✗', x)
else:
    print('✅ لا تعارض في الوسائط/الترتيب بين التطبيق والنواة')
