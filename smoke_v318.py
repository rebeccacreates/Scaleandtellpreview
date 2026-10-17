from pathlib import Path
from bs4 import BeautifulSoup
from playwright.sync_api import sync_playwright
import subprocess, time, urllib.request, json, zipfile, re
ROOT=Path(__file__).resolve().parents[1]
# The sandbox browser blocks network navigation. Route-independent runtime test via set_content.
for name in ['index.html','manifest.webmanifest','sw.js','privacy.html','deletion.html','icons/icon-180.png','icons/icon-192.png','icons/icon-512.png']:
 assert (ROOT/name).is_file()
manifest=json.loads((ROOT/'manifest.webmanifest').read_text());assert manifest['short_name']=='Scale & Tell'
try:
 with sync_playwright() as p:
  b=p.chromium.launch(headless=True,executable_path='/usr/bin/chromium',args=['--no-sandbox','--disable-dev-shm-usage'])
  page=b.new_page(viewport={'width':390,'height':844})
  # An in-memory localStorage stub avoids about:blank opaque-origin storage restrictions.
  html=(ROOT/'index.html').read_text()
  html=__import__('re').sub(r'<script[^>]*src="https://cdn\.jsdelivr\.net/[^"]+"[^>]*></script>', '', html, count=1)
  stub='<script>Object.defineProperty(window,"localStorage",{configurable:true,value:(()=>{const m=new Map();return {getItem:k=>m.has(k)?m.get(k):null,setItem:(k,v)=>m.set(k,String(v)),removeItem:k=>m.delete(k)}})()});</script>'
  html=html.replace('</head>',stub+'</head>',1)
  failures=[];page.on('pageerror',lambda e:failures.append(str(e)))
  page.set_content(html,wait_until='domcontentloaded',timeout=90000)
  page.wait_for_timeout(500)
  result=page.evaluate('''() => ({title:document.title,pushHour,html:founderStudioMarkup(),emptyBinder:founderDoc('binder'),emptyYear:founderDoc('year'),printables:founderDoc('printables'),import:importRecordsMarkup(),images:document.querySelectorAll('img[src^="data:image/webp"]').length})''')
  assert result['title']=='Scale & Tell | Keeper Beta'
  assert result['pushHour']==17
  assert '$14.99' in result['html'] and 'free' in result['html']
  assert 'Start with your first reptile' in result['emptyBinder']
  assert 'My Year in Scales' in result['emptyYear']
  assert 'Blank feeding record' in result['printables']
  assert 'Add your reptile first' in result['import']
  assert result['images']>3
  populated=page.evaluate('''() => {animals=['Oro'];species={Oro:'Ball Python'};profiles={Oro:{morph:'Enchi',sex:'Male'}};entries=[{animal:'Oro',section:'Feeding Tracker',date:'2026-10-15',detail:'Ate'},{animal:'Oro',section:'Calendar',date:'2026-10-18',detail:'Feeding reminder',done:false}];return {binder:founderDoc('binder'),year:founderDoc('year'),printables:founderDoc('printables'),import:importRecordsMarkup()}}''')
  assert 'Oro' in populated['binder'] and 'Enchi' in populated['binder'] and 'Feeding reminder' in populated['binder']
  assert 'Oro' in populated['year'] and 'Oro' in populated['printables']
  assert 'Screenshot transcription is not automated yet' in populated['import']
  # Simulate a failed server opt-out. The local subscription must remain untouched.
  disable=page.evaluate('''async () => {
     let unsubscribed=false;cloudSession={user:{id:'test'}};cloudClient={rpc:async()=>({error:{message:'offline'}})};pushDeviceEnabled=true;
     Object.defineProperty(navigator,'serviceWorker',{configurable:true,value:{getRegistration:async()=>({pushManager:{getSubscription:async()=>({endpoint:'https://fcm.googleapis.com/test',unsubscribe:async()=>{unsubscribed=true;return true}})}})}});
     const result=await pushDisable(true);return {result,unsubscribed,pushDeviceEnabled};
  }''')
  assert disable=={'result':False,'unsubscribed':False,'pushDeviceEnabled':True},disable
  synced=page.evaluate('''async () => {
     const calls=[];cloudClient={rpc:async(name,args)=>{calls.push({name,args});return {error:null}}};
     pushReady=true;notificationPrefs={feeding:true,shed:false,enclosure:true,other:false};
     Object.defineProperty(navigator,'serviceWorker',{configurable:true,value:{getRegistration:async()=>({pushManager:{getSubscription:async()=>({endpoint:'https://fcm.googleapis.com/test',toJSON:()=>({keys:{p256dh:'example',auth:'example'}})})}})}});
     await pushSyncPreferences();return calls;
  }''')
  assert synced and synced[0]['args']['p_categories']==['feeding','enclosure'],synced
  assert not failures, failures
  print('PASS: local package files, manifest, JS runtime, approved art, beta pricing, manual import text, empty/populated printables, failed opt-out, category sync')
  b.close()
finally:
 pass
