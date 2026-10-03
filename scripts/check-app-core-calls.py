import re, glob

core_files = glob.glob('FieldwatchCore/Sources/FieldwatchCore/*.swift')
core = "\n".join(open(p, encoding='utf-8').read() for p in core_files)

# فهرس: Type.func ⇒ [labels]
decls = {}
for m in re.finditer(r'(?:public |internal )?(?:static )?func\s+(\w+)\s*\(', core):
    pass
# نلتقط بدقة: داخل enum/struct/class، الدوال العامة
for tm in re.finditer(r'public (?:enum|struct|final class|class)\s+(\w+)', core):
    tname = tm.group(1)
    # مقطع النوع حتى النوع التالي (تقريبي)
    nxt = re.search(r'\npublic (?:enum|struct|final class|class)\s+\w+', core[tm.end():])
    body = core[tm.end(): tm.end() + (nxt.start() if nxt else 20000)]
    for fm in re.finditer(r'public (?:static )?func\s+(\w+)\s*\(', body):
        fname = fm.group(1)
        i, depth, buf = fm.end(), 1, ''
        while i < len(body) and depth > 0:
            c = body[i]
            if c in '([{': depth += 1
            elif c in ')]}': depth -= 1
            if depth > 0: buf += c
            i += 1
        d, cur, chunks = 0, '', []
        for ch in buf:
            if ch in '([{<': d += 1
            elif ch in ')]}>': d -= 1
            if ch == ',' and d == 0: chunks.append(cur); cur = ''
            else: cur += ch
        chunks.append(cur)
        labels = []
        for c in chunks:
            lm = re.match(r'\s*_?\s*(\w+)\s*:', c)
            live = re.match(r'\s*(\w+)\s*:', c)
            if live: labels.append(live.group(1))
            elif c.strip(): labels.append('_')
        if labels and labels[-1] == '_': labels.pop()
        decls.setdefault(tname, {})[fname] = labels

problems = []
for p in sorted(glob.glob('FieldwatchApp/Sources/*.swift')):
    s = open(p, encoding='utf-8').read()
    for tm in re.finditer(r'\b([A-Z]\w{3,})\.(\w+)\s*\(', s):
        t, fn = tm.group(1), tm.group(2)
        if t not in decls or fn not in decls[t]: continue
        decl = decls[t][fn]
        i, depth, buf = tm.end(), 1, ''
        while i < len(s) and depth > 0:
            c = s[i]
            if c in '([{': depth += 1
            elif c in ')]}': depth -= 1
            if depth > 0: buf += c
            i += 1
        d, cur, chunks = 0, '', []
        for ch in buf:
            if ch in '([{<': d += 1
            elif ch in ')]}>': d -= 1
            if ch == ',' and d == 0: chunks.append(cur); cur = ''
            else: cur += ch
        chunks.append(cur)
        got = []
        for c in chunks:
            lm = re.match(r'\s*(\w+)\s*:', c)
            got.append(lm.group(1) if lm else '_')
        if got and got[-1] == '_' and decl and decl[-1] != '_': got.pop()  # closure أخير
        got = [g for g in got if g != '_']
        if not got: continue
        unknown = [g for g in got if g not in decl]
        line = s[:tm.start()].count('\n') + 1
        if unknown:
            problems.append(f'{p}:{line}  {t}.{fn}(…) وسائط غير معروفة: {unknown} | التعريف: {decl}')

print(f'دوال النواة المفهرسة: {sum(len(v) for v in decls.values())} في {len(decls)} نوعًا')
if problems:
    print(f'⚠️ {len(problems)}:')
    for x in problems: print('  •', x)
else:
    print('✅ كل نداءات دوال النواة تطابق تعريفاتها')
