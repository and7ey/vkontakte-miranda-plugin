(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (�) 2008 Andrey Lukyanov

    This program is free software; you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation; either version 2 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
*)

{-----------------------------------------------------------------------------
 vk_common.pas

 [ Description ]
 Module includes common functions used by other modules

 [ Known Issues ]
 See the code

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_common;

interface

type
  TFriendName = record
    Nick     : String;
    FirstName: String;
    LastName : String;
  end;

  function GetContactByID(uid: Integer): THandle;
  function FullNameToNameSurnameNick(S: String): TFriendName;
  function RusDateToDateTime(RDate: String; LMonthes: Boolean): TDateTime;

implementation

uses
  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used

  htmlparse, // module to simplify html parsing

  Windows,
  SysUtils,
  Classes;

// =============================================================================
// function to get contact handle by id
// -----------------------------------------------------------------------------
function GetContactByID(uid: Integer): THandle;
var hContact: THandle;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(GetContactByID) Searching contact by id: '+IntToStr(uid)+'...'));
  Result := 0;
  hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
	while hContact <> 0 do
  begin
    // by default MS_DB_CONTACT_FINDFIRST returns all contacts found
    // next line verifies that found contact belongs to our protocol
    if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, lParam(PChar(piShortName))) <> 0 Then
    begin
      if DBGetContactSettingDword(hContact, piShortName, 'ID', 0) = uid Then
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(GetContactByID) ... found id: '+IntToStr(DBGetContactSettingDword(hContact, piShortName, 'ID', 0))+' - match found!'));
          Result := hContact;
          Exit;
        end;
      Netlib_Log(vk_hNetlibUser, PChar('(GetContactByID) ... found id: '+IntToStr(DBGetContactSettingDword(hContact, piShortName, 'ID', 0))+' - no match'));
    end;
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
	end;
end;

// =============================================================================
// function to extract Nick, Name and Surname from strings like
// 'Name Nick Surname'
// 'Name Nick1 Nick2 Surname'
// 'Name Surname'
// -----------------------------------------------------------------------------
function FullNameToNameSurnameNick(S: String): TFriendName;
begin
 result.Nick := Copy(S, Pos(' ',S)+1, LastPos(' ',S)-Pos(' ',S)-1);
 result.FirstName := Copy(S, 1, Pos(' ',S)-1);
 result.LastName := Copy(S, LastPos(' ',S)+1, Length(S)-LastPos(' ',S));
end;

// =============================================================================
// function to convert date in Russian like '15 ��� 2008 � 22:18'
// to TDateTime
// -----------------------------------------------------------------------------
function RusDateToDateTime(RDate: String; LMonthes: Boolean): TDateTime;
const Monthes: array[1..12] of string = ('���', '���', '���', '���','���','���', '���', '���', '���', '���','���', '���');
const MonthesLong: array[1..12] of string = ('������', '�������', '�����', '������','���','����', '����', '�������', '��������', '�������','������', '�������');
var
    i: Integer;
    FormatSettings: TFormatSettings;
begin
   if LMonthes then
    for i:=1 to 12 do
     RDate := StringReplace(RDate, ' ' + MonthesLong[i] + ' ', '/' + IntToStr(i) + '/', [rfIgnoreCase])
   else
    for i:=1 to 12 do
     RDate := StringReplace(RDate, ' ' + Monthes[i] + ' ', '/' + IntToStr(i) + '/', [rfIgnoreCase]);

   RDate := StringReplace(RDate, ' � ', ' ', [rfIgnoreCase]);
   GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, FormatSettings);

   FormatSettings.DateSeparator := '/';
   FormatSettings.TimeSeparator := ':';
   FormatSettings.ShortDateFormat := 'd/m/yyyy';
   FormatSettings.ShortTimeFormat := 'h:nn';

   Result := StrToDateTime(RDate, FormatSettings);
end;


begin
end.
