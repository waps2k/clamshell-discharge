# Clamshell Discharge

Apple Silicon MacBook에서 **어댑터를 꽂은 채 배터리를 능동 방전**하고, **덮개를 닫은 클램쉘 모드에서도** 계속 동작하게 해 주는 메뉴 막대 앱입니다.

방전은 [actuallymentor/battery](https://github.com/actuallymentor/battery) CLI가 SMC로 어댑터를 차단해서 처리하고, 이 앱은 클램쉘 잠자기 제어·퇴근 감지·메뉴 막대 UI를 더합니다.

## 왜 필요한가

능동 방전 중에는 어댑터가 꽂혀 있어도 macOS가 **배터리 전원**으로 인식합니다. 그래서 `caffeinate -s`(AC 전원에서만 유효)로는 잠자기를 막지 못하고, 덮개를 닫으면 잠들어 버립니다. 이 앱은 방전 중에만 `pmset disablesleep 1`로 클램쉘 잠자기를 막고, 끝나면 반드시 원래 값으로 되돌립니다.

## 기능

- **메뉴 막대 팝오버 (메인 화면)**
  - 메뉴 막대 아이콘에 충전량(%)과 상태 아이콘이 표시됩니다: 충전 ⚡, 유지 모드 ⛵, 수동 방전 ↓, 꽂힘 대기 🔌, 배터리.
  - 클릭하면 팝오버가 열립니다.
    - 배터리 그림, 충전량, 상태 배지(충전 중 / 방전 중·유지 모드 / 방전 중·수동 방전 / 배터리 사용 중 / 충전 완료)
    - 최근 4시간 사용 기록 막대
    - 공급원, 완충까지 시간 또는 남은 사용 시간
    - 최대·설계 용량, 시스템 전력, 배터리 전력, 전류, 전압, SOH, 사이클, 온도, macOS 판정
    - 충전 유지, 퇴근 충전, 자동 업무 모드, 수동 방전을 바로 제어하는 스위치
    - CPU 사용량 상위 프로세스
  - 우클릭하면 기존 메뉴가 나옵니다.
- **방전 시작 / 중지**: 메뉴에서 목표(90·85·80·75·70·60·50%)를 고르면 그 값까지 방전합니다.
- **자동 업무 모드**
  - 전원(어댑터 물리 연결) + 외장 모니터 → 덮개를 닫아도 계속 동작
  - 배터리이거나, 덮개가 닫혔는데 외장 모니터가 없으면 → 즉시 잠자기
- **퇴근 감지**: 덮개를 닫은 채 외장 모니터나 어댑터를 뽑으면 방전을 멈추고, 잠자기 설정을 복원한 뒤 바로 잠듭니다. 가방 속에서 뜨거워지는 걸 막습니다.
- **안전장치**: 목표는 20% 미만으로 설정할 수 없습니다. 목표보다 3% 이상 내려가면 강제로 중단합니다. 어떻게 종료되든(정상 종료, 중지, 앱 종료, 오류) 방전 해제와 잠자기 복원을 실행합니다.
- **충전 유지 모드 (세일링)**: 전원이 연결된 동안 배터리를 60~100% 중 설정한 수준(추천 60%) 근처로 유지합니다. 목표에 닿으면 어댑터 입력을 차단해 배터리로 쓰다가, 3% 내려오면 다시 충전합니다. 원하면 덮개가 닫혀 있을 때(클램쉘)만 적용할 수 있습니다.
  - 이 방식을 쓰는 이유: 최근 macOS·펌웨어에서는 충전만 따로 멈추는 SMC 키(`CH0B`/`CH0C`/`CHTE`)가 없는 기기가 있습니다. 그래서 어댑터 차단 키(`CHIE`)만으로 구간을 유지합니다.
  - 잠자기에 들어가기 직전과 앱이 종료될 때는 어댑터 차단을 항상 해제합니다. 잠든 동안 배터리가 닳지 않게 하기 위해서입니다.
- **퇴근 충전**: 퇴근 시각(기본 18:00)과 요일을 정해 두면, 정한 시간(기본 90분) 전부터 유지 모드를 멈추고 목표(기본 100%)까지 충전합니다. 퇴근 시각 30분 뒤에 유지 모드로 돌아갑니다.
- **배터리 대시보드**: 충전량 그래프(6시간·24시간·7일·30일), 배터리 성능(SOH = 현재 최대 용량 ÷ 설계 용량)의 일별 그래프, 사이클 수, macOS 상태(Condition)를 보여 주고, 유지·퇴근 충전 설정도 여기서 합니다. 기록은 `~/Library/Application Support/ClamshellDischarge/history.csv`에 1분마다 저장되고 90일치를 보관합니다.
- 로그 보기, 로그인 시 자동 실행

## 요구 사항

- Apple Silicon MacBook, macOS 13 이상
- [battery CLI](https://github.com/actuallymentor/battery) 설치
  ```bash
  curl -s https://raw.githubusercontent.com/actuallymentor/battery/main/setup.sh | bash
  ```
- AlDente 같은 다른 충전 관리 앱은 제거해야 합니다. SMC 설정이 서로 충돌합니다.

## 설치

1. [Releases](../../releases)에서 `ClamshellDischarge-<버전>.zip`을 받아 압축을 풀고, `/Applications`로 옮깁니다.
2. 처음 열 때는 **우클릭 → 열기**를 선택합니다. 유료 인증서가 아닌 ad-hoc 서명이기 때문입니다.
3. 메뉴 막대 아이콘에서 **권한 설정 (최초 1회)…** 를 누르고 관리자 비밀번호를 입력합니다.
   `/etc/sudoers.d/clamshell-discharge`가 만들어지며, 허용되는 명령은 다음 두 개뿐입니다.
   ```
   <사용자> ALL = (root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1
   ```
   덮개가 닫힌 상태에서는 비밀번호 창을 띄울 수 없으므로, 이 권한이 있어야 잠자기 설정을 자동으로 바꿀 수 있습니다.

## CLI

앱 번들에 들어 있는 스크립트를 터미널에서 직접 쓸 수도 있습니다.

```bash
/Applications/ClamshellDischarge.app/Contents/Resources/clamshell-discharge 80      # 80%까지 방전
/Applications/ClamshellDischarge.app/Contents/Resources/clamshell-discharge --restore  # 비상 복구
```

## 빌드

Xcode(또는 Command Line Tools)의 `swiftc`가 필요합니다.

```bash
./build.sh            # build/ClamshellDischarge.app + zip
./build.sh --install  # + /Applications 설치
```

## 제거

```bash
sudo rm /etc/sudoers.d/clamshell-discharge
rm -rf /Applications/ClamshellDischarge.app ~/.battery/clamshell-discharge.*
sudo pmset -a disablesleep 0
```

## 주의

- SMC를 직접 건드리는 도구입니다. 본인 책임 하에 사용하세요.
- MagSafe가 없는 모델에서는 LED 관련 `SMCWriteKey ... e00002bc` 오류가 보일 수 있습니다. 무시해도 됩니다.
- macOS 버전에 따라 battery CLI의 충전 한도 키가 지원되지 않을 수 있습니다. 방전 기능과는 무관합니다.
- 자동 업무 모드에서 전원이 연결돼 있으면 덮개를 연 상태에서도 시스템 잠자기가 막힙니다. 디스플레이는 평소처럼 꺼집니다.

## 라이선스

MIT
