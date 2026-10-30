import base64
import io
import json
import math
import os
import struct
import threading
import unittest
import urllib.error
import urllib.request
from copy import deepcopy
from unittest.mock import patch
import numpy as np
from PIL import Image
from http.server import ThreadingHTTPServer
from photo_parts.geometry import scalar, build_stl
from photo_parts.vision import analyze, validate_plan, prepare_images
from photo_parts.app import Handler, generate


def dimension(key,label=None):
    return {'id':key,'label':label or key,'help':'Die bezeichnete Strecke in Millimetern messen.','kind':'mm','choices':[],'image_index':0,'a':[.1,.5],'b':[.9,.5]}


def tube():
    return {'name':'Hülse','summary':'Hohle Hülse nach bestätigten Maßen.','status':'ready',
            'dimensions':[dimension('outer'),dimension('inner'),dimension('length')],
            'operations':[{'op':'add','kind':'cylinder','size':['outer','outer','length'],'position':['0','0','0'],'rotation':[0,0,0]},
                          {'op':'subtract','kind':'cylinder','size':['inner','inner','length+2'],'position':['0','0','0'],'rotation':[0,0,0]}],
            'assumptions':[],'blockers':[]}


def triangles(stl):
    count=struct.unpack_from('<I',stl,80)[0]
    return np.array([struct.unpack_from('<9f',stl,84+i*50+12) for i in range(count)]).reshape(-1,3,3)


class GeometryTests(unittest.TestCase):
    def test_real_closed_tube_with_hole_and_exact_dimensions(self):
        data=build_stl(tube(),{'outer':50,'inner':35,'length':60})
        tris=triangles(data);points=tris.reshape(-1,3)
        np.testing.assert_allclose(np.ptp(points,axis=0),[50,50,60],atol=.001)
        # Each undirected edge occurs twice; signed volume matches a polygonal
        # tube and is much smaller than a solid cylinder.
        vertices,index=np.unique(np.round(points,5),axis=0,return_inverse=True)
        faces=index.reshape(-1,3);edges=np.sort(np.concatenate([faces[:,[0,1]],faces[:,[1,2]],faces[:,[2,0]]]),axis=1)
        _,counts=np.unique(edges,axis=0,return_counts=True);self.assertTrue((counts==2).all())
        volume=np.einsum('ij,ij->i',tris[:,0],np.cross(tris[:,1],tris[:,2])).sum()/6
        expected_polygon_volume=32*math.sin(2*math.pi/64)*(25**2-17.5**2)*60
        self.assertAlmostEqual(volume,expected_polygon_volume,delta=.1)
    def test_real_worker_exports_stl(self):
        self.assertGreater(len(generate(tube(),{'outer':50,'inner':35,'length':60},True)),84)
    def test_no_code_execution_or_unbounded_math(self):
        for expr in ['__import__("os").system("id")','x[0]','2**100000','1/0','nan','1e300','True']:
            with self.subTest(expr=expr),self.assertRaises((ValueError,SyntaxError)):scalar(expr,{})
        self.assertEqual(scalar('length - 2*diameter',{'length':157,'diameter':8})[0],141)
    def test_missing_measurements_unlinked_values_and_approvals_are_rejected(self):
        p=tube()
        with self.assertRaises(ValueError):build_stl(p,{'outer':50,'inner':35})
        p['assumptions']=['Kanten ohne zusätzliche Verrundung.']
        with self.assertRaises(ValueError):build_stl(p,{'outer':50,'inner':35,'length':60})
        self.assertGreater(len(build_stl(p,{'outer':50,'inner':35,'length':60},True)),84)
        p=tube();p['dimensions'].append(dimension('unused'))
        with self.assertRaises(ValueError):build_stl(p,{'outer':50,'inner':35,'length':60,'unused':10})
        p=tube();p['blockers']=['Innenmaß größer als Außenmaß.']
        with self.assertRaises(ValueError):build_stl(p,{'outer':50,'inner':60,'length':60},True)
    def test_boolean_cut_can_form_open_clip_and_pin(self):
        plan=tube();plan['dimensions']=[dimension(k) for k in ['inside','gap','pin','pin_length']]
        plan['operations']=[
            {'op':'add','kind':'cylinder','size':['inside+2','inside+2','2'],'position':['0','0','0'],'rotation':[0,0,0]},
            {'op':'subtract','kind':'cylinder','size':['inside','inside','4'],'position':['0','0','0'],'rotation':[0,0,0]},
            {'op':'subtract','kind':'box','size':['5','gap','4'],'position':['2.5','0','0'],'rotation':[0,0,0]},
            {'op':'add','kind':'cylinder','size':['pin','pin','pin_length'],'position':['-5','0','0'],'rotation':[0,0,0]},
        ]
        self.assertGreater(len(build_stl(plan,{'inside':3,'gap':2,'pin':2.5,'pin_length':2})),84)


class VisionTests(unittest.TestCase):
    def photo(self):
        b=io.BytesIO();Image.new('RGB',(40,30),(200,180,150)).save(b,'PNG');return base64.b64encode(b.getvalue()).decode()
    def test_real_request_contract_uses_all_views_no_storage_and_strict_schema(self):
        result={'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':json.dumps(tube())}]}]}
        def respond(request,timeout):
            payload=json.loads(request.data)
            self.assertFalse(payload['store']);self.assertTrue(payload['text']['format']['strict'])
            self.assertEqual(payload['model'],'configured-vision-model')
            self.assertEqual(len(payload['input'][0]['content']),5)
            return io.BytesIO(json.dumps(result).encode())
        with patch('photo_parts.vision.urllib.request.urlopen',side_effect=respond):
            p=analyze([self.photo()]*4,{'outer':50,'inner':35,'length':60},None,'test-only-key','configured-vision-model')
        self.assertEqual(p['name'],'Hülse')
    def test_wrong_photo_counts_and_mutating_existing_questions_are_rejected(self):
        with self.assertRaises(ValueError):prepare_images([self.photo()]*3)
        with self.assertRaises(ValueError):prepare_images([self.photo()]*9)
        previous=tube();changed=deepcopy(previous);changed['dimensions'][0]['help']='Anderes Maß!'
        with self.assertRaises(ValueError):validate_plan(changed,4,previous)
        changed=tube();changed['dimensions'][0]['image_index']=8
        with self.assertRaises(ValueError):validate_plan(changed,4)
    def test_ready_plan_with_missing_answers_cannot_escape_measurement_stage(self):
        response={'status':'completed','output':[{'type':'message','content':[{'type':'output_text','text':json.dumps(tube())}]}]}
        with patch('photo_parts.vision.urllib.request.urlopen',return_value=io.BytesIO(json.dumps(response).encode())):
            with self.assertRaises(ValueError):analyze([self.photo()]*4,{},None,'test-only-key','configured-vision-model')


class HttpTests(unittest.TestCase):
    def test_service_rejects_unauthenticated_calls_and_unconfigured_vision(self):
        server=ThreadingHTTPServer(('127.0.0.1',0),Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        try:
            url='http://127.0.0.1:'+str(server.server_port)+'/v1/analyze'
            with patch.dict(os.environ,{'PHOTO_PART_ACCESS_TOKEN':'t'*32,'OPENAI_API_KEY':'','PHOTO_PART_MODEL':''}):
                with self.assertRaises(urllib.error.HTTPError) as denied:urllib.request.urlopen(urllib.request.Request(url,data=b'{}'))
                self.assertEqual(denied.exception.code,401)
                request=urllib.request.Request(url,data=b'{"answers":{}}',headers={'Authorization':'Bearer '+'t'*32})
                with self.assertRaises(urllib.error.HTTPError) as missing:urllib.request.urlopen(request)
                self.assertEqual(missing.exception.code,503)
        finally:server.shutdown();server.server_close();thread.join()


if __name__=='__main__':unittest.main()
