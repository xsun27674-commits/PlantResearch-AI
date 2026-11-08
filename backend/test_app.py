import io
import os
import tempfile
os.environ['PLANT_DATA_DIR']=tempfile.mkdtemp()
from fastapi.testclient import TestClient
import pymupdf as fitz
import pandas as pd
from backend.app import app
c=TestClient(app)
def test_pdf():
    doc=fitz.open(); page=doc.new_page(); page.insert_text((72,72),'Arabidopsis research. DOI 10.1234/plant.2026')
    r=c.post('/api/papers',files={'file':('paper.pdf',doc.tobytes(),'application/pdf')}); assert r.status_code==200
    p=r.json(); assert 'Arabidopsis' in p['pages'][0]['text']; assert p['doi_candidates']==['10.1234/plant.2026']
    assert c.get('/api/results/'+p['id']+'/download').status_code==200

def test_excel_statistics_charts_exports():
    out=io.BytesIO(); pd.DataFrame({'group':['A','A','B'],'value':[1,3,5],'height':[2,4,7]}).to_excel(out,index=False)
    r=c.post('/api/data',files={'file':('test.xlsx',out.getvalue())}); assert r.status_code==200
    d=r.json(); assert d['rows']==3 and d['preview'][0]['value']==1; assert d['statistics']['value']['mean']==3
    for kind,x in [('bar','group'),('scatter','height'),('box','value'),('heatmap','value')]:
        chart=c.post(f"/api/data/{d['id']}/chart",json={'kind':kind,'x':x,'y':'value'}); assert chart.status_code==200; assert chart.content.startswith(b'\x89PNG')
    xlsx=c.get(f"/api/results/{d['id']}/download?format=xlsx"); assert not pd.read_excel(io.BytesIO(xlsx.content)).empty
    assert c.get(f"/api/results/{d['id']}/download").status_code==200
    assert c.post(f"/api/data/{d['id']}/chart",json={'kind':'execute','x':'value'}).status_code==400

def test_errors_and_no_key(monkeypatch):
    monkeypatch.delenv('DEEPSEEK_API_KEY',raising=False)
    assert c.post('/api/assistant',json={'message':'分析'}).status_code==503
    assert c.post('/api/papers',files={'file':('bad.pdf',b'bad')}).status_code==400
    assert c.post('/api/data',files={'file':('bad.exe',b'bad')}).status_code==400
    assert c.get('/api/results/unknown/download').status_code==404

def test_provider_failure(monkeypatch):
    monkeypatch.setenv('DEEPSEEK_API_KEY','test-only')
    import httpx
    async def fail(*args,**kwargs): raise httpx.ConnectError('test')
    monkeypatch.setattr(httpx.AsyncClient,'post',fail)
    r=c.post('/api/assistant',json={'message':'分析'}); assert r.status_code==502; assert '模型服务调用失败' in r.json()['detail']

def test_local_assistant_tool(monkeypatch):
    monkeypatch.delenv('DEEPSEEK_API_KEY',raising=False)
    d=c.post('/api/data',files={'file':('test.csv',b'value\n1\n3\n')}).json()
    r=c.post('/api/assistant',json={'message':'请检查缺失值和描述性统计','data_id':d['id']})
    assert r.status_code==200 and r.json()['provider']=='local'
    assert '非AI生成' in r.json()['answer']
