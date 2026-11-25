# 소리 출처와 라이선스

이 폴더의 효과음(`sfx/`)과 배경음악(`music/`)은 **전부 이 프로젝트에서 코드로 직접 합성한 오리지널**입니다.

- 녹음, 샘플 팩, 다른 게임/음악의 소리 파일은 하나도 쓰지 않았습니다.
- 만든 방법: `tools/audio/synth.py` 의 수학 함수(사인파, 잡음, 필터, 울림)로 소리를 만들고,
  `tools/audio/make_sfx.py`(효과음 76종), `tools/audio/make_music.py`(경기장/메뉴 음악, 승리/패배 음악)가
  악기 소리와 악보까지 직접 계산해서 파일로 씁니다.
- 라이선스: 이 프로젝트의 것이며, 다른 곳에 써도 되도록 CC0(퍼블릭 도메인)으로 둡니다.

## 다시 만들기

```
pip install numpy scipy        # ffmpeg 도 필요 (음악 OGG 변환)
python3 tools/audio/make_music.py
python3 tools/audio/make_sfx.py   # 효과음 + scripts/audio/sound_bank.gd(소리 목록) 를 새로 씀
```

같은 시드로 돌리므로 항상 같은 소리가 나옵니다. 소리를 바꾸려면 위 파일의 숫자를 고치고 다시 돌리면 됩니다.
