param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
)

$ErrorActionPreference = "Stop"

$OutDir = Join-Path $ProjectRoot "data\localization"
$Entries = [ordered]@{}
$Sources = @{}

$JsonFields = @(
    "name", "display_name", "title", "subtitle", "label", "text",
    "desc", "description", "tooltip", "prompt", "choice_text",
    "loc_name", "loc_desc"
)
$SceneProps = @(
    "text", "tooltip_text", "placeholder_text", "title",
    "ok_button_text", "cancel_button_text", "dialog_text", "window_title"
)

function Get-RelativePath([string]$Path) {
    $rootUri = [System.Uri](([System.IO.Path]::GetFullPath($ProjectRoot).TrimEnd('\') + '\'))
    $pathUri = [System.Uri]([System.IO.Path]::GetFullPath($Path))
    return [System.Uri]::UnescapeDataString($rootUri.MakeRelativeUri($pathUri).ToString()).Replace("\", "/")
}

function Test-PathLike([string]$Value) {
    $lower = $Value.ToLowerInvariant()
    return $lower.StartsWith("res://") `
        -or $lower.StartsWith("uid://") `
        -or $lower.StartsWith("assets/") `
        -or $lower.StartsWith("icons/") `
        -or $lower.StartsWith("sfx/") `
        -or $lower.StartsWith("vfx/") `
        -or $Value.Contains("/") `
        -or $Value.Contains("\") `
        -or $lower.EndsWith(".png") `
        -or $lower.EndsWith(".ogg") `
        -or $lower.EndsWith(".wav") `
        -or $lower.EndsWith(".tscn") `
        -or $lower.EndsWith(".tres") `
        -or $lower.EndsWith(".prefab") `
        -or $lower.EndsWith(".anim") `
        -or $lower.EndsWith(".json") `
        -or $lower.EndsWith(".gd")
}

function Test-LocKey([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or (Test-PathLike $Value)) {
        return $false
    }
    if ($Value.Contains(" ") -or $Value.Contains("`n") -or $Value.Contains("`t")) {
        return $false
    }
    return (($Value -match '^[A-Za-z][A-Za-z0-9_.-]*$') -and ($Value.Contains(".") -or $Value.Contains("_")))
}

function ConvertTo-Slug([string]$Value) {
    $slug = ($Value.Trim() -replace '[^A-Za-z0-9]+', '_').Trim('_').ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return "item"
    }
    return $slug
}

function ConvertFrom-LocKeyToText([string]$Key, [string]$FieldName) {
    $base = ($Key -split '\.')[-1]
    foreach ($suffix in @("_display_name", "_name", "_title", "_subtitle", "_desc", "_description", "_tooltip", "_text")) {
        if ($base.EndsWith($suffix)) {
            $base = $base.Substring(0, $base.Length - $suffix.Length)
            break
        }
    }
    $words = @($base -split '[_\-.]+' | Where-Object { $_ })
    if ($words.Count -eq 0) {
        return ""
    }
    if (@("name", "display_name", "title", "subtitle", "loc_name") -contains $FieldName) {
        return ($words | ForEach-Object {
            if ($_.Length -le 1) { $_.ToUpperInvariant() } else { $_.Substring(0, 1).ToUpperInvariant() + $_.Substring(1).ToLowerInvariant() }
        }) -join " "
    }
    return ""
}

function Add-Entry([string]$Key, [string]$Value, [string]$Source, [string]$Note) {
    if ([string]::IsNullOrWhiteSpace($Key)) {
        return
    }
    if (-not $Entries.Contains($Key)) {
        $Entries[$Key] = $Value
    } elseif ([string]::IsNullOrEmpty([string]$Entries[$Key]) -and -not [string]::IsNullOrEmpty($Value)) {
        $Entries[$Key] = $Value
    }
    if (-not $Sources.ContainsKey($Key)) {
        $Sources[$Key] = @()
    }
    $Sources[$Key] += [ordered]@{
        source = $Source
        note = $Note
    }
}

function Get-JsonPrefix([string]$Path, [string]$ObjectId) {
    $relative = Get-RelativePath ([System.IO.Path]::ChangeExtension($Path, $null))
    $parts = $relative -split '[\\/]'
    if ($parts.Count -ge 3 -and $parts[0] -eq "data") {
        $category = $parts[1].Replace("_", ".")
        return "$category.$ObjectId"
    }
    return (($parts | ForEach-Object { ConvertTo-Slug $_ }) -join ".")
}

function Read-JsonNode($Node, [string]$Path, [string]$ObjectId, [string[]]$Trail) {
    if ($null -eq $Node) {
        return
    }
    if ($Node -is [System.Array]) {
        for ($i = 0; $i -lt $Node.Count; $i++) {
            Read-JsonNode $Node[$i] $Path $ObjectId ($Trail + [string]$i)
        }
        return
    }
    if ($Node -is [System.Management.Automation.PSCustomObject]) {
        $localId = $ObjectId
        if ($Node.PSObject.Properties.Name -contains "id") {
            $localId = [string]$Node.id
        }
        foreach ($prop in $Node.PSObject.Properties) {
            $field = $prop.Name
            $value = $prop.Value
            $nextTrail = $Trail + $field
            if ($JsonFields -contains $field -and $value -is [string] -and -not (Test-PathLike $value)) {
                if (Test-LocKey $value) {
                    $key = $value
                    $text = ConvertFrom-LocKeyToText $value $field
                    $note = "existing localization key in data"
                } else {
                    $prefix = Get-JsonPrefix $Path $localId
                    $key = "$prefix.$(($nextTrail | ForEach-Object { ConvertTo-Slug $_ }) -join '.')"
                    $text = $value
                    $note = "literal data string"
                }
                Add-Entry $key $text "$(Get-RelativePath $Path):$($nextTrail -join '.')" $note
            } else {
                Read-JsonNode $value $Path $localId $nextTrail
            }
        }
    }
}

function Read-JsonFiles {
    $dataDir = Join-Path $ProjectRoot "data"
    if (-not (Test-Path $dataDir)) {
        return
    }
    Get-ChildItem $dataDir -Recurse -Filter "*.json" | Sort-Object FullName | ForEach-Object {
        if ($_.FullName.StartsWith($OutDir)) {
            return
        }
        $raw = Get-Content $_.FullName -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return
        }
        $payload = $raw | ConvertFrom-Json
        Read-JsonNode $payload $_.FullName $_.BaseName @()
    }
}

function Read-SceneFiles {
    $scenesDir = Join-Path $ProjectRoot "scenes"
    if (-not (Test-Path $scenesDir)) {
        return
    }
    Get-ChildItem $scenesDir -Recurse -Filter "*.tscn" | Sort-Object FullName | ForEach-Object {
        $path = $_.FullName
        $sceneStem = [System.IO.Path]::GetFileNameWithoutExtension($path)
        $currentNode = $sceneStem
        $lineNo = 0
        Get-Content $path -Encoding UTF8 | ForEach-Object {
            $lineNo += 1
            $line = $_
            if ($line -match '^\[node name="([^"]+)"') {
                $currentNode = $Matches[1]
                return
            }
            if ($line -notmatch '^([A-Za-z0-9_/\-]+)\s*=\s*(.+)$') {
                return
            }
            $prop = $Matches[1]
            $rawValue = $Matches[2]
            if ($SceneProps -notcontains $prop) {
                return
            }
            if ($rawValue -notmatch '"((?:\\.|[^"\\])*)"') {
                return
            }
            $value = [regex]::Unescape($Matches[1])
            if ([string]::IsNullOrWhiteSpace($value) -or (Test-PathLike $value)) {
                return
            }
            $key = "ui.$sceneStem.$(ConvertTo-Slug $currentNode).$(ConvertTo-Slug $prop)"
            Add-Entry $key $value "$(Get-RelativePath $path):$lineNo" "scene property"
        }
    }
}

function Test-UserFacingCodeString([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value.Length -lt 3 -or (Test-PathLike $Value) -or (Test-LocKey $Value)) {
        return $false
    }
    if (@("info", "warn", "error", "debug", "header", "body", "small", "display", "num_small", "num_large") -contains $Value.ToLowerInvariant()) {
        return $false
    }
    if ($Value.TrimStart().StartsWith("->")) {
        return $false
    }
    if ($Value.Contains("%") -and -not ($Value.Contains(" ") -or $Value.Contains(":"))) {
        return $false
    }
    if ($Value -match '^[_$&]') {
        return $false
    }
    if ($Value -cmatch '^[a-z0-9_]+$') {
        return $false
    }
    $withoutFormats = $Value -replace '%[-+ #0-9.]*[bcdeEfFgGosuxX]', ''
    $lettersOnly = $withoutFormats -replace '[^\p{L}]', ''
    if ([string]::IsNullOrEmpty($lettersOnly)) {
        return $false
    }
    return $withoutFormats -match '\p{L}'
}

function Read-GdScriptFiles {
    $scriptsDir = Join-Path $ProjectRoot "scripts"
    if (-not (Test-Path $scriptsDir)) {
        return
    }
    foreach ($file in @(Get-ChildItem $scriptsDir -Recurse -Filter "*.gd" | Sort-Object FullName)) {
        $path = $file.FullName
        $relativeForFilter = (Get-RelativePath $path)
        if (-not $relativeForFilter.StartsWith("scripts/presentation/")) {
            continue
        }
        $scriptsUri = [System.Uri](([System.IO.Path]::GetFullPath($scriptsDir).TrimEnd('\') + '\'))
        $pathUri = [System.Uri]([System.IO.Path]::GetFullPath($path))
        $scriptRel = [System.Uri]::UnescapeDataString($scriptsUri.MakeRelativeUri($pathUri).ToString())
        $scriptKey = [System.IO.Path]::ChangeExtension($scriptRel, $null).Replace("\", ".").Replace("/", ".").Trim(".")
        $lineNo = 0
        foreach ($line in @(Get-Content $path -Encoding UTF8)) {
            $lineNo += 1
            $trimmed = $line.Trim()
            if ($trimmed.StartsWith("#")) {
                continue
            }
            if ($line -notmatch '\.text\s*=|\.title\s*=|\.tooltip_text\s*=|\.placeholder_text\s*=|ui_toast_requested|_make_[A-Za-z0-9_]*\(|add_tab\(|add_item\(|ask\(|Localization\.t\(|Localization\.tf\(') {
                continue
            }
            foreach ($match in [regex]::Matches($line, '"((?:\\.|[^"\\])*)"')) {
                $value = [regex]::Unescape($match.Groups[1].Value)
                if (-not (Test-UserFacingCodeString $value)) {
                    continue
                }
                $key = "ui.code.$scriptKey.$lineNo"
                Add-Entry $key $value "$(Get-RelativePath $path):$lineNo" "probable UI string in GDScript"
            }
        }
    }
}

function Write-Outputs {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $existingEnPath = Join-Path $OutDir "en.json"
    $existingRuPath = Join-Path $OutDir "ru.json"
    $existingEn = @{}
    $existingRu = @{}
    if (Test-Path $existingEnPath) {
        (Get-Content $existingEnPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
            $existingEn[$_.Name] = [string]$_.Value
        }
    }
    if (Test-Path $existingRuPath) {
        (Get-Content $existingRuPath -Raw -Encoding UTF8 | ConvertFrom-Json).PSObject.Properties | ForEach-Object {
            $existingRu[$_.Name] = [string]$_.Value
        }
    }
    foreach ($key in $existingEn.Keys) {
        if (-not $Entries.Contains($key)) {
            $Entries[$key] = $existingEn[$key]
            $Sources[$key] = @([ordered]@{ source = "preserved from existing en.json"; note = "manual or stale key" })
        }
    }
    foreach ($key in $existingRu.Keys) {
        if (-not $Entries.Contains($key)) {
            $Entries[$key] = ""
            $Sources[$key] = @([ordered]@{ source = "preserved from existing ru.json"; note = "manual or stale key" })
        }
    }
    $sortedKeys = @($Entries.Keys | Sort-Object)
    $en = [ordered]@{}
    $ru = [ordered]@{}
    $src = [ordered]@{}
    foreach ($key in $sortedKeys) {
        $en[$key] = if ($existingEn.ContainsKey($key) -and $existingEn[$key] -ne "") { $existingEn[$key] } else { $Entries[$key] }
        $ru[$key] = if ($existingRu.ContainsKey($key)) { $existingRu[$key] } else { "" }
        $src[$key] = $Sources[$key]
    }
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText((Join-Path $OutDir "en.json"), (($en | ConvertTo-Json -Depth 20) + "`n"), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $OutDir "ru.json"), (($ru | ConvertTo-Json -Depth 20) + "`n"), $utf8NoBom)
    [System.IO.File]::WriteAllText((Join-Path $OutDir "_sources.json"), (($src | ConvertTo-Json -Depth 20) + "`n"), $utf8NoBom)

    $filled = @($sortedKeys | Where-Object { -not [string]::IsNullOrEmpty([string]$Entries[$_]) }).Count
    $missing = $sortedKeys.Count - $filled
    $readme = @"
# Localization Data

Generated by ``pwsh -File scripts/tools/extract_localization.ps1``.

- ``en.json`` contains extracted English/source strings and generated placeholders for existing localization keys.
- ``ru.json`` contains the same keys with empty values, ready for translation.
- ``_sources.json`` maps every key back to the file/property/line it came from.

Current extraction: $($sortedKeys.Count) keys, $filled with source text, $missing empty placeholders.

Runtime loading is handled by ``scripts/infrastructure/localization.gd``. It registers these JSON files as Godot ``Translation`` resources through ``TranslationServer``.

Re-run the extractor after adding or renaming content defs.
"@
    [System.IO.File]::WriteAllText((Join-Path $OutDir "README.md"), $readme, $utf8NoBom)
    Write-Host "Extracted $($sortedKeys.Count) localization keys into $(Get-RelativePath $OutDir)"
}

Read-JsonFiles
Read-SceneFiles
Read-GdScriptFiles
Write-Outputs
