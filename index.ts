/** Scale & Tell STAGING web-push sender.
 * Deployment: verify_jwt=false because this function validates user tokens for
 * config/test itself, and dispatch uses a *separate* 256-bit cron bearer secret.
 * Secrets are NEVER in the PWA, SQL migration, repository, or browser bundle.
 * Runtime uses new SUPABASE_*_KEYS JSON dictionaries (with legacy fallback).
 */
import { createClient } from 'npm:@supabase/supabase-js@2.57.4'
import webpush from 'npm:web-push@3.6.7'
import { timingSafeEqual } from 'node:crypto'

type Env = { url: string; publishable: string; service: string; publicVapid: string; privateVapid: string; subject: string; cron: string }
function namedKey(name: string): string {
  try {const value=JSON.parse(Deno.env.get(name)||'{}');return typeof value.default==='string'?value.default:''}catch{return ''}
}
function env(): Env { return {
  url: Deno.env.get('SUPABASE_URL') || '',
  publishable: namedKey('SUPABASE_PUBLISHABLE_KEYS') || Deno.env.get('SUPABASE_ANON_KEY') || '',
  service: namedKey('SUPABASE_SECRET_KEYS') || Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') || '',
  publicVapid: Deno.env.get('SCALE_PUSH_VAPID_PUBLIC') || '',
  privateVapid: Deno.env.get('SCALE_PUSH_VAPID_PRIVATE') || '',
  subject: Deno.env.get('SCALE_PUSH_SUBJECT') || '',
  cron: Deno.env.get('SCALE_PUSH_CRON_SECRET') || '',
} }
function equalSecret(a: string,b: string) {
  const left = new TextEncoder().encode(a),right=new TextEncoder().encode(b)
  return left.length === right.length && left.length>0 && timingSafeEqual(left,right)
}
const allowedOrigins = new Set([
  'https://rebeccacreates.github.io',
  'http://127.0.0.1:8766',
  'http://localhost:8766',
])
function cors(req: Request) {
  const origin = req.headers.get('origin') || ''
  return { 'Access-Control-Allow-Origin': allowedOrigins.has(origin) ? origin : 'https://rebeccacreates.github.io',
    'Vary':'Origin','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type',
    'Access-Control-Allow-Methods':'POST, OPTIONS','Cache-Control':'no-store' }
}
function reply(req: Request, body: unknown, status=200) {
  return new Response(JSON.stringify(body),{status,headers:{...cors(req),'Content-Type':'application/json'}})
}
function ready(e: Env) { return Boolean(e.url&&e.publishable&&e.service&&e.publicVapid&&e.privateVapid&&e.subject.startsWith('mailto:')&&e.cron.length>=32) }
function setupPush(e: Env) { webpush.setVapidDetails(e.subject,e.publicVapid,e.privateVapid) }
async function send(e: Env, sub: { endpoint:string; p256dh:string; auth_secret:string }, body: Record<string,string>) {
  setupPush(e)
  // Generic notification contents avoid publishing names/health notes on lock screens.
  await webpush.sendNotification({endpoint:sub.endpoint,keys:{p256dh:sub.p256dh,auth:sub.auth_secret}},JSON.stringify(body),{TTL:3600})
}
function codeOf(err: unknown) { const e=err as {statusCode?:number,status?:number};return Number(e?.statusCode||e?.status||0) }

export default {
  async fetch(req: Request) {
    if(req.method==='OPTIONS') return new Response(null,{status:204,headers:cors(req)})
    if(req.method!=='POST') return reply(req,{error:'Method not allowed'},405)
    const e=env()
    let input: Record<string,unknown>
    try { input=await req.json();if(!input || typeof input!=='object'||Array.isArray(input))throw Error() }
    catch {return reply(req,{error:'Invalid JSON'},400)}
    const action=input.action
    if(action!=='config'&&action!=='test'&&action!=='dispatch') return reply(req,{error:'Unknown action'},400)
    // Cron is separate from all user operations; there is no browser-authorized dispatch.
    if(action==='dispatch') {
      if(!ready(e)||!equalSecret((req.headers.get('authorization')||'').replace(/^Bearer /,''),e.cron))
        return reply(req,{error:'Unauthorized'},401)
      const admin=createClient(e.url,e.service,{auth:{persistSession:false,autoRefreshToken:false}})
      const {data:jobs,error}=await admin.rpc('care_push_claim_due',{p_limit:100})
      if(error)return reply(req,{error:'Delivery queue unavailable'},503)
      let sent=0,failed=0,disabled=0
      for(const job of jobs||[]) {
        try {
          await send(e,job,{title:'Scale & Tell ♡',body:'You have care due today. Open Care Schedule to review.',})
          const {error:finishError}=await admin.rpc('care_push_finish',{p_delivery_id:job.delivery_id,p_sent:true,p_gone:false,p_error:null})
          if(finishError)throw finishError
          sent++
        } catch(err) {
          const gone=[404,410].includes(codeOf(err))
          await admin.rpc('care_push_finish',{p_delivery_id:job.delivery_id,p_sent:false,p_gone:gone,p_error:gone?'Push endpoint expired':'Push service unavailable'})
          if(gone)disabled++;else failed++
        }
      }
      return reply(req,{processed:(jobs||[]).length,sent,failed,disabled})
    }
    // User routes NEVER treat the publishable browser key as authentication.
    const token=(req.headers.get('authorization')||'').match(/^Bearer (.+)$/i)?.[1]||''
    if(!token || !e.url || !e.publishable) return reply(req,{error:'Sign in required'},401)
    const userClient=createClient(e.url,e.publishable,{auth:{persistSession:false,autoRefreshToken:false},global:{headers:{Authorization:`Bearer ${token}`}}})
    const {data:{user},error:authError}=await userClient.auth.getUser(token)
    if(authError||!user) return reply(req,{error:'Sign in required'},401)
    if(action==='config') {
      if(!ready(e))return reply(req,{ready:false})
      const admin=createClient(e.url,e.service,{auth:{persistSession:false,autoRefreshToken:false}})
      const {error:dbError}=await admin.from('care_push_subscriptions').select('id').limit(1)
      return reply(req,dbError?{ready:false}:{ready:true,vapidPublic:e.publicVapid})
    }
    if(!ready(e)) return reply(req,{error:'Reminders are not configured'},503)
    const endpoint=input.endpoint
    if(typeof endpoint!=='string'||endpoint.length>2048)return reply(req,{error:'Invalid subscription'},400)
    // Rate limit and check the specific endpoint's owner inside the database.
    const {data:claimed,error:limitError}=await userClient.rpc('care_push_claim_test',{p_endpoint:endpoint})
    if(limitError)return reply(req,{error:'Test unavailable'},503)
    if(!claimed)return reply(req,{error:'Enable reminders first or wait one minute before another test'},429)
    const admin=createClient(e.url,e.service,{auth:{persistSession:false,autoRefreshToken:false}})
    const {data:sub,error:subError}=await admin.from('care_push_subscriptions')
      .select('endpoint,p256dh,auth_secret').eq('user_id',user.id).eq('endpoint',endpoint).eq('enabled',true).maybeSingle()
    if(subError||!sub)return reply(req,{error:'Subscription not found'},404)
    try {await send(e,sub,{title:'Scale & Tell test ♡',body:'Your phone reminder connection is working.'});return reply(req,{sent:true})}
    catch(err){return reply(req,{error:[404,410].includes(codeOf(err))?'Subscription expired. Turn reminders off and enable them again.':'Push service did not accept the test.'},502)}
  }
}
