rem http://www.rsdn.ru/article/winshell/batanyca.xml
rem Переходим в текущую папку
cd %~dp0
rem Компилируем файл ресурсов
brcc32.exe -32 icons.rc
rem Создаем dll
dcc32.exe proto_VKONTAKTE.dpr -$D- -$L- -$O- -$C- -$G- -$Y-
pause

