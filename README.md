# HW Testing Laptop Provisioner

Single-purpose Windows 11 provisioning for standalone Harvard-Westlake testing laptops.

## Target state

- Stock Windows 11 26H2
- LibreOffice installed
- LibreOffice Writer default Western font: Arial
- Writer default save format: Microsoft Word 2007-365 (.docx)
- Provisioning is performed while the laptop is online
- Wireless radio is disabled manually in BIOS only after validation

## Run

Open **Windows PowerShell as Administrator**, then run:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\scripts\provision.ps1
```

Use `-DryRun` to inspect the plan without making changes.

## Important scope

LibreOffice preferences are applied to the Windows account that runs the provisioner. Run provisioning from the same local account that will be used for testing.

The BIOS wireless-radio step is intentionally manual and is not automated by this repository.
