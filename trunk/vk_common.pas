(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (c) 2008-2009 Andrey Lukyanov

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

uses
     vk_global, // module with global variables and constant used

     Windows,
     Messages,
     SysUtils,
     Classes;

type
  TFriendName = record
    Nick     : WideString;
    FirstName: WideString;
    LastName : WideString;
  end;

  function GetContactByID(uid: Integer): LongWord;
  function FullNameToNameSurnameNick(S: WideString): TFriendName;
  function RusDateToDateTime(RDate: String; LMonthes: Boolean): TDateTime;

  function GetDlgString(hDlg: HWnd; idCtrl: Integer): String;
  function GetDlgUnicode(hDlg: HWnd; idCtrl: Integer): WideString;  
  function GetDlgInt(hDlg: HWnd; idCtrl: Integer): Integer;
  function GetDlgComboBoxItem(hDlg: HWnd; idCtrl: Integer): Integer;
  procedure InitComboBox(hwndCombo: HWnd; const Names: Array of TComboBoxItem);

  function GetFileSize_(sFileName: string): cardinal;

implementation

uses
  m_globaldefs,
  m_api,

  htmlparse; // module to simplify html parsing


// =============================================================================
// function to get contact handle by id
// -----------------------------------------------------------------------------
function GetContactByID(uid: Integer): LongWord;
var hContact: THandle;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(GetContactByID) Searching contact by id: '+IntToStr(uid)+'...'));
  Result := 0;
  hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
	while hContact <> 0 do
  begin
    // by default MS_DB_CONTACT_FINDFIRST returns all contacts found
    // next line verifies that found contact belongs to our protocol
    if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, Windows.lParam(PChar(piShortName))) <> 0 Then
    begin
      if DBGetContactSettingDWord(hContact, piShortName, 'ID', 0) = uid Then
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(GetContactByID) ... found id: '+IntToStr(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0))+' - match found!'));
          Result := hContact;
          Exit;
        end;
      // Netlib_Log(vk_hNetlibUser, PChar('(GetContactByID) ... found id: '+IntToStr(DBGetContactSettingDword(hContact, piShortName, 'ID', 0))+' - no match'));
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
function FullNameToNameSurnameNick(S: WideString): TFriendName;
begin
 result.Nick := Copy(S, Pos(' ',S)+1, LastPos(' ',S)-Pos(' ',S)-1);
 result.FirstName := Copy(S, 1, Pos(' ',S)-1);
 result.LastName := Copy(S, LastPos(' ',S)+1, Length(S)-LastPos(' ',S));
end;

// =============================================================================
// function to convert date in Russian like '15 мар 2008 в 22:18'
// to TDateTime
// -----------------------------------------------------------------------------
function RusDateToDateTime(RDate: String; LMonthes: Boolean): TDateTime;
const Monthes: array[1..12] of string = ('€нв', 'фев', 'мар', 'апр','ма€','июн', 'июл', 'авг', 'сен', 'окт','но€', 'дек');
const MonthesLong: array[1..12] of string = ('€нвар€', 'феврал€', 'марта', 'апрел€','ма€','июн€', 'июл€', 'августа', 'сент€бр€', 'окт€бр€','но€бр€', 'декабр€');
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

   RDate := StringReplace(RDate, ' в ', ' ', [rfIgnoreCase]);
   GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, FormatSettings);

   FormatSettings.DateSeparator := '/';
   FormatSettings.TimeSeparator := ':';
   FormatSettings.ShortDateFormat := 'd/m/yyyy';
   FormatSettings.ShortTimeFormat := 'h:nn';

   Result := StrToDateTime(RDate, FormatSettings);
end;

// =============================================================================
// function to get text of dialog item
// -----------------------------------------------------------------------------
function GetDlgString(hDlg: HWnd; idCtrl: Integer): String;
var
  dlg_text: array[0..1023] of Char;
begin
  ZeroMemory(@dlg_text,SizeOf(dlg_text));
  GetDlgItemText(hDlg,idCtrl,@dlg_text,1023);
  Result := dlg_text;
end;

// =============================================================================
// function to get text of dialog item
// -----------------------------------------------------------------------------
function GetDlgUnicode(hDlg: HWnd; idCtrl: Integer): WideString;
var
  dlg_text: array[0..1023] of Char;
begin
  ZeroMemory(@dlg_text,SizeOf(dlg_text));
  GetDlgItemTextW(hDlg,idCtrl,@dlg_text,1023);
  Result := dlg_text;
end;

// =============================================================================
// function to get numeric value of dialog item
// -----------------------------------------------------------------------------
function GetDlgInt(hDlg: HWnd; idCtrl: Integer): Integer;
var
  dlg_text: array[0..1023] of Char;
begin
  ZeroMemory(@dlg_text,SizeOf(dlg_text));
  GetDlgItemText(hDlg,idCtrl,@dlg_text,1023);
  if Not TryStrToInt(dlg_text, Result) then
    Result := -1;
end;

// =============================================================================
// function to get numeric value of dialog combobox item
// -----------------------------------------------------------------------------
function GetDlgComboBoxItem(hDlg: HWnd; idCtrl: Integer): Integer;
begin
  Result := SendDlgItemMessage(hDlg, idCtrl, CB_GETITEMDATA, SendDlgItemMessage(hDlg, idCtrl, CB_GETCURSEL, 0, 0), 0);
end;

// =============================================================================
// function to insert values from array into combobox
// -----------------------------------------------------------------------------
procedure InitComboBox(hwndCombo: HWnd; const Names: Array of TComboBoxItem);
var
	iItem, i: Integer;
begin
 	iItem := SendMessage(hwndCombo, CB_ADDSTRING, 0, LongInt(PChar(''))); // add empty element
	SendMessage(hwndCombo, CB_SETITEMDATA, iItem, 0);
	SendMessage(hwndCombo, CB_SETCURSEL, iItem, 0); // define empty element as default

	for i := 0 to High(Names) do
	begin
  	iItem := SendMessage(hwndCombo, CB_ADDSTRING, 0, LongInt(Translate(PChar(Names[i].Name))));
  	SendMessage(hwndCombo, CB_SETITEMDATA, iItem, Names[i].Index);
	end;
end;


// =============================================================================
// function to get file size
// -----------------------------------------------------------------------------
function GetFileSize_(sFileName: string): cardinal;
var
  hFile: THandle;
  FileSize: LongWord;
begin
  hFile := CreateFile(PChar(sFileName),
    GENERIC_READ,
    0,
    nil,
    OPEN_EXISTING,
    FILE_ATTRIBUTE_NORMAL,
    0);
  FileSize := Windows.GetFileSize(hFile, nil);
  Result := FileSize;
  CloseHandle(hFile);
end;

begin
end.
