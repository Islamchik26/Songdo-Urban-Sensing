from pathlib import Path
import urllib.request, concurrent.futures
root=Path(__file__).parent
(root/'raw').mkdir(exist_ok=True)
def get(h):
 u=f'https://www.weather.go.kr/cgi-bin/aws/nph-aws_txt_min_cal_test?20251001{h:02d}00&0&MINDB_01M&512&m&1'
 p=root/'raw'/f'incheonyeonsu_512_20251001_{h:02d}00.html'
 if not p.exists():
  b=urllib.request.urlopen(u,timeout=60).read();p.write_bytes(b)
 print(h,p.stat().st_size,flush=True)
 return u
with concurrent.futures.ThreadPoolExecutor(3) as ex: urls=list(ex.map(get,range(18,24)))
(root/'source_urls.txt').write_text('\n'.join(urls)+'\n')
