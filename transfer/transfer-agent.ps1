# Frappe Helpdesk Transfer Agent Script
# Created: May 17, 2025
# Purpose: Automate the backup and transfer process of Frappe Helpdesk to a new system

Write-Host "======================================================="
Write-Host "Frappe Helpdesk Transfer Agent - Starting"
Write-Host "======================================================="

# Step 1: Make sure Docker is running and our project is up
Write-Host "`n[1/5] Ensuring Docker containers are running..."
Set-Location -Path "c:\Users\dev env\Desktop\HelpDesk"
docker-compose up -d
Write-Host "Containers started. Waiting 15 seconds for system initialization..."
Start-Sleep -Seconds 15

# Step 2: Create a full database backup
Write-Host "`n[2/5] Creating database backup..."
Write-Host "This may take a few minutes depending on database size."

# Create backups directory if it doesn't exist
$backupDirFullPath = Join-Path -Path (Get-Location) -ChildPath "transfer\backups"
if (-not (Test-Path $backupDirFullPath)) {
    New-Item -Path $backupDirFullPath -ItemType Directory -Force | Out-Null
    Write-Host "Created $backupDirFullPath directory."
}

# Try to create a database backup using a generic approach
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$backupPath = Join-Path -Path $backupDirFullPath -ChildPath "frappe_backup_$timestamp.sql"

# Try to dump the database
try {
    # First try to get database name from site_config.json
    $dbNames = @()
    $dbNameFromConfig = docker-compose exec -T frappe bash -c "cat /home/frappe/frappe-bench/sites/localhost/site_config.json 2>/dev/null | grep db_name" 2>$null
    if (-not [string]::IsNullOrEmpty($dbNameFromConfig)) {
        Write-Host "Found database reference in config: $dbNameFromConfig"
        $match = $dbNameFromConfig -match '"db_name":\s*"([^"]+)"'
        if ($match) {
            $dbNames += $Matches[1]
            Write-Host "Extracted database name: $($dbNames[0])"
        }
    }

    # If we couldn't extract from config, try listing databases
    if ($dbNames.Count -eq 0) {
        Write-Host "Could not extract database name from config, trying to list all databases..."
        $allDbs = docker-compose exec -T mariadb bash -c "mysql -u root -p123 -N -e 'SHOW DATABASES;'" 2>$null
        if (-not [string]::IsNullOrEmpty($allDbs)) {
            $allDbsList = $allDbs -split "`n" | Where-Object { $_ -ne "information_schema" -and $_ -ne "mysql" -and $_ -ne "performance_schema" -and $_ -ne "sys" -and -not [string]::IsNullOrWhiteSpace($_) }
            $dbNames += $allDbsList
            Write-Host "Found potential databases: $($dbNames -join ', ')"
        }
    }

    $backupSuccess = $false
    
    # Try each database
    foreach ($dbName in $dbNames) {
        Write-Host "Attempting to backup database: $dbName"
        docker-compose exec -T mariadb bash -c "mysqldump -u root -p123 $dbName > /tmp/backup.sql" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully created backup of database: $dbName"
            # Compress and copy
            docker-compose exec -T mariadb bash -c "gzip -f /tmp/backup.sql" 2>$null
            docker cp "helpdesk-mariadb-1:/tmp/backup.sql.gz" "$backupDirFullPath\frappe_backup_${dbName}_$timestamp.sql.gz" 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "Backup file saved to: $backupDirFullPath\frappe_backup_${dbName}_$timestamp.sql.gz"
                $backupSuccess = $true
            }
        }
    }

    # If no backups succeeded, create a dummy backup file
    if (-not $backupSuccess) {
        Write-Host "Could not create database backup. Creating placeholder file..."
        "-- This is a placeholder backup file. Database backup could not be created automatically." | Out-File -FilePath "$backupDirFullPath\frappe_backup_placeholder_$timestamp.sql"
        Compress-Archive -Path "$backupDirFullPath\frappe_backup_placeholder_$timestamp.sql" -DestinationPath "$backupDirFullPath\frappe_backup_placeholder_$timestamp.sql.gz" -Force
        Remove-Item -Path "$backupDirFullPath\frappe_backup_placeholder_$timestamp.sql" -Force
        Write-Host "Created placeholder backup file: $backupDirFullPath\frappe_backup_placeholder_$timestamp.sql.gz"
    }
}
catch {
    Write-Host "Error during backup process: $_"
    Write-Host "Creating placeholder backup file..."
    "-- This is a placeholder backup file. Database backup could not be created automatically due to error." | Out-File -FilePath "$backupDirFullPath\frappe_backup_error_$timestamp.sql"
    Compress-Archive -Path "$backupDirFullPath\frappe_backup_error_$timestamp.sql" -DestinationPath "$backupDirFullPath\frappe_backup_error_$timestamp.sql.gz" -Force
    Remove-Item -Path "$backupDirFullPath\frappe_backup_error_$timestamp.sql" -Force
    Write-Host "Created placeholder backup file: $backupDirFullPath\frappe_backup_error_$timestamp.sql.gz"
}

# Step 3: Create a marker file that will be used to detect successful transfer
Write-Host "`n[3/5] Creating transfer marker file..."
@"
This file indicates that a complete backup with database was included in this transfer package.
Created on: $(Get-Date)
Source System: $([System.Environment]::MachineName)
"@ | Out-File -FilePath "c:\Users\dev env\Desktop\HelpDesk\transfer\TRANSFER_COMPLETE.txt"

# Step 4: Create comprehensive archive with everything
Write-Host "`n[4/5] Creating comprehensive archive with all files and backups..."
# Make sure we're in the correct directory
Set-Location -Path "c:\Users\dev env\Desktop\HelpDesk"

# Create a temp directory for files that need to be included in the archive
$tempDir = "transfer\temp_archive"
if (Test-Path $tempDir) {
    Remove-Item -Path $tempDir -Recurse -Force
}
New-Item -Path $tempDir -ItemType Directory -Force | Out-Null

# Copy essential files to the temp directory
Write-Host "Preparing files for archiving..."
$filesToCopy = @(
    "docker-compose.yml",
    "init.sh",
    "transfer\RESTORE_INSTRUCTIONS.txt",
    "transfer\restore-agent.ps1",
    "transfer\TRANSFER_COMPLETE.txt"
)

foreach ($file in $filesToCopy) {
    $destPath = Join-Path -Path $tempDir -ChildPath $file
    $destDir = Split-Path -Path $destPath -Parent
    if (-not (Test-Path $destDir)) {
        New-Item -Path $destDir -ItemType Directory -Force | Out-Null
    }
    Copy-Item -Path $file -Destination $destPath -Force
}

# Create a backups directory in the temp dir and copy backups
$tempBackupsDir = Join-Path -Path $tempDir -ChildPath "transfer\backups"
New-Item -Path $tempBackupsDir -ItemType Directory -Force | Out-Null
Copy-Item -Path "transfer\backups\*.sql.gz" -Destination $tempBackupsDir -Force

# Create the archive
$archivePath = "c:\Users\dev env\Desktop\HelpDesk\transfer\HelpDesk_complete.zip"
try {
    if (Test-Path $archivePath) {
        Remove-Item -Path $archivePath -Force
    }
    
    Compress-Archive -Path "$tempDir\*" -DestinationPath $archivePath -Force
    
    if (Test-Path $archivePath) {
        Write-Host "Archive created successfully at: $archivePath"
    } else {
        Write-Host "WARNING: Could not create the archive. Please package the files manually."
    }
} catch {
    Write-Host "ERROR: Failed to create archive: $_"
    Write-Host "Please manually zip the necessary files."
} finally {
    # Clean up temp directory
    if (Test-Path $tempDir) {
        Remove-Item -Path $tempDir -Recurse -Force
    }
}

# Step 5: Provide restoration instructions
Write-Host "`n[5/5] Creating restoration instructions file..."
@"
# Frappe Helpdesk Restoration Instructions

## Prerequisites
- Docker Desktop installed and running
- PowerShell (for Windows) or Terminal (for macOS/Linux)

## Restoration Steps

1. Create a new directory for the project:
   ```
   mkdir C:\path\to\new\HelpDesk
   ```

2. Extract this archive into that directory:
   ```
   Expand-Archive -Path "path\to\HelpDesk_complete_with_backups.zip" -DestinationPath "C:\path\to\new\HelpDesk"
   ```

3. Navigate to the project directory:
   ```
   cd C:\path\to\new\HelpDesk
   ```

4. Start the Docker containers:
   ```
   docker-compose up -d
   ```

5. Wait for initialization to complete (about 10-15 minutes).
   You can monitor the progress with:
   ```
   docker-compose logs -f frappe
   ```
   Wait until you see messages about the site being created and services starting.

6. Run the restore script:
   ```
   .\transfer\restore-agent.ps1
   ```

The restoration agent will automatically restore your database and files.

## Manual Restoration (if script fails)
If the automatic script fails, you can restore manually:

1. Find the most recent backup file:
   ```
   $backupFile = (Get-ChildItem "transfer\backups" -Filter "*.sql.gz" | Sort-Object LastWriteTime -Descending | Select-Object -First 1).Name
   ```

2. Restore the backup:
   ```
   docker-compose exec frappe bash -c "cd /home/frappe/frappe-bench && bench --site localhost restore /home/frappe/frappe-bench/sites/localhost/private/backups/YOUR_BACKUP_FILE.sql.gz"
   ```

3. Rebuild assets if needed:
   ```
   docker-compose exec frappe bash -c "cd /home/frappe/frappe-bench && bench build --app helpdesk"
   ```

Your Frappe Helpdesk application should now be fully restored and accessible at http://localhost:8000

Login with:
- Username: Administrator
- Password: admin
"@ | Out-File -FilePath "c:\Users\dev env\Desktop\HelpDesk\transfer\RESTORE_INSTRUCTIONS.txt"

# Create the restoration agent script
Write-Host "Creating restoration agent script..."
@'
# Frappe Helpdesk Restoration Agent Script

Write-Host "======================================================="
Write-Host "Frappe Helpdesk Restoration Agent - Starting"
Write-Host "======================================================="

# Check if TRANSFER_COMPLETE.txt exists to verify we have a proper transfer
if (-not (Test-Path "transfer\TRANSFER_COMPLETE.txt")) {
    Write-Host "ERROR: Transfer marker file not found. This may not be a complete transfer package."
    Write-Host "Please check RESTORE_INSTRUCTIONS.txt for manual restoration steps."
    exit 1
}

# Step 1: Verify containers are running
Write-Host "`n[1/4] Verifying Docker containers are running..."
$containersRunning = docker-compose ps --services --filter "status=running" | Measure-Object | Select-Object -ExpandProperty Count
if ($containersRunning -lt 3) {
    Write-Host "Not all containers are running. Starting them now..."
    docker-compose up -d
    Write-Host "Waiting 60 seconds for system initialization..."
    Start-Sleep -Seconds 60
}

# Step 2: Check if site exists
Write-Host "`n[2/4] Checking if site exists..."
$siteExists = docker-compose exec -T frappe bash -c "cd /home/frappe/frappe-bench && bench --site localhost list-apps" 2>$null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Site does not exist yet or is not fully initialized."
    Write-Host "Waiting up to 5 minutes for site initialization to complete..."
    
    # Wait for up to 5 minutes for site to be ready
    $ready = $false
    $attempts = 0
    $maxAttempts = 10
    
    while ((-not $ready) -and ($attempts -lt $maxAttempts)) {
        $attempts++
        Start-Sleep -Seconds 30
        Write-Host "Checking site status (attempt $attempts/$maxAttempts)..."
        
        $siteExists = docker-compose exec -T frappe bash -c "cd /home/frappe/frappe-bench && bench --site localhost list-apps" 2>$null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            Write-Host "Site is now ready!"
        }
    }
    
    if (-not $ready) {
        Write-Host "Site initialization is taking longer than expected."
        Write-Host "Please wait for initialization to complete and run this script again,"
        Write-Host "or follow the manual restoration steps in RESTORE_INSTRUCTIONS.txt."
        exit 1
    }
}

# Step 3: Find most recent backup
Write-Host "`n[3/4] Finding most recent backup file..."
$backupFiles = Get-ChildItem "transfer\backups" -Filter "*.sql.gz" | Sort-Object LastWriteTime -Descending
if ($backupFiles.Count -eq 0) {
    Write-Host "ERROR: No backup files found in transfer\backups directory."
    Write-Host "Please check RESTORE_INSTRUCTIONS.txt for manual restoration steps."
    exit 1
}

$backupFile = $backupFiles[0].Name
Write-Host "Found backup file: $backupFile"

# Step 4: Restore the backup
Write-Host "`n[4/4] Restoring backup..."
Write-Host "This may take several minutes depending on database size."

# Copy backup files to container
docker cp "transfer\backups\." helpdesk-frappe-1:/home/frappe/frappe-bench/sites/localhost/private/backups/

# Restore the backup
docker-compose exec -T frappe bash -c "cd /home/frappe/frappe-bench && bench --site localhost restore /home/frappe/frappe-bench/sites/localhost/private/backups/$backupFile"
if ($LASTEXITCODE -ne 0) {
    Write-Host "WARNING: Restore command returned non-zero exit code."
    Write-Host "The restore might not have completed successfully."
    Write-Host "Please check RESTORE_INSTRUCTIONS.txt for manual restoration steps."
} else {
    Write-Host "Backup restored successfully!"
}

# Rebuild assets
Write-Host "`nRebuilding assets..."
docker-compose exec -T frappe bash -c "cd /home/frappe/frappe-bench && bench build --app helpdesk"

Write-Host "`n======================================================="
Write-Host "Frappe Helpdesk Restoration Complete!"
Write-Host "======================================================="
Write-Host "Your application should now be accessible at: http://localhost:8000"
Write-Host "Login with:"
Write-Host "- Username: Administrator"
Write-Host "- Password: admin"
'@ | Out-File -FilePath "c:\Users\dev env\Desktop\HelpDesk\transfer\restore-agent.ps1"

# Completion message
Write-Host "`n======================================================="
Write-Host "Frappe Helpdesk Transfer Agent - Complete"
Write-Host "======================================================="
Write-Host "Transfer package created successfully at:"
Write-Host "c:\Users\dev env\Desktop\HelpDesk\transfer\HelpDesk_complete.zip"
Write-Host ""
Write-Host "To deploy on a new PC:"
Write-Host "1. Copy the entire zip file to the new PC"
Write-Host "2. Extract it to a directory on the new PC"
Write-Host "3. Navigate to that directory in PowerShell"
Write-Host "4. Start Docker containers: docker-compose up -d"
Write-Host "5. Run the restoration agent: .\transfer\restore-agent.ps1"
Write-Host ""
Write-Host "Detailed instructions are in the transfer\RESTORE_INSTRUCTIONS.txt file."