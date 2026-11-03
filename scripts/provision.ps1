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

Write-Log ('=' * 72)
Write-Log 'HW TESTING LAPTOP PROVISIONER'
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User: $env:USERNAME"
Write-Log "Log: $Log"
Write-Log ('=' * 72)

if (-not (Test-Admin)) { throw 'Run from an elevated Windows PowerShell session.' }
if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) { throw 'winget is required.' }
Pass 'Administrator and winget preflight'

if ($DryRun) {
    Write-Log 'DRY RUN: would install LibreOffice, apply machine-wide Writer defaults, and verify configuration.'
    exit 0
}

$soffice = Get-Soffice
if ($soffice) {
    Pass 'LibreOffice already installed'
} else {
    Write-Log 'Installing LibreOffice with winget...'
    & winget.exe install --id TheDocumentFoundation.LibreOffice -e --source winget --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "LibreOffice installation failed with exit code $LASTEXITCODE" }
    $soffice = Get-Soffice
    if (-not $soffice) { throw 'LibreOffice install completed but soffice.exe was not found.' }
    Pass 'LibreOffice installed'
}

Get-Process soffice,soffice.bin -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

$loRoot = Split-Path (Split-Path $soffice -Parent) -Parent
$configDir = Join-Path $loRoot 'share\registry\data'
if (-not (Test-Path $configDir)) { throw "LibreOffice configuration directory not found: $configDir" }

$configPath = Join-Path $configDir 'hw-testing-laptop.xcu'
$config = @'
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema">
  <item oor:path="/org.openoffice.VCL/DefaultFonts/org.openoffice.VCL:LocalizedDefaultFonts['en']">
    <prop oor:name="LATIN_TEXT" oor:op="fuse" oor:type="xs:string">
      <value>Arial;Liberation Sans;Arimo;Nimbus Sans L;DejaVu Sans;Helvetica;SansSerif</value>
    </prop>
  </item>
  <item oor:path="/org.openoffice.Setup/Office/Factories/org.openoffice.Setup:Factory['com.sun.star.text.TextDocument']">
    <prop oor:name="ooSetupFactoryDefaultFilter" oor:op="fuse">
      <value>Office Open XML Text</value>
    </prop>
  </item>
</oor:items>
'@

Set-Content -Path $configPath -Value $config -Encoding UTF8 -Force
Pass 'Machine-wide LibreOffice Writer configuration written'

if (-not (Get-ChildItem "$env:WINDIR\Fonts" -ErrorAction SilentlyContinue | Where-Object Name -Match '^arial')) {
    Fail 'Arial font files were not detected in Windows Fonts'
} else {
    Pass 'Arial font detected'
}

[xml]$verify = Get-Content -Path $configPath -Raw
if ($verify.OuterXml -notmatch 'LATIN_TEXT' -or $verify.OuterXml -notmatch 'Arial') {
    Fail 'Arial Writer default configuration verification failed'
} else {
    Pass 'Writer default font configuration is Arial-first'
}
if ($verify.OuterXml -notmatch 'Office Open XML Text') {
    Fail 'DOCX default format configuration verification failed'
} else {
    Pass 'Writer default save format configuration is DOCX'
}

try {
    $version = & $soffice --headless --version 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) {
        Pass ("LibreOffice executable validation: " + $version.Trim())
    } else {
        Fail "LibreOffice executable returned exit code $LASTEXITCODE"
    }
} catch {
    Fail "LibreOffice executable validation failed: $($_.Exception.Message)"
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
Write-Log 'FINAL MANUAL STEPS:'
Write-Log '  [ ] Open LibreOffice Writer and confirm a new document shows Arial'
Write-Log '  [ ] Save a test document and confirm DOCX is selected by default'
Write-Log '  [ ] Reopen the saved DOCX'
Write-Log '  [ ] Disable the wireless radio in BIOS'
Write-Log '  [ ] Confirm the laptop has no wireless connectivity'
Write-Log ''
Write-Log "Full log: $Log"

if ($Failures.Count -gt 0) { exit 1 }
exit 0
