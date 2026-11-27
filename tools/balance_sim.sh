#!/bin/bash
# 밸런스 자동 대결: 한 줄에 한 판씩 적은 파일을 받아 여러 판을 동시에 돌리고 승률을 요약한다.
# 줄 모양:  이름:묶음:번호 smoke_test 인자들...
#   예)     ai:tank:1 bot=masher mystats=6,6,6,6,6 aistats=7,10,1,2,10 seed=1 maxf=3600
#           kite:sword:1 bot=kiter weapon=shuriken aistats=6,6,6,6,6 aiweapon=sword seed=1 maxf=5400
# 실행:    tools/balance_sim.sh 판목록.txt [동시에 돌릴 수, 기본 4]
# 주의: 같은 설정도 판마다 결과가 조금씩 다르다. 묶음마다 24판 이상 보는 것이 좋다.
set -e
jobs=$1; par=${2:-4}
cd "$(dirname "$0")/.."
out=$(mktemp)
run_one() {
	tag=$1; shift
	r=$(timeout 200 godot --headless --fixed-fps 60 -s res://tests/smoke_test.gd -- only=duel "$@" 2>&1 | grep RESULT || true)
	echo "$tag $r"
}
export -f run_one
xargs -P"$par" -L1 bash -c 'run_one "$@"' _ < "$jobs" > "$out"
python3 tools/balance/summarize.py "$out"
