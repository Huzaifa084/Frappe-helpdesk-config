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
if ($LASTEXITCODE -ne 0) {
    Write-Host "Asset rebuild failed. Trying alternative approach..."
} else {
    Write-Host "Initial assets rebuilt successfully!"
}

# Perform a complete asset rebuild with force option
Write-Host "`nPerforming complete asset rebuild..."
docker-compose exec -T frappe bash -c "cd /home/frappe/frappe-bench && bench build --force"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Complete asset rebuild failed. You may need to run this manually."
    Write-Host "Command: docker-compose exec frappe bash -c 'cd /home/frappe/frappe-bench && bench build --force'"
} else {
    Write-Host "Complete asset rebuild successful!"
}

# Clear cache to ensure new assets are used
Write-Host "`nClearing cache..."
docker-compose exec -T frappe bash -c "cd /home/frappe/frappe-bench && bench --site localhost clear-cache"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Cache clear failed. You may need to run this manually."
} else {
    Write-Host "Cache cleared successfully!"
}

Write-Host "`n======================================================="
Write-Host "Frappe Helpdesk Restoration Complete!"
Write-Host "======================================================="
Write-Host "Your application should now be accessible at: http://localhost:8000"
Write-Host "Login with:"
Write-Host "- Username: Administrator"
Write-Host "- Password: admin"
