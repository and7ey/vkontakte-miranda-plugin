rem http://www.rsdn.ru/article/winshell/batanyca.xml
rem ���室�� � ⥪���� �����
cd %~dp0
rem ��������㥬 䠩� ����ᮢ
brcc32.exe -32 dlgopt.rc
rem ��६�頥� १���� � ����� � �஥�⮬
move dlgopt.RES ..\..\dlgopt.RES
pause

