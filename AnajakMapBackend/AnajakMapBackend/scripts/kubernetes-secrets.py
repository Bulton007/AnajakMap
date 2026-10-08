"""Create an ignored local manifest without displaying secrets or applying it."""
import json
from pathlib import Path
root=Path(__file__).resolve().parent.parent
values={}
for line in (root/'.env').read_text().splitlines():
    if line and not line.startswith('#') and '=' in line:
        k,v=line.split('=',1);values[k]=v
items=[]
def secret(name,data):
    items.append({'apiVersion':'v1','kind':'Secret','metadata':{'name':name,'namespace':'anajakmap-local'},'type':'Opaque','stringData':data})
common=['REDIS_PASSWORD','RABBIT_USER','RABBIT_PASSWORD','OBJECT_ACCESS_KEY','OBJECT_SECRET_KEY','JWT_PUBLIC_KEY','DATA_ENCRYPTION_KEY','SERVICE_TOKEN']
for s in ['identity','trip','ai-guide','discovery','expense','reservation','journal','notification','gateway']:
    prefix=s.upper().replace('-','_')
    data={k:values[k] for k in common}
    if s=='identity':
        data['JWT_PRIVATE_KEY']=values['JWT_PRIVATE_KEY']
        for key in ['GMAIL_USERNAME','GMAIL_APP_PASSWORD','AUTH_TERMS_URL','AUTH_PRIVACY_URL','AUTH_POLICY_VERSION','AUTH_LINK_BASE','MAIL_PROVIDER_URL','MAIL_PROVIDER_KEY']:
            if values.get(key):data[key]=values[key]
    secret(f'{s}-service-secrets',{**data,'DB_PASSWORD':values[f'{prefix}_APP_PASSWORD']})
    secret(f'{s}-migration-secrets',{**data,'DB_PASSWORD':values[f'{prefix}_DB_PASSWORD']})
secret('infrastructure-secrets',{k:values[k] for k in ['REDIS_PASSWORD','RABBIT_USER','RABBIT_PASSWORD','OBJECT_ACCESS_KEY','OBJECT_SECRET_KEY']})
secret('oracle-secrets',{'ORACLE_PWD':values['ORACLE_PASSWORD'],**{k:v for k,v in values.items() if k.endswith('_DB_PASSWORD') or k.endswith('_APP_PASSWORD')}})
(root/'.local').mkdir(exist_ok=True)
out=root/'.local/kubernetes-secrets.json'
out.write_text(json.dumps({'apiVersion':'v1','kind':'List','items':items},indent=2))
out.chmod(0o600)
print('Prepared ignored .local/kubernetes-secrets.json. Nothing applied to any cluster.')
