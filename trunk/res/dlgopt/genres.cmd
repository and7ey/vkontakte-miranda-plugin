@echo off
rem http://www.rsdn.ru/article/winshell/batanyca.xml
echo Changing directory to %~dp0
cd %~dp0
echo Compiling resources file:
brcc32.exe -32 dlgopt.rc
if %ERRORLEVEL% == 0 (
echo Moving result to project directory:
move dlgopt.res ..\..\dlgopt.res
)
echo ---------------------------------------------
pause

