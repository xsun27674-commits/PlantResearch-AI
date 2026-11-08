import io
import json
import numpy as np
import pandas as pd
import pytest
from backend.test_app import c


def upload(df):
    stream = io.BytesIO()
    df.to_excel(stream, index=False)
    response = c.post('/api/data', files={'file': ('植物.xlsx', stream.getvalue())})
    assert response.status_code == 200
    return response.json()['id']


@pytest.mark.parametrize('kind', ['box', 'bar'])
def test_chinese_groups_and_missing(kind, monkeypatch):
    import matplotlib.axes
    captured = []
    method = 'bar' if kind == 'bar' else 'boxplot'
    original = getattr(matplotlib.axes.Axes, method)
    def capture(self, *args, **kwargs):
        captured.append(args)
        return original(self, *args, **kwargs)
    monkeypatch.setattr(matplotlib.axes.Axes, method, capture)
    df = pd.DataFrame({'处理组': ['对照组']*18+['处理组']*18,
                       '荧光焦点数': list(range(36)),
                       '相对荧光强度': [np.nan]+list(range(1,36)),
                       '细胞核面积': list(range(35))+[np.nan],
                       '重复': [1]*36, '植物': ['拟南芥']*36, '批次': ['一']*36})
    key = upload(df)
    for y, dropped in [('荧光焦点数',0), ('相对荧光强度',1), ('细胞核面积',1)]:
        response = c.post(f'/api/data/{key}/chart', json={'kind':kind,'x':'处理组','y':y})
        assert response.status_code == 200
        assert response.content.startswith(b'\x89PNG')
        report = json.loads(response.headers['X-Analysis-Parameters'])['analysis']
        assert report['dropped_rows'] == dropped
        assert report['used_rows'] == 36-dropped
        assert report['shown_groups'] == 2
    if kind == 'bar':
        assert captured[0][0] == ['对照组', '处理组']
        assert captured[0][1] == [8.5, 26.5]
    else:
        assert list(captured[0][0][0]) == list(range(18))
        assert list(captured[0][0][1]) == list(range(18,36))


@pytest.mark.parametrize('kind,x,y', [('scatter','处理组','值'),('bar','值','处理组'),('box','处理组','处理组'),('box','处理组',None)])
def test_incompatible_columns(kind,x,y):
    key=upload(pd.DataFrame({'处理组':['对照组','处理组'],'值':[1,2]}))
    response=c.post(f'/api/data/{key}/chart',json={'kind':kind,'x':x,'y':y})
    assert response.status_code == 400
    assert '数值列' in response.json()['detail']
    assert 'Unable to parse' not in response.text


def test_empty_pairs_and_unchanged_data():
    key=upload(pd.DataFrame({'处理组':['对照组',None],'值':[None,2]}))
    response=c.post(f'/api/data/{key}/chart',json={'kind':'box','x':'处理组','y':'值'})
    assert response.status_code == 400
    assert '没有可绘制' in response.json()['detail']
    from backend.app import frame
    assert frame(key)['值'].isna().sum() == 1


def test_scatter_filters_paired_missing_and_infinite():
    from backend.app import save
    # Stored frame uses the same JSON shape as an uploaded dataset.
    key=save('data',{'frame':{'columns':['x','y'],'index':[0,1,2,3],
                             'data':[[1,2],[None,3],[4,None],[5,float('inf')]]}})
    response=c.post(f'/api/data/{key}/chart',json={'kind':'scatter','x':'x','y':'y'})
    assert response.status_code == 200
    report=json.loads(response.headers['X-Analysis-Parameters'])['analysis']
    assert report['used_rows'] == 1 and report['dropped_rows'] == 3


def test_group_limit_is_reported():
    key=upload(pd.DataFrame({'处理组':[f'组{i}' for i in range(51)],'值':range(51)}))
    response=c.post(f'/api/data/{key}/chart',json={'kind':'bar','x':'处理组','y':'值'})
    assert response.status_code == 200
    report=json.loads(response.headers['X-Analysis-Parameters'])['analysis']
    assert report['total_groups'] == 51 and report['shown_groups'] == 50
    assert report['plotted_rows'] == 50 and report['dropped_rows'] == 0
