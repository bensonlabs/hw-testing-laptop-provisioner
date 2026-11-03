# HW Testing Laptop Provisioner

Single-purpose Windows 11 provisioning for standalone Harvard-Westlake testing laptops.

## Target state

- Stock Windows 11 26H2
- LibreOffice installed
- LibreOffice Writer default Western font: Arial
- Writer default save format: Microsoft Word 2007-365 (.docx)
- Default save folder: the current user's Desktop
- Provisioning is performed while the laptop is online
- Wireless radio is disabled manually in BIOS only after validation

## Run

Open **Windows PowerShell as Administrator**, then run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force; irm https://raw.githubusercontent.com/bensonlabs/hw-testing-laptop-provisioner/main/scripts/provision.ps1 -OutFile $env:TEMP\hw-testing-laptop-provision.ps1 -ErrorAction Stop; & $env:TEMP\hw-testing-laptop-provision.ps1
```

Use `-DryRun` to inspect the plan without making changes.

## Important scope

LibreOffice defaults are applied machine-wide using `share\registry\hw-testing-laptop.xcd`. Existing per-user preferences or document templates may override these defaults, so perform the manual checks from the actual testing account. Existing user profiles are preserved.

Requires winget. Close LibreOffice before running or rerunning the script. An existing installation is reused without upgrading. The script checks the configuration payload and LibreOffice console startup; confirm the actual Writer font and save behavior manually before handoff.

After all automated checks pass, open Writer in the testing account, confirm Arial in a new document, save with DOCX and the Desktop folder selected by default, and reopen that file. Then disable wireless in BIOS and confirm there is no network connection, including Ethernet or a dock.

The BIOS wireless-radio step is intentionally manual and is not automated by this repository.

The save folder setting is shared by LibreOffice applications, including Writer. It uses `$(home)/../Desktop`, which resolves from each user's Documents folder to their Desktop on the stock Windows profiles targeted here. If Documents has been redirected (for example by OneDrive), verify the save location manually before handoff.
