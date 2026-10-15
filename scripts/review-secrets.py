#!/usr/bin/env python3
"""Inspect only staged project text. Never scans personal files or prints matches."""
import re
import subprocess
from pathlib import Path
files = subprocess.check_output(['git', 'diff', '--cached', '--name-only', '-z']).decode().split('\0')
patterns = [r'gh[pousr]_[A-Za-z0-9]{20,}', r'github_pat_[A-Za-z0-9_]{20,}', r'sk-[A-Za-z0-9]{20,}', r'AKIA[0-9A-Z]{16}', r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----', r'/Us' + r'ers/(?!example(?:/|\b))[^/\s]+/', r'(?i)(?:password|token|secret)\s*[:=]\s*[\"\'][^\"\']{12,}[\"\']']
failed = []
for name in filter(None, files):
    content = subprocess.check_output(['git', 'show', ':' + name]).decode('utf-8')
    if any(re.search(pattern, content) for pattern in patterns):
        failed.append(name)
if failed:
    print('Review required for: ' + ', '.join(failed))
    raise SystemExit(1)
print(f'Staged source review: {len(list(filter(None, files)))} files; no configured secret/path pattern matches.')
