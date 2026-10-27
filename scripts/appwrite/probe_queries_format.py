#!/usr/bin/env python3
"""Probe v4: cursor pagination with JSON-object queries (read-only)."""
import json
import os
import urllib.parse
import urllib.request
import urllib.error

ENDPOINT = 'https://fra.cloud.appwrite.io/v1'
PROJECT = '6a4408f300217885fd7b'
DATABASE = '6a4409b50019dd39dde5'
KEY = os.environ.get('APPWRITE_API_KEY', '')

base = f'/databases/{DATABASE}/collections/salary_withdrawals/documents'


def call(qparams, label):
    req = urllib.request.Request(ENDPOINT + base + '?' + urllib.parse.urlencode(qparams),
                                 method='GET', headers={
        'X-Appwrite-Project': PROJECT,
        'X-Appwrite-Key': KEY,
        'Content-Type': 'application/json',
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            body = json.load(resp)
        docs = body.get('documents', [])
        print(f'  {label}: 200 OK total={body.get("total")} n={len(docs)}'
              + (f' first={docs[0]["$id"][:12]} last={docs[-1]["$id"][:12]}' if docs else ''))
        return body
    except urllib.error.HTTPError as e:
        msg = e.read().decode('utf-8', 'replace')[:110]
        print(f'  {label}: {e.code} {msg}')
        return None


L100 = ('queries[]', json.dumps({'method': 'limit', 'values': [100]}))
p1 = call([L100], 'page1 limit100')
if p1 and p1.get('documents'):
    cursor = p1['documents'][-1]['$id']
    p2 = call([L100, ('queries[]', json.dumps({'method': 'cursorAfter', 'values': [cursor]}))],
              f'page2 cursorAfter({cursor[:12]}..)')
    if p2:
        ids1 = {d['$id'] for d in p1['documents']}
        ids2 = {d['$id'] for d in p2['documents']}
        print(f'  overlap={len(ids1 & ids2)} (want 0) | page2 n={len(p2["documents"])}')
    # check attribute presence on a doc
    d0 = p1['documents'][0]
    print('  doc keys sample:', sorted(d0.keys()))
