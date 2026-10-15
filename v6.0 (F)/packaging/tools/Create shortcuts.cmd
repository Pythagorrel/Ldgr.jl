@echo off
REM Creates the LDGR shortcuts on the Desktop and in the Start Menu for the current user.
start "" /wait "%~dp0..\LDGR.exe" --install
