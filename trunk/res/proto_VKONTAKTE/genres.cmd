rem http://www.rsdn.ru/article/winshell/batanyca.xml
rem ���室�� � ⥪���� �����
cd %~dp0
rem ��������㥬 䠩� ����ᮢ
brcc32.exe -32 icons.rc
rem ������� dll
dcc32.exe proto_VKONTAKTE.dpr -$D- -$L- -$O- -$C- -$G- -$Y-
pause

