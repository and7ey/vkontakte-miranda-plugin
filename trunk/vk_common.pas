(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (c) 2008-2010 Andrey Lukyanov

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

  function IfThen(AValue: Boolean; const ATrue: Integer; const AFalse: Integer = 0): Integer;

  function GenerateApiUrl(sParms: String): String;

  function GetJSONResponse(sResponse: String; sParm: String = 'response'): Variant;
  function GetJSONResponseChild0(sHTML: String; sFieldName: String): Variant;
  function GetJSONError(sResponse: String): Integer;

  function UnixToDateTime(USec: Longint): TDateTime;
  function DateTimeToUnix(dtDateTime: TDateTime): Integer;

implementation

uses
  m_globaldefs,
  m_api,

  uLkJSON, // module to parse JSON data

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

function IfThen(AValue: Boolean; const ATrue: Integer; const AFalse: Integer = 0): Integer;
begin
  if AValue then
    Result := ATrue
  else
    Result := AFalse;
end;

// =============================================================================
// function to generate md5
// -----------------------------------------------------------------------------
function GenerateMD5(sParms: String): String;
var
  mdi: TMD5_INTERFACE;
  md5hash: TMD5_Digest;
  md5Signature: String;
  i: byte;
  pParms: PChar;
begin
  // Netlib_Log(vk_hNetlibUser, PChar('sParms='+sParms)); // TEMP!
  FillChar(mdi, SizeOf(mdi), 0);
	mdi.cbSize := SizeOf(mdi);
	PluginLink^.CallService(MS_SYSTEM_GET_MD5I, 0, Windows.lParam(@mdi));
  GetMem(pParms, Length(sParms)+1);
  StrPCopy(pParms, sParms);
  mdi.md5_hash(pParms^, StrLen(pParms), md5hash);
  // GetMem(pParms, (Length(sParms) + 1) * SizeOf(WideChar));
  // lstrcpynw(pParms, PWideChar(sParms), (Length(sParms) + 1) * SizeOf(WideChar));
  // mdi.md5_hash(pParms^, (Length(sParms) + 1) * SizeOf(WideChar), md5hash);
  for i := 0 to 15 do
    md5Signature := md5Signature + IntToHex(md5hash[i], 2);
  FreeMem(pParms);
	Result := LowerCase(md5Signature);
end;

// =============================================================================
// function to generate VK API signature
// http://vkontakte.ru/developers.php?o=-1&p=%D0%90%D0%B2%D1%82%D0%BE%D1%80%D0%B8%D0%B7%D0%B0%D1%86%D0%B8%D1%8F+Desktop-%D0%BF%D1%80%D0%B8%D0%BB%D0%BE%D0%B6%D0%B5%D0%BD%D0%B8%D0%B9
// -----------------------------------------------------------------------------
function GenerateApiSignature(slParms: TStringList): String;
var
 sSig: String;
begin
 slParms.Sorted := True; // needed for correct signature generation
 slParms.QuoteChar := '^';
 slParms.Delimiter := '^';
 slParms.Add('api_id=' + vk_api_appid); // application id
 slParms.Add('v=3.0'); // API version
 slParms.Add('format=JSON'); // format of result - JSON
 sSig := vk_id + // mid - user's id
         URLDecode(Replace(slParms.DelimitedText,'^','')) +  // had to URLDecode parms here, since signature should be generated in such a way
         vk_secret;
 // Netlib_Log(vk_hNetlibUser, PChar('sSig='+sSig)); // TEMP!
 Result := GenerateMD5(sSig);
 // Netlib_Log(vk_hNetlibUser, PChar('md5(sSig)='+Result)); // TEMP!
end;

// =============================================================================
// function to generate VK API url
// symbol ^ to be used in parms as delimeter
// http://vkontakte.ru/developers.php?o=-1&p=%D0%90%D0%B2%D1%82%D0%BE%D1%80%D0%B8%D0%B7%D0%B0%D1%86%D0%B8%D1%8F+Desktop-%D0%BF%D1%80%D0%B8%D0%BB%D0%BE%D0%B6%D0%B5%D0%BD%D0%B8%D0%B9
// -----------------------------------------------------------------------------
function GenerateApiUrl(sParms: String): String;
var slParms: TStringList;
begin
 slParms := TStringList.Create();
 slParms.Delimiter := '^';
 slParms.QuoteChar := #0;
 slParms.DelimitedText := sParms;
 slParms.Delimiter := '&';
 Result := vk_url_api +
           '?api_id=' + vk_api_appid + // application id
           '&' +
           slParms.DelimitedText +
           '&format=JSON' +
           '&sid=' + vk_session_id + // session id
           '&sig=' + GenerateApiSignature(slParms) +
           '&v=3.0';
 Result := UTF8Encode(Result);
 // Netlib_Log(vk_hNetlibUser, PChar('url='+Result));
end;

// =============================================================================
// function to get integer response from the JSON answer like {"response":10847}
// -----------------------------------------------------------------------------
function GetJSONResponse(sResponse: String; sParm: String = 'response'): Variant;
var FeedRoot: TlkJSONobject;
begin
 Result := 1; // Unknown error occured - default value
 FeedRoot := TlkJSON.ParseText(sResponse) as TlkJSONobject;
 try
   Result := FeedRoot.Field[sParm].Value;
 finally
   FeedRoot.Free;
 end;
end;

function GetJSONResponseChild0(sHTML: String; sFieldName: String): Variant;
var jsoFeed: TlkJSONobject;
begin
  Result := '';
  jsoFeed := TlkJSON.ParseText(sHTML) as TlkJSONobject;
  try
    if Assigned(jsoFeed) then
      Result := Trim(HTMLDecodeW(jsoFeed.Field['response'].Child[0].Field[sFieldName].Value));
  finally
    jsoFeed.Free;
  end;
end;

// =============================================================================
// function to get error code response from the JSON
// {"error":{"error_code":9,"error_msg":"Flood control enabled for this action","request_params":[{"key":"api_id","value":"1931262"},{"key":"method","value":"messages.send"},{"key":"uid","value":"1234567"},{"key":"message","value":"?"},{"key":"format","value":"JSON"},{"key":"sid","value":"91af4123345b8235c7b8cd80e170a18f49e9dfbcb966f8307a6904a0de"},{"key":"sig","value":"3f11234562712ab09f6c771cc088348e"},{"key":"v","value":"3.0"}]}}

// TO DO: replace this code with usage of XML (m_xml.inc)
// sample code: http://trac.miranda.im/mainrepo/browser/importtxt/trunk/BICQ5IP.inc
// -----------------------------------------------------------------------------
function GetJSONError(sResponse: String): Integer;
var FeedRoot: TlkJSONobject;
begin
 Result := 1; // Unknown error occured - default value
 FeedRoot := TlkJSON.ParseText(sResponse) as TlkJSONobject;
 try
   Result := FeedRoot.Field['error'].Field['error_code'].Value;
 finally
   FeedRoot.Free;
 end;
end;

function UnixToDateTime(USec: Longint): TDateTime; 
const
  UnixStartDate: TDateTime = 25569;
begin
  Result := (Usec / 86400) + UnixStartDate;
end;

function DateTimeToUnix(dtDateTime: TDateTime): Integer;
const
  UnixStartDate: TDateTime = 25569; // 1970-01-01 00:00:00 in TDateTime
begin
  Result := Trunc((dtDateTime-UnixStartDate)*86400); // SecondsPerDay = 60*24*60; = 86400;
end;

begin
end.
