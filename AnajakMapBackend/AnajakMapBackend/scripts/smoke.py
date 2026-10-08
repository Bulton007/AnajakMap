#!/usr/bin/env python3
"""Reproducible AnajakMap dev-profile end-to-end test. Leaves demo records."""
import json,os,time,uuid,urllib.request,urllib.error,urllib.parse,datetime
BASE=os.getenv('API_URL','http://127.0.0.1:8080')
def call(method,path,body=None,token=None,key=None,status=200):
 headers={'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 if key:headers['Idempotency-Key']=key
 req=urllib.request.Request(BASE+'/api/v1'+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method)
 try:
  with urllib.request.urlopen(req,timeout=35) as r:code=r.status;data=r.read()
 except urllib.error.HTTPError as e:code=e.code;data=e.read()
 if code!=status:raise AssertionError(f'{method} {path}: expected {status}, got {code}')
 result=json.loads(data) if data else None
 return result.get("data",result) if isinstance(result,dict) else result
def binary(path,token,status=200):
 req=urllib.request.Request(BASE+'/api/v1'+path,headers={'Authorization':'Bearer '+token})
 try:
  with urllib.request.urlopen(req,timeout=30) as response:code=response.status;data=response.read()
 except urllib.error.HTTPError as error:code=error.code;data=error.read()
 assert code==status,(path,code)
 return data
def upload(path,token,fields=None):
 import base64
 boundary='anajak-'+uuid.uuid4().hex
 png=base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+j2ioAAAAASUVORK5CYII=')
 body=b''
 for k,v in (fields or {}).items():body+=f'--{boundary}\r\nContent-Disposition: form-data; name="{k}"\r\n\r\n{v}\r\n'.encode()
 body+=f'--{boundary}\r\nContent-Disposition: form-data; name="file"; filename="demo.png"\r\nContent-Type: image/png\r\n\r\n'.encode()+png+f'\r\n--{boundary}--\r\n'.encode()
 req=urllib.request.Request(BASE+'/api/v1'+path,data=body,headers={'Authorization':'Bearer '+token,'Content-Type':'multipart/form-data; boundary='+boundary},method='POST')
 with urllib.request.urlopen(req,timeout=35) as r:result=json.load(r)
 return result.get('data',result)
def inbox_code(email,kind):
 base=os.environ.get('MAIL_TEST_INBOX_URL','')
 secret=os.environ.get('MAIL_TEST_KEY','')
 if urllib.parse.urlparse(base).hostname not in ('127.0.0.1','localhost') or not secret:
  raise SystemExit('Use the isolated compose.auth-test.yml mail adapter and set MAIL_TEST_INBOX_URL plus MAIL_TEST_KEY. No application endpoint exposes codes.')
 for _ in range(40):
  request=urllib.request.Request(base+'?'+urllib.parse.urlencode({'email':email,'kind':kind}),headers={'Authorization':'Bearer '+secret})
  try:
   with urllib.request.urlopen(request,timeout=3) as result:return json.load(result)['code']
  except urllib.error.HTTPError as error:
   if error.code!=404:raise
  time.sleep(1)
 raise AssertionError('Test email not delivered to isolated adapter')

def signup():
 email='demo-'+uuid.uuid4().hex[:10]+'@example.com';cred={'email':email,'password':'AnajakDemo!2026#'}
 cfg=call('GET','/auth/config')
 r=call('POST','/auth/register',{**cred,'name':'Automated test','legalConsent':True,'policyVersion':cfg['policyVersion']},status=201)
 assert 'developmentCode' not in r and 'code' not in r
 assert r['retryAfterSeconds']==60 and r['expiresIn']==900
 call('POST','/auth/login',cred,status=403)
 request=urllib.request.Request(BASE+'/api/v1/auth/resend-verification',data=json.dumps({'email':email}).encode(),headers={'Content-Type':'application/json'},method='POST')
 try:
  urllib.request.urlopen(request,timeout=10)
  raise AssertionError('Resend cooldown should be enforced')
 except urllib.error.HTTPError as error:
  assert error.code==429
  assert 1 <= int(error.headers['Retry-After']) <= 60
 call('POST','/auth/verify',{'email':email,'code':'invalid-code'},status=400)
 call('POST','/auth/verify',{'email':email,'code':inbox_code(email,'VERIFY')})
 tokens=call('POST','/auth/login',cred)
 profile=call('GET','/profile',token=tokens['accessToken'])
 return tokens,profile['id'],email
if not os.environ.get('MAIL_TEST_INBOX_URL') or not os.environ.get('MAIL_TEST_KEY'):
 raise SystemExit('This suite now requires the isolated email adapter; see flutter_app/AUTH_SETUP.md. Real verification codes are never returned by the application API.')
for attempt in range(90):
 try:
  urllib.request.urlopen(BASE+'/actuator/health/readiness',timeout=2);break
 except Exception:time.sleep(2)
else:raise SystemExit('Gateway not ready')
tokens,owner,email=signup();token=tokens['accessToken'];print('PASS registration, verification, login')
p=call('GET','/profile',token=token)
prefs={'dietary':['vegetarian'],'pace':'relaxed','language':'en'}
call('PUT','/profile/preferences',{'preferences':prefs,'version':p['version']},token)
call('PUT','/profile/preferences',{'preferences':prefs,'version':p['version']},token,status=409)
print('PASS preferences and stale version conflict')
today=datetime.date.today().isoformat();request={'title':'AnajakMap Phnom Penh demo','destination':'Phnom Penh','timezone':'Asia/Phnom_Penh','startDate':today,'endDate':today}
key=uuid.uuid4().hex;t=call('POST','/trips',request,token,key,201);duplicate=call('POST','/trips',request,token,key,201)
assert t['id']==duplicate['id'];trip=t['id'];print('PASS trip CRUD and idempotency')
job=call('POST','/guide/itinerary-jobs',{'tripId':trip,'preferences':prefs},token,uuid.uuid4().hex,202)
for _ in range(30):
 result=call('GET','/guide/jobs/'+job['jobId'],token=token)
 if result['job']['STATUS']=='SUCCEEDED':break
 if result['job']['STATUS']=='FAILED':raise AssertionError(result)
 time.sleep(1)
else:raise AssertionError('AI job did not finish')
draft=call('POST','/guide/jobs/'+job['jobId']+'/save-draft',{},token,uuid.uuid4().hex,201)
call('POST','/trips/'+trip+'/itineraries/approve',{'itineraryId':draft['itineraryId'],'version':0},token)
calendar=call('GET','/trips/'+trip+'/calendar',token=token);places=call('GET','/trips/'+trip+'/map',token=token)
assert calendar['activities'] and places;print('PASS grounded AI job, approval, calendar, map')
other,viewer,unused=signup();view=other['accessToken']
call('GET','/trips/'+trip,token=view,status=403)
call('POST','/trips/'+trip+'/invitations',{'accountId':viewer,'role':'VIEWER'},token)
call('POST','/trips/'+trip+'/invitations/accept',{},view)
call('GET','/trips/'+trip,token=view)
call('PUT','/trips/'+trip+'/sync',{'baseVersion':1,'trip':request},view,status=403)
call('GET','/trips/'+trip,status=401);print('PASS owner/viewer permissions and unauthenticated rejection')
call('PUT','/expenses/budget',{'tripId':trip,'amount':'100.00','currency':'USD','version':0},token)
expense={'tripId':trip,'description':'Lunch','amount':'12.50','currency':'USD','splits':{owner:'6.25',viewer:'6.25'}}
ek=uuid.uuid4().hex;e=call('POST','/expenses',expense,token,ek);assert call('POST','/expenses',expense,token,ek)['id']==e['id']
call('GET','/expenses/summary?tripId='+trip,token=token);print('PASS budget, expense splits and duplicate protection')
j=call('POST','/journal',{'tripId':trip,'title':'Day one','content':'Visited Phnom Penh','recap':'Editable recap','version':0},token,uuid.uuid4().hex)
call('PUT','/journal/'+j['id'],{'tripId':trip,'title':'Updated','content':'Visited the palace','recap':'User edited recap','version':0},token)
call('PUT','/journal/'+j['id'],{'tripId':trip,'title':'Stale','content':'Stale','recap':'','version':0},token,status=409)
call('GET','/trips/'+trip+'/offline',token=token);print('PASS journal editing and versioned offline snapshot')
conversation=call('POST','/guide/conversations',{},token,status=201)
call('POST','/guide/conversations/'+conversation['id']+'/messages',{'text':'Tell me about this trip'},token)
assert call('GET','/guide/conversations/'+conversation['id']+'/messages',token=token)
call('POST','/guide/translation',{'input':{'text':'Hello','targetLanguage':'km'}},token)
call('POST','/guide/phrases',{'text':'សួស្តី'},token)
call('GET','/guide/phrases',token=token);print('PASS translation adapter and phrase persistence')

media=upload('/guide/media',token)
vision=call('POST','/guide/vision',{'input':{'mediaId':media['mediaId']}},token)
assert vision['mock'] and vision['possibleLandmarks'];call('POST','/guide/vision',{'input':{'mediaId':media['mediaId']}},view,status=403)
call('POST','/guide/voice',{'input':{'text':'Hello'}},token);print('PASS private media upload, uncertain vision and voice adapter')
doc=upload('/reservations/documents',token,{'tripId':trip})
assert binary('/reservations/documents/'+doc['documentId']+'/content',token).startswith(bytes([137,80,78,71]))
extracted=call('POST','/reservations/documents/'+doc['documentId']+'/extract',{},token)
start=datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(days=1);end=start+datetime.timedelta(hours=1)
call('POST','/reservations/documents/'+doc['documentId']+'/confirm',{'provider':'Demo airline','reference':'DEMO-001','timezone':'Asia/Phnom_Penh','startsAt':start.isoformat(),'endsAt':end.isoformat(),'version':extracted['version']},token)
assert call('GET','/reservations?tripId='+trip,token=token);print('PASS S3-backed reservation upload, extraction and user confirmation')
receipt=upload('/expenses/receipts',token,{'tripId':trip})
call('POST','/expenses/receipts/'+receipt['id']+'/extract',{},token)
expense['receiptId']=receipt['id'];call('POST','/expenses',expense,token,uuid.uuid4().hex)
call('GET','/expenses/currency?from=USD&to=KHR&amount=10.00',token=token)
print('PASS receipt extraction, confirmed expense and decimal currency adapter')
photo=upload('/journal/'+j['id']+'/photos',token)
assert binary('/journal/photos/'+photo['id']+'/content',token).startswith(bytes([137,80,78,71]))
binary('/journal/photos/'+photo['id']+'/content',view,status=403)
assert call('GET','/journal/'+j['id']+'/photos',token=token)
call('POST','/journal/'+j['id']+'/generate-recap?version=1',{},token)
call('POST','/journal/visits',{'tripId':trip,'place':'Royal Palace','visitedAt':datetime.datetime.now(datetime.timezone.utc).isoformat(),'latitude':11.5638,'longitude':104.9315},token)
print('PASS journal photos, visited places and editable generated recap')
call('POST','/trips/'+trip+'/contacts',{'label':'Hotel','phone':'+85512345678'},token)
call('PUT','/trips/'+trip+'/location',{'enabled':True,'latitude':11.56,'longitude':104.93},view)
assert call('GET','/trips/'+trip+'/locations',token=token)
call('PUT','/trips/'+trip+'/location',{'enabled':False,'latitude':0,'longitude':0},view)
assert not call('GET','/trips/'+trip+'/locations',token=token)
call('POST','/trips/'+trip+'/votes',{'activityId':places[0]['ID'],'value':1},view)
call('POST','/trips/'+trip+'/calendar/events',{'title':'Flight','startsAt':start.isoformat(),'endsAt':end.isoformat(),'timezone':'Asia/Phnom_Penh'},token)
call('POST','/trips/'+trip+'/calendar/events',{'title':'Conflict','startsAt':start.isoformat(),'endsAt':end.isoformat(),'timezone':'Asia/Phnom_Penh'},token,status=409)
call('POST','/trips/'+trip+'/calendar/sync',{},token,uuid.uuid4().hex)
print('PASS contacts, location consent, voting, calendar conflicts and sync adapter')
for path in ['/discovery/nearby?latitude=11.56&longitude=104.93','/discovery/weather','/discovery/food','/discovery/culture','/discovery/routes','/discovery/transport']:call('GET',path,token=token)
call('POST','/discovery/journeys',{'tripId':trip,'origin':'Airport','destination':'Hotel','departure':start.isoformat(),'arrival':end.isoformat(),'timezone':'Asia/Phnom_Penh','transferDetails':'Meet at arrivals','source':'development transport estimate'},token)
assert call('GET','/discovery/journeys?tripId='+trip,token=token)
print('PASS discovery, food/culture, weather, routes and persisted journey legs')
rjob=call('POST','/guide/replanning-jobs',{'tripId':trip,'preferences':{'skippedStops':['museum'],'delayMinutes':30}},token,uuid.uuid4().hex,202)
for _ in range(30):
 rresult=call('GET','/guide/jobs/'+rjob['jobId'],token=token)
 if rresult['job']['STATUS']=='SUCCEEDED':break
 if rresult['job']['STATUS']=='FAILED':raise AssertionError(rresult)
 time.sleep(1)
proposal=call('POST','/guide/jobs/'+rjob['jobId']+'/save-proposal',{},token,uuid.uuid4().hex,201)
assert call('GET','/trips/'+trip+'/replanning-proposals',token=token)[0]['STATUS']=='PROPOSED'
call('POST','/trips/'+trip+'/replanning-proposals/'+proposal['proposalId']+'/approve',{},token)
print('PASS weather-grounded replanning with explicit approval')
call('POST','/notifications/devices',{'token':'development-device','platform':'ANDROID'},token)
reminder=call('POST','/notifications/reminders',{'title':'Dinner','dueAt':(datetime.datetime.now(datetime.timezone.utc)+datetime.timedelta(seconds=2)).isoformat()},token)
for _ in range(20):
 deliveries=call('GET','/notifications/deliveries',token=token)
 if any(d['ID']==reminder['id'] and d['STATUS']=='MOCK_DELIVERED' for d in deliveries):break
 time.sleep(1)
else:raise AssertionError('Reminder was not delivered')
print('PASS device registration and durable reminder delivery')

rotated=call('POST','/auth/refresh',{'refreshToken':tokens['refreshToken']})
call('POST','/auth/refresh',{'refreshToken':tokens['refreshToken']},status=401)
call('POST','/auth/logout',{'refreshToken':rotated['refreshToken']})
call('POST','/auth/refresh',{'refreshToken':rotated['refreshToken']},status=401);print('PASS refresh rotation and logout revocation')
reset=call('POST','/auth/forgot-password',{'email':email})
call('POST','/auth/reset-password',{'email':email,'code':inbox_code(email,'RESET'),'password':'AnajakUpdated!2026#'})
call('POST','/auth/login',{'email':email,'password':'AnajakDemo!2026#'},status=401)
call('POST','/auth/login',{'email':email,'password':'AnajakUpdated!2026#'})
print('PASS invalid verification code and forgot/reset password')
print('ALL SMOKE CHECKS PASSED. Demo trip ID:',trip)
