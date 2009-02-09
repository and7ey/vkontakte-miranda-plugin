@echo off
rem http://www.rsdn.ru/article/winshell/batanyca.xml
echo Переходим в текущую папку %~dp0
cd %~dp0
echo Компилируем файл ресурсов:
brcc32.exe -32 dlgopt.rc
if %ERRORLEVEL% == 0 (
echo Перемещаем результат в папку с проектом:
move dlgopt.res ..\..\dlgopt.res
)
echo ---------------------------------------------
pause

