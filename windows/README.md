# Clamshell Discharge for Windows (미리보기)

macOS 판과 같은 화면 구성으로 만든 Windows 10/11 트레이 앱입니다. 실행 파일은 **하나**이고, 실행할 때 노트북 제조사를 감지해서 맞는 충전 제어 방식을 고릅니다.

> **미리보기 단계입니다.** 충전 제어는 아직 **Lenovo만** 지원하며, 실제 기기에서 검증 중입니다. 다른 제조사 노트북에서는 배터리 모니터링(대시보드, SOH, 기록)과 덮개 닫힘 동작만 됩니다.

## 지원 현황

| 제조사 | 방식 | 유지 수준 | 상태 |
|---|---|---|---|
| **Lenovo ThinkPad** | 충전 시작·중지 임계값 (Lenovo PM 드라이버 `IBMPmDrv` + `PWRMGRV` 레지스트리) | 60~99% 자유롭게 | 구현됨, 검증 필요 |
| **Lenovo IdeaPad / Yoga / Legion** | 보존 모드 (Energy Management 드라이버 `EnergyDrv`) | 펌웨어 고정 (대략 60% 또는 80%) | 구현됨, 검증 필요 |
| ASUS · Dell · HP · Samsung · LG | — | — | 예정 |

필요한 드라이버:
- ThinkPad: **Lenovo Power Management Driver** (Lenovo Vantage나 System Update로 설치됨)
- IdeaPad/Yoga/Legion: **Lenovo Energy Management** 드라이버

## 기능 (macOS 판과 같음)

- 충전 유지(한도 방식), **출근 충전**·**퇴근 충전** 일정, **지금 충전 (출장·외출)** 80% / 100%
- 대시보드(충전량, 일별 SOH), 사용 기록, 용량 막대, 다국어

## macOS 판과 다른 점

- **"60% 유지"는 충전 한도 방식입니다.** Windows 노트북은 대부분 "어댑터를 꽂은 채 배터리 쓰기(능동 방전)"를 할 수 없습니다. 대신 꽂혀 있으면 정한 %에서 충전을 멈추고 전원으로 동작합니다. 이미 그보다 높으면, 배터리를 써서 내려올 때까지 기다리거나 어댑터를 잠시 뽑아야 합니다.
- **덮개 닫힘 동작은 Windows 전원 설정**(`powercfg` LIDACTION)을 씁니다. **덮개 닫아도 동작 (전원 연결 시)**를 켜면 "전원 연결 시 아무것도 안 함 / 배터리면 절전"으로 바꾸고, 끄면 원래 값으로 되돌립니다. USB와 블루투스 키보드로 깨우기는 Windows 기본 기능이라 별도 처리가 없습니다.
- 용량 단위는 **mWh**입니다. Windows가 mWh로 보고합니다.
- 관리자 권한이 필요합니다. 실행하면 UAC 창이 뜹니다. 충전 한도(레지스트리 HKLM, Lenovo 드라이버)와 전원 설정을 바꾸기 때문입니다.
- **로그인 시 자동 실행**은 작업 스케줄러에 "가장 높은 권한으로 실행" 작업을 만듭니다. 그래서 매번 UAC 창이 뜨지 않습니다.
- **앱을 종료하면 충전 한도를 풀고**(정상 충전), 덮개 설정을 원래대로 되돌립니다.

## 설치와 실행

1. [Releases](../../releases)에서 `win-v…` 미리보기의 `ClamshellDischarge-Windows.zip`을 받아 압축을 풉니다.
2. `ClamshellDischarge.exe`를 실행합니다. 서명되지 않은 앱이라 **SmartScreen**이 막으면 **추가 정보 → 실행**을 누릅니다. 이어서 UAC 창에서 **예**를 누릅니다.
3. 작업 표시줄 오른쪽 아래(트레이)에 배터리 숫자 아이콘이 나타납니다. **왼쪽 클릭**하면 메인 화면, **오른쪽 클릭**하면 메뉴가 열립니다. 아이콘이 보이지 않으면 **^**(숨겨진 아이콘)를 확인하세요.

## Lenovo에서 테스트하는 방법

1. 메인 화면 **배터리 → 충전 제어**에 무엇이 표시되는지 확인합니다. ("ThinkPad 충전 임계값" / "보존 모드 (약 80%, 고정)" / "지원 안 됨")
2. **충전 유지**를 켜고, ThinkPad라면 수준을 현재 배터리보다 낮게(예: 현재 85%면 80%) 정합니다.
3. 1분쯤 뒤 상태 배지가 **충전 중지 상태 · 한도 80%**로 바뀌는지, Windows 배터리 아이콘에도 충전이 멈췄다고 나오는지 확인합니다.
4. Lenovo Vantage를 열어 충전 임계값 또는 보존 모드가 같은 값으로 바뀌었는지 확인합니다.
5. 문제가 있으면 메인 화면 아래 **진단 정보 복사**를 누르고, [Issues](../../issues)에 붙여 넣어 주세요. 진단 정보에는 기종, 감지된 방식, 드라이버 상태, 배터리 값이 들어 있습니다.

## 빌드

.NET 10 SDK가 필요합니다. `EnableWindowsTargeting` 덕분에 macOS나 Linux에서도 컴파일할 수 있습니다(실행은 Windows만).

```bash
cd windows
dotnet publish -c Release -o publish     # publish/ClamshellDischarge.exe (단일 파일)
```

- 번역 표는 macOS 판 `Sources/L10n.swift`에서 만듭니다: `python3 tools/gen_l10n_cs.py`. Windows 전용 문구는 `windows/L10n.cs`의 `Extra` 표에 있습니다.
- GitHub Actions(`.github/workflows/windows.yml`)가 Windows에서 빌드하고 `--selftest`로 기본 동작을 점검합니다. `win-v*` 태그를 push하면 미리보기 릴리스를 만듭니다.

## 출처

- ThinkPad 임계값 프로토콜: [wesmar/lbm](https://github.com/wesmar/lbm) (MIT) README의 Implementation 절
- 보존 모드 프로토콜: [dara-oladapo/power-helper](https://github.com/dara-oladapo/power-helper) (MIT)

## 주의

- 제조사 드라이버의 비공개 인터페이스를 사용합니다. **본인 책임 하에 사용하세요.** 기종이나 드라이버 버전에 따라 동작하지 않을 수 있습니다.
- Lenovo Vantage가 같은 설정을 덮어쓸 수 있습니다. 한쪽에서만 바꾸세요.
