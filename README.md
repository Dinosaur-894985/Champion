# 챔피언 (Champion)

오프라인에서 AI와 1대1로 싸우는 1인칭 3D 근접 전투 게임입니다. (Godot 4.3)

지금은 첫 단계인 **연습장**만 있습니다. 1인칭으로 걸어 다니며 칼로 허수아비를 베어 볼 수 있어요.

## 게임 받아서 실행하기 (Windows)

1. 이 저장소의 **Releases** 에서 `최신 빌드` 를 열고 `Champion-Windows.zip` 을 받습니다.
   (아직 Releases 에 없으면 **Actions** 탭 → 가장 위의 `Windows 빌드` → 아래쪽 **Artifacts** 의 `Champion-Windows` 를 받으세요. GitHub 로그인이 필요합니다.)
2. 압축을 풀고 `Champion.exe` 를 더블클릭합니다.
3. Windows 가 "PC 보호" 창을 띄우면 **추가 정보 → 실행** 을 누르세요. (서명이 없는 개인 게임이라 처음에만 뜹니다.)

## 조작법

| 키 | 동작 |
| --- | --- |
| W A S D | 이동 |
| Shift | 달리기 (기력 사용) |
| Space | 점프 |
| 마우스 | 둘러보기 |
| 왼쪽 클릭 | 베기 (연속으로 누르면 좌우 번갈아 베기) |
| 오른쪽 클릭 | 내려찍기 (느리지만 강함) |
| Esc | 일시정지 / 마우스 풀기 |

## 폴더 구성

- `scenes/main.tscn` 게임 시작 장면
- `scripts/main.gd` 연습장 (하늘, 바닥, 울타리, 나무, 허수아비 배치)
- `scripts/player.gd` 플레이어 (이동, 시점, 칼 휘두르기)
- `scripts/dummy.gd` 허수아비 (맞으면 흔들림, 체력, 쓰러졌다 다시 일어남)
- `scripts/hud.gd` 화면 표시 (조준점, 기력, 기록, 시작 화면)
- `scripts/lowpoly.gd` 각진 로우폴리 모양을 만드는 도우미
- `scripts/sfx.gd` 임시 효과음
- `tests/smoke_test.gd` 자동 점검 (걸어가서 허수아비를 베어 보고 결과 확인)
- `.github/workflows/build-windows.yml` Windows 실행 파일 자동 빌드

## 개발자용

Godot 4.3 에디터에서 `project.godot` 을 열면 됩니다. 자동 점검:

```
godot --headless --fixed-fps 60 -s res://tests/smoke_test.gd
```
