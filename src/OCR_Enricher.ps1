param(
    [string]$Directory = "D:\eb",  
    [switch]$KeepBackups = $true,    
    [ValidateSet("Basic", "Detailed", "Off")]
    [string]$LogLevel = "Basic"      
    $PythonExePath = "python" # For customizability )

# Requires installation of ocrmypdf: https://ocrmypdf.readthedocs.io/en/latest/installation.html
# Requires a Python environment with PyPDF2 and ocrmypdf, and the pdf_utils module accessible

# ----- Configuration -----
$ErrorLogFile = "$Directory\error_log.txt"
$ResultLogFile = "$Directory\result_log.txt"

# ----- Functions -----
# (Existing functions: Test-For-SearchableText, Test-IsValidPDF - unchanged)

function Perform-OCR {
    param([string]$inputFilePath, [string]$outputFilePath)

    try {
        # Use subprocess for flexibility
        $result = & $PythonExePath C:\path\to\your\pdf_utils.py perform_ocr $inputFilePath $outputFilePath 
        if ($result -eq "Success") {
            return $true
        } else {
            return $false
        }
    } catch {
        # Log the error
        Add-Content -Path $ErrorLogFile -Value "Error performing OCR on: $inputFilePath - $($_.Exception.Message)"
        return $false
    }
}

# ----- Main Script Logic -----

# Ensure log files exist
New-Item -Path $ErrorLogFile, $ResultLogFile -ItemType File -Force -ErrorAction SilentlyContinue

# Get all PDF files recursively
$pdfFiles = Get-ChildItem -Path $Directory -Recurse -Filter "*.pdf"

# Process PDFs in parallel for performance
$pdfFiles | ForEach-Object -Parallel {
    $file = $_  # Capture in closure

    Write-Output "Processing file: $($file.FullName)"

    if (-not (Test-For-SearchableText -filePath $file.FullName)) {
        $tempOutputFile = [System.IO.Path]::Combine($file.DirectoryName, [System.IO.Path]::GetRandomFileName() + ".pdf")

        if (Perform-OCR -inputFilePath $file.FullName -outputFilePath $tempOutputFile) {
            try {
                # Backup original file (optional)
                if ($KeepBackups) {
                    Copy-Item $file.FullName ($file.FullName + ".bak") -ErrorAction SilentlyContinue 
                }

                # Validate using Python function
                if (pdf_utils.validate_pdf $tempOutputFile) { 
                    Remove-Item $file.FullName -ErrorAction SilentlyContinue
                    Move-Item $tempOutputFile $file.FullName -ErrorAction SilentlyContinue

                    # Remove backup if keep backups is disabled
                    if (-not $KeepBackups) {
                        Remove-Item ($file.FullName + ".bak") -ErrorAction SilentlyContinue
                    }
                } else {
                    Add-Content -Path $ErrorLogFile -Value "Error: Invalid PDF output for: $($file.FullName)"
                }
                
                # Update the last modified time 
                $originalModifiedTime = $file.LastWriteTime
                (Get-Item $file.FullName).LastWriteTime = $originalModifiedTime 

                if ($LogLevel -eq "Detailed") {
                    Add-Content -Path $ResultLogFile -Value "OCR successful and validated: $($file.FullName)"
                } else {
                    Add-Content -Path $ResultLogFile -Value "Made searchable: $($file.FullName)"
                }
            } catch {
                Add-Content -Path $ErrorLogFile -Value "Error during file replacement: $($file.FullName) - $($_.Exception.Message)"
            }
        } else { 
            # OCR Processing failed. Log more details if desired
            if ($LogLevel -eq "Detailed") {
                Add-Content -Path $ErrorLogFile -Value "OCR failed for: $($file.FullName)" 
            }
            Remove-Item $tempOutputFile -ErrorAction SilentlyContinue
        } 
    } else {
        Write-Output "File already searchable: $($file.FullName)"
    }

    # Progress Reporting (example based on file count)
    if ($pdfFiles.IndexOf($file) % 50 -eq 0) {
        Write-Progress -Activity "Processing PDF Files" -Status "Processed $($pdfFiles.IndexOf($file)) out of $($pdfFiles.Count)"
    } 
} -ThrottleLimit 5 

Write-Output "Processing complete. Check log files." 
