# تصدير للقراءة فقط (GET فقط) لمجموعات الموظفين/المصروفات/الرواتب من Appwrite إلى /tmp/appwrite_snapshot.
# المتغيرات: AW_ENDPOINT AW_PROJECT AW_DB AW_KEY (مفتاح قراءة فقط) — لا تضع المفتاح في المستودع.
# الاستخدام: mkdir -p /tmp/appwrite_snapshot && python3 readonly_export_salary_links.py
# Read-only export: GET requests only.
import os, json, urllib.request, urllib.parse, datetime
E=os.environ; base=f"{E['AW_ENDPOINT']}/databases/{E['AW_DB']}/collections"
H={'X-Appwrite-Project':E['AW_PROJECT'],'X-Appwrite-Key':E['AW_KEY']}
def get(url):
    req=urllib.request.Request(url,headers=H,method='GET')
    with urllib.request.urlopen(req,timeout=60) as r: return json.load(r)
stamp=datetime.datetime.utcnow().strftime('%Y%m%dT%H%M%SZ')
for col in ['employees','expenses','salary_withdrawals','salary_cycles','salary_payments','salary_carry_over_logs']:
    docs=[]; cursor=None
    while True:
        q=[json.dumps({'method':'limit','values':[500]}), json.dumps({'method':'orderAsc','attribute':'$id'})]
        if cursor: q.append(json.dumps({'method':'cursorAfter','values':[cursor]}))
        url=f"{base}/{col}/documents?"+urllib.parse.urlencode([('queries[]',x) for x in q])
        d=get(url); batch=d['documents']; docs+=batch
        if len(batch)<500: break
        cursor=batch[-1]['$id']
    attrs=get(f"{base}/{col}/attributes?"+urllib.parse.urlencode([('queries[]',json.dumps({'method':'limit','values':[200]}))]))
    json.dump({'collection':col,'exported_at':stamp,'total':d['total'],'documents':docs,'attributes':attrs['attributes']},open(f"/tmp/appwrite_snapshot/{col}.json",'w'),ensure_ascii=False)
    print(col, len(docs), 'total=',d['total'])
