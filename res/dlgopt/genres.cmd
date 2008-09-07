rem http://www.rsdn.ru/article/winshell/batanyca.xml
rem Переходим в текущую папку
cd %~dp0
rem Компилируем файл ресурсов
brcc32.exe -32 dlgopt.rc
rem Перемещаем результат в папку с проектом
move dlgopt.RES ..\..\dlgopt.RES
pause

