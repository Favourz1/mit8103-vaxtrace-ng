param(
    [string]$PsqlPath = 'C:\Program Files\PostgreSQL\18\bin\psql.exe',
    [string]$DbHost = '127.0.0.1',
    [int]$DbPort = 55432,
    [string]$DbUser = 'vaxtrace',
    [string]$DbName = 'vaxtrace_clean'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PsqlPath)) { throw "psql not found: $PsqlPath" }
if ($DbName -notmatch '^vaxtrace_(dev|clean|test|verify)$') {
    throw 'Use a disposable vaxtrace_dev, vaxtrace_clean, vaxtrace_test, or vaxtrace_verify database.'
}

$repoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..')).Path
$psqlArgs = @('-X', '-v', 'ON_ERROR_STOP=1', '-h', $DbHost,
              '-p', $DbPort, '-U', $DbUser, '-d', $DbName)
$files = @(
    'portfolio-1-database-design/01_schema.sql',
    'portfolio-1-database-design/02_seed.sql',
    'portfolio-1-database-design/03_verify.sql',
    'portfolio-1-database-design/04_constraint_tests.sql',
    'portfolio-2-query-optimisation/03_indexes.sql',
    'portfolio-3-transactions-concurrency/01_transfer_functions.sql',
    'portfolio-3-transactions-concurrency/02_transaction_demo.sql',
    'portfolio-3-transactions-concurrency/03_adversarial_tests.sql'
)

foreach ($file in $files) {
    Write-Output "RUN $file"
    & $PsqlPath @psqlArgs '-f' (Join-Path $repoRoot $file) 2>&1
    if ($LASTEXITCODE -ne 0) { throw "Failed: $file" }
}

Write-Output 'RUN portfolio-3-transactions-concurrency/04_concurrency_test.py'
$env:PYTHONIOENCODING = 'utf-8'
& python (Join-Path $repoRoot 'portfolio-3-transactions-concurrency/04_concurrency_test.py') `
    --psql $PsqlPath --host $DbHost --port $DbPort --database $DbName --user $DbUser 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Concurrency test failed' }
Write-Output 'RUN portfolio-3-transactions-concurrency/05_final_integrity.sql'
& $PsqlPath @psqlArgs '-f' (Join-Path $repoRoot 'portfolio-3-transactions-concurrency/05_final_integrity.sql') 2>&1
if ($LASTEXITCODE -ne 0) { throw 'Final integrity test failed' }
Write-Output 'PASS: clean rebuild and functional verification'
