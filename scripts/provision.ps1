#requires -version 5.1
[CmdletBinding()]
param([switch]$DryRun)

$ErrorActionPreference = 'Stop'
$Log = Join-Path $env:USERPROFILE ("hw_testing_laptop_{0}.log" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
$Successes = [System.Collections.Generic.List[string]]::new()
$Failures = [System.Collections.Generic.List[string]]::new()

function Write-Log([string]$Message) {
    Write-Host $Message
    Add-Content -Path $Log -Value $Message -ErrorAction SilentlyContinue
}
function Pass([string]$Message) { $Successes.Add($Message); Write-Log "PASS: $Message" }
function Fail([string]$Message) { $Failures.Add($Message); Write-Log "FAIL: $Message" }
function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = [Security.Principal.WindowsPrincipal]::new($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
function Get-Soffice {
    $paths = @((Join-Path $env:ProgramFiles 'LibreOffice\program\soffice.exe'))
    $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
    if ($programFilesX86) {
        $paths += (Join-Path $programFilesX86 'LibreOffice\program\soffice.exe')
    }
    return $paths | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Set-DesktopSavePath([string]$DesktopPath, [string]$ProfilePath) {
    if (-not $DesktopPath -or -not (Test-Path -LiteralPath $DesktopPath -PathType Container)) {
        throw "Windows Desktop folder was not found: $DesktopPath"
    }
    $desktopUrl = ([uri]($DesktopPath.TrimEnd('\') + '\')).AbsoluteUri
    $profileDir = Split-Path $ProfilePath -Parent
    if (-not (Test-Path -LiteralPath $profileDir)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }
    $registry = [System.Xml.XmlDocument]::new()
    $registry.PreserveWhitespace = $true
    $oor = 'http://openoffice.org/2001/registry'
    if (Test-Path -LiteralPath $ProfilePath) {
        $registry.Load($ProfilePath)
    } else {
        $registry.LoadXml('<oor:items xmlns:oor="http://openoffice.org/2001/registry"/>')
    }
    if ($registry.DocumentElement.LocalName -ne 'items' -or $registry.DocumentElement.NamespaceURI -ne $oor) {
        throw "Unexpected LibreOffice profile format: $ProfilePath"
    }
    $workPath = "/org.openoffice.Office.Paths/Paths/org.openoffice.Office.Paths:NamedPath['Work']"
    # Remove only the existing Work/WritePath override; retain every other preference.
    foreach ($item in @($registry.DocumentElement.ChildNodes)) {
        if ($item.LocalName -eq 'item' -and $item.GetAttribute('path', $oor) -in @($workPath, '/org.openoffice.Office.Paths/Paths/Work')) {
            foreach ($prop in @($item.ChildNodes)) {
                if ($prop.LocalName -eq 'prop' -and $prop.GetAttribute('name', $oor) -eq 'WritePath') {
                    $item.RemoveChild($prop) | Out-Null
                }
            }
            if (-not $item.SelectSingleNode('*')) {
                $registry.DocumentElement.RemoveChild($item) | Out-Null
            }
        }
    }
    $item = $registry.CreateElement('item')
    $item.SetAttribute('path', $oor, $workPath) | Out-Null
    $prop = $registry.CreateElement('prop')
    $prop.SetAttribute('name', $oor, 'WritePath') | Out-Null
    $prop.SetAttribute('op', $oor, 'fuse') | Out-Null
    $value = $registry.CreateElement('value')
    $value.InnerText = $desktopUrl
    $prop.AppendChild($value) | Out-Null
    $item.AppendChild($prop) | Out-Null
    $registry.DocumentElement.AppendChild($item) | Out-Null
    if (Test-Path -LiteralPath $ProfilePath) {
        Copy-Item -LiteralPath $ProfilePath -Destination ($ProfilePath + '.hw-testing.bak') -Force
    }
    $registry.Save($ProfilePath)
    $check = [System.Xml.XmlDocument]::new()
    $check.Load($ProfilePath)
    $ns = [System.Xml.XmlNamespaceManager]::new($check.NameTable)
    $ns.AddNamespace('oor', $oor)
    # Check the targeted Work entry rather than an unrelated path preference.
    $saved = @($check.DocumentElement.ChildNodes | Where-Object {
        $_.LocalName -eq 'item' -and $_.GetAttribute('path', $oor) -eq $workPath
    })[0].SelectSingleNode('prop[@oor:name="WritePath"]/value', $ns)
    if (-not $saved -or $saved.InnerText -ne $desktopUrl) {
        throw 'Desktop save folder profile verification failed.'
    }
    Pass "Default save folder set for $env:USERNAME : $DesktopPath"
}

Write-Log ('=' * 72)
Write-Log 'HW TESTING LAPTOP PROVISIONER'
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User: $env:USERNAME"
Write-Log "Log: $Log"
Write-Log ('=' * 72)

try {
if (-not (Test-Admin)) { throw 'Run from an elevated Windows PowerShell session.' }
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget is required.' }
Pass 'Administrator and winget preflight'

if ($DryRun) {
    Write-Log 'DRY RUN: would install LibreOffice, apply machine-wide Writer defaults, set the default save folder to Desktop, and verify configuration.'
    exit 0
}

$soffice = Get-Soffice
if ($soffice) {
    Pass 'LibreOffice already installed'
} else {
    Write-Log 'Installing LibreOffice with winget...'
    & winget.exe install --id TheDocumentFoundation.LibreOffice -e --source winget --scope machine --silent --disable-interactivity --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "LibreOffice installation failed with exit code $LASTEXITCODE" }
    $soffice = Get-Soffice
    if (-not $soffice) { throw 'LibreOffice install completed but soffice.exe was not found.' }
    Pass 'LibreOffice installed'
}

if (Get-Process soffice,soffice.bin -ErrorAction SilentlyContinue) {
    throw 'Close LibreOffice (including Quickstarter), saving any work, then rerun provisioning.'
}

$loRoot = Split-Path (Split-Path $soffice -Parent) -Parent
$configDir = Join-Path $loRoot 'share\registry'
if (-not (Test-Path $configDir)) { throw "LibreOffice configuration directory not found: $configDir" }

$configPath = Join-Path $configDir 'hw-testing-laptop.xcd'
$config = @'
<?xml version="1.0" encoding="UTF-8"?>
<oor:data xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <dependency file="main"/>
  <dependency file="writer"/>
  <oor:component-data oor:name="Writer" oor:package="org.openoffice.Office">
    <node oor:name="DefaultFont">
      <prop oor:name="Standard" oor:op="fuse">
        <value>Arial</value>
      </prop>
    </node>
  </oor:component-data>
  <oor:component-data oor:name="Setup" oor:package="org.openoffice">
    <node oor:name="Office">
      <node oor:name="Factories">
        <node oor:name="com.sun.star.text.TextDocument" oor:op="fuse">
          <prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse">
            <value>Office Open XML Text</value>
          </prop>
        </node>
      </node>
    </node>
  </oor:component-data>
  <oor:component-data oor:name="Paths" oor:package="org.openoffice.Office">
    <node oor:name="Paths">
      <node oor:name="Work" oor:op="fuse">
        <prop oor:name="WritePath" oor:op="fuse">
          <!-- On stock Windows, $(home) is the current user's Documents folder. -->
          <value>$(home)/../Desktop</value>
        </prop>
      </node>
    </node>
  </oor:component-data>
</oor:data>
'@

Set-Content -Path $configPath -Value $config -Encoding UTF8 -Force
Pass 'Machine-wide LibreOffice Writer configuration written'

if (-not (Get-ChildItem "$env:WINDIR\Fonts" -ErrorAction SilentlyContinue | Where-Object Name -IEQ 'arial.ttf')) {
    Fail 'Arial font files were not detected in Windows Fonts'
} else {
    Pass 'Arial font detected'
}

[xml]$verify = Get-Content -Path $configPath -Raw
$ns = [System.Xml.XmlNamespaceManager]::new($verify.NameTable)
$ns.AddNamespace('oor', 'http://openoffice.org/2001/registry')
$font = $verify.SelectSingleNode('/oor:data/oor:component-data[@oor:name="Writer"]/node[@oor:name="DefaultFont"]/prop[@oor:name="Standard"]/value', $ns)
$filter = $verify.SelectSingleNode('/oor:data/oor:component-data[@oor:name="Setup"]/node[@oor:name="Office"]/node[@oor:name="Factories"]/node[@oor:name="com.sun.star.text.TextDocument"]/prop[@oor:name="ooSetupFactoryDefaultFilter"]/value', $ns)
if ($font -and $font.InnerText -eq 'Arial') {
    Pass 'Writer default font configuration is Arial'
} else {
    Fail 'Arial Writer default configuration verification failed'
}
if ($filter -and $filter.InnerText -eq 'Office Open XML Text') {
    Pass 'Writer default save format configuration is DOCX'
} else {
    Fail 'DOCX default format configuration verification failed'
}

$savePath = $verify.SelectSingleNode('/oor:data/oor:component-data[@oor:name="Paths"]/node[@oor:name="Paths"]/node[@oor:name="Work"]/prop[@oor:name="WritePath"]/value', $ns)
if ($savePath -and $savePath.InnerText -eq '$(home)/../Desktop') {
    Pass 'Machine-wide Desktop fallback configuration written'
} else {
    Fail 'Desktop default save folder configuration verification failed'
}

# Use Windows' actual Desktop location, including folder redirection.
# Run under the local account that will be used for testing.
$desktop = [Environment]::GetFolderPath([Environment+SpecialFolder]::DesktopDirectory)
$userConfig = Join-Path $env:APPDATA 'LibreOffice\4\user\registrymodifications.xcu'
Set-DesktopSavePath -DesktopPath $desktop -ProfilePath $userConfig

try {
    $console = Join-Path (Split-Path $soffice -Parent) 'soffice.com'
    if (-not (Test-Path $console)) { throw "LibreOffice console executable not found: $console" }
    $version = & $console --headless --version 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0 -and $version -match 'LibreOffice') {
        Pass ("LibreOffice executable validation: " + $version.Trim())
    } else {
        Fail "LibreOffice executable validation failed (exit code $LASTEXITCODE): $version"
    }
} catch {
    Fail "LibreOffice executable validation failed: $($_.Exception.Message)"
}

} catch {
    Fail $_.Exception.Message
}

Write-Log ''
Write-Log ('=' * 72)
Write-Log 'FINAL SUMMARY'
Write-Log ('=' * 72)
Write-Log "Passed checks: $($Successes.Count)"
Write-Log "Failed checks: $($Failures.Count)"
foreach ($item in $Successes) { Write-Log "  PASS - $item" }
foreach ($item in $Failures) { Write-Log "  FAIL - $item" }
Write-Log ''
if ($Failures.Count -gt 0) {
    Write-Log 'Provisioning FAILED. Resolve the failures and rerun before handoff.'
}
Write-Log 'FINAL MANUAL STEPS (only after all checks pass):'
Write-Log '  [ ] Open LibreOffice Writer and confirm a new document shows Arial'
Write-Log '  [ ] Save a test document and confirm DOCX and the Desktop folder are selected by default'
Write-Log '  [ ] Reopen the saved DOCX'
Write-Log '  [ ] Disable the wireless radio in BIOS'
Write-Log '  [ ] Confirm the laptop has no wireless connectivity'
Write-Log ''
Write-Log "Full log: $Log"

if ($Failures.Count -gt 0) { exit 1 }
exit 0
