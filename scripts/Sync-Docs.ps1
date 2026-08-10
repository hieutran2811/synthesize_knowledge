[CmdletBinding()]
param(
    [string]$DocsPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs')
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$docsRoot = (Resolve-Path $DocsPath).Path

function Write-Utf8NoBom {
    param([string]$Path, [string]$Content)
    [IO.File]::WriteAllText($Path, $Content, $utf8NoBom)
}

function Get-RelativeLink {
    param([string]$FromDirectory, [string]$ToPath)
    $from = New-Object Uri(($FromDirectory.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar))
    $to = New-Object Uri($ToPath)
    return [Uri]::UnescapeDataString($from.MakeRelativeUri($to).ToString())
}

function Get-Title {
    param([string]$Content, [string]$Fallback)
    $match = [regex]::Match($Content, '(?m)^#\s+(.+?)\s*$')
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return $Fallback
}

function Get-ExistingDate {
    param([string]$Content)
    $match = [regex]::Match($Content, '(?i)Cập nhật lần cuối:\*{0,2}\s*(\d{4}-\d{2}-\d{2})')
    if ($match.Success) { return $match.Groups[1].Value }
    return 'null'
}

function Get-VersionScope {
    param([string]$Content)
    $head = (($Content -split "`r?`n") | Select-Object -First 60) -join ' '
    $match = [regex]::Match($head, '(?i)(?:Phạm vi (?:phiên bản|chính)|Mục tiêu phiên bản|Version scope)\s*:\s*(.{1,160}?)(?:\.|\||$)')
    if (-not $match.Success) { return 'unspecified' }
    $value = $match.Groups[1].Value -replace '[`*_>#]', ''
    return $value.Trim()
}

function Add-FrontMatter {
    param([IO.FileInfo]$File, [string]$Content, [string]$Topic)
    if ($Content.StartsWith("---`n") -or $Content.StartsWith("---`r`n")) {
        $body = [regex]::Replace($Content, '(?s)^---\r?\n.*?\r?\n---\r?\n', '')
        $sourceCount = ([regex]::Matches($body, 'https?://')).Count
        $updated = Get-ExistingDate $body
        $scope = (Get-VersionScope $body).Replace('\', '\\').Replace('"', '\"')
        $result = [regex]::Replace($Content, '(?m)^source_count:\s*\d+\s*$', ('source_count: {0}' -f $sourceCount))
        if ($updated -ne 'null') {
            $result = [regex]::Replace($result, '(?m)^content_updated:\s*(?:null|\d{4}-\d{2}-\d{2})\s*$', ('content_updated: {0}' -f $updated))
        }
        if ($scope -ne 'unspecified') {
            $result = [regex]::Replace($result, '(?m)^version_scope:\s*"unspecified"\s*$', ('version_scope: "{0}"' -f $scope))
        }
        return $result
    }

    $title = (Get-Title $Content $File.BaseName).Replace('\', '\\').Replace('"', '\"')
    $scope = (Get-VersionScope $Content).Replace('\', '\\').Replace('"', '\"')
    $sourceCount = ([regex]::Matches($Content, 'https?://')).Count
    $updated = Get-ExistingDate $Content
    $metadata = @(
        '---'
        ('title: "{0}"' -f $title)
        ('topic: {0}' -f $Topic)
        'level: mixed'
        'review_status: needs_review'
        ('content_updated: {0}' -f $updated)
        'last_verified: null'
        ('version_scope: "{0}"' -f $scope)
        ('source_count: {0}' -f $sourceCount)
        '---'
        ''
    ) -join "`n"
    return $metadata + $Content.TrimStart("`r", "`n")
}

function Add-GlossaryLink {
    param([IO.FileInfo]$File, [string]$Content, [string]$TopicDirectory)
    if ($File.Name -eq 'glossary.md') { return $Content }
    $firstLines = (($Content -split "`r?`n") | Select-Object -First 30) -join "`n"
    if ($firstLines -match '(?i)glossary\.md') { return $Content }

    $glossary = Join-Path $TopicDirectory 'glossary.md'
    if (-not (Test-Path -LiteralPath $glossary)) { return $Content }
    $link = Get-RelativeLink $File.DirectoryName $glossary
    $line = "> Thuật ngữ: [Glossary]($link)."
    $h1 = [regex]::Match($Content, '(?m)^#\s+.+$')
    if (-not $h1.Success) { return $Content }
    return $Content.Insert($h1.Index + $h1.Length, "`n`n$line")
}

$changed = 0
$files = Get-ChildItem $docsRoot -Recurse -File -Filter '*.md'
foreach ($file in $files) {
    $relative = $file.FullName.Substring($docsRoot.Length + 1)
    $segments = $relative -split '[\\/]'
    $topic = if ($segments.Count -gt 1) { $segments[0] } else { 'governance' }
    $topicDirectory = if ($segments.Count -gt 1) { Join-Path $docsRoot $topic } else { $null }
    $original = [IO.File]::ReadAllText($file.FullName, [Text.Encoding]::UTF8)
    $content = Add-FrontMatter $file $original $topic
    if ($topicDirectory) { $content = Add-GlossaryLink $file $content $topicDirectory }
    if ($content -ne $original) {
        Write-Utf8NoBom $file.FullName $content
        $changed++
    }
}

$startMarker = '<!-- AUTO-GENERATED-DOC-INDEX:START -->'
$endMarker = '<!-- AUTO-GENERATED-DOC-INDEX:END -->'
$topicDirectories = Get-ChildItem $docsRoot -Directory | Where-Object Name -ne 'assets'
foreach ($topicDirectory in $topicDirectories) {
    $roadmapPath = Join-Path $topicDirectory.FullName 'roadmap.md'
    if (-not (Test-Path -LiteralPath $roadmapPath)) { continue }
    $items = Get-ChildItem $topicDirectory.FullName -Recurse -File -Filter '*.md' |
        Where-Object Name -ne 'roadmap.md' |
        ForEach-Object {
            $body = [IO.File]::ReadAllText($_.FullName, [Text.Encoding]::UTF8)
            $title = Get-Title $body $_.BaseName
            $link = Get-RelativeLink $topicDirectory.FullName $_.FullName
            [PSCustomObject]@{ Title = $title; Link = $link }
        } | Sort-Object Link
    $generated = @($startMarker, '', '## Tài liệu trong chủ đề', '')
    $generated += $items | ForEach-Object { '- [{0}]({1})' -f $_.Title, $_.Link }
    $generated += @('', $endMarker)
    $block = $generated -join "`n"
    $roadmap = [IO.File]::ReadAllText($roadmapPath, [Text.Encoding]::UTF8)
    $pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?' + [regex]::Escape($endMarker)
    $updatedRoadmap = if ($roadmap -match $pattern) {
        [regex]::Replace($roadmap, $pattern, [Text.RegularExpressions.MatchEvaluator]{ param($m) $block })
    } else {
        $roadmap.TrimEnd() + "`n`n---`n`n" + $block + "`n"
    }
    if ($updatedRoadmap -ne $roadmap) {
        Write-Utf8NoBom $roadmapPath $updatedRoadmap
        $changed++
    }
}

Write-Host "Synchronized $changed files under $docsRoot"
