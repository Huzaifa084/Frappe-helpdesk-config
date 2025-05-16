# Frappe Helpdesk Transfer Process Guide

## Source PC (Current Installation)

1. **Create Transfer Package**:
   ```powershell
   # Navigate to your HelpDesk directory
   cd "c:\Users\dev env\Desktop\HelpDesk"
   
   # Run the transfer agent script
   powershell -ExecutionPolicy Bypass -File ".\transfer\transfer-agent.ps1"
   ```

2. **Copy Transfer Package**:
   After the script completes, copy the `transfer\HelpDesk_complete.zip` file to a USB drive, network share, or cloud storage.

## Target PC (New Installation)

1. **Prerequisites**:
   - Make sure Docker Desktop is installed and running
   - Make sure PowerShell is available

2. **Create Directory**:
   ```powershell
   # Create a directory for your Helpdesk application
   mkdir C:\HelpDesk
   ```

3. **Copy and Extract**:
   ```powershell
   # Copy the HelpDesk_complete.zip file to the new directory
   # Then extract it
   cd C:\HelpDesk
   Expand-Archive -Path "HelpDesk_complete.zip" -DestinationPath "."
   ```

4. **Fix Line Endings** (Critical for Linux containers):
   ```powershell
   # Fix line endings in shell scripts to prevent Docker errors
   $content = Get-Content -Path ".\init.sh" -Raw
   $content = $content -replace "`r`n", "`n"
   [System.IO.File]::WriteAllText(".\init.sh", $content)
   ```

5. **Start Docker Containers**:
   ```powershell
   # Start Docker containers
   docker-compose up -d
   ```

5. **Wait for Initialization**:
   ```powershell
   # Monitor the initialization process (press Ctrl+C when complete)
   docker-compose logs -f frappe
   ```

6. **Run Restoration**:
   ```powershell
   # Execute the restoration script
   .\transfer\restore-agent.ps1
   ```

7. **Verify Installation**:
   - Open a browser and navigate to: http://localhost:8000
   - Login with:
     - Username: Administrator
     - Password: admin

## Troubleshooting

If you encounter any issues:

- Check Docker container status:
  ```powershell
  docker-compose ps
  ```

- View container logs:
  ```powershell
  docker-compose logs frappe
  docker-compose logs mariadb
  ```

- Follow manual restoration steps in `transfer\RESTORE_INSTRUCTIONS.txt` if the automatic process fails

- Ensure ports 8000-8005 are not in use by other applications

## Note

The transfer package contains:
- Docker configuration files
- Database backup
- All necessary application files
- Restoration scripts and instructions

No manual configuration is required if using the automated restoration process.
