# MCRealDiskSize

Plugin typu **FileProperties** dla Multi Commandera, który dodaje kolumny pokazujące realny rozmiar zajęty lokalnie na dysku. Przydaje się szczególnie dla OneDrive Files On-Demand, gdzie plik może mieć logicznie np. 10 GB, ale lokalnie zajmować 0 B.

## Co dodaje plugin

Po instalacji w konfiguracji kolumn powinny pojawić się kolumny z kategorii **Real Disk Size**:

- **Rozmiar na dysku** / **Na dysku** – czytelny rozmiar, np. `0 B`, `128 KB`, `1.42 GB`.
- **Rozmiar na dysku RAW** / **Na dysku RAW** – liczba bajtów, przydatna do sortowania i filtrowania.
- **Status lokalny/OneDrive** / **Status dysku** – atrybuty typu `ONLINE_ONLY`, `LOCAL_AVAILABLE`, `ALWAYS_LOCAL`, `UNPINNED`, `PINNED`, `OFFLINE`, `RECALL_ON_DATA_ACCESS`, `SPARSE`, `COMPRESSED`.

## Ważne ograniczenie

Ten plugin **nie zmienia wbudowanej kolumny Size** i **nie zmienia działania `Tools -> Calculate folder size`**. Dodaje osobną kolumnę, którą trzeba ręcznie włączyć w układzie kolumn.

Dla folderów plugin liczy rozmiar rekurencyjnie. Kolumna jest zarejestrowana jako asynchroniczna, ale przy bardzo dużych folderach nadal może to chwilę potrwać.


## Ważne dla Multi Commander 15.8

Wersja `0.1.1.0` zawiera obejście problemu z ładowaniem w Multi Commander 15.8: aplikacja odrzuca pluginy zgłaszające interfejs SDK `2.4.0.0` jako zbyt stare, więc w `GetExtensionInfo()` wpisano `2.5.0.0` jako wersję interfejsu.

To jest obejście zgodności, nie pełna aktualizacja SDK. Jeżeli plugin nadal nie załaduje się albo Multi Commander będzie niestabilny, usuń DLL z `Extensions\MCRealDiskSize` i poczekaj na publiczny SDK Multi Commander zgodny z 15.8.

## Wymagania

- Windows 10/11.
- Multi Commander w tej samej architekturze co plugin: zwykle x64.
- Visual Studio 2022 albo Build Tools 2022 z workloadem **Desktop development with C++**.
- MSVC v143 C++ toolset.
- Windows 10/11 SDK.
- PowerShell 5.1 lub nowszy.
- Dostęp do internetu przy pierwszym uruchomieniu skryptu pobierającego SDK.

## Budowanie

Otwórz PowerShell w katalogu projektu `MCRealDiskSize`.

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\scripts\01_download_sdk.ps1
.\scripts\02_build.ps1 -Platform x64 -Configuration Release
```

Jeżeli masz 32-bitowego Multi Commandera:

```powershell
.\scripts\02_build.ps1 -Platform Win32 -Configuration Release
```

Gotowa DLL pojawi się tutaj:

```text
bin\x64\Release\MCRealDiskSize.dll
```

albo dla 32-bit:

```text
bin\Win32\Release\MCRealDiskSize.dll
```

## Instalacja

### Instalacja z GitHub Release

Pobierz plik `MCRealDiskSize-v<wersja>-x64.zip` z najnowszego GitHub Release i wypakuj folder `MCRealDiskSize` do:

```text
<MultiCommander>\Extensions\
```

Po wypakowaniu DLL powinna leżeć tutaj:

```text
<MultiCommander>\Extensions\MCRealDiskSize\MCRealDiskSize.dll
```

Opis release powinien zawierać informację o zgodności, np.:

```text
Compatibility:
- Multi Commander 15.8
- Windows 10/11 x64
```

### Instalacja ze skryptu lokalnego

Najprościej:

```powershell
.\scripts\03_install_to_multicommander.ps1 -Platform x64 -Configuration Release -MultiCommanderPath "C:\Program Files\MultiCommander"
```

Dla wersji portable wskaż katalog, w którym leży `MultiCommander.exe`, np.:

```powershell
.\scripts\03_install_to_multicommander.ps1 -Platform x64 -Configuration Release -MultiCommanderPath "D:\Tools\MultiCommander"
```

Skrypt kopiuje DLL do:

```text
<MultiCommander>\Extensions\MCRealDiskSize\MCRealDiskSize.dll
```

## Wymagania do samodzielnego utworzenia DLL

Do samodzielnego zbudowania pliku DLL potrzebne są:

- Windows 10/11.
- Visual Studio 2022 albo Build Tools 2022.
- Workload **Desktop development with C++**.
- MSVC v143 C++ toolset.
- Windows 10/11 SDK.
- PowerShell 5.1 lub nowszy.
- Dostęp do internetu przy pierwszym pobraniu Multi Commander SDK albo gotowy katalog `external\MultiCommander-SDK-main`.

Release ZIP można utworzyć lokalnie poleceniem:

```powershell
.\scripts\New-ReleasePackage.ps1 -Version 1.0.0 -Platform x64 -Configuration Release
```

Wynik pojawi się w:

```text
artifacts\release\MCRealDiskSize-v1.0.0-x64.zip
```

## Automatyczne release w GitHub Actions

Workflow release uruchamia się dla GitHub Release oraz tagów w formacie `V1.0.0`, `v1.0.0`, `V1.0.0.1` albo `v1.0.0.1`. Wersja pluginu w DLL i nazwie ZIP pochodzi z taga bez początkowego `V`/`v`.

Build najpierw próbuje użyć self-hosted runnera z labelami `self-hosted`, `Windows`, `X64`. Jeżeli nie dodasz secreta `RUNNER_STATUS_TOKEN`, workflow nie może sprawdzić dostępności runnerów przez GitHub API i wybiera self-hosted jako domyślną ścieżkę. Żeby włączyć automatyczny fallback na `windows-latest`, dodaj secret `RUNNER_STATUS_TOKEN` z uprawnieniem odczytu administracji repozytorium. Wtedy workflow sprawdzi dostępność runnera; jeśli nie znajdzie wolnego self-hosted runnera, użyje `windows-latest` i dodatkowo zapisze ZIP jako Actions artifact.

## Włączenie kolumn w Multi Commanderze

1. Zamknij i uruchom ponownie Multi Commandera.
2. Wejdź w **Configuration -> Manage Plug-ins and Extensions**.
3. Sprawdź, czy `MCRealDiskSize` jest widoczny i aktywny.
4. W panelu plików kliknij prawym przyciskiem na nagłówkach kolumn.
5. Wybierz **Customize columns...**.
6. Dodaj kolumny z kategorii **Real Disk Size**:
   - `Rozmiar na dysku`
   - opcjonalnie `Rozmiar na dysku RAW`
   - opcjonalnie `Status lokalny/OneDrive`

## Jak interpretować wyniki

Przykład dla OneDrive:

| Plik | Size w Multi Commanderze | Rozmiar na dysku z pluginu |
|---|---:|---:|
| plik online-only 10 GB | 10 GB | 0 B lub bardzo mało |
| plik pobrany lokalnie 10 GB | 10 GB | ok. 10 GB |
| plik sparse / częściowo zaalokowany | 10 GB | tylko zaalokowane bloki |

## Gdy plugin się nie pojawia

Sprawdź po kolei:

1. Czy architektura DLL zgadza się z Multi Commanderem: x64 do x64, Win32 do 32-bit.
2. Czy DLL jest w podfolderze `Extensions\MCRealDiskSize\`.
3. Czy po skopiowaniu DLL uruchomiłeś Multi Commandera ponownie.
4. Czy plik DLL nie jest zablokowany przez Windows: PPM na DLL -> Properties -> Unblock.
5. Czy masz zgodną wersję SDK/Multi Commandera. Projekt używa aktualnego SDK z gałęzi `main`.

## Technika liczenia

Dla plików sparse, skompresowanych i cloud-placeholder plugin używa `GetCompressedFileSizeW`, czyli API Windows zwracające rzeczywisty użyty rozmiar przechowywania. Dla zwykłych nieskompresowanych plików wynik jest zaokrąglany do rozmiaru klastra woluminu, aby lepiej odpowiadał temu, co Windows pokazuje jako „size on disk”.


## v0.1.2 note

This build registers the size columns as string properties instead of numeric properties.
Reason: on Multi Commander 15.8 with the public SDK compatibility override, string properties render correctly, while the first numeric columns may stay empty.

Columns:
- `Na dysku` shows a readable allocated size such as `0 B`, `64 KB`, `1.42 GB`.
- `Na dysku RAW` shows a zero-padded byte count. It is ugly, but it sorts correctly as text.
- `Status dysku` shows OneDrive/Cloud Files attributes.

If you still see old blank columns, remove the old columns from the layout and add them again from `Customize columns...`.
