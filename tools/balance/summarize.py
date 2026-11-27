# 밸런스 자동 대결 결과 요약 (tools/balance_sim.sh 가 부른다). 묶음마다 승률과 남은 체력을 보여 준다.
import sys,re,collections
d=collections.defaultdict(list)
for l in open(sys.argv[1]):
    m=re.match(r'(\S+) RESULT win=(\w+) me_hp=(-?\d+)/(\d+) ai_hp=(-?\d+)/(\d+) frames=(\d+)',l)
    if not m: print("BAD",l.strip()); continue
    tag=m.group(1).rsplit(':',1)[0]
    w,mh,mm,ah,am,f=m.group(2),*map(int,m.groups()[2:])
    d[tag].append((w,max(mh,0)/mm,max(ah,0)/am,f/60))
for t in sorted(d):
    r=d[t]; n=len(r)
    me=sum(x[0]=='me' for x in r); ai=sum(x[0]=='ai' for x in r)
    print(f"{t:28s} n={n} me_win={me/n:4.0%} ai_win={ai/n:4.0%} me_hp_left={sum(x[1] for x in r)/n:4.0%} ai_hp_left={sum(x[2] for x in r)/n:4.0%} t={sum(x[3] for x in r)/n:4.1f}s")
