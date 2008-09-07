(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (С) 2008 Andrey Lukyanov

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
 vk_core.pas

 [ Description ]
 Module with core functions - connect with the server, disconnect, read
 contacts, their statuses etc.

 [ Known Issues ]
 - See the code
 - Status of friends is read only

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_core;

interface

uses

  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used
  vk_common, // module with common functions
  vk_http, // module to connect with the site
  vk_avatars, // module to support avatars

  vk_xstatus, // module to support additional status

  vk_opts, // my unit to work with options
  MSHTML_TLB, // module to parse html
  htmlparse, // module to simplify html parsing

  Windows,
  Messages,
  SysUtils,
  Classes,
  ComObj,
  ActiveX,
  Variants,
  ShellAPI,
  StrUtils;

  function vk_AddFriend(frID: Integer; frNick: String; frStatus: Integer; frFriend: Byte): Integer;
  function SearchByName(wParam: wParam; lParam: lParam): Integer; cdecl;
  function AddToList(wParam: wParam; lParam: lParam): Integer; cdecl;
  procedure SetStatusOffline();
  function ContactDeleted(wParam: wParam; lParam: lParam): Integer; cdecl;
  procedure TimerKeepOnline(Wnd: HWnd; Msg, TimerID, SysTime: Longint); stdcall;
  procedure TimerUpdateFriendsStatus(Wnd: HWnd; Msg, TimerID, SysTime: Longint); stdcall;

{$include res\dlgopt\i_const.inc} // contains list of ids used in dialogs

type
  TThreadConnect = class(TThread)
  private
     { Private declarations }
  protected
    procedure Execute; override;
  end;
  TThreadGetFriends = class(TThread)
  private
    { Private declarations }
  protected
    procedure Execute; override;
  end;
  TThreadSearchContacts = class(TThread)
  private
    { Private declarations }
  protected
    procedure Execute; override;
  end;
  TThreadKeepOnline = class(TThread)
  private
    { Private declarations }
  protected
    procedure Execute; override;
  end;

var
  ThrIDConnect: TThreadConnect;
  ThrIDGetFriends: TThreadGetFriends;
  ThrIDSearchContacts: TThreadSearchContacts;
  ThrIDKeepOnline: TThreadKeepOnline;


implementation

type // enchanced type required for search results
  PPROTOSEARCHRESULT_VK = ^TPROTOSEARCHRESULT_VK;
  TPROTOSEARCHRESULT_VK = record
    psr: TPROTOSEARCHRESULT; // standard Miranda's search result structure (includes name, surname, nick and mail)
    id: String; // contains unique contact's id
    SecureID: String; // id, which is required to add contact on the server
    Status: Integer; // status of contact found
end;

var
  searchId: Integer; // variable to keep info about search request number
  sbn: TPROTOSEARCHBYNAME; // variable to keep search query data
  FirstName_temp: String;
  LastName_temp: String;

// =============================================================================
// Login Dialog function
// this function is executed only when password OR login are not input
// in the Options
// -----------------------------------------------------------------------------
function DlgLogin(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
var
  str: String;  // temp variable for types conversion
  pc: PChar;    // temp variable for types conversion
begin
  Result:=False;
  case Msg of
     WM_INITDIALOG:
       begin
         SetWindowText(Dialog, PChar(piShortName));
         // translate all dialog texts
         TranslateDialogDefault(Dialog);
         // read login from settings, if exists
         vk_o_login := DBReadString(0, piShortName, opt_UserName, nil);
         SetDlgItemText(Dialog, VK_LOGIN_EMAIL, PChar(vk_o_login)); // e-mail
         if vk_o_login <> '' then
           SetFocus(GetDlgItem(Dialog, VK_LOGIN_PASS));
       end;
     WM_COMMAND:
       begin
         case wParam of
           IDOK, VK_LOGIN_OK:
             begin
               SetLength(Str, 256);
               pc := PChar(Str);
               GetDlgItemText(Dialog, VK_LOGIN_EMAIL, pc, 256);
               vk_o_login := pc;

               SetLength(Str, 256);
               pc := PChar(Str);
               GetDlgItemText(Dialog, VK_LOGIN_PASS, pc, 256);
               vk_o_pass := pc;
               if (vk_o_pass<>'') and (vk_o_login<>'') then
               begin
                 EndDialog(Dialog, 0);
                 Result:=True;
               end;
             end;
           IDCANCEL, VK_LOGIN_CANCEL:
             begin
               EndDialog(Dialog, 0);
               Result:=True;
             end;
           VK_LOGIN_NEWID:
             begin
               ShellAPI.ShellExecute(0, 'open', vk_url_register, nil, nil, 0);
               Result := True;
             end;
         end;
       end;
  end;
end;

// =============================================================================
// function to inform user about something
// the following values of uType are possible:
//  MB_ICONWARNING
//    An exclamation-point icon appears in the message box.
//  MB_ICONINFORMATION
//    An icon consisting of a lowercase letter i in a circle appears in the message box.
//  MB_ICONASTERISK
//    An icon consisting of a lowercase letter i in a circle appears in the message box.
//  MB_ICONSTOP
//     A stop-sign icon appears in the message box.
// -----------------------------------------------------------------------------
procedure MessageUser(lpText: String; uType: Integer);
begin
    { for future popup purposes
      if (!ShowPopUpMsg(NULL, szLevelDescr[level], szMsg, (BYTE)level))
        return; // Popup showed successfuly
    }
   MessageBox(0, Translate(PChar(lpText)), Translate(piShortName), MB_OK + uType);
end;


// =============================================================================
// function to login to website
// returns one of the following value:
//  LOGINERR_WRONGPASSWORD = 1;
//  LOGINERR_NONETWORK     = 2;
//  LOGINERR_PROXYFAILURE  = 3;
//  LOGINERR_BADUSERID     = 4;
//  LOGINERR_NOSERVER      = 5;
//  LOGINERR_TIMEOUT       = 6;
//  LOGINERR_WRONGPROTOCOL = 7;
//  LOGINERR_OTHERLOCATION = 8;
//  if successfull = 0
// -----------------------------------------------------------------------------
function vk_Connect(): integer;
var HTML: String; // html content of the page received
begin
  if Assigned(CookiesGlobal) Then
    CookiesGlobal.Clear; // clear cookies

  ErrorCode := 2; // zero out error code - LOGINERR_NONETWORK     = 2;

  // read login and pass from the database
  vk_o_login := DBReadString(0, piShortName, opt_UserName, '');
  vk_o_pass := DBReadString(0, piShortName, opt_UserPass, '');

  if trim(vk_o_pass) <> '' Then // decrypt password
      pluginLink^.CallService(MS_DB_CRYPT_DECODESTRING, SizeOf(vk_o_pass), Windows.lparam(vk_o_pass));

  if (vk_o_pass = '') or (vk_o_login = '') then
  begin
    // ask user about login & pass if not given
    DialogBox(hInstance, MAKEINTRESOURCE('LOGIN'), 0, @DlgLogin);
    if (vk_o_pass = '') or (vk_o_login = '') then
    begin
      ErrorCode := 1;  // LOGINERR_WRONGPASSWORD = 1;
      Result := ErrorCode;
      Exit;
    end;
  end;

  // here is real connection happens
  HTML := HTTP_NL_Get(Format(vk_url_pda_login, [vk_o_login, URLEncode(vk_o_pass)]));

  // no info received
  If trim(HTML) = '' Then
    ErrorCode := 2; // LOGINERR_NONETWORK     = 2;

  // pass or login is incorrect
  If Pos('<div id="error">', HTML) > 0 Then
    ErrorCode := 1; // LOGINERR_WRONGPASSWORD = 1;

  // OK
  If Pos('div class="menu2"', HTML) > 0 Then
    ErrorCode := 0; // succesfull login!

  Result := ErrorCode;

  // GAP: result of connection / error message is not provided to the user
end;

// =============================================================================
// procedure to logout from the server
// -----------------------------------------------------------------------------
procedure vk_Logout();
begin
  // GAP (?): result is not validated
  HTTP_NL_Get(vk_url_pda_logout, REQUEST_HEAD);
end;

// =============================================================================
// procedure to add new contact into Miranda's list
// returns Handle to added/existing contact
// -----------------------------------------------------------------------------
function vk_AddFriend(frID: Integer; frNick: String; frStatus: Integer; frFriend: Byte): Integer;
var hContactNew: THandle; // handle to new contact
    hContact: THandle;
    DefaultGroup: WideString;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_AddFriend) Trying to add friend, id: '+IntToStr(frID)+', nick: '+frNick));

  // duplicate match
  hContact := GetContactByID(frID);
  if hContact<>0 then // contact already exists in Miranda's list
  Begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AddFriend) ... friend already exists, id: '+IntToStr(DBGetContactSettingDword(hContact, piShortName, 'ID', 0))+', nick: '+DBReadString(hContact, piShortName, 'Nick', '')));
    Result := hContact;
    Exit;
  End;

  // if really new contact
  hContactNew := pluginLink^.CallService(MS_DB_CONTACT_ADD, 0, 0);
  If hContactNew <> 0 Then
  Begin
    DBWriteContactSettingDWord(hContactNew, piShortName, 'ID', frID);
    DBWriteContactSettingString(hContactNew, piShortName, 'Nick', PChar(frNick));
    // DBWriteContactSettingWord(hContactNew, piShortName, 'Status', frStatus); // we can not update it here, it causes crash in newstatusnotify plugin
                                                                                // so, the code is moved below
    DBWriteContactSettingByte(hContactNew, piShortName, 'Friend', frFriend);

    // assign group for contact, if given in settings
    DefaultGroup := DBReadString(0, piShortName, opt_UserDefaultGroup, nil);
    if DefaultGroup<>'' then
      DBWriteContactSettingUnicode(hContactNew, 'CList', 'Group', PWideChar(DefaultGroup));
  End;
  CallService(MS_PROTO_ADDTOCONTACT, hContactNew, lParam(PChar(piShortName)));

  If hContactNew <> 0 Then
    DBWriteContactSettingWord(hContactNew, piShortName, 'Status', frStatus);

  Netlib_Log(vk_hNetlibUser, PChar('(vk_AddFriend) ... friend added'));
  Result := hContactNew;
end;

// function to get minimum information about friends
function vk_GetFriends(): integer;
type
  TFriends = record  // new type of record
    ID: Integer;
    Name: String;
    InList: Boolean;  // friend exists in Miranda's list
    Online: Boolean;  // friend is online
  end;

var i, i1: Integer;  // temp variable
    str1, str2: String; // temp variables
    Friends: Array of TFriends;
    FriendsOnline: Array of Integer;
    TempList: TStringList;

    hContact: THandle;

    HTML: String; // html content of the page received
    PadsList: String;

    iHTTP: IHTMLDocument2; // these 2 variables required for
    v: Variant;            // String -> IHTMLDocument2 conversions

begin

  // *** get friends online
  // they can be on several pages, so retrieve all
  // GAP: status of friends is read only
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting online friends from the server...'));
  i:=1;
  HTML := HTTP_NL_Get(Format(vk_url_pda_friendsonline,[i]));
  PadsList := TextBetween(HTML, '<div class="pad">','</div>');
  While Pos('a href="/friendsonline', PadsList)<>0 Do
  Begin
    Delete(PadsList, 1, Pos('</a>', PadsList)+3);
    i:=i+1;
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... page '+IntToStr(i)+' with online friends found, getting it'));
    HTML := HTML + HTTP_NL_Get(Format(vk_url_pda_friendsonline,[i]));
  End;

  CoInitialize(nil);  // since this function is called in a separate thread,
                      // this code is mandatory for CreateComObject function

  // the code below converts String value received with Get function to
  // iHTMLDocument2, which is required for parsing
  try
    iHTTP := CreateComObject(Class_HTMLDocument) as IHTMLDocument2;
    v := VarArrayCreate([0,0], VarVariant);
    v[0] := HTML;
    iHTTP.Write(PSafeArray(System.TVarData(v).VArray));
  except
    iHTTP:=nil;
  end;

  TempList := TStringList.Create();
  TempList.Sorted := True; // list should be sorted and
  TempList.Duplicates := dupIgnore; // duplicates shouldn't be allowed

  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting online friends details...'));
  // parsing list of friends
  If Assigned(iHTTP) Then
  Begin
    TempList := getElementsByAttrPart(iHTTP, 'a','href','/id');
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... '+IntToStr(TempList.Count-1)+' friend(s) online found'));
    for i:=0 to TempList.Count-1 do
      Begin
        str1 := Trim(TextBetween(TempList.Strings[i], '/id', '">'));
        str2 := Trim(TextBetween(TempList.Strings[i], '>', '</A>'));
        if (str1 <> '0') and (str1 <> '') and (str2 <> '') Then
        Begin
          SetLength(FriendsOnline, Length(FriendsOnline)+1);
          FriendsOnline[High(FriendsOnline)] := StrToInt(str1);
          Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... found online friend with id: '+str1));
        End;
      End;
  End;

  TempList.Clear;
  iHTTP := nil;

  // *** get full list of friends
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting all friends from the server...'));
  i:=1;
  HTML := HTTP_NL_Get(Format(vk_url_pda_friends,[i]));
  PadsList := TextBetween(HTML, '<div class="pad">','</div>');
  While Pos('a href="/friends', PadsList)<>0 Do
  Begin
    Delete(PadsList, 1, Pos('</a>', PadsList)+3);
    i:=i+1;
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... page '+IntToStr(i)+' with friends found, getting it'));
    HTML := HTML + HTTP_NL_Get(Format(vk_url_pda_friends,[i]));
  End;

  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting friends details...'));
  try
    iHTTP := CreateComObject(Class_HTMLDocument) as IHTMLDocument2;
    v := VarArrayCreate([0,0], VarVariant);
    v[0] := HTML;
    iHTTP.Write(PSafeArray(System.TVarData(v).VArray));
  except
    iHTTP:=nil;
  end;

  If Assigned(iHTTP) Then
    TempList := getElementsByAttrPart(iHTTP, 'a','href','/id');

  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... '+IntToStr(TempList.Count-1)+' friend(s) found'));

  For i:=0 to TempList.Count-1 Do
  Begin
    str1 := Trim(TextBetween(TempList.Strings[i], '/id', '">'));
    str2 := Trim(TextBetween(TempList.Strings[i], '>', '</A>'));
    if (str1 <> '0') and (str1 <> '') and (str2 <> '') Then
    Begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... found friend with id: '+str1));
      // if friend is found, add him/her into our Friends array
      SetLength(Friends, Length(Friends)+1);
      Friends[High(Friends)].ID := StrToInt(str1); // High(Friends) = Length(Friends) - 1
      Friends[High(Friends)].Name := HTMLDecode(str2);
      Friends[High(Friends)].InList := False;
      Friends[High(Friends)].Online := False;
      for i1:=Low(FriendsOnline) to High(FriendsOnline) do // mark online Friends
        if StrToInt(str1) = FriendsOnline[i1] Then
          begin
            Friends[High(Friends)].Online := True;
            break;
          end;
    End;
  End;

  TempList.Free;
  SetLength(FriendsOnline, 0);
  iHTTP := nil;

  // at this moment array Friends contains our list of friends at the server

  // checking each contact in our Miranda's list
  hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
	while hContact <> 0 do
  begin
    // by default MS_DB_CONTACT_FINDFIRST returns all contacts found
    // next line verifies that found contact belongs to our protocol
    if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, lParam(PChar(piShortName))) <> 0 Then
    begin
      // make all our contacts in Miranda by default not Friends
  		DBWriteContactSettingByte(hContact, piShortName, 'Friend', 0);

      // updating status & nick of existing contacts
      for i:=Low(Friends) to High(Friends) do
        if (Friends[i].ID = DBGetContactSettingDword(hContact, piShortName, 'ID', 0)) and (Friends[i].ID<>0) Then
        Begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Updating data of existing contact, id: '+IntToStr(Friends[i].ID)+', nick: '+Friends[i].Name));
          Friends[i].InList := True;
          DBWriteContactSettingString(hContact, piShortName, 'Nick', PChar(Friends[i].Name));
      		DBWriteContactSettingByte(hContact, piShortName, 'Friend', 1); // found on server list - making friend
          if Friends[i].Online Then
          begin
            if DBGetContactSettingWord(hContact, piShortName, 'Status', ID_STATUS_OFFLINE) <> ID_STATUS_ONLINE then
       	      DBWriteContactSettingWord(hContact, piShortName, 'Status', ID_STATUS_ONLINE);
          end
          Else
          begin
            if DBGetContactSettingWord(hContact, piShortName, 'Status', ID_STATUS_OFFLINE) <> ID_STATUS_OFFLINE then
              DBWriteContactSettingWord(hContact, piShortName, 'Status', ID_STATUS_OFFLINE);
          end;
          Break;
        End;
    end;
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
	end;

  // probably, new Friends appeared on the server - should add them to contact list
  for i:=0 to High(Friends) do
  if Not Friends[i].InList Then
  Begin
    if Friends[i].Online Then
        vk_AddFriend(Friends[i].ID, Friends[i].Name, ID_STATUS_ONLINE, 1)
    Else
        vk_AddFriend(Friends[i].ID, Friends[i].Name, ID_STATUS_OFFLINE, 1);
  End;

  CoUninitialize();

  vk_StatusAdditionalGet(); // get additional statuses of friends

  Result := High(Friends); // function returns number of Friends on the server

end;


// =============================================================================
// procedure to delete friend from the server
// -----------------------------------------------------------------------------
procedure vk_DeleteFriend(FriendID: Integer);
begin
  // GAP (?): result is not validated
  HTTP_NL_Get(Format(vk_url_frienddelete, [FriendID]), REQUEST_HEAD);
end;

// =============================================================================
// procedure to find contacts
// find first 20 contacts
// -----------------------------------------------------------------------------
procedure vk_SearchFriends(cName, cSurname: String; searchID: Integer);
var
    HTML: String;
    iHTTP: IHTMLDocument2; // these 2 variables required for
    v: Variant;            // String -> IHTMLDocument2 conversions
    FoundTemp: TStringList;
    i: Byte;
    TempInteger: Integer;
    FriendDetails_temp: String;
    FoundCount: Integer;

    psre: TPROTOSEARCHRESULT_VK; // to keep search results

    FriendStatus,
    FriendID,
    FriendFullName,
    FriendNick,
    FriendFirstName,
    FriendLastName,
    FriendSecID: String;

    FriendFN: TFriendName;

begin
  HTML := HTTP_NL_Get(Format(vk_url_searchbyname,[cName, cSurname, 0]));

  if Not TryStrToInt(TextBetween(HTML, 'Найдено ', ' человек'), FoundCount) Then
    FoundCount := 10;

  if FoundCount > 10 Then // get next 10 found contacts
    HTML := HTML + HTTP_NL_Get(Format(vk_url_searchbyname,[cName, cSurname, 10]));


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
      FoundTemp := getElementsByAttr(iHTTP, 'div', 'classname', 'result clearFix');
      for i:=0 to FoundTemp.Count-1 do
      Begin
        FriendDetails_temp := TextBetweenInc(FoundTemp.Strings[i],'<DIV class=info>','</LI>');

        FriendID := TextBetween(FriendDetails_temp, 'friend.php?id=', '">');
        FriendFullName := HTMLRemoveTags(Trim(TextBetween(FriendDetails_temp, '<DT>Имя:', '<DT>')));
        if FriendFullName='' Then
          FriendFullName := HTMLRemoveTags(Trim(TextBetween(FriendDetails_temp, '<DT>Имя:', '</DD>')));
        FriendSecID := TextBetween(FoundTemp.Strings[i], '&amp;h=', '">Добавить в друзья');
        FriendStatus := TextBetween(FriendDetails_temp, '<span class=''bbb''>', '</span>');

        if TryStrToInt(FriendID, TempInteger) and (FriendID<>'') and (FriendFullName<>'') and (FriendSecID<>'') Then
        Begin
          FriendFN := FullNameToNameSurnameNick(FriendFullName);
          FriendNick := FriendFullName; // FriendFN.Nick;
          FriendFirstName := FriendFN.FirstName;
          FriendLastName := FriendFN.LastName;

          FillChar(psre, sizeof(psre), 0);
          psre.psr.cbSize := sizeOf(psre);
          psre.psr.nick := PChar(FriendNick);
          psre.psr.firstName := PChar(FriendFirstName);
          psre.psr.lastName := PChar(FriendLastName);
          psre.psr.email := PChar('');
          psre.id := FriendID;
          psre.SecureID := FriendSecID;
          if FriendStatus = 'Online' then
            psre.Status := ID_STATUS_ONLINE
          Else
            psre.Status := ID_STATUS_OFFLINE;

          // add contacts to search results
          ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_DATA, THandle(searchID), lParam(@psre));
        End;
      End;
    End;

  End;
  CoUninitialize();

end;

// =============================================================================
// procedure to make our user online on the server
// -----------------------------------------------------------------------------
procedure vk_KeepOnline();
begin
  // we don't care about result
  // we also don't need page html body, so request head only
  HTTP_NL_Get(vk_url_pda_keeponline, REQUEST_HEAD);
end;

// =============================================================================
// procedure to read OUR name and ID
// -----------------------------------------------------------------------------
procedure vk_GetUserNameID();
var UserName, UserID: String;
    HTML: String;
begin
  // {"user": {"id": 999999, "name": "Автор плагина"}, ...
  HTML := HTTP_NL_Get(vk_url_username);
  UserID := TextBetween(HTML, '"id": ', ',');
  UserName := TextBetween(HTML, '"name": "', '"');

  if UserName <> '' Then
    DBWriteContactSettingString (0, piShortName, 'Nick', PChar(UserName));
  if UserID <> '' Then
    DBWriteContactSettingString (0, piShortName, 'ID', PChar(UserID));
end;

// =============================================================================
// procedure to change the status of all contacts to offline
// -----------------------------------------------------------------------------
procedure SetStatusOffline();
var hContact: THandle;
begin
  hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
	while hContact <> 0 do
  begin
    if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, lParam(PAnsiChar(piShortName))) <> 0 Then
      if DBGetContactSettingWord(hContact, piShortName, 'Status', ID_STATUS_OFFLINE) = ID_STATUS_ONLINE then
        DBWriteContactSettingDWord(hContact, piShortName, 'Status', ID_STATUS_OFFLINE);
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
	end;
end;

// =============================================================================
// function is called when
// user deletes contact from list
// this function deletes it from the server
// -----------------------------------------------------------------------------
function ContactDeleted(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  if DBGetContactSettingByte(wParam, piShortName, 'Friend', 0) = 1 Then // delete from the server only contacts marked as Friend
    vk_DeleteFriend(DBGetContactSettingDword(wParam, piShortName, 'ID', 0));
  Result := 0;
end;

// =============================================================================
// function to add found contact to the list
// -----------------------------------------------------------------------------
function AddToList(wParam: wParam; lParam: lParam): Integer; cdecl;
var psre: PPROTOSEARCHRESULT_VK;
begin
  psre := PPROTOSEARCHRESULT_VK(lParam); // it contains data of contact, user trying to add

  // values below will be required for authorization request
  psre_id := StrToInt(String(PChar(psre.id)));
  psre_secureid := String(PChar(psre.SecureID));

  Result := vk_AddFriend(StrToInt(psre.id), psre.psr.nick, psre.Status, 0);

  // add the contact temporarily and invisibly, just to get user info or something
  If wParam = PALF_TEMPORARY Then
  Begin
    DBWriteContactSettingByte(Result, 'CList', 'NotOnList', 1);
		DBWriteContactSettingByte(Result, 'CList', 'Hidden', 1);
  End;
end;

// =============================================================================
// function allows to search contacts by name, surname and id
// -----------------------------------------------------------------------------
function SearchByName(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  searchId := 1;
  sbn := PPROTOSEARCHBYNAME(lParam)^; // put lParam into separate global variable
  FirstName_temp := sbn.pszFirstName;
  LastName_temp := sbn.pszLastName;

  // call separate thread to send the msg
  ThrIDSearchContacts := TThreadSearchContacts.Create(False);

  Result := searchId;
end;

// =============================================================================
// function to regular update user's status on the server (to keep online)
// -----------------------------------------------------------------------------
procedure TimerKeepOnline(Wnd: HWnd; Msg, TimerID, SysTime: Longint); stdcall;
begin
  Case vk_Status Of
    ID_STATUS_ONLINE:
      begin
        if not Assigned(ThrIDKeepOnline) then
          ThrIDKeepOnline := TThreadKeepOnline.Create(False);
      end;
    ID_STATUS_INVISIBLE:
      // SetStatus(ID_STATUS_INVISIBLE, 0);
  End;
end;

// =============================================================================
// function to regular update friends status
// -----------------------------------------------------------------------------
procedure TimerUpdateFriendsStatus(Wnd: HWnd; Msg, TimerID, SysTime: Longint); stdcall;
begin
  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
  begin
    If Assigned(ThrIDGetFriends) Then
      WaitForSingleObject(ThrIDGetFriends.Handle, 3000);
    ThrIDGetFriends := TThreadGetFriends.Create(False); // initiate new thread for this
  end;
end;


// =============================================================================
// connection thread
// -----------------------------------------------------------------------------
procedure TThreadConnect.Execute;
var
  ThreadNameInfo: TThreadNameInfo;
  vk_Status_Temp: Integer;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(TThreadConnect) Thread started...'));

  ThreadNameInfo.FType := $1000;
  ThreadNameInfo.FName := 'TThreadConnect';
  ThreadNameInfo.FThreadID := $FFFFFFFF;
  ThreadNameInfo.FFlags := 0;
  try
    RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
  except
  end;

  // change status to online or invisible
  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
    Begin
      // changing status to connecting first
      vk_Status_Temp := vk_Status;
      vk_Status := ID_STATUS_CONNECTING;
      ProtoBroadcastAck(piShortName,
        0,
        ACKTYPE_STATUS,
        ACKRESULT_SUCCESS,
        THANDLE(vk_StatusPrevious),
        vk_Status);
      // connecting to the server
      vk_Status := vk_Connect();
      if vk_Status <> 0 Then // error occuried
      begin
          vk_Status := ID_STATUS_OFFLINE; // need to change status to offline
          ProtoBroadcastAck(piShortName, 0, ACKTYPE_LOGIN, ACKRESULT_FAILED, 0, ErrorCode);
          case ErrorCode of
            LOGINERR_WRONGPASSWORD: MessageUser('Connection failed. Your e-mail or password was rejected.', MB_ICONSTOP);
            LOGINERR_NONETWORK: MessageUser('Connection failed. Unknown error during sign on.', MB_ICONSTOP);
          end;

      end
      else
          vk_Status := vk_Status_Temp;
    End;

  // really change the status
  ProtoBroadcastAck(piShortName,
    0,
    ACKTYPE_STATUS,
    ACKRESULT_SUCCESS,
    THANDLE(vk_StatusPrevious),
    vk_Status);

  // the code below should be executed only AFTER we informed miranda
  // that status is changed - otherwise other plugins are informed incorrectly
  if vk_Status = ID_STATUS_OFFLINE Then
  begin
    SetStatusOffline(); // make all contacts offline
    vk_Logout(); // call procedure from vk_parse to logout from the site
  end;
  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
  begin
    vk_GetFriends(); // read list of friends from the server
    vk_GetUserNameID(); // update OUR name and id
  end;

  ThrIDConnect := nil;

  Netlib_Log(vk_hNetlibUser, PChar('(TThreadConnect) ... thread finished'));
end;




// =============================================================================
// get friends thread
// -----------------------------------------------------------------------------
procedure TThreadGetFriends.Execute;
var
  ThreadNameInfo: TThreadNameInfo;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(TThreadGetFriends) Thread started...'));

  ThreadNameInfo.FType := $1000;
  ThreadNameInfo.FName := 'TThreadGetFriends';
  ThreadNameInfo.FThreadID := $FFFFFFFF;
  ThreadNameInfo.FFlags := 0;
  try
    RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
  except
  end;

 // call procedure from vk_parse to receive new messages
  vk_GetFriends();

  ThrIDGetFriends := nil;

  Netlib_Log(vk_hNetlibUser, PChar('(TThreadGetFriends) ... thread finished'));
end;


// =============================================================================
// search contacts thread
// -----------------------------------------------------------------------------
procedure TThreadSearchContacts.Execute;
var ThreadNameInfo: TThreadNameInfo;
begin
 Netlib_Log(vk_hNetlibUser, PChar('(TThreadSearchContacts) Thread started...'));

 ThreadNameInfo.FType := $1000;
 ThreadNameInfo.FName := 'TThreadSearchContacts';
 ThreadNameInfo.FThreadID := $FFFFFFFF;
 ThreadNameInfo.FFlags := 0;
 try
   RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
 except
 end;

//  MessageBox(0, PChar(FirstName_temp), PChar(LastName_temp), MB_OK);

  // search when online is possible only
  if (vk_Status <> ID_STATUS_ONLINE) and (vk_Status <> ID_STATUS_INVISIBLE) Then
    MessageBox(0, PChar(StringReplace(Translate(err_search_noconnection), '%s', piShortName, [rfReplaceAll])), Translate(err_search_title), MB_OK or MB_ICONERROR)
  Else
    // call function from vk_parse
    vk_SearchFriends(FirstName_temp, LastName_temp, searchID);

  // search is finished
  ProtoBroadcastAck(piShortName, 0, ACKTYPE_SEARCH, ACKRESULT_SUCCESS, THandle(searchId), 0);

  searchID := -1;

  Netlib_Log(vk_hNetlibUser, PChar('(TThreadSearchContacts) ... thread finished'));
end;


// =============================================================================
// thread to keep us online
// -----------------------------------------------------------------------------
procedure TThreadKeepOnline.Execute;
var ThreadNameInfo: TThreadNameInfo;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(TThreadKeepOnline) Thread started...'));

  ThreadNameInfo.FType := $1000;
  ThreadNameInfo.FName := 'TThreadKeepOnline';
  ThreadNameInfo.FThreadID := $FFFFFFFF;
  ThreadNameInfo.FFlags := 0;
  try
    RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
  except
  end;

  vk_KeepOnline(); // call procedure from vk_parse to make us online on the server
  ThrIDKeepOnline := nil;

  Netlib_Log(vk_hNetlibUser, PChar('(TThreadKeepOnline) ... thread finished'));
end;

begin
end.
