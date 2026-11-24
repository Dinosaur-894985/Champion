# 챔피언 (Champion)

오프라인에서 AI와 1대1로 싸우는 1인칭 3D 근접 전투 게임입니다. (Godot 4.3)

지금 할 수 있는 것
- **AI와 대결**: 칼을 든 결투사와 1대1. 상대 칼이 빛나면 공격이 온다는 신호예요. 막거나, 맞기 직전에 막아서 튕겨내거나, 옆으로 대시해서 피하세요.
- **연습장**: 허수아비 3개를 마음껏 베어 볼 수 있어요.

## 웹에서 바로 하기 (다운로드 없음)

main 에 합쳐질 때마다 웹 버전이 자동으로 올라갑니다: https://dinosaur-894985.github.io/Champion/
(처음 한 번, 저장소 Settings → Pages → Source 를 **GitHub Actions** 로 바꿔야 합니다.)
크롬이나 엣지에서 여는 것을 추천해요.

## 게임 받아서 실행하기 (Windows)

1. 이 저장소의 **Releases** 에서 `최신 빌드` 를 열고 `Champion-Windows.zip` 을 받습니다.
   (아직 Releases 에 없으면 **Actions** 탭 → 가장 위의 `게임 빌드` → 아래쪽 **Artifacts** 의 `Champion-Windows` 를 받으세요. GitHub 로그인이 필요합니다.)
2. 압축을 풀고 `Champion.exe` 를 더블클릭합니다.
3. Windows 가 "PC 보호" 창을 띄우면 **추가 정보 → 실행** 을 누르세요. (서명이 없는 개인 게임이라 처음에만 뜹니다.)

## 조작법

| 키 | 동작 |
| --- | --- |
| W A S D | 이동 |
| Shift | 누르는 순간 대시 (대시 중엔 공격을 피함), 누르고 있으면 달리기 |
| Space | 점프 |
| 마우스 | 둘러보기 |
| 왼쪽 클릭 | 베기 (연속으로 누르면 좌우 번갈아 베기) |
| Q | 내려찍기 (느리지만 강하고, 상대의 막기를 깨뜨림) |
| 오른쪽 클릭 (누르고 있기) | 막기. 맞기 직전에 누르면 **튕겨내기** → 상대가 크게 흔들려 반격 기회 |
| Esc | 메뉴 |

## 폴더 구성

- `scenes/main.tscn` 게임 시작 장면
- `scripts/main.gd` 연습장 (하늘, 바닥, 울타리, 나무, 허수아비 배치)
- `scripts/player.gd` 플레이어 (이동, 시점, 칼 휘두르기)
- `scripts/duelist.gd` AI 결투사 (다가오기, 예고 후 공격, 막기, 반격, 회피)
- `scripts/fx.gd` 불꽃, 파편 효과
- `scripts/dummy.gd` 허수아비 (맞으면 흔들림, 체력, 쓰러졌다 다시 일어남)
- `scripts/hud.gd` 화면 표시 (조준점, 기력, 기록, 시작 화면)
- `scripts/lowpoly.gd` 각진 로우폴리 모양을 만드는 도우미
- `scripts/sfx.gd` 임시 효과음
- `fonts/` 한글 글꼴 (나눔고딕, OFL 라이선스)
- `tests/smoke_test.gd` 자동 점검 (허수아비 베기 + 자동 조종으로 AI와 대결)
- `.github/workflows/build.yml` 자동 점검, Windows 실행 파일, 웹 버전 빌드

## 개발자용

Godot 4.3 에디터에서 `project.godot` 을 열면 됩니다. 자동 점검:

```
godot --headless --fixed-fps 60 -s res://tests/smoke_test.gd
# 대결만, 막지 않는 자동 조종으로:  ... -- only=duel bot=masher seed=3
```
