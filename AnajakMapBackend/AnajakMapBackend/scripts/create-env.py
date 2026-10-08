import secrets,base64
from pathlib import Path
p=Path('.env.example').read_text()
for line in p.splitlines():
 if not line or line.startswith('#'):continue
 k,v=line.split('=',1)
 if k=='JWT_PUBLIC_KEY':v=base64.b64encode(Path('.local/jwt-public.der').read_bytes()).decode()
 elif k=='JWT_PRIVATE_KEY':v=base64.b64encode(Path('.local/jwt-private.der').read_bytes()).decode()
 elif k=='DATA_ENCRYPTION_KEY':v=base64.b64encode(secrets.token_bytes(32)).decode()
 elif k!='RABBIT_USER':v=secrets.token_hex(24)
 with Path('.env').open('a') as f:f.write(k+'='+v+'\n')
Path('.env').chmod(0o600)
