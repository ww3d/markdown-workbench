# Atlas — Versionierung

Port von arcades [`Documentation/Versioning.md`](https://github.com/dotnet/arcade/blob/291c2c52fe3d6079af97062f8918eda41e02e133/Documentation/Versioning.md)
(Pin `291c2c52`, `docs/upstream.md`), umgeschrieben auf Atlas: Aufbau, Reihenfolge und Aussagen
bleiben arcades, Bezeichner und Divergenzen sind Atlas-eigen. Beschreibt das Versionierungsschema,
das `src/DotNet.Atlas.Sdk/tools/Version.targets` und
`src/DotNet.Atlas.Sdk/tools/Version.BeforeCommonTargets.targets` implementieren, zusammen mit den
Atlas-Zusaetzen daneben (`Version.Compute.targets`, `Version.DeterministicTimestamp.BeforeCommonTargets.targets`).

## Versionierungsplan

Atlas-Pakete folgen [SemVer2](https://semver.org) fuer ihre Versionierung. Eine Version hat die
Form

```
MAJOR.MINOR.PATCH-PRERELEASE+BUILDMETADATA
```

MAJOR, MINOR und PATCH folgen SemVer2 strikt. PRERELEASE und BUILDMETADATA sind optional;
Buildmetadaten duerfen zwei Pakete nicht unterscheiden und zaehlen nicht in die Praezedenz. Zwei
Fragen bleiben offen: was in PRERELEASE und BUILDMETADATA steht, und ob die Versionierung
datumsvariierend oder datums-unabhaengig ist.

## Datums-unabhaengige vs. datumsvariierende Versionierung

Eine Build-Versionsnummer ist **datums-unabhaengig**, wenn wiederholte Builds desselben Commits
dieselbe Version ergeben (z. B. ueber Commit-Tiefe), und **datumsvariierend**, wenn sie sich aus
Datum und Tageszaehler ergibt.

**Datums-unabhaengig.** Vorteile: reproduzierbar ohne externen Input; parallele, unabhaengige
Build-Zweige brauchen keine Orchestrierung; Buildmetadaten (SHA) machen die Quelle leicht
identifizierbar. Nachteile: manche Feeds vertragen kein erneutes Publizieren derselben
Version-/Namens-Kombination; die meisten Builds sind bei gleichem Input nicht bit-identisch, ein
Teil-Respin erzwingt also das Leeren von Package-Caches; unterschiedliche Build-Konfigurationen
(z. B. checked vs. release) lassen sich ueber die Version allein nicht unterscheiden.

**Datumsvariierend.** Vorteile: Respins ueberschreiben nichts ausser Release-Versionen am Ende
eines Zyklus; Nicht-Standard-Builds kollidieren nicht mit Standard-Builds desselben Commits;
Datei-Versionen steigen monoton (MSI-Anforderung); der Determinismus bleibt erhalten, das Datum
ist nur ein weiterer Build-Parameter (`OfficialBuildId`), und ein erneuter Build mit demselben
Datum erzeugt aequivalente Binaries. Nachteile: mehrere Build-Zweige brauchen Orchestrierung fuer
eine kohaerente Version; identische Bits ueber zwei Builds hinweg zu reproduzieren braucht die
Kenntnis der Input-Parameter; die Quell-SHA ist aus der Version allein nicht ablesbar.

**Fazit (arcade, von Atlas uebernommen):** datumsvariierend, kombiniert mit der SHA als
Buildmetadatum — eindeutig, identifizierbar und ohne die Nachteile datums-unabhaengiger
Versionierung.

## Build-Determinismus

Datumsvariierende Versionierung schliesst Determinismus nicht aus: Das Datum ist entweder ein
uebergebener Parameter oder kommt aus Git-Informationen; ein an einem festen Commit fest gesetzter
Wert reproduziert dieselben Outputs immer wieder. Datumsvariierend heisst nur, dass dieser Input
**standardmaessig** von Build zu Build wechselt.

## Build-Arten

Die Build-Art ergibt sich aus den globalen Properties `ContinuousIntegrationBuild`,
`OfficialBuildId` und `DotNetFinalVersionKind`:

| `ContinuousIntegrationBuild` | `OfficialBuildId` | `DotNetFinalVersionKind` | Build-Art |
|---|---|---|---|
| `false` | leer | leer | Lokaler Entwickler-Build |
| `true` | leer | leer | PR-Validierungs-Build |
| `true` | `yyyymmdd.r` | leer | Taeglicher Official Build |
| `true` | `yyyymmdd.r` | `prerelease` | Finaler Prerelease-Official-Build |
| `true` | `yyyymmdd.r` | `release` | Release-Official-Build |

## `DotNetUseShippingVersions`

Ohne `OfficialBuildId` und ohne diesen Schalter tragen lokale und PR-Builds feste, nicht datierte
Platzhalterwerte: `Version` = `X.Y.Z-dev`, `FileVersion` = `42.42.42.42424`, `AssemblyVersion` =
`42.42.42.42` (Target `_InitializeAssemblyVersion` in `Version.targets`, gegated auf
`VersionSuffixDateStamp == ''` in `Version.BeforeCommonTargets.targets`), `VsixVersion` =
`42.42.42.4242424` und `MsiVersion` = `42.42.42424.42` (#83). Die Platzhalter sind erkennbar, nicht
geordnet; die Round-Trip- und Monotonie-Waechter der `MsiVersion` nehmen ihren Platzhalter
ausdruecklich aus.

`DotNetUseShippingVersions=true` schaltet fuer einen nicht offiziellen Build denselben
Berechnungspfad wie fuer einen Official Build ein: Datum und Tageszaehler kommen dann vom
aktuellen UTC-Datum, `r = 1`. Das ist nuetzlich, um MSI-Installationen aus einem Dev-Build testweise
gegeneinander zu installieren — Datei-Versionen muessen dafuer steigen. Ein so gebauter Build ist
dadurch nicht mehr deterministisch: derselbe Commit erzeugt an verschiedenen Tagen verschiedene
Versionen.

## Versionsteile aus dem Repository

Ein Repo bzw. Projekt gibt das dreiteilige Versionspraefix ueber `VersionPrefix`
(**MAJOR.MINOR.PATCH**) vor — repo-weit in `Config.props`, nicht in `eng/Versions.props`
(`docs/configuration.md` § "Versionsquellen") —, alternativ zweiteilig ueber `MajorVersion`/`MinorVersion` (PATCH
defaultet dann auf `0`). Ist nichts gesetzt, gilt `1.0.0`.

Grenzen, und wer sie durchsetzt: **MINOR** 0–654 und **PATCH** 0–9999 prueft Atlas selbst und
bricht sonst ab (`MaxMinor` und `MaxBuild` in
`src/DotNet.Atlas.Sdk/src/CalculateAssemblyAndFileVersions.cs`). Fuer **MAJOR** gibt es keine
Atlas-Pruefung; die Obergrenze 65535 folgt aus der Feldbreite einer Assembly-Version und schlaegt
erst im Compiler zu.

## Package-Version

Die Package-Version besteht aus **PACKAGE_MAJOR.PACKAGE_MINOR.PACKAGE_PATCH** plus optionalem
Prerelease-Label:

| Build-Art | Prerelease-Label | Beispiel |
|---|---|---|
| Lokaler Entwickler-Build | `dev` | `1.2.3-dev` |
| PR-Validierungs-Build | `ci` | `1.2.3-ci` |
| Taeglicher Official Build | **PRERELEASE_LABELS**.**SHORT_DATE**.**REVISION** | `1.2.3-preview.1.12345.1` |
| Finaler Prerelease-Official-Build | **PRERELEASE_LABELS**.`final` | `1.2.3-beta.1.final` |
| Release-Official-Build | (leer) | `1.2.3` |

**PRERELEASE_LABELS** in Official Builds: `PreReleaseVersionLabel` plus `PreReleaseVersionIteration`,
getrennt durch `.` (SemVer2) oder ohne Trenner (`SemanticVersioningV1=true`); ohne Iteration entfaellt
der Zusatz.

In Official Builds werden **SHORT_DATE** und **REVISION** aus `OfficialBuildId` (Format
`20yymmdd.r`) abgeleitet: **REVISION** = `r`, **SHORT_DATE** = `yy * 1000 + mm * 50 + dd`. In PR- und
Entwickler-Builds fehlen beide, ausser `DotNetUseShippingVersions=true` setzt sie aus dem aktuellen
Datum mit `r = 1` (Abschnitt oben) — nicht deterministisch.

**Tageszaehler-Cap 99 (Atlas-Divergenz zu arcade).** arcade laesst `r` bis 199 zu; Atlas bricht den
Build bei `r >= 100` ab (`The daily counter encoded in BuildNumber must be between 0 and 99, …`, `MaxDailyCounter` in
`src/DotNet.Atlas.Sdk/src/BuildNumberParser.cs`, den MsiVersion und FileVersion teilen). Grund: Tag und Tageszaehler teilen
sich dieselben Stellen der berechneten **FILE_REVISION** (Abschnitt "Datei-Version" unten, Formel
`(50 * mm + dd) * 100 + r`) — ein Zaehler ab 100 griffe in die Stellen des Folgetags, und ein
spaeterer Build am selben Tag bekaeme eine niedrigere Datei-Version, genau die, die ein
MSI-Upgrade zur Entscheidung liest. Massgeblich fuer Konsumenten: `docs/configuration.md`
§ "Tageszaehler in `OfficialBuildId`"; Beleg: `docs/decisions.md`, Eintrag "2026-08-03 — #39".

**PATCH_NUMBER** = (**SHORT_DATE** - `VersionBaseShortDate`) * 100 + `r`, `VersionBaseShortDate`
defaultet auf `19000` (nur zusammen mit einer MAJOR- oder MINOR-Erhoehung aendern). Ist ein Paket
**release-only** (`PreReleaseVersionLabel` leer), traegt seine Package-Version im Official Build
kein Prerelease-Label, und jeder Official Build muss ein eindeutiges **PATCH_NUMBER** erzeugen;
ein Repo erreicht das dauerhaft mit `ReleaseOnlyVersion=true` in `Config.props` (ein leeres
`PreReleaseVersionLabel` allein fuellt der Default `preview` wieder; MSBuild unterscheidet "leer
gesetzt" nicht von "nicht gesetzt"). Diese Regel gilt nicht fuer Entwickler- und
PR-Validierungs-Builds (kein eindeutiges
`OfficialBuildId` dort). `SuppressFinalPackageVersion=true` haelt ein Projekt trotz finalem,
stabilem Repo-Build auf Prerelease-Paketen.

Die dreiteilige Package-Version selbst:

| Teil | Wert | Bedingung |
|---|---|---|
| **PACKAGE_MAJOR** | **MAJOR** | |
| **PACKAGE_MINOR** | **MINOR** | |
| **PACKAGE_PATCH** | **PATCH** | `PreReleaseVersionLabel` nicht leer |
| | **PATCH_NUMBER** | sonst |

**Atlas' eigenes Werkzeug-Paket weicht von § "Empfohlene Einstellungen" ab.** `DotNet.Atlas.VersionInfo`
(`atlas-version`) ist ein Global Tool, traegt aber dieselbe Package-Version wie das SDK-Paket desselben Laufs,
mit dessen Prerelease-Label. Grund: Werkzeug und SDK teilen die Leser im Quelltext, ein Pack-Lauf und eine
Version sagen, welche Leser ein Werkzeug hat, ohne zweites Versionsschema und zweiten Release-Schritt
(`docs/decisions/2026-09-28T1910Z-atlas-126-version-reader-decisions.md`, Entscheidung 5). Preis: eine
Installation braucht bis zum finalen Release `--prerelease` oder eine genannte Version
(`docs/configuration.md` § "Dasselbe ohne Projekt: `atlas-version`"). Die andere Empfehlung,
`AutoGenerateAssemblyVersion=true`, setzt das Werkzeug.

## Assembly-Version

Vierteilige Version (**ASSEMBLY_MAJOR.ASSEMBLY_MINOR.ASSEMBLY_PATCH.ASSEMBLY_REVISION**).
**PATCH_NUMBER_HI** = **PATCH_NUMBER** / 50000, **PATCH_NUMBER_LO** = **PATCH_NUMBER** % 50000.

| Teil | Wert | Bedingung |
|---|---|---|
| **ASSEMBLY_MAJOR** | **MAJOR** | |
| **ASSEMBLY_MINOR** | **MINOR** | |
| **ASSEMBLY_PATCH** | **PATCH** | `AutoGenerateAssemblyVersion` = `false` |
| | **PATCH_NUMBER_HI** | sonst |
| **ASSEMBLY_REVISION** | `0` | `AutoGenerateAssemblyVersion` = `false` |
| | **PATCH_NUMBER_LO** | sonst |

## Datei-Version (File Version)

Vierteilige Version (**FILE_MAJOR.FILE_MINOR.FILE_PATCH.FILE_REVISION**), muss in jedem Official
Build steigen (MSI-Anforderung). Ist `AutoGenerateAssemblyVersion=true`, ist die Datei-Version
identisch zur Assembly-Version, sonst:

| Teil | Wert |
|---|---|
| **FILE_MAJOR** | **MAJOR** |
| **FILE_MINOR** | **MINOR** * 100 + **PATCH** / 100 |
| **FILE_PATCH** | (**PATCH** % 100) * 100 + `yy` |
| **FILE_REVISION** | (50 * `mm` + `dd`) * 100 + `r` |

Der Tageszaehler-Cap 99 (Abschnitt "Package-Version" oben) gilt hier mit derselben Begruendung:
**FILE_REVISION** ist die Formel, deren Monotonie der Cap sichert.

## VSIX-Version

`VsixVersion` = `VsixVersionPrefix`.**SHORT_DATE** `r` (zweistellig), arcade-gleich; `VsixVersionPrefix`
defaultet auf den **urspruenglichen** `VersionPrefix` (#83) — ein release-only-Build schreibt die
dritte Stelle von `VersionPrefix` auf **PATCH_NUMBER** um, und das Datum stuende sonst doppelt in der
Version (gemessen `1.2.747301.2647301`). `DotNetFinalVersionKind=release` ohne release-only aendert
`VsixVersion` nicht. Ein VSIX-Manifest mit dem Token `|%CurrentProject%;GetVsixVersion|` bekommt sie beim
Bau; Atlas prueft danach Format und Gleichheit (`ATLAS0107`/`ATLAS0108`). Fuer
VisualStudio.Extensibility schreibt Atlas dieselbe `VsixVersion` nach `CoreCompile` direkt in
`Identity/@Version` des generierten Manifests und ueberschreibt damit einen im Code gesetzten Wert;
`ThisAssembly.VsixVersion` steht dem Projekt nur zur Anzeige bereit.

**Zweite Begruendung des Caps 99:** die Revision der `VsixVersion` (**SHORT_DATE** * 100 + `r`) folgt
derselben Formel wie **FILE_REVISION**. Mit arcades `r` bis 199 laege `20260923.100` (Revision
`26473100`) ueber dem Folgetag `20260924.1` (`2647401`) — die Monotonie braeche fuer VSIX-Updates genauso.

## MSI-Version (`MsiVersion`)

Fuer WiX-Projekte rechnet Atlas die MSI-`ProductVersion` als `MsiVersion` (nicht `ProductVersion`, das
in WiX-v3-Projekten die Formatkennung ist; Task `CalculateMsiVersion`). Windows Installer vergleicht nur
die ersten drei Felder (255/255/65535), das vierte wird gespeichert und angezeigt, aber nie verglichen;
Burn vergleicht alle vier. Eine streng monotone, umkehrbare Abbildung in drei Felder gibt es nur mit
begrenzten Wertebereichen (Decision-Log `2026-09-24T0045Z`, Entscheidung 7), deshalb zwei Schemata,
gewaehlt ueber `MsiVersionScheme`:

| Schema | Formel | Beispiel `1.2.3` @ `20260923.5` | Grenzen |
|---|---|---|---|
| `Readable` (Default) | `MAJOR.MINOR.Tage.(PATCH*100+r)`, Tage seit 2000-01-01 | `1.2.9762.305` | MAJOR ≤ 255, MINOR ≤ 255, PATCH ≤ 654 |
| `Packed` | `V = ((MAJOR*36 + MINOR)*36525 + Tage)*100 + r`; Felder `V>>24`, `(V>>16)&255`, `V&65535`, viertes Feld PATCH | `8.84.48453.3` | MAJOR ≤ 31, MINOR ≤ 35, PATCH ≤ 65534 |

- **Ordnung und benannte Kroeten.** `Readable`: Major > Minor > Tag; Builds desselben Tages sind fuer MSI
  gleich — das Paket setzt dafuer `AllowSameVersionUpgrades="yes"` in seinem `MajorUpgrade` (ICE61), und ein Downgrade innerhalb eines Kalendertags
  derselben Linie ist deshalb still moeglich. `Packed`: Major > Minor > Tag > `r`, streng **ohne PATCH** — PATCH steht im vierten Feld, das Windows Installer nicht vergleicht; **deshalb sind zwei
  Builds, die sich nur im PATCH unterscheiden (gleicher Tag, gleiches `r`), fuer MSI gleich und
  installieren sich nebeneinander** (zwei Produkte in ARP, gemessen im State Audit M11); am Build ist das
  nicht erkennbar. Beleg: `CalculateMsiVersionMonotonicityTests.Execute_Packed_PatchOnlyDifference_ProducesIdenticalMsiFields_DocumentedSideBySideToad`
  (Packed-PATCH-Fall mit dem MSI-Komparator).
- **Rueckrechnung** exakt auf MAJOR, MINOR, PATCH, Datum und `r`, in beiden Schemata (Waechter mit dem
  MSI- und dem Burn-Komparator).
- **Pruefung:** Atlas prueft alle vier Felder gegen die MSI- und die Schemagrenzen und bricht vor WiX ab,
  statt still ueberzulaufen (arcade packt bitweise ohne Pruefung).
- **Jahresgrenze 2099:** gemeinsame Grenze des ganzen Schemas (die Datei-Version traegt `yy`), keine
  MSI-Grenze; ein Build-Datum ausserhalb 2000-2099 bricht ab.
- **Release-only** nimmt PATCH aus dem urspruenglichen `VersionPrefix`, nicht aus dem umgeschriebenen.
- **Bundles:** ab WiX v4 traegt das Bundle die Atlas-SemVer (Burn ordnet SemVer); ein WiX-v3-Bundle die
  `MsiVersion` (v3-Burn vergleicht vier UInt16).
- **Die volle Atlas-Version** steht als Preprozessor-Variable `AtlasVersion` bereit und als MSI-Property
  `AtlasVersion`, sobald das Projekt `<PropertyRef Id="AtlasVersion" />` traegt — der WiX-Linker uebernimmt
  ein unreferenziertes Fragment nicht (gemessen); ARP zeigt sonst nur die kodierte Zahl. Dieselbe Zeile
  bringt die MSI-Property `AtlasCommit` mit, den Commit des Builds (`GitHeadSha`); ohne Commit fehlt sie.
- **Inkrementalitaet:** WiX baut bei einer nur geaenderten Preprozessor-Variable nicht neu (State Audit
  M10); Atlas schreibt die Werte deshalb in eine generierte Datei unter `obj`, die Eingang des WiX-Builds
  ist — eine neue `OfficialBuildId` im selben `obj` liefert die neue Version.

## Empfohlene Einstellungen

**Global Tools:** `AutoGenerateAssemblyVersion=true` und `PreReleaseVersionLabel` leer (Paket ist
release-only). **MSBuild-Task- und Analyzer-Projekte:** `AutoGenerateAssemblyVersion=true`.
**Bibliotheken** fuer .NET Standard oder .NET Framework: `AutoGenerateAssemblyVersion=false`
belassen — sonst muessen Konsumenten bei jedem neuen Build ihre Binding-Redirects nachziehen.

## SemVer1-Fallback

Wo SemVer2 nicht nutzbar ist (aeltere NuGet-Versionen), faellt Atlas wie arcade auf
[SemVer1](https://semver.org/spec/v1.0.0.html) zurueck: keine eingebauten Buildmetadaten, das
Prerelease-Feld nur `[0-9A-Za-z-]`. `+` und `.` aus dem SemVer2-Prerelease-Feld werden dabei durch
`-` ersetzt. Opt-in ueber `SemanticVersioningV1=true`. Beispiele: `1.2.3-dev`, `1.2.3-ci`,
`1.2.3-beta-12345-01`, `1.2.3-beta-final`, `1.2.3` (die Zahl in `-01` ist zweistellig gepolstert).

## Generierung der Assembly-Informational-Version

Das .NET-SDK generiert die Informational Version; referenziert ein Projekt SourceLink
(Atlas-Default), haengt es die volle Commit-SHA an:
`[AssemblyInformationalVersionAttribute("1.2.3-beta.12345.1+fe80f83075d723eddd6e26582c75f27f242c69c4")]`.
`/p:IncludeSourceRevisionInInformationalVersion=false` unterdrueckt den `+<sha>`-Teil (auch in
`ProductVersion`) — davon wird abgeraten, weil sich der Quell-Commit sonst nicht mehr aus der
Assembly ablesen laesst; noetig nur, wenn ein Konsument zwingend SemVer1 parst. In Builds ohne
Datumsstempel (`VersionSuffixDateStamp` leer) setzt Atlas `IncludeSourceRevisionInInformationalVersion=false`
selbst (`Version.BeforeCommonTargets.targets`), damit unveraenderte Artefakte deterministischer
Builds teilbar bleiben.

Wie Atlas die Informational Version zusaetzlich mit einer BuiltBy-Annotation versieht (Host, Branch
und Commit im Dev-Build, nur Commit im Official Build) und wie sich das zwischen managed und
nativem Code unterscheidet, steht in `docs/configuration.md` § "BuiltBy-Annotation (nativ und
managed)" — das ist ein eigener Emitter-Mechanismus, keine Aenderung an der hier beschriebenen
Versionsberechnung.

## NuGet-Paket-Repository-Informationen

Pakete aus einem Projekt mit SourceLink-Referenz, gepackt mit dem Standard-NuGet-Pack-Target,
tragen Repository-URL und Commit-SHA in der Nuspec:

```xml
<repository type="git" url="https://github.com/<org>/<repo>" commit="<volle-sha>" />
```

## Implementierung

`src/DotNet.Atlas.Sdk/tools/Version.targets` implementiert das hier beschriebene Schema,
`src/DotNet.Atlas.Sdk/tools/Version.BeforeCommonTargets.targets` die Vorstufe davon. Atlas' zentrale
Berechnung der abgeleiteten Werte steht in `Version.Compute.targets`, die `DeterministicTimestamp`-Ableitung des
offiziellen Builds in `Version.DeterministicTimestamp.BeforeCommonTargets.targets` (beide #126). Ein Konsument,
der das Atlas-SDK nutzt, bekommt das Schema automatisch — kein weiterer Schritt noetig.

### Parameter

| Parameter | Umfang | Beschreibung |
|---|---|---|
| `OfficialBuildId` | Atlas | ID des aktuellen Builds, Format `yyyyMMdd.r` (`r` <= 99, siehe oben). Wird dem Build von aussen mitgegeben. |
| `SemanticVersioningV1` | Atlas | `true` fuer SemVer1-kompatible Versionen. Default `false`. |
| `DotNetUseShippingVersions` | Atlas | `true` erzeugt datierte Versionsstrings auch in nicht offiziellen Builds statt fixer Platzhalter wie `42.42.42.42`. |
| `DotNetFinalVersionKind` | Atlas | Art der erzeugten Version: `release`, `prerelease` oder leer. |
| `PreReleaseVersionLabel` | Atlas | Prerelease-Label (z. B. `beta`, `preview`). `ci` und `dev` sind fuer nicht offizielle CI- bzw. Entwickler-Builds reserviert. |
| `PreReleaseVersionIteration` | Atlas | Numerische Iteration des Prerelease-Labels, mit `.` angehaengt (SemVer2) bzw. ohne Trenner (SemVer1). |
| `VersionPrefix` | .NET-SDK | Fuehrender Teil der Version. Leer und beide `MajorVersion`/`MinorVersion` gesetzt: `$(MajorVersion).$(MinorVersion).0`. |
| `MajorVersion` | Atlas | Major-Version fuer `VersionPrefix`. |
| `MinorVersion` | Atlas | Minor-Version fuer `VersionPrefix`. |
| `ContinuousIntegrationBuild` | .NET-SDK | Ob der Build auf einem CI-Server laeuft (PR- oder Official Build). |

### Ausgabe

Von der Atlas-SDK-Versionierung gesetzte Properties, verfuegbar nach `GetAssemblyVersion`:

| Name | Umfang | Beschreibung |
|---|---|---|
| `OfficialBuild` | Atlas | `true`, wenn `OfficialBuildId` nicht leer ist. |
| `AssemblyVersion` | .NET-SDK | `42.42.42.42`, wenn im Projekt nicht gesetzt, der Build nicht offiziell ist und `DotNetUseShippingVersions` nicht `true` ist. |
| `FileVersion` | .NET-SDK | `42.42.42.42424` unter denselben Bedingungen. |
| `VersionPrefix` | .NET-SDK | `$(MajorVersion).$(MinorVersion).0`, wenn vom Projekt nicht gesetzt. |
| `VersionSuffix` | .NET-SDK | Suffix-Teil der Version inklusive Prerelease-Anteil. |

## Release

Ablauf fuer eine offizielle, veroeffentlichte Version des Atlas-SDKs, in zwei Aufrufen. Er gilt fuer beide
Pakete des Repos, `DotNet.Atlas.Sdk` und `DotNet.Atlas.VersionInfo` (`atlas-version`): der erste Aufruf packt
beide mit derselben Version, der zweite schiebt alles, was unter `artifacts/packages/<Konfiguration>/Shipping/`
liegt.

```
.\Build.cmd -pack -configuration Release /p:OfficialBuildId=<20yymmdd.r>
.\eng\common\build.ps1 -publish -configuration Release /p:OfficialBuildId=<20yymmdd.r> /p:UsingNuGetPush=true
```

Der erste baut und packt, der zweite veroeffentlicht **ohne neu zu bauen** — so bleibt ein Paket, das
zwischen den beiden Aufrufen von Hand signiert wurde, unberuehrt. `OfficialBuildId` gehoert in beide
Aufrufe, und zwar derselbe: ohne ihn bricht der Push ab (Punkt "Kein Push ohne Datum" unten).

**Versionslinie** (Entscheid @ww3d 2026-09-26, [#124, Antwort zu Punkt 35](https://github.com/ww3d/atlas/issues/124#issuecomment-5848118229)): Atlas folgt den .NET-Release-Kanaelen —
die Linie 10.x fuer net10, bei net11 geht Atlas auf 11.x. `Config.props` setzt dafuer
`VersionPrefix` = `10.0.0`, `PreReleaseVersionLabel` = `preview`, `PreReleaseVersionIteration` = `1`;
datierte Builds heissen `10.0.0-preview.1.<SHORT_DATE>.<r>`. Das finale 10.0 ist derselbe Stand mit
`/p:DotNetFinalVersionKind=release` in **beiden** Aufrufen oben und ergibt `10.0.0`; danach steigt
PATCH in `Config.props` (`10.0.1`, datiert `10.0.1-preview.1.*`), wie bei .NET 10.0.x. Eine neue Linie
ist ein neuer Major (`11.0.0`, Iteration wieder `1`). *Abweichung vom arcade-Brauch, nicht von seiner
Mechanik:* arcade fuehrt `release/10.0` dauerhaft als `10.0.0-beta.<SHORT_DATE>.<r>`, ohne Iteration
und nie final.

**Kadenz** (Vorgabe @ww3d 2026-09-25, #80): nach jedem gemergten PR, der den Paketinhalt aendert
(`src/DotNet.Atlas.Sdk/` oder `src/DotNet.Atlas.VersionInfo/`), folgt ein datierter Build der laufenden Linie —
so, wie es eine CI taete. Dabei wechselt nur die `OfficialBuildId` (Datum und Tageszaehler `r`); Praefix, Label
und Iteration bleiben. Ein PR ohne Paketinhalt (Tests, Doku, Repo-Skripte) loest keinen Build aus. Einen
Pin-PR gibt es nur, wenn Atlas' eigener Build oder ein Konsument den neuen Inhalt braucht.

Die Einstellungen dazu stehen in Atlas' eigener `Config.props` im Repo-Root: Produktversion
(`VersionPrefix`, `PreReleaseVersionLabel`, `PreReleaseVersionIteration`) und Hochlade-Ziel
(`NuGetPushUrls`). `UsingNuGetPush` setzt sie bewusst nicht — der Push bleibt ein Opt-in beim
Aufruf.

- **Ein vorheriger Build im selben Klon schadet nicht mehr** (seit #80, PR 2): die Datei mit
  `AtlasSdkVersion` liegt je Konfiguration und wird bei jedem Pack neu erzeugt
  (`SdkVersionFileE2ETests`). Bis dahin war vor dem ersten Aufruf `git clean -xdf -- artifacts/`
  noetig.
- **Beginnt eine neue Linie oder Vorabstufe, wird zuerst `Config.props` gehoben** (per PR, vor dem
  ersten Aufruf oben): `VersionPrefix` fuer eine neue Linie oder nach einem finalen Release,
  `PreReleaseVersionIteration` nur, wenn innerhalb einer Linie eine zweite Vorabstufe gewollt ist.
  Bleibt ein Wert auf einem aelteren Stand, sortiert ein datierter Build **unter** das bereits
  Veroeffentlichte (`0.1.0-preview.1.<datum>` < `0.1.0-preview.2.*`; `10.0.0-preview.1.*` < `10.0.0`).

- **Signieren geschieht von Hand, zwischen den beiden Aufrufen** (`dotnet nuget sign …`); es gibt
  keinen Signing-Code (`docs/decisions/2026-09-16T2231Z-atlas-45-seed-bootstrap-decisions.md`
  § "Entscheidung 3"; ein Backend ist Phase 2 in `docs/roadmap.md`).
- **Der Tageszaehler `r` in `OfficialBuildId` wird von Hand gefuehrt** — es gibt keinen Generator,
  der ihn ermittelt oder hochzaehlt.
- **Kein Push ohne Datum:** Das Push-Target
  (`src/DotNet.Atlas.Sdk/toolset/PushNuGetPackages.targets`) bricht mit Fehler ab, wenn
  `VersionSuffixDateStamp` leer ist — ein `-dev`-Paket ohne Datum ist nicht eindeutig und darf
  keinen Feed erreichen.
- **Kein Push einer Version, die schon auf dem Feed liegt:** das Target fragt vorher jeden Feed und
  bricht ab, wenn die Version dort liegt oder der Feed es nicht sagen kann (seit #80, PR 2; der
  Cella-Feed ersetzte ein veroeffentlichtes Paket beim zweiten Push, statt ihn abzulehnen). Eine
  neue `OfficialBuildId` ist der Weg, nicht das Ueberschreiben. **Fuer Atlas' eigenen Release greift
  die Pruefung erst ab dem Pin auf ein Paket, das sie enthaelt** — `-publish` nimmt das Toolset aus
  dem gepinnten Paket; bis dahin schuetzt nur die Feed-Einstellung (bei ww3d, #80).
- **Der Pin auf die neu abgelegte Version wird im naechsten eigenen PR gehoben**, nicht in
  demselben (`docs/decisions/2026-09-16T2231Z-atlas-45-seed-bootstrap-decisions.md`
  § "Entscheidung 6").
- Der Schalter heisst `UsingNuGetPush` (Default `false`), die Ziel-Liste `NuGetPushUrls` (Item, in
  `Config.props` gesetzt). Der API-Schluessel kommt aus der Umgebungsvariablen
  `ATLAS_NUGET_PUSH_API_KEY`, bewusst keine Property — ein per `-p:` uebergebener Schluessel
  laende sonst im Binlog. Ist die Variable leer, pusht der Aufruf ohne `--api-key`.
