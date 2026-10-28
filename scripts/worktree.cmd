@echo off
setlocal EnableDelayedExpansion

rem Worktree helper for this repo. See docs/agents/worktrees.md.
rem
rem   scripts\worktree.cmd new <branch>
rem   scripts\worktree.cmd list
rem   scripts\worktree.cmd rm <path^|branch-dashed> [-Force]

set "COMMAND=%~1"
set "TARGET=%~2"
set "FORCE="
if /I "%~3"=="-Force" set "FORCE=1"
if /I "%~3"=="--force" set "FORCE=1"

call :resolve_root
if errorlevel 1 (
  echo Not inside a git repository.
  exit /b 1
)
set "WORKTREEROOT=%REPOROOT%\.worktrees"

if "%COMMAND%"=="" goto :usage
if /I "%COMMAND%"=="new" goto :cmd_new
if /I "%COMMAND%"=="list" goto :cmd_list
if /I "%COMMAND%"=="rm" goto :cmd_rm
goto :usage

:cmd_new
if "%TARGET%"=="" goto :usage
git check-ref-format --branch "%TARGET%" >nul 2>&1
if errorlevel 1 (
  echo '%TARGET%' is not a valid branch name.
  exit /b 1
)

set "WTPATH=%WORKTREEROOT%\%TARGET:/=-%"
if exist "%WTPATH%" (
  echo A worktree already exists at %WTPATH%
  exit /b 1
)
git show-ref --verify --quiet "refs/heads/%TARGET%"
if not errorlevel 1 (
  echo Branch '%TARGET%' already exists. A branch gets one worktree, never a second.
  exit /b 1
)

set "BASE=main"
git fetch --quiet origin main >nul 2>&1
if not errorlevel 1 set "BASE=origin/main"
if "%BASE%"=="main" echo Warning: could not fetch origin; branching from local main.

if not exist "%WORKTREEROOT%" mkdir "%WORKTREEROOT%" >nul 2>&1
git -C "%REPOROOT%" worktree add --no-track "%WTPATH%" -b "%TARGET%" %BASE%
if errorlevel 1 (
  echo git worktree add failed for %WTPATH%
  exit /b 1
)

echo.
echo Worktree: %WTPATH%
echo Branch:   %TARGET% (from %BASE%)
echo Next:     cd /d "%WTPATH%"
exit /b 0

:cmd_list
echo Worktree root: %WORKTREEROOT%
echo.
git -C "%REPOROOT%" worktree list
exit /b 0

:cmd_rm
if "%TARGET%"=="" goto :usage
if not exist "%WORKTREEROOT%" (
  echo No .worktrees folder at %WORKTREEROOT%
  exit /b 1
)

set "WTPATH=%TARGET%"
if not exist "%WTPATH%" set "WTPATH=%WORKTREEROOT%\%TARGET:/=-%"
if not exist "%WTPATH%" (
  echo No worktree at %WTPATH%
  exit /b 1
)
for %%i in ("%WTPATH%") do set "RESOLVED=%%~fi"

set "CHECK=!RESOLVED:%WORKTREEROOT%\=!"
if /I "!CHECK!"=="!RESOLVED!" (
  echo Refusing to remove "%RESOLVED%": it is outside %WORKTREEROOT%.
  exit /b 1
)
if /I "%CD%"=="!RESOLVED!" (
  echo You are inside this worktree. Run the command from the primary checkout.
  exit /b 1
)
set "INCHECK=!CD:%RESOLVED%\=!"
if /I not "!INCHECK!"=="%CD%" (
  echo You are inside this worktree. Run the command from the primary checkout.
  exit /b 1
)

set "DIRTY="
for /f "usebackq delims=" %%i in (`git -C "!RESOLVED!" status --porcelain`) do set "DIRTY=1"
if defined DIRTY if not defined FORCE (
  echo Worktree has uncommitted or untracked changes. Commit them, or rerun with -Force to discard.
  exit /b 1
)

set "BRANCH="
for /f "usebackq delims=" %%i in (`git -C "!RESOLVED!" rev-parse --abbrev-ref HEAD`) do set "BRANCH=%%i"

if defined FORCE (
  git -C "%REPOROOT%" worktree remove --force "!RESOLVED!"
) else (
  git -C "%REPOROOT%" worktree remove "!RESOLVED!"
)
if errorlevel 1 (
  echo git worktree remove failed for !RESOLVED!
  exit /b 1
)
git -C "%REPOROOT%" worktree prune
if errorlevel 1 (
  echo git worktree prune failed
  exit /b 1
)

echo Removed: !RESOLVED!
if defined BRANCH if /I not "!BRANCH!"=="HEAD" echo Branch '!BRANCH!' still exists. Delete it with: git branch -D !BRANCH!
exit /b 0

:resolve_root
set "REPOROOT="
for /f "usebackq tokens=1,* delims= " %%a in (`git worktree list --porcelain 2^>nul`) do (
  if /I "%%a"=="worktree" if not defined REPOROOT for %%p in ("%%b") do set "REPOROOT=%%~fp"
)
if not defined REPOROOT exit /b 1
exit /b 0

:usage
echo Usage:
echo   scripts\worktree.cmd new ^<branch^>
echo   scripts\worktree.cmd list
echo   scripts\worktree.cmd rm ^<path^|branch-dashed^> [-Force]
exit /b 1
