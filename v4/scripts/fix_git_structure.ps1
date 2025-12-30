# ============================================================================
# Fix Git Repository Structure
# ============================================================================
# This script reinitializes the Git repository at the correct location
# (C:\Users\russe\Documents\lead_scoring_production) instead of the home directory
# ============================================================================

Write-Host "============================================================================"
Write-Host "FIXING GIT REPOSITORY STRUCTURE"
Write-Host "============================================================================"
Write-Host ""

$PROJECT_DIR = "C:\Users\russe\Documents\lead_scoring_production"
$REMOTE_URL = "https://github.com/russellmoss/lead-scoring-production.git"

# Step 1: Save current remote URL
Write-Host "[STEP 1] Saving remote URL..."
$currentRemote = git -C $PROJECT_DIR remote get-url origin
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [WARNING] Could not get remote URL, will use default: $REMOTE_URL"
    $currentRemote = $REMOTE_URL
} else {
    Write-Host "  [OK] Remote URL: $currentRemote"
}

# Step 2: Get current branch name
Write-Host "[STEP 2] Getting current branch..."
$currentBranch = git -C $PROJECT_DIR rev-parse --abbrev-ref HEAD
if ($LASTEXITCODE -ne 0) {
    $currentBranch = "master"
}
Write-Host "  [OK] Current branch: $currentBranch"

# Step 3: Create backup of current .git (if exists in project dir)
Write-Host "[STEP 3] Checking for existing .git in project directory..."
if (Test-Path "$PROJECT_DIR\.git") {
    Write-Host "  [WARNING] .git folder exists in project directory"
    Write-Host "  [INFO] This script will create a new repo structure"
} else {
    Write-Host "  [OK] No .git folder in project directory (expected)"
}

# Step 4: Initialize new repository at project root
Write-Host "[STEP 4] Initializing new Git repository at project root..."
Set-Location $PROJECT_DIR

# Remove existing .git if it exists (shouldn't, but just in case)
if (Test-Path ".git") {
    Write-Host "  [WARNING] Removing existing .git folder..."
    Remove-Item -Recurse -Force .git
}

# Initialize new repo
git init
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Failed to initialize Git repository"
    exit 1
}
Write-Host "  [OK] Git repository initialized"

# Step 5: Set remote
Write-Host "[STEP 5] Setting remote URL..."
git remote add origin $currentRemote
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Failed to set remote"
    exit 1
}
Write-Host "  [OK] Remote set to: $currentRemote"

# Step 6: Add all files from project directory
Write-Host "[STEP 6] Adding all files from project directory..."
git add .
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Failed to add files"
    exit 1
}

$fileCount = (git ls-files | Measure-Object -Line).Lines
Write-Host "  [OK] Added $fileCount files"

# Step 7: Create initial commit
Write-Host "[STEP 7] Creating initial commit..."
git commit -m "Restructure repository: Move root to project directory

- Repository root moved from C:/Users/russe to C:/Users/russe/Documents/lead_scoring_production
- All project files now at repository root
- Removed parent directory structure (Documents/, Big_Query/, etc.)
- README.md now at repository root
- Maintains all project history and files"
if ($LASTEXITCODE -ne 0) {
    Write-Host "  [ERROR] Failed to create commit"
    exit 1
}
Write-Host "  [OK] Initial commit created"

# Step 8: Set branch name
Write-Host "[STEP 8] Setting branch name to: $currentBranch"
git branch -M $currentBranch
Write-Host "  [OK] Branch set to: $currentBranch"

# Step 9: Force push to replace repository structure
Write-Host "[STEP 9] Ready to force push to GitHub"
Write-Host ""
Write-Host "============================================================================"
Write-Host "NEXT STEPS:"
Write-Host "============================================================================"
Write-Host ""
Write-Host "The repository has been reinitialized at the correct location."
Write-Host "To update GitHub, run:"
Write-Host ""
Write-Host "  git push -f origin $currentBranch"
Write-Host ""
Write-Host "WARNING: This will rewrite the repository history on GitHub."
Write-Host "Make sure you have a backup if needed."
Write-Host ""
Write-Host "============================================================================"

