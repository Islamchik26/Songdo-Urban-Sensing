from pathlib import Path
import re,html,csv,json,hashlib
from datetime import datetime,timezone,timedelta
root=Path(__file__).parent
rows={}; duplicate_count=0
for p in sorted((root/'raw').glob('incheonyeonsu_512_*.html')):
 s=p.read_bytes().decode('euc-kr')
 assert '인천연수 512' in s
 for line in s.splitlines():
  m=re.search(r'stn_tm_select\(\d+,(\d{12})\)',line)
  if not m:continue
  cells=[html.unescape(re.sub('<[^>]*>','',x)).strip() for x in re.findall(r'<td[^>]*>(.*?)</td>',line,re.I)]
  assert len(cells)==16,(p,cells)
  ts=datetime.strptime(m[1],'%Y%m%d%H%M').replace(tzinfo=timezone(timedelta(hours=9)))
  windspeed=float(cells[10]);winddir=cells[8] if windspeed>0 else ''
  r=[ts.astimezone(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),'512',cells[7],cells[14],cells[10],winddir,'',cells[15],ts.isoformat(),cells[8],cells[9],cells[11],cells[13]]
  if m[1] in rows:
   assert rows[m[1]]==r;duplicate_count+=1
  rows[m[1]]=r
out=[rows[k] for k in sorted(rows)]
assert len(out)==361,len(out)
assert all(datetime.fromisoformat(b[0])-datetime.fromisoformat(a[0])==timedelta(minutes=1) for a,b in zip(out,out[1:]))
fields=['TIMESTAMP_UTC','STATION_ID','AIR_TEMP_C','REL_HUMIDITY_PCT','WIND_SPEED_MPS','WIND_FROM_DEG','STATION_PRESSURE_HPA','SEA_LEVEL_PRESSURE_HPA','TIMESTAMP_ORIGINAL_KST','WIND_FROM_DEG_RAW','WIND_COMPASS_RAW','WIND_10MIN_FROM_DEG_RAW','WIND_10MIN_SPEED_MPS_RAW']
with (root/'kma_observations.csv').open('w',newline='') as f:
 w=csv.writer(f);w.writerow(fields);w.writerows(out)
meta={'station_id':'512','station_name':'Incheonyeonsu (인천연수)','network':'KMA AWS (not ASOS)','data_kind':'official_observations','source_url':(root/'source_urls.txt').read_text().splitlines()[0],'source_urls':(root/'source_urls.txt').read_text().splitlines(),'station_metadata_url':'https://data.kma.go.kr/tmeta/stn/selectStnDetail.do?isSelectStn=Y&pgmNo=82&stdStnNo=512','timezone':'UTC','original_timezone':'Asia/Seoul (KST, UTC+09:00)','cadence_seconds':60,'sample_count':len(out),'start_utc':out[0][0],'end_utc':out[-1][0],'retrieval_date_utc':'2026-10-22','retrieval_timestamp_note':'Original downloads occurred on this UTC date; exact per-response receipt timestamps were not logged.','latitude':37.39684,'longitude':126.66209,'station_ground_elevation_m':8.13,'pressure_elevation_m':None,'units':{'AIR_TEMP_C':'degrees Celsius','REL_HUMIDITY_PCT':'percent','WIND_SPEED_MPS':'m/s, original 1-minute mean wind','WIND_FROM_DEG':'degrees clockwise from north, original numeric 1-minute wind direction','STATION_PRESSURE_HPA':'hPa, NOT AVAILABLE','SEA_LEVEL_PRESSURE_HPA':'hPa'},'processing':['Parsed official public table, preserved original HTML byte-for-byte.','Sorted actual minute samples by timestamp and removed '+str(duplicate_count)+' identical overlapping hour-boundary records.','Converted KST timestamps to UTC without changing sampling interval.','Retained raw numeric wind direction and 10-minute wind fields in extra columns.','Set WIND_FROM_DEG blank when wind speed is zero; raw published direction remains WIND_FROM_DEG_RAW.','No interpolation, random input, upsampling, pressure reconstruction, or invented observations.'],'limitations':['Public display table has no station pressure or QC flags; absence of flags does not assert full quality control.','Sea-level pressure cannot be used as station pressure, and no independent pressure-reduction validation is possible.','8.13m is station ground elevation, not verified barometer elevation.','Minute wind averages do not provide 10Hz turbulence measurements.','Historical station coordinates are not date-specific verified relocation history.'],'raw_sha256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/'raw').glob('*.html'))}}
meta.update({'wind_definition_source_url': 'https://bd.kma.go.kr/contest/faq_view.do', 'wind_definition_reference': 'KMA FAQ Q15: wind direction is where wind comes from; Q16: north0/360 degrees and clockwise east90, west270; minute observations can have0.1degree resolution.', 'attribution': 'Source: Korea Meteorological Administration (KMA), Incheonyeonsu AWS512 minute observations,2025-10-01. Downloaded2026-10-22; UTC conversion and calm-direction normalization documented here.', 'copyright_policy_url': 'https://data.kma.go.kr/cmmn/static/staticPage.do?page=pageCr', 'licensing_note': 'No explicit dataset-specific license badge appears in the downloaded legacy observation tables. The KMA portal copyright policy describes KOGL Type1 for marked KMA-owned works; no specific KOGL designation is asserted for these unmarked tables.'})
(root/'kma_provenance.json').write_text(json.dumps(meta,ensure_ascii=False,indent=2)+'\n')
print(json.dumps({'rows':len(out),'duplicates':duplicate_count,'first':out[0],'last':out[-1],'calm_rows':sum(r[5]=='' for r in out),'minmax':{fields[i]:[min(float(r[i]) for r in out),max(float(r[i]) for r in out)] for i in [2,3,4,7]}},indent=2))
