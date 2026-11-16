#!/usr/bin/env python3
"""Compare the agreed 10 and 30 RPS cases through verified lab HTTPS."""
import concurrent.futures,datetime,http.client,json,os,pathlib,socket,ssl,subprocess,threading,time,urllib.parse,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
os.chdir(ROOT)
os.environ['KUBECONFIG']=str(ROOT/'.state/artifacts/admin.conf')
os.umask(0o077)
K=str(ROOT/'.state/artifacts/kubectl')
folder=ROOT/'.state/capacity'/datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
folder.mkdir(parents=True)
ctx=ssl.create_default_context(cafile='.state/tls/ca.crt')
local=threading.local()
def now():return datetime.datetime.now(datetime.timezone.utc).isoformat()
class Connection(http.client.HTTPSConnection):
    def connect(self):
        sock=socket.create_connection(('192.168.56.10',443),timeout=3,source_address=('192.168.56.1',0))
        self.sock=ctx.wrap_socket(sock,server_hostname='app.dpg.test')
def get_resource(*args):
    return json.loads(subprocess.check_output([K,*args,'-o','json'],text=True))
def query(expr):
    url='http://127.0.0.1:19097/api/v1/query?'+urllib.parse.urlencode({'query':expr})
    return json.load(urllib.request.urlopen(url,timeout=5))['data']['result']
queries={
 'cpu_cores':'sum by(container)(rate(container_cpu_usage_seconds_total{namespace="dpg-app",pod=~"app-(nginx|php)-.*",container=~"nginx|php|exporter"}[1m]))',
 'memory_bytes':'sum by(container)(container_memory_working_set_bytes{namespace="dpg-app",pod=~"app-(nginx|php)-.*",container=~"nginx|php|exporter"})',
 'hpa_current':'kube_horizontalpodautoscaler_status_current_replicas{namespace="dpg-app"}',
 'hpa_desired':'kube_horizontalpodautoscaler_status_desired_replicas{namespace="dpg-app"}',
 'php_queue':'sum(phpfpm_listen_queue{namespace="dpg-app"})',
 'php_active':'sum(phpfpm_active_processes{namespace="dpg-app"})',
}
def snapshot():return {'time':now(),**{name:query(q) for name,q in queries.items()}}
def request():
    start=time.monotonic();stamp=now();code=0;valid=False;error=None
    try:
        if not getattr(local,'connection',None):local.connection=Connection('app.dpg.test',context=ctx,timeout=3)
        c=local.connection;c.request('GET','/');response=c.getresponse();body=response.read();code=response.status
        if code==200:
            data=json.loads(body);valid=data.get('service')=='digipay-sre-lab' and data.get('client_ip')=='192.168.56.1'
    except Exception as exc:
        error=type(exc).__name__
        if getattr(local,'connection',None):local.connection.close();local.connection=None
    return {'time':stamp,'code':code,'valid_json_and_ip':valid,'seconds':time.monotonic()-start,'error':error}
def percentile(values,q):return sorted(values)[max(0,int(len(values)*q+0.999)-1)]

def main():
    nodes=get_resource('get','nodes')['items']
    assert len(nodes)==3 and all(any(c['type']=='Ready' and c['status']=='True' for c in n['status']['conditions']) for n in nodes)
    deployments=get_resource('-n','dpg-app','get','deployments')
    assert all(d['status'].get('readyReplicas',0)>=2 for d in deployments['items'])
    (folder/'before-deployments.json').write_text(json.dumps(deployments,indent=2)+'\n')
    forward=None;results=[];all_samples=[]
    try:
        with (folder/'forward.log').open('w') as log:
            forward=subprocess.Popen([K,'-n','monitoring','port-forward','service/monitoring-kube-prometheus-prometheus','19097:9090'],stdout=log,stderr=log)
        for _ in range(30):
            try:query('up');break
            except OSError:time.sleep(0.5)
        for rps in [10,30]:
            print(f'{now()} starting {rps} RPS for 120 seconds',flush=True)
            rows=[];metrics=[snapshot()];missed=0;inflight=set();start=time.monotonic()
            with concurrent.futures.ThreadPoolExecutor(max_workers=16) as pool:
                for index in range(rps*120):
                    due=start+index/rps;time.sleep(max(0,due-time.monotonic()))
                    done={f for f in inflight if f.done()}
                    for f in done:rows.append(f.result())
                    inflight-=done
                    if time.monotonic()-due>1/rps or len(inflight)>=16:missed+=1
                    else:inflight.add(pool.submit(request))
                for f in concurrent.futures.as_completed(inflight):rows.append(f.result())
            elapsed=time.monotonic()-start;metrics.append(snapshot())
            values=[x['seconds'] for x in rows]
            summary={'rps_target':rps,'duration_target_seconds':120,'started_at':metrics[0]['time'],'ended_at':now(),'requests':len(rows),'scheduler_missed':missed,'elapsed_seconds':elapsed,'achieved_rps':len(rows)/elapsed,'codes':{str(c):sum(x['code']==c for x in rows) for c in sorted({x['code'] for x in rows})},'functional_errors':sum(not x['valid_json_and_ip'] for x in rows),'latency_above_300ms':sum(x['seconds']>0.3 for x in rows),'p50_seconds':percentile(values,.5),'p95_seconds':percentile(values,.95),'p99_seconds':percentile(values,.99),'max_seconds':max(values),'metrics':metrics}
            results.append(summary);all_samples.extend({'rps_target':rps,**x} for x in rows)
            print(json.dumps({k:v for k,v in summary.items() if k!='metrics'}),flush=True)
        (folder/'after-deployments.json').write_text(json.dumps(get_resource('-n','dpg-app','get','deployments'),indent=2)+'\n')
    finally:
        if forward:forward.terminate();forward.wait(timeout=10)
        (folder/'results.json').write_text(json.dumps({'measured_at':now(),'method':'Fixed-rate schedule; up to 16 in-flight HTTP/1.1 keep-alive connections. Verified TLS and client IP. Metrics snapshots before/after each stage; CPU uses trailing 1m rates.','stages':results},indent=2)+'\n')
        (folder/'requests.jsonl').write_text(''.join(json.dumps(x)+'\n' for x in all_samples))
        print('Evidence: '+str(folder.relative_to(ROOT)),flush=True)
    assert len(results)==2 and all(s['functional_errors']==0 and s['scheduler_missed']==0 and s['latency_above_300ms']==0 for s in results),'See measured results; target case did not pass all checks'
if __name__=='__main__':main()
