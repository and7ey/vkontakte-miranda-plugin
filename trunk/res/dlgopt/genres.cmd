@echo off
rem http://www.rsdn.ru/article/winshell/batanyca.xml
echo ���室�� � ⥪���� ����� %~dp0
cd %~dp0
echo ��������㥬 䠩� ����ᮢ:
brcc32.exe -32 dlgopt.rc
if %ERRORLEVEL% == 0 (
echo ��६�頥� १���� � ����� � �஥�⮬:
move dlgopt.res ..\..\dlgopt.res
)
echo ---------------------------------------------
pause

