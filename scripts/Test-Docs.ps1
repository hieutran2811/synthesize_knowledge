[CmdletBinding()]
param(
    [switch]$Strict,
    [int]$MaxWarningOutput = 50,
    [string]$DocsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs')
)

$ErrorActionPreference = 'Stop'
$docsRoot = (Resolve-Path $DocsPath).Path
$errors = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]
$requiredMetadata = @('title', 'topic', 'level', 'review_status', 'content_updated', 'last_verified', 'version_scope', 'source_count')
$versionPattern = '(?i)\b(version|phiên bản|release|LTS|EOL|deprecated|Java\s+(8|11|17|21|25)|Spring Boot\s+[234]|Kubernetes\s+1\.|PostgreSQL\s+1[4-9]|SQL Server\s+20|Angular\s+[0-9])\b'

function Add-Error([string]$Message) { $errors.Add($Message) }
function Add-Warning([string]$Message) { $warnings.Add($Message) }

function Get-CodeAwareLines {
    param([string[]]$Lines)
    $insideFence = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^\s*```') {
            $insideFence = -not $insideFence
            continue
        }
        if (-not $insideFence) {
            [PSCustomObject]@{ Number = $i + 1; Text = $Lines[$i] }
        }
    }
}

$topicDirectories = Get-ChildItem $docsRoot -Directory | Where-Object Name -ne 'assets'
foreach ($topic in $topicDirectories) {
    foreach ($required in @('roadmap.md', 'glossary.md')) {
        if (-not (Test-Path -LiteralPath (Join-Path $topic.FullName $required))) {
            Add-Error "$($topic.Name): missing $required"
        }
    }
}

$files = Get-ChildItem $docsRoot -Recurse -File -Filter '*.md'
$largeFiles = 0
$needsReview = 0
$versionSensitiveWithoutSources = 0
$internalLinks = 0

foreach ($file in $files) {
    $relative = $file.FullName.Substring($docsRoot.Length + 1).Replace('\', '/')
    $content = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $lines = $content -split "`r?`n"
    if ($lines.Count -gt 1000) { $largeFiles++; Add-Warning "${relative}: $($lines.Count) lines; review for splitting" }

    if ($lines.Count -lt 3 -or $lines[0] -ne '---') {
        Add-Error "${relative}: missing YAML front matter"
        continue
    }
    $frontMatterEnd = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '---') { $frontMatterEnd = $i; break }
    }
    if ($frontMatterEnd -lt 0) { Add-Error "${relative}: unclosed YAML front matter"; continue }
    $frontMatter = ($lines[1..($frontMatterEnd - 1)] -join "`n")
    foreach ($key in $requiredMetadata) {
        if ($frontMatter -notmatch "(?m)^$([regex]::Escape($key)):\s*") { Add-Error "${relative}: missing metadata '$key'" }
    }
    if ($frontMatter -match '(?m)^review_status:\s*needs_review\s*$') { $needsReview++ }
    $sourceMatch = [regex]::Match($frontMatter, '(?m)^source_count:\s*(\d+)\s*$')
    $sourceCount = if ($sourceMatch.Success) { [int]$sourceMatch.Groups[1].Value } else { 0 }
    $segments = $relative -split '/'
    $isKnowledgeDocument = $segments.Count -gt 1 -and $file.Name -notin @('roadmap.md', 'glossary.md')
    if ($isKnowledgeDocument -and $content -match $versionPattern -and $sourceCount -eq 0) {
        $versionSensitiveWithoutSources++
        Add-Warning "${relative}: version-sensitive content without an external source"
    }

    $codeAware = @(Get-CodeAwareLines $lines)
    $h1Count = @($codeAware | Where-Object Text -match '^#\s+').Count
    if ($h1Count -ne 1) { Add-Error "${relative}: expected exactly one H1 outside code fences, found $h1Count" }
    $fenceCount = @($lines | Where-Object { $_ -match '^\s*```' }).Count
    if ($fenceCount % 2 -ne 0) { Add-Error "${relative}: unbalanced fenced code blocks" }

    if ($segments.Count -gt 1 -and $file.Name -ne 'glossary.md') {
        $head = ($lines | Select-Object -First 35) -join "`n"
        if ($head -notmatch '(?i)glossary\.md') { Add-Error "${relative}: missing glossary link near the top" }
    }

    foreach ($entry in $codeAware) {
        foreach ($match in [regex]::Matches($entry.Text, '!?(?:\[[^\]]*\])\((?<target>[^\s\)]+)')) {
            $target = $match.Groups['target'].Value.Trim('<', '>')
            if ($target -match '^(https?://|mailto:|tel:|#)') { continue }
            $internalLinks++
            $pathPart = ($target -split '#', 2)[0]
            if ([string]::IsNullOrWhiteSpace($pathPart)) { continue }
            try { $pathPart = [Uri]::UnescapeDataString($pathPart) } catch { }
            try {
                $resolved = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $pathPart))
                if (-not $resolved.StartsWith($docsRoot, [StringComparison]::OrdinalIgnoreCase)) {
                    Add-Error "${relative}:$($entry.Number): link escapes docs root: $target"
                } elseif (-not (Test-Path -LiteralPath $resolved)) {
                    Add-Error "${relative}:$($entry.Number): missing link target: $target"
                }
            } catch {
                Add-Error "${relative}:$($entry.Number): invalid link target: $target"
            }
        }
    }
}

foreach ($topic in $topicDirectories) {
    $roadmap = Join-Path $topic.FullName 'roadmap.md'
    if ((Test-Path -LiteralPath $roadmap) -and ([IO.File]::ReadAllText($roadmap) -notmatch 'AUTO-GENERATED-DOC-INDEX:START')) {
        Add-Error "$($topic.Name)/roadmap.md: missing generated clickable document index"
    }
}

Write-Host "Docs: $($files.Count); topics: $($topicDirectories.Count); internal links: $internalLinks"
Write-Host "Needs review: $needsReview; files over 1000 lines: $largeFiles; version-sensitive without sources: $versionSensitiveWithoutSources"
foreach ($warning in ($warnings | Select-Object -First $MaxWarningOutput)) { Write-Warning $warning }
if ($warnings.Count -gt $MaxWarningOutput) {
    Write-Warning "Suppressed $($warnings.Count - $MaxWarningOutput) additional warning(s); use the backlog and targeted scans for details."
}
foreach ($error in $errors) { Write-Error $error -ErrorAction Continue }

if ($errors.Count -gt 0) {
    Write-Host "Validation failed with $($errors.Count) error(s) and $($warnings.Count) warning(s)."
    exit 1
}

Write-Host "Validation passed with $($warnings.Count) warning(s)."
