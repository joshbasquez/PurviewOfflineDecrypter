# Josh Basquez
# github.com/joshbasquez/PurviewOfflineDecrypter
# ======================
# powershell script, run manually or as a scheduled task
# Use a certificate to authenticate as an app registration
# added as a Purview Super User.

# -authenticates to purview for accessToken to decrypt 
# -scan a common share on-prem for encrypted files
# -copy them to a protected share, remove labels and encryption
# -generate log files for precheck, post report, and activityLog



cd "C:\Program Files (x86)\Microsoft Purview Information Protection\Powershell\PurviewInformationProtection"
import-module .\PurviewInformationProtection.psd1
$scanLog = "c:\Temp\ScanLog_$(get-date -f yyyyMMdd_HHmm)z_activityLog.log"
$RootPath = "S:"    # on-prem common share drive 
$targetPath = "P:"  # on-prem protected share drive (permissions  
$precheckFileName = "c:\temp\$(get-date -f yyyyMMdd_HHmm)z - share files precheck.csv"
$finalReportFilename = "C:\temp\$(get-date -f yyyyMMdd_HHmm)z - share files final report.csv"
$tenantID=""
$appID = ""

# set the Certificate store (CurrentUser or LocalMachine)
$cuStore = [System.Security.Cryptography.X509Certificates.StoreLocation]::CurrentUser


# cert based authentication to app registration
Set-AIPAuthentication -CertificateThumbprint "" `
-CertificateStoreLocation $cuStore -AppId $appID -TenantId $tenantID `
-DelegatedUser "user1@contoso.com" -SkipCertificateChainValidation

write-host "Authenticated to Purview. Script begin...`n`n"
sleep -s 3

# Get all .docx and .xlsx files recursively. Include Filter for office filetypes to scan/decrypt
write-host "Collecting all docx and xlsx files on protected share..."
$files = Get-ChildItem -Path $RootPath -Recurse -File -Include *.docx, *.xlsx -ErrorAction SilentlyContinue | select versioninfo, lastwritetime, creationtime, length
write-host "Files collected: $($files.count)" -f yellow 
write-host "Cleaning up file report for export..." -NoNewline
# Flatten the Filepath and add protectionStatus
foreach($file in $files){
$file | Add-Member -MemberType NoteProperty -Name "FilePath" -Value $file.VersionInfo.FileName
$file | Add-Member -MemberType NoteProperty -Name "ProtectionStatus" -Value "UNK"
}
$files = $files | select lastwritetime, creationtime, length, filePath, ProtectionStatus
Write-Host "COMPLETE" -ForegroundColor Yellow
write-host "Exporting files report..." -NoNewline
$files | export-csv -NoTypeInformation -Path $precheckFileName
write-host "COMPLETE" -ForegroundColor Yellow


"$(get-date -f yyyyMMdd) - PSUTap - Begin Scan Files. Files to Scan: $($files.count)" | add-content $scanLog
$i = 1
$decryptcount = 0

foreach ($file in $files) {
        # Call Get-FileStatus (assumes module/cmdlet already available)
        write-host "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] Processing File $($file.FilePath)"
        "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] Checking File $($file.FilePath)" | Add-Content $scanLog
        $status = Get-FileStatus $file.FilePath
        $file.ProtectionStatus = $status.IsRMSProtected
        # Check RMS protection
        if ($status -and $status.IsRMSProtected -eq $true) {
            write-host "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] Attempting to copy and decrypt." -f Yellow
            "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] $($file.FilePath) is protected. Copying to P: Drive" | Add-Content $scanLog
            $destinationPath = "$($file.FilePath -replace $rootPath,$targetPath)"
            # Create destination folder tree if it doesn't exist
            $destinationDir = Split-Path $destinationPath -Parent
            if (-not (Test-Path $destinationDir)) {
                "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] $destinationDir does not exist. Creating Directory Path." | Add-Content $scanLog
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }
            copy-item $file.FilePath $destinationPath
            "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] $destinationPath Created. Removing Decryption." | Add-Content $scanLog
            try {
            Remove-FileLabel -Path $destinationPath -RemoveProtection -RemoveLabel -JustificationMessage "for discovery use only" | Out-Null
            "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] $destinationPath decrypted." | Add-Content $scanLog
            $decryptcount++
            }
            catch {
            "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] ERROR decrypting $destinationPath. script continued. " | Add-Content $scanLog
            }
        } # CLOSE if protected
        else {
        write-host "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] file not encrypted. Skipped." -f Yellow
        "$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] $($file.FilePath) is not protected. Skipped." | Add-Content $scanLog
        }

        $i++
} # close foreach

write-host "File Copied and Decrypted: $decryptcount"
"$(get-date -f yyyyMMdd_HHmm)z - PSUTap [$i/$($files.count)] Total Files copied and decrypted: $decryptCount. Script complete." | Add-Content $scanLog
$files | export-csv -NoTypeInformation $finalReportFilename







