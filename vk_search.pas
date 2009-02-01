(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (С) 2009 Andrey Lukyanov

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
 vk_search.pas

 [ Description ]
 Module to support search functionality

 [ Known Issues ]
 See the code

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_search;

interface

uses
  m_globaldefs,
  m_api,
  Classes;

type
  PPROTOSEARCHRESULT_VK = ^TPROTOSEARCHRESULT_VK;
  TPROTOSEARCHRESULT_VK = record
    cbSize   : int;
    nick     : PChar;
    firstName: PChar;
    lastName : PChar;
    email    : PChar;
    reserved : array [0..15] of Byte;
    // protocol-specific fields
    id       : Integer; // contains unique contact's id
    SecureID : PChar; // id, which is required to add contact on the server
    Status   : Integer; // status of contact found
  end;

type
  CUSTOMSEARCHRESULTS_VK = record
    nSize       : size_t;
    nFieldCount : int;
    szFields    : ^TCHAR;
    psr         : TPROTOSEARCHRESULT_VK;
  end;

  procedure SearchInit();
  procedure SearchDestroy();

implementation

uses
  vk_global, // module with global variables and constant used
  vk_core, // module with core functions
  vk_common, // module with common functions
  vk_http, // module to connect with the site

  MSHTML_TLB, // module to parse html
  htmlparse, // module to simplify html parsing

  Messages,
  ComObj,
  ActiveX,
  Variants,
  Windows,
  SysUtils;

  function SearchAdv(wnd: HWnd): DWord; forward;
  function SearchName(lParam: lParam): DWord; forward;
  function SearchID(lParam: lParam): DWord; forward;

const
  SearchHandle = 230;

var
  vk_hSearchBasic,
  vk_hSearchByName,
  vk_hCreateAdvSearchUI,
  vk_hSearchByAdvanced,
  vk_hAddToList: THandle;

// =============================================================================
// function to add found contact to the list
// -----------------------------------------------------------------------------
function AddToList(wParam: wParam; lParam: lParam): Integer; cdecl;
var psre: TPROTOSEARCHRESULT_VK;
    psreNick: String;
    psreStatus: Integer;
begin
  if lParam <> 0 then
  begin
    psre :=  PPROTOSEARCHRESULT_VK(lParam)^;
    // values below will be required for authorization request
    psreID := psre.id;
    psreSecureID := psre.SecureID;

    psreNick := psre.firstName;
    psreStatus := psre.Status;

    Result := vk_AddFriend(psreID, psreNick, psreStatus, 0);

    // add the contact temporarily and invisibly, just to get user info or something
    If wParam = PALF_TEMPORARY Then
    Begin
      DBWriteContactSettingByte(Result, 'CList', 'NotOnList', 1);
		  DBWriteContactSettingByte(Result, 'CList', 'Hidden', 1);
    End;
  end
  else
    Result := 0; // failure
end;

// =============================================================================
// function allows to search contacts by id
// -----------------------------------------------------------------------------
function SearchBasic(wParam: wParam; lParam: lParam): Integer; cdecl;
var res: DWord;
begin
  if lParam = 0 then
    result := 0
  else
  begin
    // search when online is possible only
    if (vk_Status <> ID_STATUS_ONLINE) and (vk_Status <> ID_STATUS_INVISIBLE) then
    begin
      Result := 0;
    end
    else
    begin
      result := SearchHandle;
      CloseHandle(BeginThread(nil, 0, @SearchID, pointer(lParam), 0, res));
    end;
  end;
end;

// =============================================================================
// function allows to search contacts by name and surname
// -----------------------------------------------------------------------------
function SearchByName(wParam: wParam; lParam: lParam): Integer; cdecl;
var res: DWord;
begin
  if lParam = 0 then
    result := 0
  else
  begin
    // search when online is possible only
    if (vk_Status <> ID_STATUS_ONLINE) and (vk_Status <> ID_STATUS_INVISIBLE) then
    begin
      Result := 0;
    end
    else
    begin
      result := SearchHandle;
      CloseHandle(BeginThread(nil, 0, @SearchName, pointer(lParam), 0, res));
    end;
  end;
end;

// =============================================================================
// function allows to search contact by all details
// -----------------------------------------------------------------------------
function SearchByAdvanced(wParam: wParam; lParam: lParam): Integer; cdecl;
var res: DWord;
begin
  if lParam = 0 then
    result := 0
  else
  begin
    // search when online is possible only
    if (vk_Status <> ID_STATUS_ONLINE) and (vk_Status <> ID_STATUS_INVISIBLE) Then
    Begin
      // don't display message here - miranda does it
      // MessageBox(0, PChar(StringReplace(Translate(err_search_noconnection), '%s', piShortName, [rfReplaceAll])), Translate(err_search_title), MB_OK or MB_ICONERROR);
      Result := 0;
    End
    Else
    Begin
      result := SearchHandle;
      CloseHandle(BeginThread(nil, 0, @SearchAdv, pointer(lParam), 0, res));
    End;
  end;
end;


// =============================================================================
// function to work with Advanced Search dialog
// -----------------------------------------------------------------------------
function AdvancedSearchDlgProc(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
      begin
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_GENDER), GenderField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_MARITALSTATUS), MaritalStatusField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_POLITICALVIEWS), PoliticalViewsField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_DOB), DOBField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_MOB), MOBField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_YOB), YearsField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_COUNTRY), CountryField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_GRADYEAR), YearsField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_ED_STATUS), EdStatusField);
        InitComboBox(GetDlgItem(Dialog, VK_ADVSRCH_CITY), CitiesField);

        // translate all dialog texts
        TranslateDialogDefault(Dialog);

        Result := True;
      end;
    WM_COMMAND:
      begin
        case loword(wParam) of
          IDOK:
            begin
              SendMessage(GetParent(Dialog),WM_COMMAND,IDOK+(BN_CLICKED) shl 16, GetDlgItem(GetParent(Dialog),IDOK));
              Result := True;
            end;
          IDCANCEL:
            begin
              Result := True;
            end;

        end;
      end;
  end;
end;

// =============================================================================
// function to display advanced search dialog
// -----------------------------------------------------------------------------
function CreateAdvSearchUI(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  If (lParam <> 0) And (hInstance <> 0) Then
    Result := CreateDialog(hInstance, MAKEINTRESOURCE('VK_SEARCHADVANCED'), lParam, @AdvancedSearchDlgProc)
  else
    Result := 0; // failure
end;

// =============================================================================
// procedure to find contacts by name, surname and other details
// find first 20 contacts
// -----------------------------------------------------------------------------
procedure vk_SearchFriends(SearchURL: String; SearchID: Integer; SearchPages: Integer);
var
    HTML: String;
    iHTTP: IHTMLDocument2; // these 2 variables required for
    v: Variant;            // String -> IHTMLDocument2 conversions
    FoundTemp: TStringList;
    i: Byte;
    TempInteger: Integer;
    FriendDetails_temp: String;
    FoundCount: Integer;

    csr: CUSTOMSEARCHRESULTS_VK;  // variables for customer search results
    columns: array [0..3] of TCHAR;

    FriendStatus,
    FriendID,
    FriendFullName,
    FriendSecID,
    FriendGraduated,
    FriendFaculty: String;

begin
  SearchURL := SearchURL + vk_url_search_suffix;

  HTML := HTTP_NL_Get(Format(SearchURL, [0]));

  if SearchPages > 1 then
  begin
    if Not TryStrToInt(TextBetween(HTML, 'Найдено ', ' человек'), FoundCount) Then
      FoundCount := 10;

    for i:=1 to SearchPages-1 do
      if FoundCount > i*10 Then // get next 10 found contacts
        HTML := HTML + HTTP_NL_Get(Format(SearchURL, [i*10]));
  end;


  CoInitialize(nil);  // since this function is called in a separate function,
                      // this code is mandatory for CreateComObject function
  If Trim(HTML) <> '' Then
  Begin
    try
      iHTTP := CreateComObject(Class_HTMLDocument) as IHTMLDocument2;
      v := VarArrayCreate([0,0], VarVariant);
      v[0] := HTML;
      iHTTP.Write(PSafeArray(System.TVarData(v).VArray));
    except
      iHTTP:=nil;
    end;

    if Assigned(iHTTP) Then
    Begin
      // for unicode should use columns[0].W, see mRadio Mod for example
      columns[0].a := 'ID';               // id
      columns[1].a := 'Nick';             // имя
      columns[2].a := 'Graduated';        // выпуск
      columns[3].a := 'Faculty';          // факультет
      columns[0].w := 'ID';
      columns[1].w := 'Nick';
      columns[2].w := 'Graduated';
      columns[3].w := 'Faculty';
      csr.nSize       := SizeOf(csr);
      csr.nFieldCount := 4;
      csr.szFields    := @columns;
      csr.psr.cbSize  := 0; // sending just column names
      ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_SEARCHRESULT, SearchID, DWord(@csr));

      FoundTemp := getElementsByAttr(iHTTP, 'div', 'classname', 'result clearFix');
      if FoundTemp.Count > 0 then
        for i := 0 to FoundTemp.Count - 1 do
        Begin

          FriendDetails_temp := TextBetweenInc(FoundTemp.Strings[i],'<DIV class=info','</LI>');

          FriendID := TextBetween(FriendDetails_temp, 'friend.php?id=', '">');
          FriendFullName := HTMLRemoveTags(Trim(TextBetween(FriendDetails_temp, '<DT>Имя:', '<DT>')));
          if FriendFullName = '' Then
            FriendFullName := HTMLRemoveTags(Trim(TextBetween(FriendDetails_temp, '<DT>Имя:', '</DD>')));
          FriendFullName := HTMLDecode(Trim(FriendFullName));
          FriendGraduated := TextBetween(FriendDetails_temp, '<DT>Выпуск:', '<DT>');
          FriendGraduated := Trim(HTMLRemoveTags(HTMLDecode(FriendGraduated)));
          if Pos('&nbsp', FriendDetails_temp) > 0 then
            FriendFaculty := TextBetween(FriendDetails_temp, '<DT>Факультет:', '&nbsp')
          else
            FriendFaculty := TextBetween(FriendDetails_temp, '<DT>Факультет:', '</DD>');
          FriendFaculty := Trim(HTMLRemoveTags(HTMLDecode(FriendFaculty)));
          FriendSecID := TextBetween(FoundTemp.Strings[i], '&amp;h=', '">Добавить в друзья');
          FriendStatus := TextBetween(FriendDetails_temp, '<span class=''bbb''>', '</span>');

          if TryStrToInt(FriendID, TempInteger) and (FriendID<>'') and (FriendFullName<>'') and (FriendSecID<>'') Then
          Begin
            FillChar(csr, sizeof(csr), 0);
            csr.psr.cbSize := sizeOf(csr.psr);
            csr.psr.nick := StrNew(PChar(FriendID));
            csr.psr.firstName := StrNew(PChar(FriendFullName));
            csr.psr.lastName := StrNew(PChar(FriendGraduated));
            csr.psr.email := StrNew(PChar(FriendFaculty));
            csr.psr.id := TempInteger;
            csr.psr.SecureID := StrNew(PChar(FriendSecID));
            if FriendStatus = 'Online' then
              csr.psr.Status := ID_STATUS_ONLINE
            else
              csr.psr.Status := ID_STATUS_OFFLINE;

            columns[0].a := PChar(FriendID);
            columns[1].a := PChar(FriendFullName);
            columns[2].a := PChar(FriendGraduated);
            columns[3].a := PChar(FriendFaculty);
            columns[0].w := PWideChar(WideString(FriendID));
            columns[1].w := PWideChar(WideString(FriendFullName));
            columns[2].w := PWideChar(WideString(FriendGraduated));
            columns[3].w := PWideChar(WideString(FriendFaculty));

            csr.nSize       := SizeOf(csr);
            csr.nFieldCount := 4;
            csr.szFields    := @columns;

            // add contacts to search results
            // ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_DATA, SearchID, lParam(@csr.hdr.psr));  // this line is for miranda older than 0.7.0.0
            ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_SEARCHRESULT, SearchID, DWord(@csr));
          End;
        End;
      // search finished successfully
      ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_SUCCESS, SearchID, 0);
    End
    Else // search failed, but we say that it is OK, since miranda doesn't support search failure - ACKRESULT_FAILED
      ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_SUCCESS, SearchID, 0);

  End;
  CoUninitialize();
end;

// =============================================================================
// procedure to initiate search support functionality
// -----------------------------------------------------------------------------
procedure SearchInit();
begin
  vk_hSearchBasic := CreateProtoServiceFunction(piShortName, PS_BASICSEARCH, @SearchBasic);
  vk_hSearchByName := CreateProtoServiceFunction(piShortName, PS_SEARCHBYNAME, @SearchByName);
  vk_hCreateAdvSearchUI := CreateProtoServiceFunction(piShortName, PS_CREATEADVSEARCHUI, @CreateAdvSearchUI);
  vk_hSearchByAdvanced := CreateProtoServiceFunction(piShortName, PS_SEARCHBYADVANCED, @SearchByAdvanced);
  vk_hAddToList := CreateProtoServiceFunction(piShortName, PS_ADDTOLIST, @AddToList);
end;

// =============================================================================
// procedure to destroy search support functionality
// -----------------------------------------------------------------------------
procedure SearchDestroy();
begin
  pluginLink^.DestroyServiceFunction(vk_hSearchBasic);
  pluginLink^.DestroyServiceFunction(vk_hSearchByName);
  pluginLink^.DestroyServiceFunction(vk_hCreateAdvSearchUI);
  pluginLink^.DestroyServiceFunction(vk_hSearchByAdvanced);
  pluginLink^.DestroyServiceFunction(vk_hAddToList);
end;


// =============================================================================
// advanced search functionality - runs in a separate thread
// -----------------------------------------------------------------------------
function SearchAdv(wnd: HWnd): DWord;
var
  SearchURL: String;

  srchFirstName,
  srchLastName: String;
  srchSex,
  srchStatus,
  srchPolitical,
  srchBDDay,
  srchBDMonth,
  srchBDYear,
  srchUCountry,
  srchUCity,
  srchUniversity,
  srchUFaculty,
  srchUChair,
  srchUGraduation,
  srchUEduForm,
  srchOnline: Integer;

begin
  srchFirstName := GetDlgString(wnd, VK_ADVSRCH_FIRSTNAME);
  srchLastName := GetDlgString(wnd, VK_ADVSRCH_LASTNAME);
  srchSex := GetDlgComboBoxItem(wnd, VK_ADVSRCH_GENDER);
  srchStatus := GetDlgComboBoxItem(wnd, VK_ADVSRCH_MARITALSTATUS);
  srchPolitical := GetDlgComboBoxItem(wnd, VK_ADVSRCH_POLITICALVIEWS);
  srchBDDay := GetDlgComboBoxItem(wnd, VK_ADVSRCH_DOB);
  srchBDMonth := GetDlgComboBoxItem(wnd, VK_ADVSRCH_MOB);
  srchBDYear := GetDlgComboBoxItem(wnd, VK_ADVSRCH_YOB);
  srchUCountry := GetDlgComboBoxItem(wnd, VK_ADVSRCH_COUNTRY);
  srchUCity := GetDlgComboBoxItem(wnd, VK_ADVSRCH_CITY);
  srchUniversity := 0; // GetDlgComboBoxItem(wnd, VK_ADVSRCH_COLLEGE);
  srchUFaculty := 0; // GetDlgComboBoxItem(wnd, VK_ADVSRCH_FACULTY);
  srchUChair := 0; // GetDlgComboBoxItem(wnd, VK_ADVSRCH_DEPARTMENT);
  srchUGraduation := GetDlgComboBoxItem(wnd, VK_ADVSRCH_GRADYEAR);
  srchUEduForm := GetDlgComboBoxItem(wnd, VK_ADVSRCH_ED_STATUS);
  srchOnline := Byte(IsDlgButtonChecked(wnd, VK_ADVSRCH_ONLINEONLY));

  SearchURL := Format(vk_url_search, [srchFirstName, srchLastName, srchSex, srchStatus, srchPolitical, srchBDDay, srchBDMonth, srchBDYear,
                        srchUCountry, srchUCity, srchUniversity, srchUFaculty, srchUChair, srchUGraduation, srchUEduForm, srchOnline]);

  // for debug - SetDlgItemText(wnd, VK_ADVSRCH_FIRSTNAME, PChar(SearchURL));
  vk_SearchFriends(SearchURL, SearchHandle, 2);

  Result := 0;
end;

// =============================================================================
// search by ID functionality - runs in a separate thread
// -----------------------------------------------------------------------------
function SearchID(lParam: lParam): DWord;
var
  SearchURL: String;

  srchID: String;
  srchIDInt: Integer;

begin
  srchID := PChar(lParam);

  if TryStrToInt(srchID, srchIDInt) then // id provided should be numeric
  begin
    SearchURL := Format(vk_url_searchbyid, [srchIDInt]);
    vk_SearchFriends(SearchURL, SearchHandle, 1);
  end
  else
    ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_SUCCESS, SearchHandle, 0);

  Result := 0;
end;


// =============================================================================
// search by name functionality - runs in a separate thread
// -----------------------------------------------------------------------------
function SearchName(lParam: lParam): DWord;
var
  sbn: TPROTOSEARCHBYNAME;

  SearchURL: String;

  srchFirstName,
  srchLastName: String;

begin
  sbn := PPROTOSEARCHBYNAME(lParam)^;
  srchFirstName := sbn.pszFirstName;
  srchLastName := sbn.pszLastName;

  SearchURL := Format(vk_url_search, [srchFirstName, srchLastName, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, 0]);

  vk_SearchFriends(SearchURL, SearchHandle, 2);

  Result := 0;
end;

begin
end.
