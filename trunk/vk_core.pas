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
  vk_msgs, // module to send/receive messages
  vk_xstatus, // module to support additional status
  vk_opts, // my unit to work with options
  vk_popup, // module to support popups
  vk_wall, // module to work with the wall

  htmlparse, // module to simplify html parsing

  Windows,
  Messages,
  SysUtils,
  Classes,
  ShellAPI,
  StrUtils,
  Commctrl;

  function vk_SetStatus(NewStatus: Integer): Integer;
  function vk_AddFriend(frID: Integer; frNick: WideString; frStatus: Integer; frFriend: Byte): Integer;
  procedure SetStatusOffline();
  function ContactDeleted(wParam: wParam; lParam: lParam): Integer; cdecl;
  procedure UpdateDataInit();
  procedure UpdateDataDestroy();
  procedure vk_Logout();
  function OnCreateAccMgrUI(wParam: wParam; lParam: lParam): Integer; cdecl;

{$include res\dlgopt\i_const.inc} // contains list of ids used in dialogs

type
  TThreadConnect = class(TThread)
  private
     { Private declarations }
  protected
    procedure Execute; override;
  end;
  TThreadDataUpdate = class(TThread)
  private
    { Private declarations }
  protected
    procedure Execute; override;
  end;

var
  ThrIDConnect: TThreadConnect;
  ThrIDDataUpdate: TThreadDataUpdate;

implementation

// var


// =============================================================================
// Account Manager Login function
// -----------------------------------------------------------------------------
function DlgAccMgr(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
var
  str: String;  // temp variable for types conversion
  pc: PChar;
begin
  Result:=False;
  case Msg of
     WM_INITDIALOG:
       begin
         // translate all dialog texts
         TranslateDialogDefault(Dialog);
         // read login from settings, if exists
         vk_o_login := DBReadString(0, piShortName, opt_UserName, nil);
         SetDlgItemText(Dialog, VK_ACCMGR_EMAIL, PChar(vk_o_login)); // e-mail
         if vk_o_login <> '' then
           SetFocus(GetDlgItem(Dialog, VK_ACCMGR_PASS));
         // read pass
         vk_o_pass := DBReadString(0, piShortName, opt_UserPass, nil);
         if trim(vk_o_pass) <> '' Then // decrypt password
         begin
           pluginLink^.CallService(MS_DB_CRYPT_DECODESTRING, SizeOf(vk_o_pass), Windows.lparam(vk_o_pass));
           SetDlgItemText(dialog, VK_ACCMGR_PASS, PChar(vk_o_pass)); // password
         end;  

         Result := True;
       end;
     WM_CLOSE:
       begin
         EndDialog(Dialog, 0);
         Result := False;
       end;
     WM_NOTIFY:
       begin
         // if user pressed Apply
         if PNMHdr(lParam)^.code = PSN_APPLY then
           begin
             SetLength(Str, 256);
             pc := PChar(Str);
             GetDlgItemText(Dialog, VK_ACCMGR_EMAIL, pc, 256);
             DBWriteContactSettingString (0, piShortName, opt_UserName, pc);
             vk_o_login := pc;

             SetLength(Str, 256);
             pc := PChar(Str);
             GetDlgItemText(Dialog, VK_ACCMGR_PASS, pc, 256);
             // encode password
             pluginLink^.CallService(MS_DB_CRYPT_ENCODESTRING, SizeOf(pc), Windows.lparam(pc));
             DBWriteContactSettingString(0, piShortName, opt_UserPass, pc);
             vk_o_pass := pc;

             Result := True;
           end;
       end;
     WM_COMMAND:
       begin
         case wParam of
           VK_ACCMGR_NEWID:
             begin
               ShellAPI.ShellExecute(0, 'open', PAnsiChar(vk_url_prefix + vk_url_host + vk_url_register), nil, nil, 0);
               Result := True;
             end;
         end;
       end;
  end;
end;

// =============================================================================
// function to display dialog on Account Manager screen
// -----------------------------------------------------------------------------
function OnCreateAccMgrUI(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Result := CreateDialogParam(hInstance, MAKEINTRESOURCE('ACCMGR'), lParam, @DlgAccMgr, 0);
end;


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
  Result := False;
  case Msg of
     WM_INITDIALOG:
       begin
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
                 Result := True;
               end;
             end;
           IDCANCEL, VK_LOGIN_CANCEL:
             begin
               EndDialog(Dialog, 0);
               Result := True;
             end;
           VK_LOGIN_NEWID:
             begin
               ShellAPI.ShellExecute(0, 'open', PAnsiChar(vk_url_prefix + vk_url_host + vk_url_register), nil, nil, 0);
               Result := True;
             end;
         end;
       end;
  end;
end;


// =============================================================================
// function to change the status
// -----------------------------------------------------------------------------
function vk_SetStatus(NewStatus: Integer): Integer;
begin
  if Assigned(ThrIDConnect) then
  begin
    Result := 1; // failed, since status change is already in progress
    exit;
  end;
  if (NewStatus = vk_Status) then // if new status is equal to current status
  begin
     Result := 0; // ok, but has nothing to do
     exit;
  end;
  vk_StatusPrevious := vk_Status;
  vk_Status := NewStatus;
  // plugin doesn't support all statuses, but Miranda may try to
  // setup unsupported status (for ex., when user presses Ctrl+0..9)
  // so, we should have the following lines
  case vk_Status of
    ID_STATUS_AWAY,
    ID_STATUS_DND,
    ID_STATUS_OCCUPIED,
    ID_STATUS_FREECHAT,
    ID_STATUS_ONTHEPHONE,
    ID_STATUS_OUTTOLUNCH: vk_Status := ID_STATUS_ONLINE;
    ID_STATUS_NA: vk_Status := ID_STATUS_INVISIBLE;
  end;

  if not Assigned(ThrIDConnect) then
  begin
    // initiate new thread for connection & status update
    ThrIDConnect := TThreadConnect.Create(True);
    ThrIDConnect.FreeOnTerminate := True; // we can automatically terminate the thread
    ThrIDConnect.Resume;          // since result is not so important
  end;

  Result := 0;
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
    DialogBoxW(hInstance, MAKEINTRESOURCEW(WideString('LOGIN')), 0, @DlgLogin);
    if (vk_o_pass = '') or (vk_o_login = '') then
    begin
      ErrorCode := 1;  // LOGINERR_WRONGPASSWORD = 1;
      Result := ErrorCode;
      Exit;
    end;
  end;

  // here is real connection happens
  HTML := HTTP_NL_Get(Format(vk_url_pda_login, [vk_o_login, URLEncode(UTF8Encode(vk_o_pass))]));

  // no info received
  If trim(HTML) = '' Then
    ErrorCode := 6; // LOGINERR_TIMEOUT       = 6;

  // no internet connection or other netlib error
  If trim(HTML) = 'NetLib error occurred!' Then
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
function vk_AddFriend(frID: Integer; frNick: WideString; frStatus: Integer; frFriend: Byte): Integer;
var hContactNew: THandle; // handle to new contact
    hContact: THandle;
    DefaultGroup: WideString;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_AddFriend) Trying to add friend, id: '+IntToStr(frID)+', nick: '+String(frNick)));

  // duplicate match
  hContact := GetContactByID(frID);
  if hContact <> 0 then // contact already exists in Miranda's list
  Begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AddFriend) ... friend already exists, id: '+IntToStr(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0))+', nick: '+DBReadUnicode(hContact, piShortName, 'Nick', '')));
    Result := hContact;
    // remove temporary settings
    DBDeleteContactSetting(hContact, 'CList', 'NotOnList');
    DBDeleteContactSetting(hContact, 'CList', 'Hidden');
    Exit;
  End;

  // if really new contact
  hContactNew := pluginLink^.CallService(MS_DB_CONTACT_ADD, 0, 0);
  If hContactNew <> 0 Then
  Begin
    DBWriteContactSettingDWord(hContactNew, piShortName, 'ID', frID);
    DBWriteContactSettingUnicode(hContactNew, piShortName, 'Nick', PWideChar(frNick));
    DBWriteContactSettingByte(hContactNew, piShortName, 'Friend', frFriend);
    if DBGetContactSettingByte(0, piShortName, opt_UserVKontakteURL, 0) = 1 then
      DBWriteContactSettingString(hContactNew, piShortName, 'Homepage', PChar(Format(vk_url_prefix + vk_url_host + vk_url_friend,[frID])));

    // assign group for contact, if given in settings
    DefaultGroup := DBReadUnicode(0, piShortName, opt_UserDefaultGroup, nil);
    if DefaultGroup <> '' then
    begin
      PluginLink^.CallService(MS_CLIST_GROUPCREATE, 0, Windows.lParam(DefaultGroup));
      DBWriteContactSettingUnicode(hContactNew, 'CList', 'Group', PWideChar(WideString(DefaultGroup)));
    end;
  End;
  CallService(MS_PROTO_ADDTOCONTACT, hContactNew, lParam(PChar(piShortName)));

  If hContactNew <> 0 Then
  begin
    DBWriteContactSettingWord(hContactNew, piShortName, 'Status', frStatus);
    // remove temporary settings
    DBDeleteContactSetting(hContactNew, 'CList', 'NotOnList');
    DBDeleteContactSetting(hContactNew, 'CList', 'Hidden');
  end;

  Netlib_Log(vk_hNetlibUser, PChar('(vk_AddFriend) ... friend added'));
  Result := hContactNew;
end;

// =============================================================================
// procedure to define contact's status
// -----------------------------------------------------------------------------
procedure SetContactStatus(hContact: THandle; Status: Word);
begin
	if DBGetContactSettingWord(hContact, piShortName, 'Status', ID_STATUS_OFFLINE) <> Status then
	  DBWriteContactSettingWord(hContact, piShortName, 'Status', Status);
end;

// =============================================================================
// function to get status of non-friend contact
// -----------------------------------------------------------------------------
function vk_GetContactStatus(ContactID: Integer): Integer;
var HTML: String;
begin
  Result := ID_STATUS_OFFLINE;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetContactStatus) Getting status of non-friend contact ' + IntToStr(ContactID) + '...'));
  if vk_Status = ID_STATUS_ONLINE then
  begin
    HTML := HTTP_NL_Get(Format(vk_url_pda_friend, [ContactID])); // 1,5 Kb
    if Trim(HTML) <> '' then
    begin
	    if Pos('<span class="online">Online</span>', HTML) > 0 then
	      Result := ID_STATUS_ONLINE
	    else
	      Result := ID_STATUS_OFFLINE;
    end;
  end
  else // ID_STATUS_INVISIBLE
  begin
    HTML := HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_searchbyid, [ContactID]));  // 3 Kb
    if Trim(HTML) <> '' then
    begin
	    if Pos('<span class=''bbb''>Online</span>', HTML) > 0 then
	      Result := ID_STATUS_ONLINE
	    else
	      Result := ID_STATUS_OFFLINE;
    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetContactStatus) ... status of non-friend contact ' + IntToStr(ContactID) + ' is identified as ' + IntToStr(Result)));
end;

// =============================================================================
// function to get list of friends, their statuses and additional statuses
// -----------------------------------------------------------------------------
function vk_GetFriends(): integer;
type
  TFriends = record  // new type of record
    ID: Integer;
    Name: WideString;
    InList: Boolean;  // friend exists in Miranda's list
    Online: Boolean;  // friend is online
    Deleted: Boolean; // friend is deleted from Miranda's list
    AvatarURL: String;
    Rating: Integer;
    Group: Integer;
  end;

var
  hContact: THandle;
  HTML: String; // html content of the page received

  FriendsOnline: Array of Integer;
  FriendsDeleted: Array of Integer;
  Friends: Array of TFriends;
  TempList: TStringList;
  i: Integer;
  StrTemp1, StrTemp2: String;

begin

  // get friends online
  // status of friends is read only
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting online friends from the server...'));
  HTML := HTTP_NL_Post(vk_url_prefix + vk_url_host + vk_url_feed_friendsonline, '', '');
  if Trim(HTML) <> '' then
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting online friends details...'));
	  HTML := TextBetween(HTML, 'friends'':[','],''universities');
    if Trim(HTML) <> '' then
    begin
		  TempList := TStringList.Create();
		  TempList.Sorted := True; // list should be sorted and
		  TempList.Duplicates := dupIgnore; // duplicates shouldn't be allowed
      while Pos('[', HTML) > 0 do
      begin
        TempList.Add(TextBetween(HTML, '[', ','));
        if Pos(']', HTML) > 0 then
          Delete(HTML, 1, Pos(']', HTML))
        else break;  
      end;
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... ' + IntToStr(TempList.Count) + ' friend(s) online found'));
		  For i:=0 to TempList.Count-1 Do
		  Begin
			  SetLength(FriendsOnline, Length(FriendsOnline)+1);
			  TryStrToInt(TempList.Strings[i], FriendsOnline[High(FriendsOnline)]);
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... found online friend with id: ' + TempList.Strings[i]));
		  End;
		  TempList.Free;
    end;
  end;

  // identify deleted friends
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Find friends deleted from miranda''s contact list...'));
  StrTemp1 := DBReadString(0, piShortName, opt_UserFriendsDeleted, ''); // read list of deleted friends
  if Trim(StrTemp1) <> '' then
  begin
    TempList := TStringList.Create();
		TempList.Sorted := True; // list should be sorted and
    TempList.Duplicates := dupIgnore; // duplicates shouldn't be allowed
		TempList.Delimiter := ',';
    TempList.DelimitedText := StrTemp1;
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... ' + IntToStr(TempList.Count) + ' deleted friend(s) found'));
    For i:=0 to TempList.Count-1 Do
    Begin
      SetLength(FriendsDeleted, Length(FriendsDeleted)+1);
      TryStrToInt(TempList.Strings[i], FriendsDeleted[High(FriendsDeleted)]);
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... found deleted friend with id: ' + TempList.Strings[i]));
    End;
    TempList.Free;
  end;

  // get full list of friends
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting all friends from the server...'));
  // HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_feed_friends);
  HTML := HTTP_NL_Post(vk_url_prefix + vk_url_host + vk_url_feed_friends, '', '');
  if Trim(HTML) <> '' then
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Getting friends details...'));
    HTML := TextBetween(HTML, 'friends'':[',']]');
    if Trim(HTML) <> '' then
    begin
      HTML := HTML + ']';
      while Pos('[', HTML) > 0 do
      begin
        // [1234567,"Name Surname","http:\/\/cs123.vkontakte.ru\/u1234567\/b_d919d26a.jpg",9,"","Евгении",0,1,0,"05"]
        // 1234567, {f:'Name', l:'Surname'},{p:'http://cs1264.vkontakte.ru/u5545710/b_1234567.jpg',uy:'05',uf:12345,fg:5,to:'Name',r:63,f:0,u:123,ds:0}
        StrTemp1 := TextBetween(HTML, '[', ']');
        if Trim(StrTemp1) <> '' then
        begin
          StrTemp2 := Trim(Copy(StrTemp1, 1, Pos(',', StrTemp1)-1));
          SetLength(Friends, Length(Friends)+1);
          if TryStrToInt(StrTemp2, Friends[High(Friends)].ID) then
          begin
            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... found friend with id: ' + StrTemp2));
            StrTemp2 := TextBetween(StrTemp1, ',"', '",');
            Friends[High(Friends)].Name := HTMLDecodeW(StrTemp2);
            Friends[High(Friends)].AvatarURL := 'http' + TextBetween(StrTemp1, '"http', '"');
            Friends[High(Friends)].AvatarURL := StringReplace(Friends[High(Friends)].AvatarURL, '\/', '/', [rfReplaceAll]);
            // TryStrToInt(Trim(TextBetween(StrTemp1, 'r:', ',')), Friends[High(Friends)].Rating);
            // TryStrToInt(Trim(TextBetween(StrTemp1, 'fg:', ',')), Friends[High(Friends)].Group);

            Friends[High(Friends)].InList := False;
            // mark online friends
            Friends[High(Friends)].Online := False;
            for i := Low(FriendsOnline) to High(FriendsOnline) do
            begin
              if FriendsOnline[i] = Friends[High(Friends)].ID then
              begin
                Friends[High(Friends)].Online := True;
                break;
              end;
            end;
            // mark deleted friends
            Friends[High(Friends)].Deleted := False;
            for i := Low(FriendsDeleted) to High(FriendsDeleted) do
            begin
              if FriendsDeleted[i] = Friends[High(Friends)].ID then
              begin
                Friends[High(Friends)].Deleted := True;
                break;
              end;
            end;
          end
          else
            SetLength(Friends, Length(Friends)-1);
        end;

        Delete(HTML, 1, Pos(']', HTML));
      end;
    end;
  end;

  SetLength(FriendsOnline, 0);
  SetLength(FriendsDeleted, 0);

  // at this moment array Friends contains our list of friends at the server

  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) ... updating contacts status in miranda list...'));

  // checking each contact in our Miranda's list
  hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
	while hContact <> 0 do
  begin
    // by default MS_DB_CONTACT_FINDFIRST returns all contacts found
    // next line verifies that found contact belongs to our protocol
    if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, lParam(PChar(piShortName))) <> 0 Then
    begin
      // if it is not our separate News contact or The wall contact
      if (DBGetContactSettingDWord(hContact, piShortName, 'ID', 0) <> DBGetContactSettingDWord(0, piShortName, opt_NewsSeparateContactID, 1234)) and
         (DBGetContactSettingDWord(hContact, piShortName, 'ID', 0) <> DBGetContactSettingDWord(0, piShortName, opt_WallSeparateContactID, 666)) then
      begin
        // make all our contacts in Miranda by default not Friends
  		  DBWriteContactSettingByte(hContact, piShortName, 'Friend', 0);

        // updating status & nick of existing contacts
        for i:=Low(Friends) to High(Friends) do
          if (Friends[i].ID = DBGetContactSettingDWord(hContact, piShortName, 'ID', 0)) and (Friends[i].ID <> 0) Then
          begin
            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetFriends) Updating data of existing contact, id: '+IntToStr(Friends[i].ID)+', nick: '+String(Friends[i].Name)));
            Friends[i].InList := True;
            DBWriteContactSettingUnicode(hContact, piShortName, 'Nick', PWideChar(HTMLDecodeW(Friends[i].Name)));
      	   	DBWriteContactSettingByte(hContact, piShortName, 'Friend', 1); // found on server list - making friend
            if Friends[i].Deleted Then
              DBWriteContactSettingByte(hContact, 'CList', 'Hidden', 1);
            if Friends[i].Online then
              SetContactStatus(hContact, ID_STATUS_ONLINE)
            else
              SetContactStatus(hContact, ID_STATUS_OFFLINE);
            Break;
          end;
        // if contact is not found in the server's list
        if DBGetContactSettingByte(hContact, piShortName, 'Friend', 1) = 0 then
          if DBGetContactSettingByte(0, piShortName, opt_UserNonFriendsStatusSupport, 0) = 1 then // check status of non-friends?
          begin
            SetContactStatus(hContact,
                             vk_GetContactStatus(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0)));
          end;
      end;
    end;
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
	end;
  // probably, new Friends appeared on the server - should add them to contact list
  for i:=0 to High(Friends) do
  begin
    if not Friends[i].InList then
    begin
      if Friends[i].Online then
          vk_AddFriend(Friends[i].ID, Friends[i].Name, ID_STATUS_ONLINE, 1)
      else
          vk_AddFriend(Friends[i].ID, Friends[i].Name, ID_STATUS_OFFLINE, 1);
    end;
  end;
  SetLength(Friends, 0);

  vk_StatusAdditionalGet(); // get additional statuses of friends

  Result := High(Friends); // function returns number of Friends on the server

end;


// =============================================================================
// procedure to delete friend from the server
// -----------------------------------------------------------------------------
procedure vk_DeleteFriend(FriendID: Integer);
begin
  HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_frienddelete, [FriendID]), REQUEST_HEAD)   // GAP (?): result is not validated
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
  // {"user": {"id": 999999, "name": "Name Nick Surname"}, ...
  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_username);
  UserID := TextBetween(HTML, '"id":', ',');
  UserName := TextBetween(HTML, '"name":"', '"');

  if UserName <> '' Then
    DBWriteContactSettingUnicode (0, piShortName, 'Nick', PWideChar(HTMLDecodeW(UserName)));
  if UserID <> '' Then
    DBWriteContactSettingDWord (0, piShortName, 'ID', StrToInt(UserID));
end;

// =============================================================================
// procedure to join given group
// -----------------------------------------------------------------------------
procedure vk_JoinGroup(GroupID: Integer);
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_JoinGroup) Joining of the group ' + IntToStr(GroupID) + '...'));
  // GAP (?): result is not validated
  HTTP_NL_Get(Format(vk_url_pda_group_join, [GroupID]), REQUEST_HEAD);
  Netlib_Log(vk_hNetlibUser, PChar('(vk_JoinGroup) ... finished joining of the group ' + IntToStr(GroupID)));
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
    if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, lParam(PChar(piShortName))) <> 0 Then
      SetContactStatus(hContact, ID_STATUS_OFFLINE);
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
	end;
end;

// =============================================================================
// function is called when
// user deletes contact from list
// this function deletes it from the server
// -----------------------------------------------------------------------------
function ContactDeleted(wParam: wParam; lParam: lParam): Integer; cdecl;
var StrTemp: String;
begin
  Result := 0;
  if DBGetContactSettingByte(wParam, piShortName, 'Friend', 0) = 1 Then // delete from the server only contacts marked as Friend
  begin
    if DBGetContactSettingByte(0, piShortName, opt_UserDontDeleteFriendsFromTheServer, 0) = 0 Then
      vk_DeleteFriend(DBGetContactSettingDWord(wParam, piShortName, 'ID', 0))
    else
    begin
      StrTemp := DBReadString(0, piShortName, opt_UserFriendsDeleted, '');
      if StrTemp <> '' then
        StrTemp := StrTemp + ',';
      StrTemp := StrTemp + IntToStr(DBGetContactSettingDWord(wParam, piShortName, 'ID', 0));
      DBWriteContactSettingString(0, piShortName, opt_UserFriendsDeleted, PChar(StrTemp)); // add contact to plugins list of deleted contacts
    end;
  end;
end;


// =============================================================================
// procedure to start thread for regular data update
// -----------------------------------------------------------------------------
procedure UpdateDataInit();
begin
  if not Assigned(ThrIDDataUpdate) then
    ThrIDDataUpdate := TThreadDataUpdate.Create(False);
end;

// =============================================================================
// procedure to finish thread for regular data update
// -----------------------------------------------------------------------------
procedure UpdateDataDestroy();
begin
  if Assigned(ThrIDDataUpdate) then
    begin
      ThrIDDataUpdate.Terminate;
      // WaitForSingleObject(ThrIDDataUpdate.Handle, 5000);
      ThrIDDataUpdate.WaitFor;
      FreeAndNil(ThrIDDataUpdate);
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

  PluginLink^.CallService(MS_SYSTEM_THREAD_PUSH, 0, 0);

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
      if not Terminated then // doing it only if thread is not being terminated
        vk_Status := vk_Connect();
      if vk_Status <> 0 Then // error occuried
      begin
          vk_Status := ID_STATUS_OFFLINE; // need to change status to offline
          ProtoBroadcastAck(piShortName, 0, ACKTYPE_LOGIN, ACKRESULT_FAILED, 0, ErrorCode);
          case ErrorCode of
            LOGINERR_WRONGPASSWORD: ShowPopupMsg(0, 'Error: Your e-mail or password was rejected', 2);
            LOGINERR_TIMEOUT: ShowPopupMsg(0, 'Error: Unknown error during sign on', 2);
            LOGINERR_NONETWORK: ShowPopupMsg(0, 'Error: Cannot connect to the server', 2);
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

  if Terminated then // if thread should be terminated (for ex., if miranda is being closed)
    Exit;

  // the code below should be executed only AFTER we informed miranda
  // that status is changed - otherwise other plugins are informed incorrectly
  if (vk_Status = ID_STATUS_OFFLINE) and
     (not Terminated) and
     (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 0) then
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(TThreadConnect) ... changing status to offline'));
    UpdateDataDestroy(); // stop the thread for regular data update
    SetStatusOffline(); // make all contacts offline
    vk_Logout(); // logout from the site
  end;
  if (vk_Status = ID_STATUS_INVISIBLE) Then
    vk_Logout(); // logout from the site
  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
  begin
    if not Terminated then
      vk_GetUserNameID(); // update OUR name and id
    // user agreed to join plugin's group (see OnModulesLoad)
    if DBGetContactSettingByte(0, piShortName, opt_GroupPluginJoined, 0) = 2 then
    begin
      DBWriteContactSettingByte (0, piShortName, opt_GroupPluginJoined, 3);
        vk_JoinGroup(6929403); // id of plugins group
    end;
    // write default value of last date & time of contacts' status update
    // so they will be updated again immediately in DataUpdate thread
    DBWriteContactSettingDWord (0, piShortName, opt_LastUpdateDateTimeFriendsStatus, 539033600);
    if not Terminated then // doing it only if thread is not being terminated
      UpdateDataInit(); // start separate thread for online data update
  end;


  ThrIDConnect := nil;

  PluginLink^.CallService(MS_SYSTEM_THREAD_POP, 0, 0);

  Netlib_Log(vk_hNetlibUser, PChar('(TThreadConnect) ... thread finished'));
end;

// =============================================================================
// update data thread
// -----------------------------------------------------------------------------
procedure TThreadDataUpdate.Execute;
var
  ThreadNameInfo: TThreadNameInfo;
  ContactIDNews,
  ContactIDWall: Integer;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) Thread started...'));

  ThreadNameInfo.FType := $1000;
  ThreadNameInfo.FName := 'TThreadDataUpdate';
  ThreadNameInfo.FThreadID := $FFFFFFFF;
  ThreadNameInfo.FFlags := 0;
  try
    RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
  except
  end;

  PluginLink^.CallService(MS_SYSTEM_THREAD_PUSH, 0, 0);

  // detecting news id handle
  if DBGetContactSettingByte(0, piShortName, opt_NewsSupport, 1) = 1 then
  begin
    // we need it only if getting news in a separate contact
    if DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0) = 1 then
    begin
      ContactIDNews := DBGetContactSettingDWord(0, piShortName, opt_NewsSeparateContactID, 1234);
      ContactIDNews := GetContactByID(ContactIDNews);
    end;
  end;
  // detecting wall id handle
  if DBGetContactSettingByte(0, piShortName, opt_WallReadSupport, 1) = 1 then
  begin
    // we need it only if getting wall messages in a separate contact
    if DBGetContactSettingByte(0, piShortName, opt_WallSeparateContactUse, 0) = 1 then
    begin
      ContactIDWall := DBGetContactSettingDWord(0, piShortName, opt_WallSeparateContactID, 666);
      ContactIDWall := GetContactByID(ContactIDWall);
    end;
  end;

  while true do // never ending cycle
  begin
    try
      if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) or // if thread termination is requested OR
         (ThrIDDataUpdate.Terminated) then  // miranda is being closed
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) ... miranda is being terminated, updates finished, point 1'));
        break;
      end;

      if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) then // additional check that current status is online or invisible
      begin                                                                       // however this thread should be run only when status is online or invisible
        // updating contacts' statuses
        if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_LastUpdateDateTimeFriendsStatus, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_UserUpdateFriendsStatus, 60)) / SecsPerDay then
        begin
            // write new value of last date & time of contacts' status update
            DBWriteContactSettingDWord (0, piShortName, opt_LastUpdateDateTimeFriendsStatus, DateTimeToFileDate(Now));
            vk_GetFriends();
        end;
        if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) or // check again if thread termination is requested OR
           (ThrIDDataUpdate.Terminated) then  // miranda is being closed
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) ... miranda is being terminated, updates finished, point 2 (after contacts statuses update)'));
          break;
        end;

        // checking for new messages received and for auth requests;   default value of last update is 539033600 = 1/1/1996 12:00 am
        if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_LastUpdateDateTimeMsgs, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_UserCheckNewMessages, 60)) / SecsPerDay then // code is equal to IncSecond function with negative value
        begin
            // write new value of last date & time of new message received
            DBWriteContactSettingDWord (0, piShortName, opt_LastUpdateDateTimeMsgs, DateTimeToFileDate(Now));
            vk_GetMsgsFriendsEtc();
        end;
        if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) or // check again if thread termination is requested OR
           (ThrIDDataUpdate.Terminated) then  // miranda is being closed
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) ... miranda is being terminated, updates finished, point 3 (after new msgs receiving)'));
          break;
        end;

        // updating avatars, if required
        if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsSupport, 1) = 1 then
        begin
          if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_LastUpdateDateTimeAvatars, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_UserAvatarsUpdateFreq, 60)) / SecsPerDay then
          begin
              // write new value of last date & time of new message received
              DBWriteContactSettingDWord (0, piShortName, opt_LastUpdateDateTimeAvatars, DateTimeToFileDate(Now));
              vk_AvatarsGet();
          end;
        end;

        // getting news, if required
        if DBGetContactSettingByte(0, piShortName, opt_NewsSupport, 1) = 1 then
        begin
          // if we use separate contact for News, then make the contact online
          if DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0) = 1 then
            SetContactStatus(ContactIDNews, ID_STATUS_ONLINE)
          {else  // let's not do it to simplify
            SetContactStatus(ContactIDNews, ID_STATUS_OFFLINE)};
          if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_NewsLastUpdateDateTime, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_NewsSecs, 300)) / SecsPerDay then
          begin
            // write new value of last date & time of new message received
            DBWriteContactSettingDWord (0, piShortName, opt_NewsLastUpdateDateTime, DateTimeToFileDate(Now));
            vk_GetNews();
          end;
        end
        else  // if news are not supported
        begin
          // if we used separate contact for News, then make the contact offline
          if DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0) = 1 then
            SetContactStatus(ContactIDNews, ID_STATUS_OFFLINE);
        end;
        if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) or // one more time...
           (ThrIDDataUpdate.Terminated) then  // miranda is being closed
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) ... miranda is being terminated, updates finished, point 5 (after news receiving)'));
          break;
        end;

        // getting groups news, if required
        if DBGetContactSettingByte(0, piShortName, opt_GroupsSupport, 1) = 1 then
          if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_GroupsLastUpdateDateTime, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_GroupsSecs, 300)) / SecsPerDay then
          begin
            // write new value of last date & time of new message received
            DBWriteContactSettingDWord (0, piShortName, opt_GroupsLastUpdateDateTime, DateTimeToFileDate(Now));
            vk_GetGroupsNews();
          end;

        // getting comment news, if required
        if DBGetContactSettingByte(0, piShortName, opt_CommentsSupport, 1) = 1 then
          if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_CommentsLastUpdateDateTime, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_CommentsSecs, 300)) / SecsPerDay then
          begin
            // write new value of last date & time of new message received
            DBWriteContactSettingDWord (0, piShortName, opt_CommentsLastUpdateDateTime, DateTimeToFileDate(Now));
            vk_GetCommentsNews();
          end;

        if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) or // one more time...
           (ThrIDDataUpdate.Terminated) then  // miranda is being closed
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) ... miranda is being terminated, updates finished, point 5 (after news receiving)'));
          break;
        end;

        // checking for new messages on the wall
        if DBGetContactSettingByte(0, piShortName, opt_WallReadSupport, 1) = 1 then
        begin
          // if we use separate contact for The Wall, then make the contact online
          if DBGetContactSettingByte(0, piShortName, opt_WallSeparateContactUse, 0) = 1 then
            SetContactStatus(ContactIDWall, ID_STATUS_ONLINE);
          if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_WallLastUpdateDateTime, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_WallUpdateFreq, 60)) / SecsPerDay then
          begin
            // write new value of last date & time of posts received
            DBWriteContactSettingDWord (0, piShortName, opt_WallLastUpdateDateTime, DateTimeToFileDate(Now));
            vk_WallGetMessages(0);
          end;
        end
        else // wall messages are not supported
        begin
          // if we used separate contact for News, then make the contact offline
          if DBGetContactSettingByte(0, piShortName, opt_WallSeparateContactUse, 0) = 1 then
            SetContactStatus(ContactIDWall, ID_STATUS_OFFLINE);
        end;
        if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) or // one more time...
           (ThrIDDataUpdate.Terminated) then  // miranda is being closed
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) ... miranda is being terminated, updates finished, point 6 (after msgs from the wall receiving)'));
          break;
        end;

      end;

      // keep status online, if required
      if (vk_Status = ID_STATUS_ONLINE) and (not ThrIDDataUpdate.Terminated) then
      begin
        if FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_LastUpdateDateTimeKeepOnline, 539033600)) <= ((Now * SecsPerDay) - DBGetContactSettingDWord(0, piShortName, opt_UserKeepOnline, 360)) / SecsPerDay then
        begin
            // write new value of last date & time of contacts' status update
            DBWriteContactSettingDWord (0, piShortName, opt_LastUpdateDateTimeKeepOnline, DateTimeToFileDate(Now));
            vk_KeepOnline();
        end;
      end;

    Sleep(1000);
    except
      on E: Exception do
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) Exception (' + IntToStr(E.HelpContext) + '): ' + E.Message));
        if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) or
           (ThrIDDataUpdate.Terminated) then
          break;
      end;
    end;
  end;

  PluginLink^.CallService(MS_SYSTEM_THREAD_POP, 0, 0);

  Netlib_Log(vk_hNetlibUser, PChar('(TThreadDataUpdate) ... thread finished'));
end;

begin
end.
