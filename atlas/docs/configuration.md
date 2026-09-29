# Atlas — Config.props-Referenz

`Config.props` ist die Konfigurationsflaeche, ueber die ein Konsumenten-Repo dem Atlas-SDK seine
Paket-Metadaten, seine Produktversion, sein Ausgabe-Layout, sein Hochlade-Ziel und seine
Signing-/Publishing-Einstellungen mitgibt. Die Datei ist optional: fehlt sie, greifen fuer jedes Feld
die SDK-Defaults, und der Build laeuft unveraendert. Atlas selbst nutzt dieselbe Flaeche — seine
eigene `Config.props` im Repo-Root ist ein Beispiel aus dem Bestand.

Wie Atlas aus diesen Feldern die Versionsnummern rechnet, steht in
[`docs/versioning.md`](versioning.md); diese Seite beschreibt die Flaeche, nicht die Rechnung.

## Mechanik

- Ablageort: **Repo-Root**, neben `global.json` (`$(RepoRoot)/Config.props`).
- Format: eine gewoehnliche MSBuild-`PropertyGroup` (fuer `NuGetPushUrls` eine `ItemGroup`), keine
  eigene Syntax, kein Parser.
- Wirkung: SDK-weit — die Werte gelten fuer alle Projekte des Repos.
- Einhaengung: `sdk/Sdk.props` importiert zuerst `tools/AtlasConfig.Import.props`, das
  `Config.props` importiert (nur wenn vorhanden), danach `tools/AtlasConfigDefaults.props`. Jeder
  Default dort ist mit `Condition="'$(X)' == ''"` gegatet und fuellt nur, was `Config.props` nicht
  gesetzt hat. Beide laufen, bevor `ProjectDefaults.props` und `Version.BeforeCommonTargets.targets`
  die Felder konsumieren.
- Praezedenz: Abschnitt "Rangfolge" unten.
- Sichtbarkeit: auch die Toolset-Schritte (`Build.proj`, `Sign.proj`, `Publish.proj` samt Push)
  sehen `Config.props` — ihre `toolset/Directory.Build.props` importiert dasselbe `Sdk.props`.

## Rangfolge

Niedrig nach hoch (Entscheidung 4 in
[`docs/decisions/2026-09-23T0747Z-atlas-config-props-versions-decisions.md`](decisions/2026-09-23T0747Z-atlas-config-props-versions-decisions.md)):

1. **SDK-Defaults** (arcade).
2. **`Config.props`** — schlaegt jeden SDK-Default, auch die, die arcade **ohne Bedingung** und nach
   `Config.props` setzt.
3. **`eng/Signing.props`, `eng/Publishing.props`, `eng/Build.props`** — arcades Stufen-Hooks,
   optional, fuer eine gezielte Uebersteuerung je Schritt.
4. **Projektdatei und `Directory.Build.targets`** — und alles, was eine `Directory.Build.props`
   **nach** ihrem `Sdk.props`-Import setzt.

Ausserhalb der Stufen: eine **globale Property** (`-p:`) gewinnt immer, MSBuild laesst sie von keiner
Datei ueberschreiben. Eine `Directory.Build.props`-Zeile **vor** dem `Sdk.props`-Import ist keine
eigene Stufe: sie gilt, bis `Config.props` oder ein SDK-Default sie setzt — ein gegateter Default
laesst sie stehen, ein ungegateter ueberschreibt sie (wie vor #80); bei den Stufe-2-Properties
ueberschreibt sie auch ein gegateter `Config.props`-Wert (Folgen unten). `eng/Versions.props` ist
ebenfalls keine Stufe; es kommt nach `Config.props` und ueberstimmt es fuer alles ausser den
Stufe-2-Properties (Liste in den Hook-Dateien, Absatz "Wie Stufe 2 …"); die Falle fuer die
Produktversion steht in "Versionsquellen".

Keine `ImportBefore`/`ImportAfter`-Ordner; die Stufen 3 und 4 decken den Bedarf.

**Wie Stufe 2 einen ungegateten Default schlaegt.** Ein gegateter Default fuellt nur Leeres, dort
reicht, dass `Config.props` zuerst kommt. Einige arcade-Dateien setzen Werte aber ohne Bedingung und
danach — ohne Gegenmittel ueberschriebe z. B. `tools/ProjectDefaults.props` ein `DebugType` aus
`Config.props`, `toolset/Sign.props` ein `SignToolRepackParallelism`. `tools/AtlasConfig.Import.props`
leert deshalb jede solche Property unmittelbar vor dem Import und merkt sich den Wert davor; was sie
nach dem Import traegt, hat `Config.props` gesetzt und wird gemerkt, sonst kommt der Wert davor
zurueck. Je ein Hook-Punkt setzt das Gemerkte nach den Defaults wieder ein:

| Hook-Punkt | Datei | wirkt ueber |
|---|---|---|
| letzter Import von `sdk/Sdk.props` | `tools/AtlasConfig.Reapply.props` | `ProjectDefaults.props`, `VisualStudio.props` |
| in `toolset/Sign.props`, direkt vor `eng/Signing.props` | `toolset/AtlasConfig.Sign.props` | `Sign.props` |
| in `toolset/Publish.proj`, direkt vor `eng/Publishing.props` | `toolset/AtlasConfig.Publish.props` | `Publish.proj` |

Welche Properties das sind, steht als Liste in diesen Dateien; `ConfigPrecedenceScanCoverageTests`
haelt sie gegen jede ungegatete Zuweisung der SDK-Props, sodass ein neuer arcade-Default beim
naechsten Sync auffaellt. Drei Folgen muss man kennen:

- **`Config.props` ersetzt, es haengt nicht an.** Zum Zeitpunkt des Imports sind die SDK-Defaults
  noch nicht gesetzt; `<AssemblySearchPaths>$(AssemblySearchPaths);{GAC}</AssemblySearchPaths>` sieht
  deshalb nicht arcades Liste, und der gemerkte Wert `;{GAC}` ersetzt sie spaeter ganz.
- **Leer setzen schlaegt keinen ungegateten Default.** Ein leerer Wert gilt als "nicht gesetzt".
- **Fuer diese Properties liest `Config.props` beim Import einen leeren Wert** — auch wenn vorher
  schon etwas stand (Vorspann, Umgebungsvariable). Ein `Condition="'$(X)' == ''"` in `Config.props`
  greift deshalb immer (ausser bei einer globalen Property, die ohnehin gewinnt).

**Ausnahmen: was kein Default ist.** Nicht jede ungegatete Zuweisung ist ein Default, den
`Config.props` schlagen soll (Nachtraege N1, N3 und N6 im Decision-Log). Ausgenommen bleiben die
Pfade `ArtifactsLogDir` und `ArtifactsToolsetDir`, die der Wurzel folgen (Abschnitt "Ausgabe-Layout") — `Config.props`-Wert fuer sie bleibt wirkungslos; abgeleitete Werte (etwa
`ArtifactsShippingPackagesDir`, `OutputPath`, `OfficialBuild`, `IsStableBuild`) — sie werden aus
anderen Werten neu gerechnet; die Normalisierung der Layout-Felder (`ArtifactsBinDir` und
Geschwister), die den `Config.props`-Wert gerade uebernimmt; interne Verdrahtung (`Language`,
`PublishDependsOnTargets`); und Workarounds fuer Werkzeug-Grenzen (`NuGetAudit=false` im Official
Build, dotnet/msbuild#10801; `DeterministicSourcePaths` fuer F#; `ResolveNuGetPackages` fuer C++;
die `_wpftmp`-Zeilen in `Workarounds.props`) — ein `Config.props`-Wert gilt ueberall, nur im
Sonderfall des Workarounds nicht; und die SDK-Konstanten `NetCurrent`, `NetPrevious`, `NetMinimum`,
`NetFrameworkCurrent`, `NetFrameworkMinimum`, `NetFrameworkToolCurrent` — sie nennen, womit das SDK
ausgerichtet ist (auch das Toolset baut auf `NetMinimum`); ein Repo waehlt sein Ziel ueber
`TargetFramework`, ein `Config.props`-Wert fuer sie bleibt wirkungslos; und arcades Abschaltung im
Source-only-Build (`DotNetBuildSourceOnly=true` setzt `UsingToolPdbConverter` und `UsingToolVSSDK` auf
`false`, auch gegen einen `Config.props`-Wert). Die vollstaendige Liste mit Grund steht in
`ConfigPrecedenceGuardTestSupport.Invariants`.

**Stufe 4 ueber Stufe 3 gilt per Konstruktion:** die drei `eng/`-Hooks importieren nur die
Toolset-Projekte, nie ein Projekt des Repos — ein Hook-Wert erreicht keine Projekt-Auswertung. In den
Toolset-Projekten selbst gibt es umgekehrt keine Stufe 4: sie lesen weder Projektdatei noch
`Directory.Build.targets` des Repos.

## Versionsquellen: Produkt- und Abhaengigkeitsversionen

Zwei Arten Version, zwei Orte (Entscheidung 2):

- **Produktversion** — `VersionPrefix`, `PreReleaseVersionLabel`, `PreReleaseVersionIteration` —
  in `Config.props`.
- **Abhaengigkeitsversionen** in arcades Form: `eng/Versions.props` importiert
  `eng/Version.Details.props`; dort stehen die Pakete, die ein Abhaengigkeitsfluss pflegen wuerde
  (Eingabe `eng/Version.Details.xml`, Namensschema `<PaketId ohne Punkte>PackageVersion` plus
  `<…>Version`), in `eng/Versions.props` die externen. `Directory.Packages.props` referenziert nur
  Properties (`Version="$(MicrosoftBuildVersion)"`).

**Reihenfolge-Falle: keine Produktversion in `eng/Versions.props`.** `tools/DefaultVersions.props`
importiert `eng/Versions.props` **nach** `Config.props` und ohne Bedingung. Ein `VersionPrefix` dort
ueberstimmt den aus `Config.props` still — gemessen: `9.9.9` in `eng/Versions.props` ergibt
`PackageVersion` `9.9.9-dev`, obwohl `Config.props` einen anderen `VersionPrefix` setzt. Die Stufe-2-Mechanik oben greift
hier nicht, weil `VersionPrefix` nicht auf der Stufe-2-Liste steht — die fuehrt nur, was eine
SDK-Datei ungegatet setzt. Ein Repo,
das die Produktversion bisher in `eng/Versions.props` fuehrt (arcades eigene Form), zieht sie nach
`Config.props` um. Atlas haelt das fuer sich selbst mit `VersionsPropsGuardTests` fest.

## Ableitungs-Muster: merken, spaeter neu rechnen

Sechs Felder leitet Atlas aus anderen ab — `Product`, `Authors` und `Owners` aus `ProductName` und
`Company`, sowie `NoWarn`, `WarningsNotAsErrors` und die NuGet-Audit-Codes aus `AdditionalNoWarn`,
`AdditionalWarningsNotAsErrors` und `TreatNuGetAuditWarningsAsErrors`. `Copyright` folgt einem
eigenen Weg (Abschnitt "Pflichtangaben"), weil sein Jahr aus dem Commit kommt.

Diese Ableitungen binden in der **props-Phase** und werden in der **targets-Phase** noch einmal
gerechnet. Der Grund fuer beides:

- **props-Phase, weil das .NET-SDK sonst zuvorkommt.** Es setzt `Product` und `Authors` in der
  targets-Phase auf `$(AssemblyName)`. Eine Atlas-Ableitung, die erst danach laeuft und auf "noch
  leer" prueft, faende das Feld belegt und tuete nichts.
- **targets-Phase noch einmal, weil ein spaeter gesetzter Input sonst nicht ankommt.** Atlas merkt
  sich jeden Wert, den es selbst erzeugt hat, und rechnet in der targets-Phase jedes Feld neu,
  dessen Wert **noch der gemerkte** ist. Geprueft wird also "ist das noch mein Wert", nicht "ist das
  Feld leer" — genau daran haengt, dass das SDK nichts ueberschreiben kann.

Praktische Folge: ein Grundwert wirkt, egal wo er steht.

```xml
<!-- Im Projektfile eines einzelnen Projekts, also lange nach dem Sdk.props-Import: -->
<PropertyGroup>
  <Company>Beispiel GmbH</Company>
</PropertyGroup>
```

Dieses Projekt bekommt `Authors` = `Beispiel`, `Owners` = `Beispiel` und ein `Copyright` mit
`Beispiel GmbH` — die ganze Kette folgt, in der Reihenfolge `Product`, `Authors`, `Owners`,
`Copyright`. Setzt dasselbe Projekt stattdessen `Authors` selbst, bleibt sein Wert stehen und nur
`Owners` folgt ihm. Ohne `Company` bleiben `Authors` und `Owners` leer — auch das .NET-SDK darf sie
dann nicht aus `$(AssemblyName)` raten; Atlas nimmt diesen Wert wieder zurueck. Umgekehrt macht ein
gesetztes `Authors` keine `Company`: das SDK kopiert es, Atlas nimmt auch das zurueck.

Ein Feld, das **`Config.props` selbst** setzt, fasst die Neuberechnung nie an: Atlas hat dort
nichts erzeugt, also gibt es keinen gemerkten Wert, mit dem der aktuelle uebereinstimmen koennte.

**Ausgabepfade bekommen dieses Muster nicht.** MSBuild liest `BaseIntermediateOutputPath` selbst in
der props-Phase, und der Restore laeuft vor jeder targets-Phase — eine Neuberechnung dort wuerde die
Build-Ausgabe von der Assets-Datei wegbewegen. Wer das Layout je Projekt aendern will, setzt
`OutDirName` (Abschnitt "Ausgabe-Layout" unten); wer es repo-weit aendern will, setzt die
Pfad-Felder in `Config.props`.

## Feldreferenz

### Metadaten

| Property | Bedeutung | Default |
|---|---|---|
| `ProductName` | Produktname (speist `Product`). | Name des Repo-Root-Verzeichnisses. |
| `Company` | Herausgeber; NuGet-/Assembly-Metadatum. | keiner — Pflichtangabe (Abschnitt "Pflichtangaben"). |
| `Product` | Assembly-`Product`-Metadatum. | `$(ProductName)`. |
| `Authors` | NuGet-`Authors`. | Aus `Company` abgeleitet: Teil vor dem ersten Leerzeichen, sonst `Company`; ohne `Company` leer. |
| `Owners` | NuGet-`Owners`. | `$(Authors)`. |
| `Copyright` | Copyright-Hinweis in Assembly und Paket. | `Copyright © <Jahr des Commits> $(Company). All rights reserved.` — erst im Build gesetzt, nicht in der Auswertung; ohne `Company` oder ohne Git-Commit leer. |
| `NeutralLanguage` | Neutrale Ressourcensprache. | `en-US`. |
| `PackageLicenseExpression` | SPDX-Lizenzausdruck des Pakets. | keiner — zwingend zu setzen (sonst Build-Fehler), alternativ `PackageLicenseFile`. |
| `PackageLicenseExpressionInternal` | Packt einen der beiden geschlossenen, klartextigen Lizenztexte unter `tools/Licenses/` als `License.txt` ins Paket. | keiner. Nur `MicrosoftDotNetLibrary` und `VisualStudioExtensions` sind zulaessig — bei einem packbaren Projekt (`IsPackable=true`) bricht jede andere Id den Build ab und nennt `PackageLicenseExpression` als richtigen Weg (Review-Runde 1, PR #71). |
| `PackageRequireLicenseAcceptance` | Erzwingt den Lizenz-Zustimmungsdialog beim Konsumenten-Restore. | keiner — NuGets eigener Pack-Default (`false`) gilt unveraendert; ein Konsument setzt ihn selbst, wenn gewuenscht (Entscheid ww3d, 2026-09-18, #73, siehe `docs/decisions.md`). |

**Verfuegbare Lizenz-Ids unter `tools/Licenses/`** (fuer `PackageLicenseExpression`, gegen
`ValidateLicense`, SPDX-Vorlagen-Markup — siehe die Ausnahme oben fuer die zwei klartextigen Ids):
arcade-Paritaet `MIT`, `Apache-2.0`, `MicrosoftDotNetLibrary`, `VisualStudioExtensions`; permissiv
`BSD-2-Clause`, `BSD-3-Clause`, `ISC`, `0BSD`, `Unlicense`, `BSL-1.0`; schwaches Copyleft
`MPL-2.0`, `EPL-2.0`; Public Domain `CC0-1.0` — 13 insgesamt. **Die GPL-Familie ist bewusst
ausgelassen**, nicht vertagt: acht Ids (`-only`/`-or-later` je Version), und ein ww3d-Repo unter
Copyleft ist nicht absehbar (`docs/decisions.md`, Entscheidung 12 revidiert).

### Pflichtangaben (`ATLAS0118`)

Was in eine ausgelieferte Assembly oder ein Paket geht, raet Atlas nicht (#85; Decision-Log
[`2026-09-26T0146Z`](decisions/2026-09-26T0146Z-atlas-85-pflichtangaben-decisions.md)). Abgeleitet
wird nur aus Tatsachen: `Authors`/`Owners`/`Copyright` aus einer gesetzten `Company`, das
Copyright-Jahr aus dem Committer-Datum von `HEAD` (UTC), `RepositoryUrl`/`RepositoryCommit` per
SourceLink aus Git. Der Benutzer der Maschine ist keine Quelle.

| Wann | Geprueft |
|---|---|
| jeder Pack (lokal wie CI), jedes packbare Projekt | alles unten |
| jeder Official Build (`OfficialBuildId` gesetzt), auch ohne Pack, vor dem Bau | jedes Projekt `Company` und `Copyright` (auch WiX, Abschnitt "WiX-Projekte"), ein packbares zusaetzlich alles unten |
| lokaler Bau und Test, Design-Time-Build | nichts |

| Wert | fehlt, wenn |
|---|---|
| `Company` | leer |
| `Copyright` | leer, obwohl `Company` gesetzt ist (kein Git-Commit, aus dem das Jahr kaeme) oder keins von beiden da ist |
| `PackageDescription` | leer oder NuGets Platzhalter `Package Description` — also kein `Description` im Projekt |
| `PackageLicenseExpression` / `PackageLicenseFile` | beide leer |
| `RepositoryUrl` | leer oder eine `file:`-URL (ohne Git, oder `DisableSourceLink=true`) |
| `PackageProjectUrl` | eine `file:`-URL; leer folgt sie `RepositoryUrl` |
| `RepositoryCommit` | leer oder nur Nullen |
| `RepositoryType` | leer |

Ein Lauf nennt **alle** Luecken in einem Fehler `ATLAS0118` und gibt die Bloecke zum Ausfuellen aus:
repo-weite Werte fuer `Config.props`, `Description` fuer die Projektdatei, fuer die Git-Fakten den
Hinweis auf einen Bau aus einem Checkout mit `origin`. Einen Schalter zum Abschalten gibt es nicht.
arcades sechs Einzelpruefungen in `tools/Workarounds.targets` bleiben wortgleich stehen und laufen
danach; wo `ATLAS0118` gruen ist, sind sie es auch.

`Copyright` wird erst im Build gesetzt (Target `_AtlasInitializeCopyright`, vor den Emittern); wer es
in der Auswertung lesen will, setzt es selbst. `git` laeuft dafuer einmal je Build-Knoten und
Repo-Wurzel, und nur, wo das Datum gebraucht wird: bei gesetztem `Company` ohne `Copyright` oder in
der Pruefung. Fehlt das Datum, nennt `ATLAS0118` den Grund, den `git` gemeldet hat.

### Versionierung

| Property | Bedeutung | Default |
|---|---|---|
| `VersionPrefix` | Dreiteiliges Versionspraefix (`Major.Minor.Patch`). | `1.0.0`. |
| `PreReleaseVersionLabel` | Prerelease-Label (z. B. `preview`, `beta`, `rc`). | `preview`. Ein leerer Wert in `Config.props` allein reicht nicht (MSBuild unterscheidet "nicht gesetzt" nicht von "leer gesetzt") - siehe `ReleaseOnlyVersion`. Ausserdem je Build ueberschreibbar ueber `DotNetFinalVersionKind=release`. |
| `ReleaseOnlyVersion` | Schalter fuer ein dauerhaft release-only-Produkt: macht ein leeres `PreReleaseVersionLabel` in `Config.props` wirksam, statt dass der Default `preview` es wieder fuellt. | `false`. |
| `PreReleaseVersionIteration` | Iterationszaehler des Prerelease-Labels. | `1`. |
| `SemanticVersioningV1` | SemVer 1.0 statt 2.0 (Label ohne `.`-Trenner). | `false`. |
| `DotNetUseShippingVersions` | Datierte Versionsstrings auch in nicht offiziellen Builds. | keiner (= `false`). Ohne ihn traegt ein Build ohne `OfficialBuildId` die festen Platzhalter `X.Y.Z-dev` und `FileVersion 42.42.42.42424`. Details in [`docs/versioning.md`](versioning.md). |

**Tageszaehler in `OfficialBuildId`.** Das Format ist `20yymmdd.r`; der Tageszaehler `r` ist auf
**99** begrenzt (arcade: 199). Tag und Zaehler teilen sich dieselben Stellen der berechneten
`FileVersion` (`dd * 100 + r`) — ein groesserer Zaehler griffe in den Folgetag und ein spaeterer
Build bekaeme eine niedrigere `FileVersion`, genau die, die ein MSI-Upgrade liest. Ein
`OfficialBuildId` mit einem Zaehler ab `100` bricht den Build deshalb (`The daily counter encoded in
BuildNumber must be between 0 and 99, …`), statt still falsch zu sortieren. Siehe `docs/decisions.md`,
Eintrag 2026-08-03 — #39.

**Byte-gleiche Pakete im offiziellen Build (`DeterministicTimestamp`).** Mit `OfficialBuildId` setzt
Atlas `DeterministicTimestamp` auf das Datum dieser Id, 00:00 UTC (seit #80; arcade setzt nichts).
NuGet stempelt damit jeden Eintrag des Pakets, und zwei Packs desselben Stands mit derselben
`OfficialBuildId` ergeben dieselben Bytes (`DeterministicPackageE2ETests`). Vorrang haben
`SOURCE_DATE_EPOCH` und ein ausdruecklich gesetztes `DeterministicTimestamp`; ohne `OfficialBuildId`
bleibt es beim Verhalten des .NET SDK (Uhrzeit des Packs). Eine Id, die keinen Kalendertag nennt
(`20260231.1`), setzt nichts; ueber ihr Format urteilt die Pruefung weiter unten im Build.

### Ausgabe-Layout

Seit #83 (Decision-Log
[`2026-09-24T0045Z-atlas-output-layout-decisions.md`](decisions/2026-09-24T0045Z-atlas-output-layout-decisions.md),
Entscheidungen 1-5) gilt ein Modell aus drei Ebenen: **eine Wurzel**, **ein Preset**, **neun Schablonen**.

#### Wurzel `ArtifactsDir`

Ein Knopf, eine Rangfolge (hoch nach niedrig):

| Quelle | Form |
|---|---|
| Skript-Parameter | `Build.cmd -artifactsDir <pfad>`, `build.sh --artifactsDir <pfad>` (geht als globale Property an MSBuild) |
| Umgebung | `ATLAS_ARTIFACTS_DIR` |
| `Config.props` | `<ArtifactsDir>…</ArtifactsDir>` |
| Default | `<repo>/artifacts/` |

- Ein **relativer Wert wird gegen die Repo-Wurzel aufgeloest**, nie gegen das Arbeitsverzeichnis —
  auf Skript- und MSBuild-Seite gleich (Gleichlauf-Waechter `ArtifactsDirScriptMsBuildAgreementTests`).
- Das Skript wertet `Config.props` nur fuer seine eigenen Schritte aus und nur, wenn die Datei ein
  `ArtifactsDir` nennt (echte MSBuild-Auswertung, kein Parser). Alle MSBuild-Laeufe — Skript, `dotnet`,
  VS, VS Code — lesen `Config.props` selbst.
- log, tmp und toolset schreibt das Skript selbst (Binlog, `TEMP`, `MSBUILDDEBUGPATH`, das entpackte
  Toolset) und leitet sie aus **derselben Quelle** ab wie MSBuild (Nachtrag N1 zu Entscheidung 1):
  nennen weder `Config.props` noch die `Directory.Build.props` der Wurzel ein Preset, einen
  `Artifacts*DirName`, `ArtifactsLogPattern`/`ArtifactsTmpPattern`, ein direkt gesetztes `ArtifactsTmpDir`
  oder `UseArtifactsOutput`, nimmt es die Atlas-Defaults unter der Wurzel direkt (reine
  Wurzel-Verschiebung, keine Auswertung). Sonst wertet
  es einen Stub (`.tools/_AtlasLayoutProbe/_AtlasLayoutProbe.proj`) ueber die normale Kette aus, samt
  `Directory.Build.props` der Wurzel, und reicht die Ergebnisse als globale Properties weiter; ein
  Projekt, das anders rechnet, bricht mit `ATLAS0115`. **Voraussetzung fuer diese Auswertung:** Atlas
  ist wie im README ueber die `Directory.Build.props` der Wurzel eingebunden (`<Import Project="Sdk.props"
  Sdk="DotNet.Atlas.Sdk" />`) — nur dort erreicht der Stub es. Fehlt dieser Import, liefert die Auswertung
  leere Werte, und das Skript bricht mit genau dieser Begruendung ab. Den einen MSBuild-Aufruf dieser Auswertung
  selbst deckt ein vorlaeufiges `MSBUILDDEBUGPATH` auf den Default-Ort ab (benannte Grenze).
- Ohne Skript gilt der Default-Ort von MSBuild selbst, nicht die Wurzel: `dotnet build -bl` ohne Pfad
  schreibt `msbuild.binlog` ins **Arbeitsverzeichnis** (gemessen), und MSBuild-Absturzprotokolle landen
  ohne `MSBUILDDEBUGPATH` im Temp-Verzeichnis des Systems (`dotnet/msbuild`,
  `src/Shared/Debugging/DebugUtils.cs`, `GetDebugDumpPath`). Beides liegt vor jeder
  Projektauswertung und ist fuer Atlas nicht erreichbar — `-bl:<pfad>` bzw. das Skript nutzen.
- Unter der Wurzel liegt **alles**, was ein Build schreibt: bin, obj, Pakete, Publish, Testberichte,
  SymStore, VSSetup, tmp, Log, Binlog, `MsbuildDebugLogs`, Toolset; `-clean` loescht sie und
  verweigert das fuer die Repo-Wurzel, ein Laufwerk, einen Vorfahren des Repos, das Benutzerprofil oder einen seiner Vorfahren, einen Ordner mit `.git` sowie `.dotnet`/`.tools`/`.packages` der Repo-Wurzel.
  `.dotnet`, `.tools` und `.packages` bleiben an der Repo-Wurzel (eigene Hebel, wie arcade).
- Eine Wurzel **ausserhalb des Repos** wird als `SourceRoot` eingetragen (Pfade in PDBs bleiben
  deterministisch); das Skript legt dem Toolset dort eine Kopie von `global.json` bei, damit der
  SDK-Resolver `DotNet.Atlas.Sdk` findet.
- `dotnet build --artifacts-path <p>` setzt `ArtifactsPath`: ohne gesetztes `ArtifactsDir` wird das die
  Wurzel (und waehlt das Preset `Sdk`); nennen beide verschiedene Ordner, bricht der Build mit
  `ATLAS0101` ab, statt den Baum zu spalten.

#### Preset `ArtifactsLayout`

| Wert | Baum |
|---|---|
| `Atlas` (Default) | arcade-Form, unveraendert: `bin/<Projekt>/[<Plattform>/]<Config>/[<tfm>/][<rid>/]`, Ordnernamen `bin obj packages TestResults SymStore VSSetup log tmp toolset`, `Shipping`/`NonShipping`, Konfiguration wie definiert. |
| `Sdk` | Form des .NET-SDK-Artifacts-Layouts: `bin/<Projekt>/<pivot>`, `publish/<Projekt>/<pivot>`, `package/<config>/shipping`, `test`, alles klein (`log tmp toolset symstore vssetup`). Benannte Abweichung vom SDK: eine Plattform ≠ AnyCPU haengt als `_<plattform>` am Pivot (`debug_x64`), sonst ueberschrieben sich AnyCPU- und x64-Ausgabe. |
| `Project` | bin/obj im Projektordner wie der .NET-Default (`<Projekt>/bin/[<Plattform>/]<Config>/<tfm>/`), alles andere unter `ArtifactsDir` mit den arcade-Namen. |

`UseArtifactsOutput=true` (oder ein `ArtifactsPath` von `--artifacts-path`) waehlt `Sdk`; ein
ausdruecklich gesetztes `ArtifactsLayout` gewinnt, mit Warnung `ATLAS0102` — Atlas schaltet
`UseArtifactsOutput` dann ab; kommt der Schalter global, geht das nicht, und der Build bricht mit `ATLAS0111`. Wie beim .NET-SDK sieht
Atlas `UseArtifactsOutput` nur, wenn es **vor** der `Sdk.props`-Importzeile in `Directory.Build.props`
steht oder global gesetzt ist; steht es spaeter (oder ein `ArtifactsPath`, das es einschaltet), bleibt
das gewaehlte Preset, Atlas schaltet `UseArtifactsOutput` ab und warnt mit `ATLAS0116` — sonst schrieben
alle Zielframeworks eines Projekts in denselben Ordner. Leert ein Projekt `ArtifactsPath` nach dem Import,
warnt `_AtlasWarnArtifactsPathNotDerived` vor `PrepareForPublish`, weil die SDK-eigene `ArtifactsPath`
dann auf ihren eigenen Default faellt.

Die **Ordnernamen** sind Properties des Presets und einzeln ueberschreibbar: `ArtifactsBinDirName`,
`ArtifactsObjDirName`, `ArtifactsPublishDirName`, `ArtifactsPackagesDirName`,
`ArtifactsTestResultsDirName`, `ArtifactsSymStoreDirName`, `ArtifactsVSSetupDirName`,
`ArtifactsLogDirName`, `ArtifactsTmpDirName`, `ArtifactsToolsetDirName`, `ArtifactsShippingDirName`,
`ArtifactsNonShippingDirName`. Die Publishing-Strecke liest die Aeste nur ueber die `Artifacts*Dir`-
Properties, nie als Literal.

#### Schablonen

Jeder Ast hat eine Schablone — den Teilpfad unter seinem Ast-Ordner; eine absolute Schablone steht fuer
sich (so legt `Project` bin/obj in den Projektordner):

| Schablone | `Atlas` | `Sdk` | Platzhalter |
|---|---|---|---|
| `ArtifactsBinPattern` | `{Project}/{Platform}/{Configuration}` | `{Project}/{Pivot}{_Platform}` | alle |
| `ArtifactsObjPattern` | wie bin | wie bin | alle |
| `ArtifactsPublishPattern` | leer (= SDK-Default `publish/` unter dem Ausgabepfad) | `{Project}/{Pivot}{_Platform}` | alle |
| `ArtifactsPackagesPattern`, `ArtifactsTestResultsPattern`, `ArtifactsSymStorePattern`, `ArtifactsLogPattern`, `ArtifactsTmpPattern` | `{Configuration}` | `{Configuration}` (klein) | nur `{Configuration}` |
| `ArtifactsVSSetupPattern` | `{Configuration}` | `{Configuration}` (klein) | `{Configuration}`, `{Project}`, `{Platform}` |

| Platzhalter | Wert |
|---|---|
| `{Project}` | `OutDirName` (Default: Projektname) |
| `{ProjectDir}` | Projektordner relativ zur Repo-Wurzel, leer fuer ein Projekt in der Wurzel |
| `{Configuration}` | `Configuration` |
| `{Platform}` | `PlatformName`, leer fuer AnyCPU |
| `{TargetFramework}` | TFM; Legacy-.NET-Framework per Konvention `net<Version ohne Punkte>` (nur ohne Profil); leer fuer WiX v4+ (`native`) und C++ |
| `{RuntimeIdentifier}` | der RID, den das SDK an den Pfad haengen wuerde — explizit oder inferiert, nie der Default-RID einer .NET-Framework-Exe |
| `{Pivot}` | die SDK-Formel: Konfiguration, `_tfm` nur bei Multi-Targeting, `_rid` nur explizit, klein |
| `{Architecture}` | Architektur des RID, sonst `PlatformTarget`, sonst Plattform (`Win32` → `x86`) |

Die Praefix-Form `{_Name}` (auch `{-Name}`, `{.Name}`) setzt den Trenner nur bei nicht leerem Wert.
Eine relative Schablone bleibt unter ihrem Ast-Ordner, gleich welche Platzhalter leer ausfallen:
`{Platform}/{Configuration}` ergibt bei AnyCPU `Release/`, `{TargetFramework}{_RuntimeIdentifier}/Debug`
ohne TFM und RID `Debug/`.
Die ersten vier Platzhalter sind vor dem Projekt-Body bekannt, die letzten vier erst danach. **Enthaelt
eine bin- oder obj-Schablone einen spaeten Platzhalter, gehoert ihr der ganze Pfad:** Atlas schaltet
das TFM-/RID-Anhaengen des SDK ab. In einem mehrfach gezielten Projekt muss sie dann `{TargetFramework}`
oder `{Pivot}` nennen, sonst bricht der Build mit `ATLAS0105`. bin- und obj-Schablone sind nur gemeinsam spaet
(`ATLAS0112`), und der obj-Teil vor dem ersten weiteren Platzhalter muss `{Project}` oder `{ProjectDir}` enthalten
(`ATLAS0113`) — dort liegt die Restore-Ausgabe je Projekt. Ein Projekt in der Wurzel hat kein `{ProjectDir}`;
die obj-Schablone braucht dort `{Project}`. In C++- und WiX-v3-Projekten ist `{Pivot}` die
Konfiguration (klein) und `{Architecture}` die Plattform. Einen Platzhalter, den ein repo-weiter
Ast nicht kennt, weist `ATLAS0103`/`ATLAS0104` ab, einen falsch geschriebenen in bin/obj/publish
(`{configuration}`, `{Framework}`) `ATLAS0117` — die Namen sind gross-/kleinschreibungsgenau.

Ein einzelner Ast laesst sich weiter ganz verlegen (`ArtifactsBinDir`, `ArtifactsObjDir`,
`ArtifactsPackagesDir`, `ArtifactsTmpDir`, `ArtifactsTestResultsDir`, `ArtifactsPublishDir`,
`ArtifactsSymStoreDirectory`, `VisualStudioSetupOutputPath`, `VisualStudioSetupIntermediateOutputPath`;
relativ = gegen die Repo-Wurzel); der Wert ersetzt dann Ast und Schablone. `ArtifactsLogDir` und
`ArtifactsToolsetDir` folgen der Wurzel und sind nicht einzeln setzbar.

#### Einhaengepunkte und Durchsetzung

| Projekttyp | Fenster |
|---|---|
| SDK-Stil C#/VB/F# | `BeforeMicrosoftNETSdkTargets` (nach dem Body, vor den SDK-Ableitungen von `PublishDir`, `PackageOutputPath`, `DefaultItemExcludes`); spaete Platzhalter im Common-Fenster |
| Legacy csproj/vbproj, WiX v4+ | `CustomBeforeMicrosoftCommonTargets` |
| C++ (`vcxproj`) | `ForceImportBeforeCppTargets` — setzt `OutDir`, `IntDir` und `IntermediateOutputPath` gemeinsam; ein vorher gesetzter Hook wird verkettet |
| WiX v3 | `CustomBeforeWixTargets` (Abschnitt "WiX" unten) |

Die obj-**Basis** (`BaseIntermediateOutputPath`) entsteht vor dem Body aus `{Project}`/`{ProjectDir}`,
sonst liefen Restore und Build auseinander (MSB3539).

**Ein im Projekt gesetzter `OutputPath`/`IntermediateOutputPath` (bzw. `OutDir`/`IntDir`) wird in den
Baum zurueckgeholt** — die VS-Vorlage `bin\Debug\` ist genau der Streuner, den der Waechter "sauberer
Projektordner" verbietet. `EnforceArtifactsLayout=false` im Projekt laesst den eigenen Wert stehen —
mit dem TFM-/RID-Anhaengen des SDK wie ohne Atlas, auch unter einer spaeten Schablone; einen Pfad, den
das Projekt nicht selbst setzt, fuehrt Atlas weiter nach dem Preset.
**Benannte Ausnahme: klassische Web-Anwendungen (WAP)** haben `EnforceArtifactsLayout=false` als
Default, weil IIS Express und der VS-Debugger `bin\` im Projektordner erwarten; eine WAP mit `true`
wird verlegt wie alles andere.

Atlas' Wurzel ist in allen drei Presets aus den Default-Items ausgeschlossen (`DefaultItemExcludes`): ein
Projekt in der Repo-Wurzel kompiliert keine Streudateien aus `artifacts\log`, `tmp`, `packages` oder
`publish` mit.

#### Publish

Mit einer Publish-Schablone (Preset `Sdk` oder selbst gesetzt) setzt Atlas `PublishDir` fuer jede
Welt, die es liest — SDK-Publish **und ClickOnce** —, unter `ArtifactsPublishDir` bzw.
`<ArtifactsDir>/<publish>/`. Klassische Web-Anwendungen publizieren ueber `PublishUrl` (Web Publishing
Pipeline) an denselben Ort. Ein im Projekt direkt gesetztes `PublishDir` bleibt woertlich (SDK-Vertrag).

Ohne Schablone (Preset `Atlas`) gilt der bisherige Weg: leer = SDK-Default (`<OutputPath>publish/`,
ClickOnce `<OutputPath>app.publish/`); `ArtifactsPublishDir` gesetzt = derselbe Teilpfad, den das
Projekt unter `ArtifactsBinDir` hat (`publish/Werkzeug/Release/net10.0/publish/`). Liegt der
Ausgabepfad eines Projekts mit `EnforceArtifactsLayout=false` ausserhalb von `ArtifactsBinDir`, laesst
Atlas die Ableitung aus und warnt. Bei mehr als einer TFM-/RID-Zelle mit einem woertlichen `PublishDir`
bricht der Fan-out (`OuterPublish`) ab, statt Zellen still zu ueberschreiben.

#### Diagnose-Codes

| Code | Art | im Design-Time-Build | Bedeutung |
|---|---|---|---|
| `ATLAS0101` | Fehler | Warnung | `ArtifactsPath` (z. B. `--artifacts-path`) und `ArtifactsDir` nennen verschiedene Wurzeln. |
| `ATLAS0102` | Warnung | Warnung | `UseArtifactsOutput=true` trifft auf ein ausdruecklich gesetztes, anderes `ArtifactsLayout`; das `ArtifactsLayout` gewinnt, Atlas schaltet `UseArtifactsOutput` dafuer ab. Per `NoWarn` unterdrueckbar (im Skript unter `/warnaserror` ein Fehler). |
| `ATLAS0103` | Fehler | Warnung | Eine repo-weite Schablone (Pakete, Testberichte, SymStore, Log, tmp) nennt einen anderen Platzhalter als `{Configuration}`. |
| `ATLAS0104` | Fehler | Warnung | `ArtifactsVSSetupPattern` nennt einen anderen Platzhalter als `{Configuration}`, `{Project}`, `{Platform}`. |
| `ATLAS0105` | Fehler | Warnung | Mehrfach gezieltes Projekt, bin-/obj-Schablone mit spaetem Platzhalter, aber ohne `{TargetFramework}`/`{Pivot}`. |
| `ATLAS0106` | Warnung | still | Zwei VSIX-Projekte (gleicher `TargetName`) oder AnyCPU und eine Plattform desselben Projekts schreiben unter der flachen `ArtifactsVSSetupPattern` denselben `.vsix`; Abhilfe `{Project}`/`{Platform}` in der Schablone. Per `NoWarn` unterdrueckbar (im Skript unter `/warnaserror` ein Fehler). **Bekannte Grenzen:** unter `-m` (paralleles MSBuild) ist die Reihenfolge der Claim-Datei-Schreibvorgaenge nicht deterministisch — welches der beiden Projekte warnt, kann von Lauf zu Lauf wechseln; nach dem Verschieben oder Umbenennen eines Projekts kann eine alte, von `Clean` nicht geraeumte Claim-Datei faelschlich eine Kollision melden. |
| `ATLAS0107` | Fehler | Warnung | Die Version im gebauten VSIX-Manifest ist kein gueltiges `System.Version`. |
| `ATLAS0108` | Fehler | Warnung | Das Quellmanifest nutzt den Token `\|%CurrentProject%;GetVsixVersion\|`, die gebaute Manifest-Version weicht aber von `VsixVersion` ab. |
| `ATLAS0109` | Fehler | Warnung | Ein WiX-v3-Projekt wird unter `dotnet build` gebaut; WiX v3 baut nur mit `MSBuild.exe`. |
| `ATLAS0110` | Warnung | still | Ein WiX-v3-Projekt setzt `WixTargetsPath` ohne Bedingung selbst, ein Kanal (Skript, `.rsp`) setzt ihn global — die globale Property verwirft den Projektwert. Im Skript unter `/warnaserror` ein Fehler; per `NoWarn` unterdrueckbar. |
| `ATLAS0111` | Fehler | Warnung | Ein ausdruecklich gesetztes, anderes `ArtifactsLayout` trifft auf ein **globales** `UseArtifactsOutput=true`, das Atlas nicht abschalten kann. |
| `ATLAS0112` | Fehler | Warnung | Nur eine der beiden Schablonen `ArtifactsBinPattern`/`ArtifactsObjPattern` nutzt einen spaeten Platzhalter; beide oder keine, weil das Abschalten des TFM-/RID-Anhaengens fuer beide Pfade gilt. |
| `ATLAS0113` | Fehler | Warnung | Die obj-Basis (Teil der `ArtifactsObjPattern` vor dem ersten weiteren Platzhalter) nennt kein Projekt — jedes Projekt restaurierte in denselben Ordner. Ein Projekt in der Wurzel hat kein `{ProjectDir}`; die obj-Schablone braucht dort `{Project}`. |
| `ATLAS0114` | Fehler | Warnung | `ArtifactsLayout` ist keins der Presets `Atlas`, `Sdk`, `Project`. |
| `ATLAS0115` | Fehler | Warnung | Das Build-Skript legt log/tmp/toolset anders ab, als das Projekt sie berechnet — ein Layout, das nur in einer Projektdatei oder einer tieferen `Directory.Build.props` steht. log/tmp/toolset sind repo-weit; ihr Layout gehoert nach `Config.props` oder in die `Directory.Build.props` der Wurzel, die auch das Skript auswertet. log und tmp werden nur verglichen, wenn das Projekt in der Konfiguration des Skripts baut, gleich geschrieben (nicht bei abweichender Solution-Zuordnung oder `SetConfiguration`, auch nicht bei `staging` gegen `Staging`); beide Vergleiche beachten Gross-/Kleinschreibung. |
| `ATLAS0116` | Warnung | Warnung | `UseArtifactsOutput=true` (oder ein `ArtifactsPath`) steht in `Directory.Build.props` erst nach der `Sdk.props`-Importzeile, als das Preset schon gewaehlt war; Atlas schaltet es ab, die Ausgabe folgt dem Preset. Per `NoWarn` unterdrueckbar (im Skript unter `/warnaserror` ein Fehler). |
| `ATLAS0117` | Fehler | Warnung | `ArtifactsBinPattern`, `ArtifactsObjPattern` oder `ArtifactsPublishPattern` nennt einen Platzhalter, den es nicht gibt — meist falsch geschrieben (`{configuration}`); er bliebe sonst als woertlicher Ordnername im Pfad. |
| `ATLAS0118` | Fehler | laeuft nicht | Pflichtangaben fehlen beim Pack oder im Official Build — kein Layout-Code, hier nur der Vollstaendigkeit halber; Abschnitt "Pflichtangaben". |
| `ATLAS0120` | Fehler | Warnung | Die gebaute Assembly traegt eine andere Version als das Versions-Manifest (`AssemblyVersion`, annotierte `AssemblyFileVersion`, `InformationalVersion` bis auf ein angehaengtes `+<sha>`, Metadaten-Paar `Version`); jedes Attribut nur, wenn das SDK oder Atlas es erzeugt hat (`GenerateAssemblyInfo` und der Schalter des einzelnen Attributs) — ein selbst geschriebenes bleibt ungeprueft. Abschnitt "Versions-Manifest und Gleichlauf-Pruefung". |
| `ATLAS0121` | Fehler | Warnung | Die Versionsressource des gebauten `.vcxproj`-Programms (`FILEVERSION`, `FileVersion`, `ProductVersion`) weicht vom Versions-Manifest ab; nur unter Windows und nur, wo Atlas die Ressource schreibt. |
| `ATLAS0122` | Fehler | Warnung | Die Version der erzeugten `.nuspec` ist als NuGet-Version eine andere als `PackageVersion` im Versions-Manifest. |

Als Design-Time-Build gilt `DesignTimeBuild=true` oder ein laufender Restore, fuer Projekte des alten
Projektsystems (Legacy-csproj/vbproj, WAP, Legacy-VSIX) zusaetzlich `BuildingProject=false`, weil VS dort kein
`DesignTimeBuild` setzt. **Benannte Grenze:** ein Legacy-Projekt, das selbst `RestoreProjectStyle=PackageReference`
setzt, bekommt die Fehler dieser Tabelle dadurch auch im echten Build nur als Warnung — unter dem Skript
(`/warnaserror`) bleiben sie Fehler.

## Hochladen (`UsingNuGetPush`)

Atlas kann die gepackten Pakete am Ende der `-publish`-Kette selbst an einen Feed schieben. Das ist
**opt-in** und tut ohne den Schalter gar nichts.

```xml
<PropertyGroup>
  <UsingNuGetPush>true</UsingNuGetPush>
</PropertyGroup>
<ItemGroup>
  <NuGetPushUrls Include="https://feed.example/nuget/v3/index.json" />
</ItemGroup>
```

- Jedes `.nupkg` aus dem Shipping-Paketordner geht an **jeden** Eintrag von `NuGetPushUrls`.
- **Kein Push ohne Datum in der Version.** Ein Build ohne `OfficialBuildId` (und ohne
  `DotNetUseShippingVersions`) erzeugt `X.Y.Z-dev` — dieselbe Versionsnummer bei jedem Lauf. Der
  Push bricht dann mit einer benannten Meldung ab, statt den NuGet-Cache jedes Konsumenten mit einer
  nicht eindeutigen Version zu vergiften.
- **Eine Version, die auf dem Feed schon liegt, stoppt den Push — bevor das erste Paket rausgeht.**
  Das Target fragt jeden Feed nach jedem Paket (`dotnet package search --exact-match`) und bricht
  ab, wenn die Version dort liegt oder der Feed die Frage nicht beantworten kann. Auf die Antwort des
  Feeds verlaesst es sich nicht: gemessen (#80) beantwortete der Cella-Feed einen zweiten Push mit
  `201 Created` und ersetzte das Paket, statt mit 409 abzulehnen. Kein `--skip-duplicate`; der
  Tageszaehler in `OfficialBuildId` wird von Hand gefuehrt. Die Suche laeuft im Toolset-Ordner unter
  `artifacts/toolset/`, sieht also die `NuGet.config` des Repos samt deren Anmeldedaten (abgeleitet aus dem Ablageort, mit Anmeldedaten nicht gemessen; `docs/backlog.md`).
- **Auch eine ungelistete Version stoppt den Push.** Die Suche fuehrt ungelistete Versionen nicht
  (gemessen auf nuget.org); findet sie nichts, fragt das Target den Feed noch einmal direkt — beim
  v3-Feed den Flat Container (`PackageBaseAddress/3.0.0`), beim v2-Feed `Packages(Id='…',Version='…')`,
  beim Ordner-Feed die Platte. Diese Frage geht **anonym** raus, mit 30 s Zeitlimit; 401, 403, ein
  anderer Status, ein Netzfehler oder eine unlesbare Antwort stoppen den Push wie "liegt schon da".
  Fuer einen Feed, der schon das Lesen nur mit Anmeldung beantwortet, laesst
  `NuGetPushSkipExistenceProbe=true` (in `Config.props` oder per `-p:`) diese zweite Frage aus; die
  Suche mit den Anmeldedaten der `NuGet.config` laeuft weiter, ungelistete Versionen sieht dann aber
  niemand.
- Der API-Schluessel kommt aus der Umgebungsvariablen `ATLAS_NUGET_PUSH_API_KEY`, bewusst nicht aus
  einer Property: ein per `-p:` uebergebener Schluessel landet im Binaerlog. **MSBuild liest den
  Wert an keiner Stelle** — auch nicht ueber eine `Condition` —, sondern loest ihn erst in der Shell
  auf (`%ATLAS_NUGET_PUSH_API_KEY%` unter `cmd`, `$ATLAS_NUGET_PUSH_API_KEY` unter `sh`); ein per
  Property expandierter Wert landet sonst als "Set Property"/"expanded from the environment"-Zeile
  in jedem Binaerlog-Replay, unabhaengig von der Verbositaet des urspruenglichen Laufs (PR #71,
  Review-Punkt 1). Ist die Variable leer, laeuft der Push ohne `--api-key` — was ein Feed mit
  anonymem Schreibzugriff so erwartet; das entscheidet ebenfalls die Shell, nicht MSBuild.
  Drei Grenzen bleiben: der Schluessel steht fuer die Dauer des Aufrufs in der Kommandozeile des
  `dotnet nuget push`-Prozesses (sichtbar etwa im Task-Manager oder in `ps`); ein Lauf mit
  `MSBUILDLOGALLENVIRONMENTVARIABLES=1` schreibt die ganze Umgebung samt Schluessel ins Binaerlog;
  und unter `cmd` darf der Schluessel kein `"` enthalten — er wird dort sonst in zwei Argumente
  zerlegt (unter `sh` bleibt er heil).
- **Signiert wird von Hand, vorher.** Es gibt keinen Signing-Code; der Ablauf steht in
  [`docs/versioning.md`](versioning.md) § "Release".

## Symbol-Store (`UsingToolPdbConverter`)

Ein CI-Build unter Windows (`ContinuousIntegrationBuild=true`, etwa `build.ps1 -ci`) importiert
`tools/SymStore.targets`: fuer jede ausgelieferte Assembly wandelt `Pdb2Pdb` die portable PDB in eine
Windows-PDB unter `artifacts/SymStore/`. Wie bei arcade ist der Konverter per Default an
(`UsingToolPdbConverter=true`, seit #80), und seine Version erzeugt das SDK
(`MicrosoftDiaSymReaderPdb2PdbVersion`, `1.1.0-beta2-19575-01`, arcades Pin — ein stabiles Release
gibt es nicht). Abschalten: `UsingToolPdbConverter=false` **und** `PublishWindowsPdb=false`; nur das
erste ergibt den Fehler "Attempt to publish Portable PDB to SymStore without conversion". Ein
Source-only-Build (`DotNetBuildSourceOnly=true`) schaltet den Konverter wie arcade selbst ab.

**Quelle.** `Microsoft.DiaSymReader.Pdb2Pdb` liegt nicht auf nuget.org, sondern auf Microsofts
oeffentlichem dnceng-Feed `dotnet-eng` (lesbar ohne Anmeldung). Ein Konsument, der unter Windows mit
`-ci` baut, fuehrt ihn in seiner `nuget.config` — und mappt ihn auf genau dieses eine Paket, damit der
Feed fuer nichts anderes Kandidat wird:

```xml
<packageSources>
  <add key="dotnet-eng" value="https://pkgs.dev.azure.com/dnceng/public/_packaging/dotnet-eng/nuget/v3/index.json" />
</packageSources>
<packageSourceMapping>
  <packageSource key="dotnet-eng">
    <package pattern="Microsoft.DiaSymReader.Pdb2Pdb" />
  </packageSource>
</packageSourceMapping>
```

Atlas' eigene `NuGet.config` fuehrt ihn genau so (`NuGetConfigGuardTests` haelt das Mapping). Ohne die
Quelle scheitert der Restore eines solchen CI-Builds an `Microsoft.DiaSymReader.Pdb2Pdb`.

## Signing und Publishing

Die Signing- und Publishing-Einstellungen eines Repos stehen in `Config.props` (Entscheidung 3) und
wirken in `Sign.proj` und `Publish.proj` — auch die, die arcades `toolset/Sign.props` bzw.
`toolset/Publish.proj` ohne Bedingung vorbelegen (Abschnitt "Rangfolge"). Ein eigenes Atlas-Backend
gibt es noch nicht (Phase 2, `DotNet.Atlas.Sign`, in `docs/roadmap.md`); einstellbar ist heute, was
arcades Toolset liest, und das Hochladen oben. arcades Hooks `eng/Signing.props` und
`eng/Publishing.props` bleiben als Stufe 3 bestehen, fuer eine Uebersteuerung je Schritt.

## Testprojekte (Teststack-Injektion)

Atlas erkennt Testprojekte am Projektnamen (`*.Tests`, `*.IntegrationTests`,
`*.PerformanceTests`; `tools/Tests.props`) und injiziert den Teststack selbst: xunit.v3
(`xunit.v3.core`, `xunit.v3.assert`, `xunit.analyzers`) plus Microsoft Testing Platform (MTP,
inkl. TRX-Report). Eigene Teststack-`PackageReference`s entfallen; Opt-out per
`DisableAtlasTestFramework=true`. Ein Konsumenten-Testprojekt braucht selbst nur:

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <OutputType>Exe</OutputType>
    <IsTestingPlatformApplication>true</IsTestingPlatformApplication>
  </PropertyGroup>
</Project>
```

- `IsTestingPlatformApplication=true` ist Pflicht: der `Tests.props`-Guard, der das legacy
  `Microsoft.NET.Test.Sdk` (VSTest) unterdrueckt, prueft dieses Flag — normalerweise setzen es
  erst die Build-Props von `Microsoft.Testing.Platform.MSBuild`, die bei der Erst-Evaluierung
  vor dem ersten Restore noch nicht importiert sind. Ohne das Flag zieht das Projekt zusaetzlich
  die VSTest-Closure.
- Testlauf: `dotnet run --project <Testprojekt> -- <Berichts-Schalter>`. **Welcher Schalter gilt,
  haengt am Host** — und beide Faelle kommen vor, weshalb sie hier beide stehen:
  - **Vom Atlas-SDK injizierter Teststack** (der Fall oben): Host ist die Microsoft Testing
    Platform, der Schalter heisst `--report-trx`, der Dateiname kommt mit
    `--report-trx-filename <datei>`.
  - **Eigene Referenz auf das Meta-Paket `xunit.v3`** statt auf den injizierten Stack: Host ist
    xunits eigener In-Process-Console-Runner, und der kennt `--report-trx` nicht (er antwortet
    `unknown option`). Dort heisst es `-result-trx <datei>`, mit einem Bindestrich.

  Gemessen an SDK 10.0.401 mit xunit.v3 4.0.1. Wer den falschen Schalter erwischt, sieht
  `unknown option` und keinen Hinweis auf den anderen — daher diese Unterscheidung.
- `dotnet test` funktioniert ebenfalls: der MTP-Opt-in im `global.json`-`test`-Block
  (`"runner": "Microsoft.Testing.Platform"`) leitet `dotnet test` auf .NET 10 auf den MTP-Pfad statt
  in den nicht mehr unterstuetzten VSTest-Pfad. (`global.json` ist der aktive Schalter; der aeltere,
  rein deklarative `dotnet.config`-`[dotnet.test.runner]`-Mechanismus wurde nach .NET 10 rc2 entfernt
  und ist auf SDK 10.0.301 wirkungslos — daher nicht eingecheckt.)
- **VSTest statt MTP.** `UseMicrosoftTestingPlatformRunner=false` (fuer Atlas' `Test`-Target
  zusaetzlich `UseVSTestRunner=true`) laesst Atlas statt der MTP-Pakete den Adapter
  `xunit.runner.visualstudio` in `XUnitRunnerVisualStudioVersion` injizieren (#101). Dazu
  `IsTestingPlatformApplication=false` setzen: xunit.v3 schaltet das Flag sonst selbst ein, und
  `tools/VSTest.targets` bricht mit `UseVSTestRunner property shouldn't be used when using
  Microsoft.Testing.Platform` ab (gemessen, SDK 10.0.401, xunit.v3 4.0.1).
- **Eigene `xunit.runner.json`.** Atlas legt selbst eine mit, ueber `XUnitCoreSettingsFile`
  (fuer `.NETCoreApp`) bzw. `XUnitDesktopSettingsFile` (fuer `.NETFramework`); der Default zeigt auf
  die Datei im SDK-Paket. Sie wird mit `CopyToOutputDirectory=PreserveNewest` ins Ausgabeverzeichnis
  kopiert — also **auch ueber eine eigene, aeltere Datei**, und der Build meldet den Tausch nicht.
  Sichtbar wird er nur als "rot im vollen Lauf, isoliert gruen", weil Einstellungen wie
  `maxParallelThreads` dabei verloren gehen. Ein Repo mit eigener Konfiguration setzt deshalb
  `XUnitCoreSettingsFile` auf seine eigene Datei, statt sich darauf zu verlassen, dass die eigene
  Datei gewinnt.
- **Befehlszeilen-Log der Runner.** MTP, VSTest und xUnit v3 schreiben die Kopfzeile
  `=== COMMAND LINE ===` vor dem Lauf ins Log und haengen die Ausgabe an. Mit
  `TestCaptureOutput=false` legen VSTest und xUnit v3 seit #90 kein Log mehr an (vorher eine Datei
  nur mit Kopfzeile) — wie MTP und arcades xUnit v2.

Herkunft der Default-Logik: Semantik aus `ww3d/buildtools` `ConfigDefaults.props` (frozen; SHA in
`docs/upstream.md`), umgeformt auf arcade-Stil — Rohwerte in den props-Dateien, Ableitungen in den
gleichnamigen targets-Dateien. Das Merken-und-neu-rechnen aus dem Abschnitt "Ableitungs-Muster"
stammt ebenfalls aus buildtools (`ProjectDefaults.props`/`.targets`). `Company` und
`PackageLicenseExpression` haben bewusst keinen SDK-Default (fail-loud statt stillem Mislabel;
Abschnitt "Pflichtangaben").

## XML-Dokumentation (`CS1591`)

Atlas unterdrueckt `CS1591` (oeffentliches Element ohne XML-Doku) nicht — arcade tut es per Default
(`tools/ProjectDefaults.props`, abschaltbar ueber `SkipArcadeNoWarnCS1591`). Ein Repo, das von arcade
kommt und `GenerateDocumentationFile=true` setzt, bekommt deshalb mit Atlas neue Befunde, unter
Atlas' `TreatWarningsAsErrors`-Default als Fehler; der Schalter `SkipArcadeNoWarnCS1591` hat keine
Wirkung mehr. Wer die Unterdrueckung behalten will, setzt `<NoWarn>$(NoWarn);1591</NoWarn>` selbst.
Hintergrund: `docs/decisions.md`, Eintrag "2026-09-22 — Quality Gate", berichtigt im Eintrag zu #80,
PR 2.

## Strong-Naming

Atlas signiert nichts mehr per Default (Entscheid ww3d, 2026-09-18, #73; Abweichung von arcades
Default `StrongNameKeyId=MicrosoftShared`). `SignAssembly` und `StrongNameKeyId` haben keinen
SDK-Default; ein Konsument, der eine strong-named Assembly braucht, setzt
`SignAssembly`/`AssemblyOriginatorKeyFile` selbst — reines .NET-SDK-Verhalten, von Atlas weder
ueberschrieben noch blockiert. Begruendung: Microsofts eigene Guidance
(`learn.microsoft.com/en-us/dotnet/standard/library-guidance/strong-naming`) — *"Strong naming has
no benefits on .NET Core/5+"*, *"should not be done by default"* — und die unumkehrbare Bindung an
einen einmal veroeffentlichten Schluessel (*"DO NOT add, remove, or change the strong naming key"*).
Details und Traeger: `docs/decisions.md`, Eintrag "Strong-Naming: ueberall raus".

## NuGet-Audit (`TreatNuGetAuditWarningsAsErrors`)

Atlas setzt `NuGetAuditMode=all`, prueft also auch transitive Pakete gegen die
Advisory-Datenbank, und setzt `TreatWarningsAsErrors` SDK-weit. Beides zusammen hiesse: ein neu
veroeffentlichtes Advisory in irgendeinem indirekten Paket macht ab dem naechsten Restore jeden
Build rot, ohne dass sich am Projekt etwas geaendert haette.

Seit dem arcade-Sync vom 2026-08-24 (Beschluss B2 in Issue #56) bleiben die vier Audit-Codes
`NU1901`-`NU1904` deshalb **Warnungen**: `ProjectDefaults.props` haengt sie an
`WarningsNotAsErrors`. Wer die Haertung will — Advisory bricht den Build —, setzt

```xml
<TreatNuGetAuditWarningsAsErrors>true</TreatNuGetAuditWarningsAsErrors>
```

— an beliebiger Stelle: in `Config.props`, in `Directory.Build.props`, als globale `-p:`-Property
**oder im Projekt-Body**. Der Projekt-Body wirkt, weil `ProjectDefaults.targets` den Schalter in der
targets-Phase noch einmal auswertet (Abschnitt "Ableitungs-Muster" oben). Vor diesem Schnitt las ihn
nur die props-Phase, und ein Projekt konnte ihn gar nicht setzen.

Einschraenkung, die zum Schalter gehoert: laut [dotnet/msbuild#10801](https://github.com/dotnet/msbuild/issues/10801)
greift `WarningsNotAsErrors` fuer NuGet-Warnungen nicht in jeder Konstellation. Wo der Schalter
also **nicht** wirkt und der Build trotz Default rot laeuft, bleibt der Notausgang `NoWarn` bzw.
`AdditionalNoWarn` mit den betroffenen Codes. In `OfficialBuild`-Laeufen ist das Audit ohnehin ganz
abgeschaltet (`NuGetAudit=false`, arcade-Verhalten).

## Legacy-/Full-MSBuild- und VSIX-Projekte

Atlas laesst sich auch in klassische (Non-SDK-Style) Projekte und VSIX-Projekte einhaengen
(`Directory.Build.props`/`.targets` mit `<Import Project="Sdk.props" Sdk="DotNet.Atlas.Sdk" />`
bzw. `Sdk.targets`, wie im SDK-Style-Fall) — gebaut wird dann nicht mit `dotnet build`, sondern mit
echtem `msbuild.exe` (Visual Studio/Build Tools).

- **Braucht MSBuild 18.0+ (Visual Studio 2026) und ein per `global.json` erreichbares .NET-10-SDK.**
  Atlas deklariert seine eigenen Build-Tasks mit `Runtime="NET"` (net10.0-Task-DLL); unter vollem
  Full-MSBuild laeuft das ueber den .NET Runtime Task Host (siehe
  [aka.ms/nettaskhost](https://aka.ms/nettaskhost)), der aus dem per `global.json` resolvten dotnet-SDK
  gestartet wird (die Mindestanforderung des Hosts selbst ist SDK 10, nicht eine bestimmte
  MSBuild-Version). Mit einer MSBuild-Version vor 18.0 — die den `Runtime="NET"`-Taskhost ueberhaupt
  nicht kennt — bricht der Build fail-loud mit einer klaren Atlas-Fehlermeldung ab, statt in einen
  kryptischen MSBuild-internen Fehler zu laufen.
- **Hinweis (A7):** ein frueher Atlas-interner Fehler liess den Task Host auf Full-MSBuild scheitern
  (`could not be found for the specified version`); die Ursache lag in einem BundledVersions-Import, der
  unter `msbuild.exe` ins Leere lief, und ist gefixt (siehe `docs/decisions.md`, D2-Nachtrag). Auf dem
  Windows-CI-Leg bestaetigt: klassische net48-Projekte (Console/Library/Web) und ein VSIX-Projekt bauen
  echt gegen das Atlas-SDK unter `msbuild.exe`.
- **Mindestausstattung einer Build-Tools-Installation** (ohne vollstaendiges Visual Studio,
  gemessen an Build Tools 2026): die Komponente ".NET SDK" (`Microsoft.NetCore.Component.SDK`) —
  ohne sie fehlt `Microsoft.DotNet.MSBuildSdkResolver`, und jedes `Sdk="Microsoft.NET.Sdk"` endet in
  `MSB4276`; fuer klassische Web-Projekte die Gruppe `WebBuildTools`; fuer ClickOnce
  `Microsoft.Component.ClickOnce.MSBuild`; und die Targeting-Packs der klassischen Ziel-Frameworks,
  die die Projekte nennen (fehlt eins, `MSB3644`) — der Resolver allein genuegt dafuer nicht.
  Ob Atlas `MSB4276` selbst mit einer klaren Meldung abfaengt, ist nicht entschieden
  (`docs/backlog.md`).
- **Ueber das Skript (`.\Build.cmd -msbuildEngine vs`)** baut ein Konsument seit #83 ohne `MSB4011`:
  `tools/BuildTasks.props` importiert `BundledVersions` nur noch fuer Nicht-SDK-Projekte, SDK-Stil-
  Projekte bekommen die Datei vom .NET-SDK selbst. Atlas' eigener Build nutzt die Korrektur erst,
  wenn sein Self-Hosting-Pin auf ein Paket mit ihr zeigt.
- **VSIX (`UsingToolVSSDK=true`)** braucht zusaetzlich `Microsoft.VSSDK.BuildTools` (nuget.org,
  Version per `MicrosoftVSSDKBuildToolsDefaultVersion` gepinnt, seit #83 `18.5.40034` — `18.9.820`
  ist auf nuget.org ungelistet) sowie ein Setzen von `UsingToolVSSDK` **vor** dem `Sdk.props`-Import
  (also in `Directory.Build.props`, nicht erst im Projekt-Body) — sonst sieht `Sdk.props`s eigene
  guarded Import-Condition das Flag zu spaet. Seit #83 baut ein VSIX-Projekt auch unter `dotnet build`
  (das arcade-Gate `MSBuildRuntimeType != 'Core'` ist gefallen; frueher endete das mit Exit 0 ohne
  `.vsix`); nur das Deployment in den VS-Experimental-Hive geht unter Core nicht, dort bricht die VSSDK
  selbst ab. Der Container liegt immer im VSSetup-Ast, auch mit `VSSDKBuildToolsAutoSetup=true`.
  Die Manifest-Version wird nach dem Bau geprueft (`ATLAS0107`/`ATLAS0108`), zwei Projekte auf
  demselben flachen `.vsix` melden `ATLAS0106`.
- **VisualStudio.Extensibility** (Out-of-Proc-Modell) wird nach dem Projekt-Body erkannt
  (`ProjectCapability` `ExtensibilityProjectExtension` bzw. die `PackageReference` auf
  `Microsoft.VisualStudio.Extensibility.Build`); seine `.vsix` kommt in den VSSetup-Ast. Atlas setzt
  die Manifest-Version (`Identity/@Version`) immer auf `VsixVersion`; ein im Code gesetzter Wert
  (`ExtensionConfiguration.Metadata.version`) wird nach `CoreCompile` ueberschrieben.
  `ThisAssembly.VsixVersion` (in jedem C#-Projekt erzeugt) dient nur der Anzeige, etwa
  `new System.Version(ThisAssembly.VsixVersion)` in der `ExtensionConfiguration`.
- **`packages.config` ist unterstuetzt.** Ein klassisches Projekt kann seine Pakete weiterhin ueber
  `packages.config` statt `PackageReference` fuehren — das ist der Fall fuer Projekttypen, die NuGet
  selbst nicht auf `PackageReference` migrieren kann (ASP.NET, C++). Restaurieren braucht **eine
  Solution oder `-p:SolutionDir=<pfad>\`**: `msbuild -t:Restore -p:RestorePackagesConfig=true` ohne
  eines von beiden bricht mit *"No solution found. Restore against a solution or pass in
  /p:SolutionDir"* ab, statt die Pakete stillschweigend nicht zu restaurieren (`docs/decisions.md`,
  Eintrag zu `atlas#45`). Mit `SolutionDir` landen die Pakete unter `<SolutionDir>packages\` — davon
  unberuehrt bleibt jede Atlas-Layout-Property (`ArtifactsBinDir` und Geschwister): die
  `packages.config`-Ablage folgt `SolutionDir`, nicht `Config.props`.

## WiX-Projekte (MSI und Bundle)

Seit #83 (Entscheidung 7) baut Atlas WiX v3 bis v7, je MSI und Bundle, allein aus NuGet-Paketen — ohne
installiertes WiX und ohne VS-Workload. Die Lizenz von WiX 6/7 (OSMF-EULA) nimmt ein Konsumenten-Repo
selbst an (`AcceptEula`); Atlas tut das nur in seinen eigenen Testfaellen.

**WiX v4+** (`WixToolset.Sdk`) bindet `Microsoft.Common.*` ein und folgt dem Layout ueber das Common-Fenster
wie ein Legacy-Projekt; `{TargetFramework}` ist leer (`native`). Atlas setzt fuer diese Projekte
`DebugType=full` (ausser `none`), weil `wix.exe -pdbType` Atlas' .NET-Wert `embedded` nicht kennt
(`WIX1098`).

**WiX v3** laedt weder `Microsoft.Common.props` noch `Directory.Build.props`. Ein Repo mit v3-Projekten
setzt in `Config.props` `<UsingToolWix3>true</UsingToolWix3>`; `Restore.cmd`/`Build.cmd` restaurieren dann
das NuGet-Paket `wix` in der Version `Wix3Version` (Default `3.14.1`, MS-RL) in den Paket-Cache. Atlas
erreicht das Projekt ueber `WixTargetsPath`, die Eigenschaft, die jedes Votive-Projekt importiert; den
Wert setzt einer von vier Kanaelen, keiner aendert das Projekt:

| Kanal | Form |
|---|---|
| Skript | `Build.cmd -msbuildEngine vs` — `toolset/Build.proj` reicht `WixTargetsPath` an alle Projekte und per Vererbung an `ProjectReference`s |
| `msbuild` direkt | eingecheckte `Directory.Build.rsp` im Repo-Wurzel mit `-p:WixTargetsPath=%MSBuildThisFileDirectory%eng\Wix3.targets` plus Stub `eng/Wix3.targets` = `<Project><Import Project="Wix3.targets" Sdk="DotNet.Atlas.Sdk" /></Project>` (die Version steht nur in `global.json`) |
| Visual Studio (wendet keine `.rsp` an) | die Zeile `<Import Project="Wix3.props" Sdk="DotNet.Atlas.Sdk" />` als erstes Element des Projekts, oder die Umgebungsvariable `WixTargetsPath` (auf den Stub) beim VS-Start |
| `.wixproj.user` | dieselbe Zeile in `<Projekt>.wixproj.user`; die Toolchain kommt dann von einem installierten WiX v3 |

Die Zeile setzt nur `WixTargetsPath` und den Layout-Hook, nie `Configuration`/`Platform` — die
`Debug|x86`-Gruppen einer Votive-Vorlage gelten weiter. Der Hook im Fenster `CustomBeforeWixTargets`
setzt `OutputPath`, `BaseIntermediateOutputPath` und `IntermediateOutputPath` aus den Schablonen, auch
gegen das `bin\$(Configuration)\` der Vorlage (ausser `EnforceArtifactsLayout=false`); `{TargetFramework}`
und `{RuntimeIdentifier}` sind leer, `{Pivot}` ist die Konfiguration. Er setzt `DefineSolutionProperties=false`,
sofern das Projekt den Wert nicht selbst setzt — WiX' Warnung "Solution properties are only available
during IDE builds" braeche sonst das Skript (`/warnaserror`). Grenze: WiX v3 baut nur mit `MSBuild.exe`;
unter `dotnet build` bricht Atlas mit `ATLAS0109` ab. Setzt ein Projekt `WixTargetsPath` selbst ohne Bedingung,
verwirft die globale Property eines Kanals diesen Wert; Atlas meldet das mit `ATLAS0110` (die bedingte Zeile
der Votive-Vorlage bleibt still). Die Pruefung liest den Projekttext, eine Zuweisung in einer importierten
Datei sieht sie nicht — benannte Grenze. In einem Design-Time-Build (ww3d-Vorgabe D1) faellt `ATLAS0109`
auf eine Warnung zurueck statt abzubrechen, `ATLAS0110` bleibt dort ganz still — siehe die Spalte
"im Design-Time-Build" der Diagnose-Tabelle.

`UsingToolWix3` steht in `Config.props` (oder in der Umgebung): die Toolset-Projekte, die das Paket
restaurieren, haben ihre eigene `Directory.Build.props` und sehen die des Repos nicht (gemessen). Die
Defaults beider Schalter liegen neben `UsingToolVSSDK` in `tools/DefaultVersions.props`.

**Eigener Hook: `AtlasCustomBeforeWixTargets`.** Nur fuer WiX v3: ein im Projekt gesetztes
`CustomBeforeWixTargets` geht nicht verloren, Atlas' Eintritt (die Kanal-Tabelle oben) reicht es an
seinen Hook weiter, der es importiert. Wird `CustomBeforeWixTargets` aber als globale Property
uebergeben, verwirft MSBuild die Zuweisung des Projekts spurlos; der in jedem Fall wirksame Ersatz
ist `AtlasCustomBeforeWixTargets`, die Atlas am Ende seines Hooks importiert. Fuer WiX v4+ gibt es
diesen Ersatz nicht: `Wix3.BeforeWixTargets.targets` wird ausschliesslich ueber die v3-Kanaele
geladen (sdk/Wix3.targets, sdk/Wix3.props), ein v4+-Projekt erreicht die Datei gar nicht, und
`AtlasCustomBeforeWixTargets` bleibt dort ungelesen.

**Versionen.** Jedes WiX-Projekt bekommt ohne Zutun die Preprozessor-Variablen `$(var.MsiVersion)` (fuer
`Version` von `Product`/`Package`), `$(var.BundleVersion)` (fuer `Bundle`: ab WiX v4 die Atlas-SemVer, unter
v3 die `MsiVersion`) und `$(var.AtlasVersion)` (die volle Atlas-Version). Das Schema waehlt
`MsiVersionScheme` (`Readable`, Default, oder `Packed`) — Rechnung und Grenzen in
[`docs/versioning.md`](versioning.md). Die volle Version steht als MSI-Property `AtlasVersion` in der MSI,
sobald das Projekt eine Zeile `<PropertyRef Id="AtlasVersion" />` in `Product` (v3) bzw. `Package` (v4+)
traegt: der WiX-Linker uebernimmt ein Fragment nur, wenn etwas es referenziert (gemessen). Dieselbe Zeile
bringt die MSI-Property `AtlasCommit` mit, den Commit des Builds (derselbe Wert wie `GitHeadSha` im
Versions-Manifest); ohne Commit (Build ohne Git) fehlt sie. `AtlasVersionInfo` liest beide zurueck.

**Hersteller.** Dazu kommen `$(var.Company)` (fuer `Manufacturer` von `Product`/`Package`/`Bundle`) und
`$(var.Copyright)` — dieselben Werte, die Assembly und Paket tragen, `Copyright` mit dem Jahr des Commits
(Abschnitt "Pflichtangaben"). Ein Official Build eines WiX-Projekts ohne sie bricht wie jedes andere mit
`ATLAS0118` ab.

## Native-Projekte (vcxproj)

Atlas laesst sich auch in native C++-Projekte (`.vcxproj`) einhaengen — genau wie die klassischen
Projekte oben ueber `Directory.Build.props`/`.targets` mit dem `Sdk.props`/`Sdk.targets`-Import.
Gebaut wird mit echtem `msbuild.exe` (Visual Studio 2026 / Build Tools mit C++-Toolchain), nicht mit
`dotnet build`.

- **Platform-Default `Win32`.** Ein direkter `msbuild Foo.vcxproj` **ohne** `/p:Platform` baut als
  `Win32`. Grund: Atlas setzt (arcade-verbatim) `Platform=AnyCPU` frueh in `RepoDefaults.props`, noch
  bevor `Microsoft.Cpp.Default.props` seinen eigenen Win32-Default setzen koennte; ein ungegatetes
  `AnyCPU` ergaebe ein invalides `AnyCPU|Debug`. Atlas gatet den Default deshalb fuer `.vcxproj` auf
  `Win32` (dokumentierte arcade-Divergenz, siehe `docs/decisions.md`, Eintrag 2026-07-22 — D3).
- **Andere Plattformen explizit.** Fuer x64/ARM64 die Plattform als Property mitgeben, z. B.
  `msbuild Foo.vcxproj /p:Platform=x64`. sln-/CI-Builds reichen `Platform` ohnehin als globale
  Property durch; dort greift der Win32-Default nicht.
- **Output-Layout mit Platform-Segment.** Native Outputs liegen unter
  `artifacts/bin/<Projekt>/<Platform>/<Config>/` (Intermediates analog unter `artifacts/obj/...`) —
  also z. B. `artifacts/bin/Foo/x64/Debug/Foo.exe` bzw. `.../Win32/Debug/Foo.exe`. Das
  Platform-Segment (fuer alles ausser dem managed `AnyCPU`) haelt Win32-, x64- und ARM64-Outputs
  desselben Projekts kollisionsfrei nebeneinander.
- **Keine managed Test-/Versions-Injektion.** Ein `Foo.Tests.vcxproj` zieht **nicht** den managed
  Teststack (weder `Microsoft.NET.Test.Sdk` und VS-Test-`Service`-Item noch die xunit.v3/MTP-
  PackageReferences), und die managed Versions-Emitter (`ThisAssembly.Generated.cs`,
  `AssemblyMetadata`) laufen fuer C++ nicht — beides ist explizit gegen C++ gegatet
  (`docs/decisions.md`, Eintrag 2026-07-22 — D3, E2).

### Nativer VERSIONINFO-Emitter

Jedes `.vcxproj`, das ein PE-Image erzeugt, bekommt seine Windows-Versionsressource automatisch: Atlas schreibt vor dem
Ressourcen-Compiler einen Header `$(IntDir)<Projekt>.NativeVersion.Generated.h` (die `VER_*`-Makros
aus denselben zentralen Werten, aus denen auch die managed Emitter speisen) plus eine
`<Projekt>.NativeVersion.Generated.rc` und haengt beide in den laufenden Build (`ClInclude`,
`ResourceCompile`, `$(IntDir)` in `$(IncludePath)`). Das Binary traegt danach Comments, CompanyName,
FileDescription, FileVersion, InternalName, LegalCopyright, LegalTrademarks, OriginalFilename,
ProductName und ProductVersion — dieselben Felder mit denselben Werten wie ein managed Binary. Die
einzige Ausnahme ist der ProductVersion-String: nativ traegt er die BuiltBy-Annotation, managed nicht
(Begruendung in `docs/decisions.md`, Eintrag 2026-08-03 — #38). Kein Projekt-Wiring noetig.

- **Nur PE-Ausgaben.** Der Emitter laeuft fuer `ConfigurationType=Application` und `DynamicLibrary`.
  Eine statische Bibliothek (oder ein `Utility`-Projekt) ist kein PE-Image — dort waere die Ressource
  unsichtbar und wuerde im schlechtesten Fall mit der des konsumierenden Binaries kollidieren.
- **Opt-out:** `AtlasSdkGenerateNativeVersionInfo=false` (Default `true`) — im Projekt-Body oder per
  `/p:`. Damit generiert und injiziert Atlas nichts; das Binary hat dann gar keine Versionsressource,
  solange das Projekt keine eigene mitbringt.
- **Doppel-Resource.** Ein Projekt mit **eigener** `VERSIONINFO` (eigene `.rc` im
  `ResourceCompile`-Item) muss das Opt-out setzen. Sonst liegen zwei Versionsressourcen im Link, und
  der Build bricht mit dem typischen Fehlerbild
  `CVT1100: duplicate resource. type:VERSION, name:1, language:0x0409` (gefolgt von
  `LNK1123: failure during conversion to COFF`) ab. Eine Auto-Erkennung fremder `.rc`-Dateien gibt es
  bewusst nicht (fremde Ressourcenskripte zu parsen ist unzuverlaessig).
- **`Comments` und `LegalTrademarks`.** `VER_COMMENTS_STR` kommt aus `$(Description)`,
  `VER_LEGALTRADEMARKS_STR` aus `$(Trademark)` — dieselben zwei Properties, aus denen das .NET-SDK
  managed `AssemblyDescriptionAttribute` und `AssemblyTrademarkAttribute` schreibt. Keine der beiden
  hat einen Atlas-Default: ungesetzt bleibt das Feld leer, nativ wie managed.
- **Feld-selektives Ueberschreiben.** Die Identitaets-Makros (`VER_COMPANYNAME_STR`,
  `VER_FILEDESCRIPTION_STR`, `VER_INTERNALNAME_STR`, `VER_ORIGINALFILENAME_STR`,
  `VER_PRODUCTNAME_STR`, `VER_LEGALCOPYRIGHT_STR`, `VER_LEGALTRADEMARKS_STR`, `VER_COMMENTS_STR`,
  `VER_DEBUG`) stehen unter `#ifndef` — wer nur ein
  einzelnes Feld anders haben will, definiert das Makro vorab (`ClCompile`/`ResourceCompile`
  `PreprocessorDefinitions`) und laesst den Emitter an. Die Versions-Makros selbst sind `#undef`-t
  und tragen immer die Atlas-Werte.
- **`FILETYPE`.** `VER_FILETYPE` (ebenfalls `#ifndef`-guarded) ist `VFT_APP` bei
  `ConfigurationType=Application` und sonst `VFT_DLL` — auch, wenn gar kein `ConfigurationType`
  gesetzt ist (Standalone-Pre-Step aus einem managed Projekt) oder ein anderer Typ steht. Das Feld
  zeigt der Explorer nicht; wer `VS_FIXEDFILEINFO.dwFileType` auswertet (Installer, Inventory),
  sieht damit den richtigen Typ. Wer den Standalone-Pre-Step aus einem Projekt heraus fuer eine EXE
  nutzt, definiert `VER_FILETYPE` vorab.
- **`OriginalFilename` und `InternalName`.** `VER_ORIGINALFILENAME_STR` und `VER_INTERNALNAME_STR`
  (beide `#ifndef`-guarded) sind
  `$(TargetName)$(TargetExt)`, ersatzweise `$(AssemblyName)$(TargetExt)`, wenn das Projekt kein
  `TargetName` fuehrt. Fehlt die Erweiterung ganz, zeigen beide Makros wie bisher auf
  `VER_FILEDESCRIPTION_STR`. Managed schreibt Roslyn in beide Felder denselben Ausgabedateinamen —
  die geteilte Ableitung ist, was die zwei Stacks hier gleich haelt. **Achtung beim
  Standalone-Pre-Step aus einem managed Projekt:** dort ist
  `$(TargetExt)` die Erweiterung *dieses* Projekts (`.dll`), nicht die des nativen Ausgabebinaries —
  in dem Fall das Makro vorab definieren.
- **Standalone-Pre-Step.** `GenerateNativeVersionFile` schreibt `_version.h` (auf Unix ein
  arcade-verbatimes `_version.c` mit `sccsid`-String) und bleibt fuer fremde native Builds
  (CMake & Co.) bestehen. Daneben legt er auf Windows eine `NativeVersion.rc` ab, deren `#include`
  auf den tatsaechlich geschriebenen Header zeigt — auch bei eigenem `$(NativeVersionFile)`. Weil
  das Skript damit headerspezifisch ist, braucht ein zweites Projekt, das seinen Header ins selbe
  Verzeichnis schreibt, ein eigenes `NativeVersionResourceFile`; sonst gewinnt der letzte Lauf und
  das erste Skript inkludiert den falschen Header. `NativeVersionResourceFile` ist ein voller Pfad —
  liegt er in einem anderen Verzeichnis als der Header, wird der `#include` relativ dazu geschrieben.
  Auf denselben Pfad wie `NativeVersionFile` darf er nicht zeigen — beide Dateien schreibt dasselbe
  Target, die zweite legte die erste um; der Lauf bricht deshalb mit einem Fehler ab.
  Der Pre-Step teilt sich den Makro-Satz mit dem vcxproj-Emitter (`_ComputeNativeVersionHeader`),
  laeuft aber unabhaengig von ihm und wird nicht automatisch eingehaengt. Der vcxproj-Emitter selbst ist per
  Definition Windows-only.
- **Versionsfelder muessen Zahlen sein.** `VER_FILEVERSION`, `VER_PRODUCTVERSION`,
  `VER_VERSIONPREFIX`, `VER_ASSEMBLYVERSION` und `VER_ASSEMBLYFILEVERSION` sind blanke Zahl-Token,
  keine String-Literale — dort laesst sich nichts escapen. Traegt `VersionPrefix` oder
  `AssemblyVersion` etwas anderes als durch Punkte getrennte Ziffern, bricht der Windows-Zweig ab mit
  `<Property> is '<Wert>', which cannot go into the numeric VERSIONINFO fields: they take a bare
  number, where nothing can be escaped. A plain dotted version is what belongs there.` Umgebender
  Leerraum (ein ueber zwei Zeilen geschriebener XML-Wert) und fuehrende Nullen werden vorher
  entfernt — letztere, weil ein C-Literal mit fuehrender Null oktal gelesen wird und `1.0.010.0`
  sonst still acht bedeutete. Das Suffix (`-preview.1`) gehoert in `VersionSuffix`, nicht in diese
  beiden Properties; die annotierten `*_STR`-Makros tragen es ohnehin. `FileVersion` und
  `AssemblyFileVersion` werden nicht geprueft, weil Atlas sie ohnehin selbst berechnet — ein dort
  gesetzter Wert erreicht die Makros gar nicht.

### BuiltBy-Annotation (nativ und managed)

Die Versions-Strings tragen eine maschinenlesbare Annotation der Form
`@Name: Wert @Name: Wert` — im Explorer sichtbar, z. B.
`42.42.42.42424 @BuiltBy: alice-DEVBOX @Branch: feat/foo @Commit: 1a2b3c…`.

- **Dev-Builds** (`OfficialBuild != true`) annotieren `@BuiltBy` (Benutzer-Host), `@Branch` und
  `@Commit`.
- **Official-Builds** (`OfficialBuild=true`, abgeleitet aus `OfficialBuildId`) annotieren **nur**
  `@Commit` — deterministisch und ohne Buildhost im ausgelieferten Binary (wie `dotnet.exe`).
  Achtung: `OfficialBuildId` muss als globale Property (`-p:OfficialBuildId=...`) oder aus
  `Directory.Build.props` kommen. Im Projekt-Body kommt es zu spaet — die Ableitung
  `OfficialBuild=true` passiert in der props-Phase (`tools/DefaultVersions.props`), und ohne sie
  annotiert der Build weiter mit `@BuiltBy`, der Buildhost landet also doch im Binary.
- **Quellen.** Der Commit kommt primaer von SourceLink; ist er leer, liest Atlas `.git/HEAD` (loser
  Ref, sonst `packed-refs`) direkt — ohne `git.exe`, der Build bleibt hermetisch. Im `.vcxproj`-Pfad
  gibt es SourceLink nicht, dort sind die `.git`-Dateien immer die Quelle. Worktrees und Submodule
  (`.git` ist dort eine Datei mit `gitdir:`) werden aufgeloest. Der Branch kommt aus `.git/HEAD` und
  bleibt bei detached HEAD leer. Host/Benutzer kommen aus `System.Environment`. Jede dieser
  Properties (`GitHeadSha`, `GitBranchName`, `HostUserName`, `HostName`) kann mit einem **nicht
  leeren** Wert explizit gesetzt werden und gewinnt dann.
- **Ein leerer Wert unterdrueckt nichts.** Die Ableitungen greifen auf `'$(X)' == ''`, und MSBuild
  kann eine leer gesetzte Property nicht von einer ungesetzten unterscheiden — `-p:GitBranchName=`
  laesst den abgeleiteten Branch also stehen. Wer ein Feld gezielt loswerden will, hat zwei Hebel:
  `GitHeadSha=N/A` unterdrueckt `@Commit` (Sonderfall aus arcade), und `OfficialBuild=true` (ueber
  `OfficialBuildId`) unterdrueckt `@BuiltBy` und `@Branch`. Beides zusammen ergibt eine Annotation
  ohne Inhalt. Ein eigener Schalter, der die Annotation als Ganzes abschaltet, existiert nicht.
  Ein selbst gesetzter `BuiltByString` **ersetzt** die Annotation dagegen vollstaendig: die
  Ableitung ist auf einen leeren Wert gegated, es wird nichts angehaengt. Ein leerer Wert taugt
  aber nicht zum Abschalten — leer und ungesetzt sind fuer MSBuild dasselbe.
  Aus Branch- und Hostnamen entfernt Atlas
  `"` und `\` — die Annotation landet in String-Literalen mehrerer Sprachen (C#-Verbatim, C), und ein
  Branchname mit Anfuehrungszeichen (git erlaubt das) wuerde sonst den Build jedes Projekts brechen.
- **Welche Felder die Annotation tragen.** Nativ sind es vier `*_STR`-Makros
  (`VER_FILEVERSION_STR`, `VER_PRODUCTVERSION_STR`, `VER_ASSEMBLYVERSION_STR`,
  `VER_ASSEMBLYINFORMATIONALVERSION_STR`); im Explorer sichtbar sind davon zwei — "Dateiversion" und
  "Produktversion". Managed traegt nur die FileVersion die Annotation, und bei **F#** nur das
  managed Attribut: `fsc` leitet seine Win32-Ressource aus dem reinen Quadrupel ab und meldet das
  als `FS2003` (siehe `docs/decisions.md`, D4-Nachtrag). Die annotierten Werte stehen als Properties bereit —
  `FileVersionString`, `AssemblyVersionString`, `AssemblyInformationalVersionString` und
  `AnnotatedProductVersionString` —, sodass ein Stack-SDK, das sich ueber
  `GenerateVersionInfoDependsOn` einhaengt, sie liest statt sie erneut zusammenzusetzen. Managed kommt
  die `ProductVersion` dagegen aus dem
  `AssemblyInformationalVersionAttribute` und bleibt unannotiert. Der Unterschied ist geprueft und
  bewusst so entschieden (`docs/decisions.md`, Eintrag 2026-08-03 — #38); Issue #38 ist damit
  geschlossen. Die numerischen Felder (`VER_FILEVERSION`, `VER_PRODUCTVERSION`)
  bleiben in beiden Faellen das reine Quadrupel.
- **Managed FileVersion.** Damit managed und native Binaries dasselbe Explorer-Bild zeigen, emittiert
  Atlas das `AssemblyFileVersionAttribute` selbst mit dem annotierten String. Die
  `ThisAssembly`-Konstanten spiegeln dagegen 1:1 die gleichnamigen MSBuild-Properties — der Wert des
  Attributs steht dort als `ThisAssembly.FileVersionString`, nicht als `.AssemblyFileVersion`. Der numerische
  Fixed-Block der Ressource (`FileVersionRaw`) bleibt davon unberuehrt — Installer und
  Inventory-Tools lesen weiter das reine Quadrupel. Das Attribut steht in einer eigenen generierten
  Quelldatei je Sprache — `$(IntermediateOutputPath)$(MSBuildProjectName).AssemblyFileVersion.Generated.cs`
  bzw. `.vb`/`.fs` —, und die Formatwarnung, die der annotierte String ausloest, ist **dort** stumm
  gestellt: C# `#pragma warning disable CS7035`, VB `#Disable Warning BC42366`, F# `#nowarn "2003"`.
  Die Unterdrueckung reicht damit genau so weit wie die Datei, die sie braucht. Ein Projekt, das
  zusaetzlich ein eigenes, schlecht formatiertes Versions-Attribut schreibt, behaelt dessen Warnung;
  `$(NoWarn)` fasst Atlas fuer diese Codes nicht an, und eine globale `-p:NoWarn=…` kann die
  Unterdrueckung deshalb weder aufheben noch ersetzen. **Beim Upgrade schlaegt das in beide
  Richtungen aus:** wo die projektweite Weitung bisher ein eigenes, schlecht formatiertes
  Versions-Attribut mit stumm gestellt hat, meldet der Compiler es jetzt wieder — und mit Atlas'
  `TreatWarningsAsErrors`-Default wird aus einem bisher gruenen Build ein roter (gemessen). Der
  erste Ausweg ist der, den man auch ohne Atlas naehme: den Attributwert in Ordnung bringen. Wer den
  Code stattdessen stumm stellen will, setzt im Projekt-Body direkt
  `<NoWarn>$(NoWarn);CS7035</NoWarn>` — projektlokal und gemessen wirksam. `AdditionalNoWarn` und
  `AdditionalWarningsNotAsErrors` gehen dafuer **ebenfalls** aus dem Projekt-Body, seit
  `ProjectDefaults.targets` sie in der targets-Phase noch einmal auswertet (Abschnitt
  "Ableitungs-Muster" oben). Vor diesem Schnitt wirkten sie nur vor dem Atlas-`Sdk.props`-Import —
  im gemeinsamen `Directory.Build.props` oder als globale `-p:`-Property — und damit repo-weit statt
  fuer das eine Projekt; diese beiden Positionen wirken unveraendert weiter.
  Beide Positionen und beide Properties sind gemessen
  (`ConsumerOwnedVersionAttribute_TurnsRedUnderTheWarningsAsErrorsDefault`); der Unterschied zwischen
  ihnen bleibt: `NoWarn` nimmt die Diagnose weg, `AdditionalWarningsNotAsErrors` stuft sie nur von
  Fehler zurueck auf Warnung. Emittiert wird die Datei nur fuer die drei
  managed SDK-Sprachen (C#, VB, F#) und nur, solange `GenerateAssemblyInfo` `true` ist — ein Projekt
  mit handgeschriebener `AssemblyInfo` bekommt wie zuvor gar kein Atlas-Attribut. Den
  `+<sha>`-Suffix haengt das .NET-SDK nur an sein eigenes
  `AssemblyInformationalVersionAttribute` an; die zentralen Atlas-Werte (und damit `ThisAssembly`,
  die `AssemblyMetadata`-Paare und der native Header) fuehren die Version ohne ihn — der Commit steht
  dort in `@Commit:` und als eigenes Metadatum `GitHeadSha`. Siehe `docs/decisions.md`,
  Eintraege 2026-07-30 — D4 und 2026-08-02 — D4.1.
- **Eigenes FileVersion-Attribut.** Wer das Attribut selbst schreibt (z. B. portierter Legacy-Code
  mit handgeschriebener `AssemblyInfo.cs`), setzt `GenerateAssemblyFileVersionAttribute=false` — der
  Standard-Schalter des .NET-SDK, den Atlas mitliest. Dann emittiert weder das SDK noch Atlas ein
  Attribut, und das eigene bleibt allein stehen. Ohne den Schalter kollidieren beide (`CS0579`).
  Achtung: der Schalter muss vor dem Atlas-`Sdk.targets`-Import sichtbar sein (Projekt-Body oder
  `Directory.Build.props`). Anders als die BuiltBy-Properties ist er kein "eigener Wert gewinnt"-Feld:
  jeder andere Wert als `false` bedeutet "Atlas annotiert". Als **globale** Property
  (`-p:GenerateAssemblyFileVersionAttribute=true`) kann der Projekt-Body sie nicht mehr umsetzen —
  dann emittiert das SDK sein eigenes Attribut, und Atlas tritt zurueck: das Binary traegt das reine
  Quadrupel ohne Annotation, statt dass der Build an `CS0579` scheitert.
- **`ThisAssembly` nur fuer C#.** Die generierte Konstanten-Quelle ist C#, also emittiert Atlas sie
  nur fuer C#-Projekte (`AtlasSdkGenerateThisAssembly`, Default `true`). VB- und F#-Projekte
  bekommen die Werte ueber die sprachneutralen `AssemblyMetadata`-Paare und den annotierten
  `FileVersion`-String; eigene Emitter fuer diese Sprachen sind Phase 6.
- **Namespace der Konstanten.** `ThisAssembly` liegt im Namespace aus `RootNamespace`, normalisiert
  zu einem gueltigen C#-Bezeichner: was nicht Teil eines Bezeichners sein kann, wird Unterstrich;
  was keinen Bezeichner beginnen kann, bekommt einen davor; leere Segmente fallen weg
  (`My-Lib` → `My_Lib`, `9Lives` → `_9Lives`). Umlaute und andere Unicode-Buchstaben bleiben stehen,
  sie sind in C#-Bezeichnern gueltig (`Grün.Werkzeuge` bleibt `Grün.Werkzeuge`); Zeichen ausserhalb
  der Basic Plane dagegen nicht — der Compiler akzeptiert sie in Bezeichnern nicht, also werden sie
  ersetzt. Ein Segment, das ein reserviertes Schluesselwort ist, bekommt das Verbatim-Praefix
  (`class` → `@class`). Ist `RootNamespace` leer, greift `AssemblyName`, dann der Projektname.
  Bis auf das Schluesselwort-Praefix ist das dieselbe Regel wie in Razors `SanitizeIdentifier` und
  MSBuilds `MakeValidEverettIdentifier`; warum Atlas dort weitergeht, steht in `docs/decisions.md`
  (Eintrag 2026-07-30 — D4).

### Versions-Manifest und Gleichlauf-Pruefung

Nach jedem Build schreibt Atlas `$(IntermediateOutputPath)$(MSBuildProjectName).AtlasVersions.json` — alle
Versionswerte dieses Builds an einer Stelle: die aus `_ComputeVersionInfo` samt annotierten Varianten,
`VsixVersion`, bei WiX-v4+-Projekten `MsiVersion`/`BundleVersion`, `OfficialBuildId`, `GitHeadSha` und
`BuiltByString`. Das erste Feld `atlasVersionManifest` nennt die Formatversion (derzeit `1`); ungesetzte Werte
stehen als leerer String darin. Die Datei liegt nur unter `obj`, geht weder nach `bin` noch ins Paket und wird
nur bei geaendertem Inhalt neu geschrieben. Ein Design-Time-Build schreibt sie nicht. WiX-v3-Projekte bekommen
keins (sie erreichen `sdk/Sdk.targets` nicht).

Danach liest Atlas die Version aus jedem Artefakt zurueck, das der Build erzeugt hat, und bricht bei einer
Abweichung ab — `ATLAS0120` fuer die Assembly, `ATLAS0121` fuer das native Programm eines `.vcxproj`,
`ATLAS0122` fuer die `.nuspec` beim Pack (Tabelle "Diagnose-Codes"). Eine Abweichung heisst: ein Schritt nach
der Berechnung hat einen Wert geaendert, etwa eine spaete Property oder ein fremdes Target. Die Pruefung laeuft
inkrementell: ein unveraendertes Artefakt gegen ein unveraendertes Manifest wird nicht erneut gelesen.

| Property | Default | Wirkung |
|---|---|---|
| `AtlasSdkGenerateVersionManifest` | `true` | `false` schreibt kein Manifest — und schaltet damit auch die Pruefung ab, die darauf aufsetzt. |
| `AtlasSdkVerifyVersionConsistency` | `true` | `false` schaltet nur die Pruefung ab. |

VSIX- und MSI-Version behalten ihre eigenen Formeln (`tools/VisualStudio.VsixVersion.targets`,
`tools/Wix/Wix.targets`); das Manifest ist die Stelle, an der alle nebeneinander stehen (`docs/decisions.md`,
Eintrag zu #126, PR B).

### Version und Commit eines Artefakts lesen (`AtlasVersionInfo`)

Ein fertiges Artefakt verraet Version und Commit, ohne dass es laeuft (Vorbild `go version -m`), aus jedem
Projekt, das Atlas nutzt:

```text
dotnet msbuild <Projekt> -t:AtlasVersionInfo -p:AtlasVersionInfoPath=artifacts/packages
dotnet msbuild <Projekt> -t:AtlasVersionInfo -p:AtlasVersionInfoPath=<Datei> -p:AtlasVersionInfoFormat=json
```

Gelesen wird eine Assembly aus ihren Metadaten (Version aus `InformationalVersion`, Commit aus dem
Metadaten-Paar `GitHeadSha` oder der annotierten Dateiversion), ein natives Windows-Programm aus seiner
Versionsressource (nur unter Windows), ein `.nupkg` aus seiner `.nuspec` (`version`, `repository/@commit`) und
jede andere Binaerdatei — auch ein Native-AOT-Programm unter Linux oder macOS — aus ihrer `@(#)`-Kennung.

- **`.msi`** (Art `msi`, nur unter Windows, ueber `msi.dll`): Version aus der MSI-Property `AtlasVersion`, fehlt
  sie, aus `ProductVersion`; Commit aus `AtlasCommit` (Abschnitt "WiX-Projekte (MSI und Bundle)").
  Ausserhalb Windows steht die Datei mit "readable on Windows only" in der Ausgabe, der Lauf geht weiter.
- **`.vsix`** (Art `vsix`): Version aus `extension.vsixmanifest` (`Metadata/Identity/@Version`, nur Manifest v2);
  Commit aus den Assemblies im Paket, im Speicher gelesen, nichts wird entpackt. Nennen sie verschiedene
  Commits, stehen alle da ("(several)", in `json` als `commits`), keiner wird ausgewaehlt — auch dann, wenn
  eine mitgelieferte, mit Atlas gebaute Bibliothek aus einem anderen Repo ihren eigenen Commit traegt. Ein VSIX
  mit Manifest v1 oder ohne Manifest gilt als Datei ohne erkennbare Version.

Ein Ordner wird rekursiv gelesen, versteckte Ordner eingeschlossen (`.dll`, `.exe`, `.nupkg`, `.msi`, `.vsix`, `.so`,
`.dylib` und ELF-/Mach-O-Programme und -Bibliotheken mit anderer oder ohne Endung, etwa `Contoso.App`, auch universelle
Mach-O-Dateien; nicht Objektdateien und abgetrennte Symbole wie `.dbg`). Ein Verweis auf eine Datei wird gelesen, in
einen Verweis auf einen Ordner steigt der Lauf nicht ab, so zaehlt ein Verweis-Kreis nichts doppelt; unter Windows gilt
das fuer jeden Ordner mit Reparse-Punkt, auch eine Junction (ob OneDrive-Ordner betroffen sind, ist nicht gemessen).
Eine Datei mit fremder Endung, die sich dafuer nicht oeffnen laesst oder als Verweis ins Leere fuehrt, zaehlt nicht,
ohne Warnung. Eine Datei, die — am Ende ihrer Verweise — keine Laenge meldet, wird nie geoeffnet: So zeigen sich neben
einer leeren Datei FIFO, Socket und Geraet, deren Oeffnen blockieren oder nie enden kann (wird eine Datei erst zwischen
Pruefung und Oeffnen zur FIFO ohne Schreiber, haengt der Lauf trotzdem: .NET kann nicht ohne Blockieren oeffnen). Traegt
sie eine Artefakt-Endung oder ist sie einzeln genannt, steht sie als Warnung da ("is empty or no regular file"), sonst
bleibt sie still aussen vor. Eine Datei ohne erkennbare Version steht mit "no version found" darin. Danach steht, ob
alle Artefakte denselben Commit nennen oder welche verschiedenen es gibt. Steuer-, Trenn- und Formatzeichen aus einem
Artefakt (etwa ein Zeilenumbruch in der Version oder eine Bidi-Umkehr) stehen im Text als `\uXXXX`. Ein relativer Pfad
gilt gegen das Projektverzeichnis. `json` gibt ein Array mit `path`, `kind`, `version`, `commit` aus, dazu `commits` und
`note` nur dort, wo sie etwas sagen.

### Dasselbe ohne Projekt: `atlas-version`

Das Paket `DotNet.Atlas.VersionInfo` bringt dieselben Leser als `dotnet tool` mit dem Befehl `atlas-version` —
ohne Projekt, ohne MSBuild, framework-abhaengig (`net10.0`, ein Paket fuer jedes Betriebssystem). Es traegt
dieselbe Version wie das SDK-Paket, bis zum finalen Release also eine Vorabversion (`docs/versioning.md`
§ "Package-Version"): Installation und `dnx` brauchen `--prerelease` oder die Version. Es startet auch auf einer
neueren Haupt-Laufzeit (`RollForward` `Major`), etwa wo nur .NET 11 installiert ist.

```text
dotnet tool install --global DotNet.Atlas.VersionInfo --prerelease
dotnet tool install --global DotNet.Atlas.VersionInfo --version <version>
atlas-version artifacts/packages
atlas-version --json <datei-oder-ordner>...
dnx DotNet.Atlas.VersionInfo --prerelease --yes <pfad>...
```

Jeder Pfad gibt denselben Text aus wie `AtlasVersionInfo` fuer ihn, nacheinander; `--json` gibt ein Array ueber alle
Pfade aus (bei einem Pfad dasselbe wie `AtlasVersionInfoFormat=json`). Ein relativer Pfad gilt gegen das aktuelle
Verzeichnis; nach `--` ist alles ein Pfad, auch was mit `-` beginnt. Der Bericht geht auf die Standardausgabe,
Warnungen, Fehler und Abweichungen auf die Fehlerausgabe. `--expect-commit` und `--expect-version` gelten je einmal;
zweimal gegeben ist ein falscher Aufruf.

- **`--expect-commit <sha>`** — jedes Artefakt, das einen Commit nennt, muss diesen nennen. Der Wert ist 7 bis 64
  Hex-Ziffern; gekuerzt vergleicht das Werkzeug ueber die kuerzere Laenge, Gross-/Kleinschreibung egal. Ein VSIX mit
  mehreren Commits stimmt nur, wenn alle stimmen. Ein Wert, der kein Commit ist, zaehlt nicht: `N/A` oder leer
  (Build ohne Git), weniger als 7 Hex-Ziffern.
- **`--expect-version <version>`** — jedes Artefakt, das eine Version nennt, muss diese nennen, gleich bis auf einen
  `+`-Anhang (Build-Metadaten; das .NET SDK haengt einer Assembly `+<sha>` an) und ohne Gross-/Kleinschreibung, wie
  NuGet Versionen vergleicht. Verglichen wird mit der angezeigten Version, und die ist je Art eine andere Groesse:
  Assembly, `.nupkg`, natives Programm und MSI nennen die Version (`$(Version)`), ein VSIX seine vierteilige
  `VsixVersion`, ein Programm mit `@(#)`-Kennung (Native AOT unter Linux/macOS) seine vierteilige `FileVersion`.
  Fuer ein VSIX gilt auch die `VsixVersion`, die aus einer datierten Vorabversion folgt: `1.2.3-preview.1.26473.1`
  ergibt `1.2.3.2647301` (Datum, Tageszaehler zweistellig; bei einem Projekt mit eigenem `VsixVersionPrefix` nicht).
  Fuer ein `@(#)`-Programm gelten beide `FileVersion`s, die `CalculateAssemblyAndFileVersions` daraus rechnet — je
  nach `AutoGenerateAssemblyVersion`, das kein Artefakt nennt: `10.0.0-preview.1.26473.1` ergibt `10.0.26.47301` oder
  `10.0.14.47301` (bei eigenem `VersionBaseShortDate` nur die erste). Eine Version ohne Datum (final, `.final`,
  release-only) traegt es nicht; gegen sie besteht ein VSIX nie, ebenso wenig ein AOT-Programm. Die Abweichungszeile nennt Art, gefundenen und erwarteten Wert (`mismatch: <pfad>: vsix version
  1.2.3.2647301, expected 1.2.3`). Ein Ausgabeordner mit fremden Assemblies (`bin/Release/...`) besteht die Pruefung
  nie: jede Abhaengigkeit nennt ihre eigene Version.
- **Ohne Wert zaehlt ein Artefakt nicht:** eine Datei ohne erkennbare Version, ein MSI ausserhalb Windows, ein
  Artefakt ohne Commit bleiben bei der jeweiligen Pruefung aussen vor. Zaehlt gar keins, gilt die Pruefung als nicht
  bestanden — nichts hat sie belegt. Ein Artefakt, das sich nicht lesen laesst oder leer ist, besteht sie ebenfalls
  nicht: unter `--expect-*` wird aus der Warnung eine Abweichung.

**Exit-Codes:** `0` gelesen (und jede Erwartung erfuellt), `1` Fehler (falscher Aufruf, ein Pfad ist weder Datei
noch Ordner; geht einer Abweichung vor, die Abweichungen des Lesbaren stehen trotzdem da), `2` eine Erwartung nicht
erfuellt oder unter `--expect-*` ein Artefakt nicht lesbar oder leer. `--help` gibt die Aufrufhilfe aus (Exit 0); ein falscher
Aufruf gibt sie mit dem Fehler auf die Fehlerausgabe. Mit `--json` steht bei einem Pfad, der weder Datei noch Ordner
ist, das Array der lesbaren trotzdem auf der Standardausgabe; bei falschem Aufruf steht dort nichts. Ohne
`--expect-*` ist eine Datei, die sich nicht oeffnen laesst, wie im Task eine Warnung, kein Fehler.

### Versionskennung in Native-AOT-Programmen

Unter Linux und macOS (macOS nicht gemessen) bekommt ein Native-AOT-Programm (`PublishAot=true`) die
`@(#)Version …`-Kennung des
Standalone-Pre-Steps: Atlas kompiliert dessen `_version.c` (`$(MSBuildProjectName).sccsid.c` unter `obj`) mit
dem Compiler, mit dem ILC linkt, und gibt das Objekt an den Linker. arcades `AddSccsidMetadata` allein reicht
nicht — ILC behaelt Assembly-Attribute nur, wenn erreichbarer Code sie liest
(`docs/research/2026-09-27T2140Z-aot-version.md`). `AtlasSdkEmbedSccsid=false` schaltet das ab; fuer
`NativeLib=Static` greift es nicht (dort linkt der Konsument selbst). Unter Windows traegt die Versionsressource
dieselbe Information: ILC uebernimmt sie aus der verwalteten Assembly.

## Multithreaded-Modus (`-mt`) der Wurzelskripte

Kein `Config.props`-Feld, sondern ein Schalter von `Build.cmd`/`build.sh` (`eng/common`). MSBuilds
Multithreaded-Modus laeuft **nur auf Wunsch**: `-mt 1` bzw. `--mt true`, lokal wie auf CI. Anders als
arcade (#17587, dort lokal standardmaessig an) schaltet Atlas ihn auch lokal nicht von selbst ein —
Entscheid @ww3d nach der Messung unten (#90). Atlas' eigene CI fragt ihn ausdruecklich an.

- **Tasks ohne `[MSBuildMultiThreadableTask]`** laufen unter `-mt` in einem Task-Host-Beiprozess und
  behalten dort das Projektverzeichnis als Arbeitsverzeichnis; ein relativer Pfad landet weiter im
  Projekt (`UnmarkedConsumerTaskE2ETests`, Inline- und kompilierte Task). Unter SDK 10.0.401 betrifft
  das nicht nur eigene Tasks: in Atlas' eigenem Build liefen 244 von 610 Task-Aufrufen dort, darunter
  `Csc`, `RestoreTask` und NuGet-Tasks. Ein Beiprozess wird wiederverwendet; der Umlauf kostete rund
  84 ms je Aufruf (gemessen unter Volllast), ein Zeitgewinn fuer Atlas' Build war nicht messbar.
- **Beiprozesse bleiben lokal stehen.** Mit Node-Reuse (lokal Standard) ueberleben sie den Build wie
  Knoten und halten geladene Task-Assemblies; eine im Repo gebaute Task-DLL laesst sich dann nicht neu
  bauen (`MSB3026`/`MSB3027`). Abhilfe: `-mt 0`, `-nodeReuse 0` (bzw. `MSBUILDDISABLENODEREUSE=1`) oder
  `TaskFactory="TaskHostFactory"` fuer die eigene Task.
- **MSBuild-Server:** `dotnet msbuild` des SDK 10.0.401 startet einen Server, der den Build
  ueberlebt — mit und ohne `-mt`. `MSBUILDUSESERVER=0` verhindert das.
- Die Atlas-Tasks selbst tragen das Attribut und laufen in-process (`MultiThreadedBuildE2ETests`).
- **Repo-Tools (`.config/dotnet-tools.json`):** `dotnet tool restore` laeuft auf CI
  (`ContinuousIntegrationBuild=true`) bis zu zweimal, lokal einmal; `RestoreRepoToolsMaxAttempts` in
  `Config.props` setzt die Zahl selbst (arcade #17593).

## Von arcade migrieren: umbenannte Schalter

Einige Schalter, die ein Konsument in seiner eigenen `Directory.Build.props` setzt, heissen in Atlas
anders als in arcade — `Arcade` ist im Namen durch `Atlas` ersetzt. Ein migrierendes Repo, das den
alten Namen setzt, verliert die Einstellung **still**: kein Fehler, keine Warnung, der alte Name wird
nicht gelesen. Am arcade-Pin `291c2c52` gegen Atlas abgeglichen:

| arcade | Atlas |
|---|---|
| `DisableArcadeTestFramework` | `DisableAtlasTestFramework` |
| `DisableArcadeExcludeFromBuildSupport` | `DisableAtlasExcludeFromBuildSupport` |
| `EnableArcadeRuntimeIdentifierInference` | `EnableAtlasRuntimeIdentifierInference` |
| `EnableArcadeRuntimeIdentifierFilters` | `EnableAtlasRuntimeIdentifierFilters` |

Gesucht wurde nach Atlas-Properties mit `Atlas` im Namen, die in einer Bedingung gelesen werden
(`sdk/`, `tools/`, `toolset/`), und nach ihrem Gegenstueck in arcades `sdk/Sdk.props`,
`tools/BeforeCommonTargets.targets` und `tools/RuntimeIdentifierInference.BeforeNETSdkTargets.targets`.

## Beispiel

Vollstaendige `Config.props` fuer ein Repo, das alle Felder explizit setzt (weglassen heisst Default
uebernehmen; `Company` und die Lizenz haben keinen, Abschnitt "Pflichtangaben"):

```xml
<Project>

  <PropertyGroup>
    <!-- Metadaten -->
    <ProductName>Widget Factory</ProductName>
    <Company>Contoso</Company>
    <Product>Widget Factory</Product>
    <Authors>Contoso</Authors>
    <Owners>Contoso</Owners>
    <Copyright>Copyright © 2026 Contoso. All rights reserved.</Copyright>
    <NeutralLanguage>en-US</NeutralLanguage>
    <PackageLicenseExpression>MIT</PackageLicenseExpression>

    <!-- Versionierung -->
    <VersionPrefix>1.2.0</VersionPrefix>
    <PreReleaseVersionLabel>preview</PreReleaseVersionLabel>
    <PreReleaseVersionIteration>1</PreReleaseVersionIteration>
    <SemanticVersioningV1>false</SemanticVersioningV1>
    <DotNetUseShippingVersions>false</DotNetUseShippingVersions>

    <!-- Ausgabe-Layout -->
    <ArtifactsDir>$(MSBuildThisFileDirectory)build\</ArtifactsDir>
    <ArtifactsBinDir>build/bin</ArtifactsBinDir>
    <ArtifactsObjDir>build/obj</ArtifactsObjDir>
    <ArtifactsPackagesDir>build/packages</ArtifactsPackagesDir>
    <ArtifactsTmpDir>build/tmp</ArtifactsTmpDir>
    <ArtifactsTestResultsDir>build/test-results</ArtifactsTestResultsDir>
    <ArtifactsPublishDir>build/publish</ArtifactsPublishDir>

    <!-- Hochladen -->
    <UsingNuGetPush>true</UsingNuGetPush>
  </PropertyGroup>

  <ItemGroup>
    <NuGetPushUrls Include="https://feed.example/nuget/v3/index.json" />
  </ItemGroup>

</Project>
```

`OutDirName` steht bewusst **nicht** in diesem Beispiel: es ist ein Pro-Projekt-Segment und gehoert
ins Projektfile, nicht in die repo-weite Flaeche.
