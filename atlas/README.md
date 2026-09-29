# Atlas

Atlas ist die vereinheitlichte Build-Infrastruktur der `ww3d`-Organisation, modelliert nah an
Microsofts `dotnet/arcade`-Oekosystem. Details in `docs/architecture-baseline.md`.

## Einbinden

Ein Konsumenten-Repo bindet `DotNet.Atlas.Sdk` ueber `global.json` ein:

```json
{
  "msbuild-sdks": {
    "DotNet.Atlas.Sdk": "0.1.0-preview.3.26475.2"
  }
}
```

und fuehrt die `cella`-Quelle in seiner eigenen `nuget.config`:

```xml
<packageSources>
  <add key="cella" value="https://nuget1.mtb.me/f/buildtools-core/api/v2/" />
</packageSources>
<packageSourceMapping>
  <packageSource key="cella">
    <package pattern="DotNet.Atlas.*" />
  </packageSource>
</packageSourceMapping>
```

Atlas legt sich wie arcade ueber ein anderes SDK, es ersetzt keins. Die Projekte bleiben
`Sdk="Microsoft.NET.Sdk"` (oder ihr bisheriges SDK); Atlas kommt ueber die beiden Dateien in der
Repo-Wurzel:

```xml
<!-- Directory.Build.props -->
<Project>
  <Import Project="Sdk.props" Sdk="DotNet.Atlas.Sdk" />
</Project>
```

```xml
<!-- Directory.Build.targets -->
<Project>
  <Import Project="Sdk.targets" Sdk="DotNet.Atlas.Sdk" />
</Project>
```

`<Project Sdk="DotNet.Atlas.Sdk">` als einziges SDK baut nichts — und `dotnet build` meldet trotzdem
Erfolg.

Die konsumierbare Flaeche (`Config.props`-Schalter, Ordner-/Ausgabelayout, Opt-in-Ziele) steht in
`docs/configuration.md`.

## Wurzelskripte

Die Wurzelskripte sind `Build.cmd`, `Restore.cmd`, `Test.cmd`, `build.sh`, `restore.sh`, `test.sh`
und das `eng/common/`, das sie aufrufen. Das SDK-Paket bringt sie **nicht** mit; ein Konsument
fuehrt sie als Kopie in seinem eigenen Repo oder verzichtet auf sie.

### Was ohne sie geht

`dotnet build`/`test`/`pack`/`publish` bzw. `msbuild` gegen Projekt oder Solution. Alles, was das SDK
in jedes Projekt importiert, wirkt dabei gleich:

- die `Config.props`-Felder aus `docs/configuration.md`, ausser den Toolset-Feldern im naechsten
  Abschnitt;
- die Wurzel `ArtifactsDir` samt Preset und Schablonen, auch ueber `ATLAS_ARTIFACTS_DIR` oder
  `-p:ArtifactsDir=` (MSBuild liest beide selbst);
- Pack samt Pflichtangaben (`ATLAS0118`), Unit-Tests per `dotnet test`;
- der Symbol-Store mit `-p:ContinuousIntegrationBuild=true` — das ist, was `-ci` an MSBuild weitergibt; seine uebrigen Folgen (Binlog an, Node-Reuse aus, Paket-Cache `.packages` im Repo, NuGet-Wiederholungen) setzt nur das Skript;
- `-mt`, `-nodeReuse`, `-bl`, `/warnaserror` und `msbuild.exe` statt `dotnet msbuild` sind
  gewoehnliche MSBuild-Schalter bzw. -Aufrufe, das Skript reicht sie nur durch.

### Was nur mit ihnen geht

- **Ablage von log, tmp und toolset unter der Wurzel**: Binlog-Default, `TEMP`, `MSBUILDDEBUGPATH`
  und der Abgleich `ATLAS0115` (`docs/configuration.md`, "Wurzel `ArtifactsDir`"). Ohne Skript gilt
  der MSBuild-Default-Ort.
- **`-clean`**: loescht den ganzen Baum unter `ArtifactsDir`, mit der Schutzliste aus
  `docs/configuration.md`; `dotnet clean` raeumt nur je Projekt.
- **SDK-Installation**: fehlt die Version aus `global.json` (`tools.dotnet`), laedt das Skript sie
  nach `.dotnet/`. `dotnet build` bricht dann mit der `errorMessage` aus `global.json` ab.
- **Die Toolset-Schritte** im SDK-Paket (`toolset/*.proj`), die nur das Skript startet:
  - `-sign` und `-publish`, samt Hochladen (`UsingNuGetPush`, `NuGetPushUrls`) und den
    Signing-/Publishing-Einstellungen aus `Config.props`;
  - Restore der Repo-Tools (`.config/dotnet-tools.json`) mit Wiederholung
    (`RestoreRepoToolsMaxAttempts`);
  - WiX v3: das Paket `wix` holt nur `Restore.cmd`/`Build.cmd` (`UsingToolWix3`, `Wix3Version`),
    auch fuer die Kanaele ohne Skript; `-msbuildEngine vs` reicht zudem `WixTargetsPath` weiter;
  - `-deploy`/`-deployDeps` (VSIX);
  - die Hooks `eng/Build.props`, `eng/Signing.props`, `eng/Publishing.props`, `eng/Tools.props`,
    `eng/AfterSolutionBuild.targets`, `eng/AfterSigning.targets`.
- **`-integrationTest`/`-performanceTest` ueber die ganze Solution**: `dotnet test` kennt diese
  Stufen nicht; ohne Skript nur je Projekt mit `dotnet build -t:IntegrationTest` bzw.
  `-t:PerformanceTest`.

### Bezug und Gleichlauf

Bezug und Gleichlauf von `eng/common` und den Wurzelskripten sind Aufgabe von Volo
(`docs/roadmap.md`, Phase 5, TemplateBundle-Pillar). Bis dahin:

- **Stand:** die Skripte kommen aus diesem Repo, vom Commit des Pakets, das die `global.json`
  pinnt — das Skript laedt sein Toolset aus genau diesem Paket. Atlas setzt keine Git-Tags; den
  Commit nennt das Paket selbst (`repository commit` im nuspec).
- **Erstbezug, von Hand:** `eng/common` und die sechs Wrapper vom Commit des gepinnten Pakets
  kopieren. Ohne `eng/common` im Repo laeuft das Update-Skript nicht.
- **Gleichlauf, per Skript:** Version in `global.json` heben, dann `eng/common/update-atlas.ps1`
  (`eng/common/update-atlas.sh` unter POSIX) laufen lassen und das Ergebnis mit der ausgegebenen
  Commit-Nachricht committen. Das Skript ersetzt `eng/common` und die sechs Wrapper durch den Stand
  dieses Commits, zieht `eng/Version.Details.xml` und die Versions-Properties nach und committet
  selbst nichts. An den Kopien wird nichts geaendert (`eng/common/README.md`); weicht eine davon vom
  zuletzt geholten Stand ab, bricht es mit der Liste ab. Ebenso haelt es bei nicht committeten
  Aenderungen an; Dateien, die sich nur im Modus unterscheiden (etwa `chmod +x` ohne `git add`),
  nennt es getrennt, mit den Befehlen zum Uebernehmen (`git add --`) und Zuruecknehmen
  (`git restore --`). Die Schalter heissen unter bash
  `--latest`, `--what-if`, `--check`, `--force`.
  - `-latest` nimmt statt der `global.json` die neueste Version der Paketquellen und schreibt sie
    dorthin.
  - `-whatIf` rechnet alles und zeigt Diff und Commit-Nachricht, schreibt aber nichts.
  - `-check` schreibt nichts und meldet je Befund eine Zeile (Update faellig, Handaenderung,
    fehlendes Ausfuehrungsrecht) — fuer die CI.
  - `-force` laeuft trotz geaendertem Arbeitsbaum, Handaenderungen, nicht erreichbarem altem Commit
    oder widerspruechlichen Versionsdateien weiter und nennt jede uebergangene Sperre.
  - Exit-Codes: `0` alles gut, `2` Befund (nur `-check`), jeder andere ein Fehler — das Skript selbst
    meldet `1`, das eingebundene `tools.ps1`/`tools.sh` kann einen eigenen durchreichen.

## Lokal ausprobieren

Eine Aenderung am SDK-Quellbaum selbst zeigt sich einem Konsumenten nicht automatisch: der lokale
Bau erzeugt immer dieselbe Entwicklungsversion (`10.0.0-dev`, `docs/versioning.md`), und NuGet
bedient eine bereits im globalen Paket-Cache liegende Version, ohne erneut auf die Quelle zu
schauen — ein zweiter lokaler Bau unter derselben Versionsnummer wird sonst still ignoriert.

`eng/tryout.ps1` (`eng/tryout.sh` unter POSIX) loest das:

1. Packt `DotNet.Atlas.Sdk` in der gewuenschten Konfiguration (Default `Release`).
2. Entfernt **genau diese eine Version** (`10.0.0-dev`) aus dem globalen NuGet-Cache — nichts
   anderes, kein anderer Konsument und kein veroeffentlichtes Paket ist betroffen.
3. Gibt den lokalen Paketordner (ausgewertet als `ArtifactsShippingPackagesDir` des SDK-Projekts,
   standardmaessig `artifacts/packages/<Konfiguration>/Shipping`, aber nicht fest verdrahtet) und die
   gepackte Versionsnummer aus.

```powershell
.\eng\tryout.ps1
```

Ein Test-Konsument zeigt danach auf den lokalen Bau statt auf `cella`:

```json
{
  "msbuild-sdks": {
    "DotNet.Atlas.Sdk": "10.0.0-dev"
  }
}
```

```xml
<packageSources>
  <add key="atlas-local" value="<vom Skript ausgegebener Ordner>" />
</packageSources>
<packageSourceMapping>
  <packageSource key="atlas-local">
    <package pattern="DotNet.Atlas.*" />
  </packageSource>
</packageSourceMapping>
```

Nach jeder weiteren Aenderung am SDK: `eng/tryout.ps1` erneut laufen lassen, dann den
Test-Konsumenten neu bauen. Haelt ein Prozess eine Cache-Datei fest (offene IDE, ein laufender
`dotnet build-server`), bricht das Skript laut ab, statt einen halb geleerten Cache-Eintrag zu
hinterlassen.

## Integrationstests

Ein Testlauf schreibt nur unter den git-ignorierten Build-Ausgabeordner des Repos (#131):
`src/DotNet.Atlas.Sdk.IntegrationTests` legt seine Sitzung (Feed, Paket-Cache, Konsumenten-Repos)
einmal je Lauf unter `artifacts/tmp/<Konfiguration>/e2e/` an, die Unit-Tests ihren Ordner unter
`artifacts/tmp/<Konfiguration>/unit/`. `TEMP`/`TMP`/`TMPDIR` zeigen fuer den Testprozess und jeden
Kindprozess dorthin. Jeder Lauf entfernt zuerst, was fruehere Laeufe dieses Klons liegen liessen —
ausser einer Sitzung, deren `session.lease` (Unit-Tests: `run.lease`) ein laufender Prozess noch
offen haelt. Die Sitzungswurzel traegt leere `Directory.*`-Dateien, eine `NuGet.config`, die jeden
Abschnitt der Repo-`NuGet.config` leert, und eine `.editorconfig` mit `root = true`, damit die
Konsumenten-Repos nichts von der Repo-Wurzel erben. `GIT_CEILING_DIRECTORIES` haelt `git` selbst im
Testordner; SourceLink kennt diese Grenze nicht, ein Test, der ohne Repository rechnet, stellt das
selbst her (etwa mit einem leeren `git init` im Konsumenten).

Zwei Saetze, ein Harness:

| Befehl | Umfang |
|---|---|
| `.\Build.cmd -integrationTest` | voller Satz — das Gate |
| `.\Build.cmd -integrationTest /p:TestScope=innerloop` | schneller Satz fuer Zwischenstaende: nur Klassen ohne `[OuterLoop]` |
| `.\Build.cmd -integrationTest /p:TestScope=outerloop` | nur die Klassen mit `[OuterLoop]` |

- **Voraussetzung auch unter Linux/macOS:** PowerShell 7 (`pwsh`) im PATH. Die Skriptkanal-Klassen
  (`ScriptLayoutAgreementTests`, `ArtifactsDirScriptMsBuildAgreementTests`, `AtlasSdkPackageCacheRaceTests`,
  `SyncEngCommonNewUpstreamEntryTests`) starten `tools.ps1` bzw. `sync-eng-common.ps1` darueber; ohne
  `pwsh` scheitern sie, statt uebersprungen zu werden.
- **Laenge der Repo-Wurzel unter Windows: hoechstens 73 Zeichen** (Debug-Bau; unter Release zwei weniger).
  Der VSSDK und WiX (gemessen: 5.0.2, 6.0.2) nehmen hoechstens 259 Zeichen je Pfad, gleich was `LongPathsEnabled`
  sagt, und der tiefste Pfad des Laufs, eine Paketdatei, die der VSSDK in die VSIX packt, liegt 186 Zeichen unter
  der Wurzel. Der Harness prueft das vor dem ersten Test und bricht mit `The repo root is too long for the integration tests under Windows` ab — samt Wurzel-Laenge, tiefstem
  Pfad, den groessten Segmenten und der laengsten Wurzel, die passt. Messung:
  [`docs/research/2026-09-28T1518Z-long-repo-root.md`](docs/research/2026-09-28T1518Z-long-repo-root.md) (#143).
- **`[OuterLoop]`** (Trait `category=outerloop`, arcades Name) traegt jede Klasse, die einen echten
  Bau oder sonst einen Kindprozess startet. Im schnellen Satz laesst ein Windows-Job-Objekt, unter Linux
  (x86_64, arm64) ein seccomp-Filter keinen Kindprozess zu; eine fehlende Markierung faellt dort als roter
  Test auf, nicht als langsamer.
- **Reine Property-Auswertung** laeuft im Testprozess (`Microsoft.Build.Locator`, das SDK aus
  `global.json`); was `.rsp`, Prozess-Umgebung, `MSBuild.exe` oder den Skriptkanal prueft, bleibt
  Kindprozess. `InProcessEvaluationParityTests` haelt beide Wege gegeneinander.
- **Bau-Tor:** hoechstens so viele Kindbauten gleichzeitig wie logische Prozessoren (`ATLAS_E2E_MAX_BUILDS` setzt einen anderen Wert), ein Bau mit `-m:k`
  zaehlt k-fach; ohne eigene Angabe baut jedes Kind mit `-m:1` (auch der Skriptkanal). Das Zeitlimit eines Prozesses
  zaehlt ab dem Tor.
- **Buendelung:** wartende Bauten am Tor laufen gemeinsam in einem Kindprozess; jeder Test behaelt sein
  eigenes Repo und bekommt nur Ausgabe und Exit-Code seines Baus. Allein laeuft, was ein Buendel nicht
  gleich faehrt (eigene Umgebung, Arbeitsordner ausserhalb des Repos, Response-Datei, weitere Schalter,
  andere SDK- oder Paket-Pins, ein Restore ueber schon vorhandene NuGet-Importe). `ATLAS_E2E_BATCH=0` schaltet die Buendelung ab - der erste Schritt,
  wenn ein Test nur gebuendelt rot ist; `BatchParityTests` haelt beide Wege gegeneinander.
- **Laufbericht:** jeder Lauf schreibt `DotNet.Atlas.Sdk.IntegrationTests_timing.md`/`.json` nach
  `artifacts\TestResults\<Konfiguration>\` — je Klasse Faelle und Sekunden, die 15 langsamsten
  Faelle, gestartete Kindprozesse mit Budget, gebuendelte Bauten, CPU-Sekunden der Kindprozesse (auch
  je startender Klasse) und daneben die CPU geteilter Compiler-Server ausserhalb des Jobs (unter Linux:
  ausserhalb der Nachfahren des Testprozesses) als Obergrenze, Belegung und Wartezeit am Tor,
  Aufbauzeit des Harness, Wandzeit; dazu Einschluss-Stufe (`job` | `subreaper` | `none`) und Zaun
  (`os` | `launcher` | `off`) und unter Linux die Nachlauf-Liste: jeder Prozess, den die Nachlese am
  Laufende beendet hat, mit Kommandozeile und Startzeit, dazu die Dauer der Nachlese und, scheitert sie,
  der Grund. Unter Linux bleiben die Prozesszahl des Jobs und die CPU je Klasse "n/a".
- **Budget:** der schnelle Satz ist rot, wenn er laenger als 45 s braucht - gemessen ab dem Start des
  Bau-Skripts (`Build.cmd`, unter Linux `./build.sh`), also mit Bau; ohne Bau-Skript (Testprogramm
  direkt) und unter macOS zaehlt nur die Testphase. `ATLAS_INTEGRATIONTEST_BUDGET_SECONDS` setzt einen
  anderen Wert, `0` schaltet es fuer Messlaeufe ab. Build.cmd nennt den Grund als eigene Fehlerzeile
  (gemessene Zeit, Budget, Anteil Bau und Testphase). xUnit meldet ein ueberzogenes Budget als Test
  Assembly Cleanup Failure an jedem Fall - eine Ursache, nicht viele kaputte Tests.
- Unter Windows haengen alle Kindprozesse eines Laufs an seinem Job-Objekt und enden mit dem
  Testprozess; dort sperrt es im schnellen Satz auch jeden Start am Starter vorbei. Unter Linux
  (x86_64, arm64) ist der Testprozess Subreaper: Waisen des Laufs fallen an ihn, und die Nachlese
  beendet sie am Laufende (nicht bei einem Absturz des Testprozesses); im schnellen Satz sperrt dort der
  seccomp-Filter. Unter macOS verweigert nur der Starter.
