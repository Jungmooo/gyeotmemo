# 곁메모 1.0.1

항상 곁에 두는 작은 할 일 메모장입니다. Windows와 macOS에서 사용할 수 있습니다. 계정이나 인터넷 연결이 필요 없습니다.

## 다운로드

[Releases](https://github.com/Jungmooo/gyeotmemo/releases)에서 `GyeotMemo-v1.0.1-win.zip`을 받아 압축을 풀고 `GyeotMemo.exe`를 실행합니다. macOS는 `GyeotMemo-v1.0.1-mac.dmg`를 받습니다. 아래 [macOS](#macos)를 참고하세요. 이 저장소는 비공개이므로 접근 권한이 있는 GitHub 계정으로 로그인해야 합니다.

기존 사용자는 곁메모를 닫은 뒤 실행 파일과 config 파일을 교체하고 기존 `data` 폴더는 유지하세요. 개인 메모와 테스트 데이터는 저장소 및 배포 파일에 포함하지 않습니다.

1.0.1에서는 메모 영역 조절 막대가 실제 입력 공간을 늘리고 줄이도록 수정했습니다. 드래그 중에 크기가 바로 반영되며, 변경한 높이가 재실행 후에도 유지됩니다. 창을 작게 줄이면 메모가 창 밖으로 넘치지 않도록 제한합니다.

## 실행

`GyeotMemo.exe`를 더블클릭합니다. 설치나 관리자 권한은 필요 없습니다.

- Windows 10 / 11, .NET Framework 4.8 환경을 기준으로 제작했습니다.
- 이 PC에서 실행과 화면 동작을 확인했습니다.
- `GyeotMemo.exe.config`는 실행 파일과 같은 폴더에 두세요.
- 폴더를 옮길 때는 **data 폴더까지 함께** 옮겨야 기존 메모가 이어집니다.
- 쓰기 권한이 있는 폴더에 보관하세요. 바탕화면이나 문서 폴더를 사용할 수 있습니다.

## 사용법

| 기능 | 사용 방법 |
| --- | --- |
| 항상 위 고정 | 상단의 `고정 / 해제` 버튼, 또는 Ctrl+Shift+P |
| 할 일 추가 | 입력 후 Enter 또는 ＋ |
| 완료 표시 | 왼쪽 체크박스 |
| 수정 | 글을 두 번 클릭, 연필 버튼, 또는 선택 후 F2 |
| 수정 확정 / 취소 | Enter / Esc. 다른 곳을 클릭해도 확정됩니다. |
| 순서 변경 | 왼쪽 점 모양 손잡이를 드래그, 또는 선택 후 Alt+↑ / ↓ |
| 삭제 | 오른쪽 × 버튼 또는 목록에서 Delete |
| 완료 항목 정리 | 목록 아래 `완료 정리` |
| 삭제 되돌리기 | 하단 `삭제 되돌리기`, 또는 목록에서 Ctrl+Z |
| 자유 메모 | 아래 메모 영역에 입력. Enter로 줄바꿈 |
| 새 할 일에 포커스 | Ctrl+N |
| 창 이동 | 상단 제목 부분을 드래그 |
| 창 크기 변경 | 가장자리나 모서리를 드래그 |
| 메모 영역 크기 변경 | 목록과 메모 사이의 가로 손잡이를 드래그 |
| 최소화 / 종료 | 상단 − / × |

할 일·메모·입력 중인 새 할 일·고정 상태·창 위치와 크기를 자동 저장합니다.
삭제 되돌리기 이력은 현재 실행 중에만 유지됩니다. 텍스트 입력란의 Ctrl+Z는 일반적인 글자 입력 되돌리기로 동작합니다.

고정은 일반 창 위에 유지하는 기능입니다. 다른 프로그램의 고정 창, 독점 전체 화면, Windows 보안 화면 위에 표시되는 것을 보장하지 않습니다.

## 저장 위치와 복구

실행 파일 옆 `data` 폴더에 저장합니다.

- `memo.json`: 현재 내용
- `memo.backup.json`: 직전 저장 백업
- `memo.unreadable-날짜-식별자.json`: 읽지 못한 원본을 보존한 파일

읽지 못한 저장 파일은 원본을 보관한 후 백업 복원을 시도합니다. 백업도 읽지 못하면 보관 파일을 남기고 새 메모를 엽니다. 더 새로운 버전의 저장 형식이거나 원본을 보관하지 못하면 저장을 차단하고 읽기 전용으로 엽니다. 하단 상태에 마우스를 올리면 저장 위치와 안내를 볼 수 있습니다.

저장 실패 시 하단에 안내가 표시됩니다. 저장하지 못한 내용이 있을 때 닫기를 누르면 창을 유지합니다. 쓰기 권한이나 파일 잠금 문제를 해결한 후 다시 시도하세요.

창을 여러 번 실행해도 같은 data 폴더에 대해서는 하나만 열립니다.
트레이, 시작 시 자동 실행, 마감일, 알림은 이번 버전에 포함하지 않았습니다.

## 소스와 빌드

이 저장소에 C# 소스, XAML, 아이콘, 매니페스트, 빌드 스크립트와 검증 코드를 담았습니다.
개발에는 .NET SDK의 Roslyn C# 컴파일러와 Windows의 .NET Framework 참조 어셈블리를 사용했습니다. 외부 NuGet 패키지는 사용하지 않습니다.

소스 압축을 푼 폴더의 PowerShell에서:

```powershell
.\build.ps1
```

`dist`에 실행 파일과 설정 파일이 생성됩니다. 빌드에는 .NET SDK가 필요하며 일반 실행에는 필요하지 않습니다.

저장 및 복구 검증을 별도 폴더에서 실행하려면:

```powershell
Start-Process .\dist\GyeotMemo.exe -ArgumentList '--self-test --data-dir C:\Temp\GyeotMemoTests' -Wait
```

지정한 폴더에 고유한 테스트 하위 폴더와 `self-test-results.txt`를 만듭니다. `--data-dir`를 생략하면 실행 파일 옆 data 폴더를 사용합니다.

`tests/run-layout-tests.ps1`은 실제 WPF GridSplitter의 드래그 처리, 입력창 높이 변화, 재실행 후 높이와 내용 복원, 최소 창 크기의 배치를 검증합니다. 실행 파일 경로는 `-ApplicationPath`로 지정할 수 있습니다.

기술 참고: [WPF Window.Topmost](https://learn.microsoft.com/en-us/dotnet/api/system.windows.window.topmost), [WPF 창 개요](https://learn.microsoft.com/en-us/dotnet/desktop/wpf/windows/).

## macOS

`mac/` 폴더에 Swift(AppKit)로 옮긴 네이티브 macOS 버전이 있습니다. 기능과 저장 형식은 Windows 버전과 같습니다.

### 설치

1. `GyeotMemo-v1.0.1-mac.dmg`를 열고 `곁메모.app`을 `Applications` 폴더로 끌어 놓습니다.
2. 처음 실행할 때 “확인되지 않은 개발자” 경고가 나올 수 있습니다. 이 앱은 ad-hoc 서명만 되어 있고 Apple 공증(notarization)을 받지 않았기 때문입니다.
   **시스템 설정 → 개인정보 보호 및 보안**에서 곁메모 항목의 **그래도 열기**를 누르세요.
   터미널을 쓴다면 `xattr -dr com.apple.quarantine /Applications/곁메모.app` 후 실행해도 됩니다.

- macOS 13 Ventura 이상, Apple silicon과 Intel Mac 모두 지원하는 유니버설 앱입니다.
- 설치나 관리자 권한, 인터넷 연결은 필요 없습니다.

### 사용법 차이

창 이동·크기 조절·최소화·닫기는 macOS 기본 창 동작(신호등 버튼)을 따릅니다. 단축키는 Ctrl 대신 ⌘을 씁니다.

| 기능 | Windows | macOS |
| --- | --- | --- |
| 항상 위 고정 | Ctrl+Shift+P | ⇧⌘P 또는 `고정 / 해제` 버튼 |
| 새 할 일에 포커스 | Ctrl+N | ⌘N |
| 할 일 추가 | Enter | Return |
| 수정 | 두 번 클릭 · 연필 · F2 | 두 번 클릭 · 연필 · 선택 후 Return 또는 F2 |
| 순서 변경 | 손잡이 드래그 · Alt+↑/↓ | 항목 드래그 · ⌥↑/↓ |
| 삭제 | × · Delete | × · Delete(⌫) |
| 완료 표시 | 체크박스 | 체크박스 · 선택 후 Space |
| 삭제 되돌리기 | 목록에서 Ctrl+Z | 목록에서 ⌘Z, `할 일` 메뉴 |
| 최소화 / 닫기 | 상단 − / × | ⌘M / ⌘W 또는 신호등 버튼 |

고정은 창을 일반 창 위(floating 레벨)에 유지합니다. 다른 앱의 전체 화면 공간이나 다른 데스크탑(Space)까지 따라가지는 않습니다.

### 저장 위치

`~/Library/Application Support/GyeotMemo`에 `memo.json`, `memo.backup.json`, `memo.unreadable-*.json`을 Windows 버전과 같은 방식으로 저장합니다. 메뉴의 **곁메모 → 저장 폴더 열기**로 Finder에서 열 수 있습니다.

저장 형식이 같으므로 Windows의 `data/memo.json`을 이 폴더에 복사하면 그대로 이어서 쓸 수 있습니다(곁메모를 닫은 상태에서 복사). 창 위치는 화면 구성이 다르면 보이는 위치로 옮겨집니다.

### 빌드와 검증

Xcode Command Line Tools(`xcode-select --install`)만 있으면 됩니다. 외부 패키지는 사용하지 않습니다.

```bash
mac/build.sh            # mac/dist/곁메모.app 과 mac/dist/GyeotMemo-v1.0.1-mac.dmg 생성
mac/build.sh --no-dmg   # .app만 생성
```

저장·복구 검증(Windows `--self-test`와 같은 8개 항목)과 실제 창을 띄워 하는 레이아웃·조작 검증:

```bash
APP="mac/dist/곁메모.app/Contents/MacOS/GyeotMemo"
"$APP" --self-test   --data-dir /tmp/GyeotMemoTests
"$APP" --layout-test --data-dir /tmp/GyeotMemoTests
```

각각 `self-test-results.txt`, `layout-test-results.txt`를 지정한 폴더에 남기고, 성공 시 종료 코드 0을 돌려줍니다.

### Mac 없이 macOS 버전 배포하기 (저장소 관리자용)

macOS 빌드는 GitHub Actions의 Mac 서버(`.github/workflows/macos.yml`)가 대신 합니다. Mac이 없어도 됩니다.

1. 평소처럼 GitHub에서 **Releases → Draft a new release**로 `v1.0.2` 같은 태그의 릴리스를 만들고 **Publish release**를 누릅니다.
2. 몇 분 뒤 **Actions** 탭의 `macOS build`가 끝나면 그 릴리스에 `GyeotMemo-v1.0.2-mac.dmg`가 자동으로 첨부됩니다. 버전 번호는 태그에서 가져옵니다(`v` 제외).
3. 실패하면 Actions 탭에서 빨간 표시가 난 실행을 열어 로그를 확인합니다. 필요하면 **Run workflow**로 다시 실행할 수 있습니다.

`mac/` 폴더를 바꾸는 push나 PR에서도 같은 빌드와 검증(`--self-test`, `--layout-test`)이 실행되고, 실행 결과 화면의 **Artifacts**에서 `.dmg`를 내려받아 볼 수 있습니다.
