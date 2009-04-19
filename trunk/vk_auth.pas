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
 vk_auth.pas

 [ Description ]
 Module to support authorization process

 [ Known Issues ]
 See the code

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_auth;

interface

uses
  m_globaldefs,
  m_api,

  Windows;

  procedure AuthInit();
  procedure AuthDestroy();
  procedure vk_AuthRequestSend(ID: Integer; MessageText: String);
  function DlgAuthAsk(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;

implementation

uses
  vk_global, // module with global variables and constant used
  vk_http, // module to connect with the site
  vk_opts, // unit to work with options
  htmlparse, // module to simplify html parsing

  Messages,
  SysUtils,
  Classes; 

type
  TAuthRequest = record
    ID: Integer;
    MessageText: String;
  end;

var
  vk_hAuthRequestSend,
  vk_hAuthRequestReceived,
  vk_hAuthRequestReceivedAllow,
  vk_hAuthRequestReceivedDeny: THandle;

  AuthRequestID: Integer; // temp variable to keep ID of contact, whom we are trying to get authorization from

// =============================================================================
// procedure to request authorization
// -----------------------------------------------------------------------------
procedure vk_AuthRequestSend(ID: Integer; MessageText: String);
var HTML: String;
    SecureID: String;
begin
  HTML := HTTP_NL_Get(Format(vk_url_auth_securityid, [ID]));
  if Trim(HTML) <> '' then
  begin
    SecureID := TextBetween(HTML, 'id=\"h\" value=\"', '\"');
    if Trim(SecureID) <> '' then
    begin
      MessageText := URLEncode(MessageText); // encode all Russian and other characters
      // GAP (?): we don't care about result as of now
      // we also don't need page html body, so request head only
      // text for verification - получил уведомление и подтвердит, что Вы его друг
      HTTP_NL_Get(Format(vk_url_authrequestsend, [ID, SecureID, MessageText]));
   end;   
 end;
end;

// =============================================================================
// procedure to accept somebody's request to add us to their contact (friend's) list
// -----------------------------------------------------------------------------
procedure vk_AuthRequestReceivedAllow(ID: String);
var HTML: String;
    RequestID: String;
    RequestIDint: Integer;
begin
  // first we have to get request's id
  HTML := HTTP_NL_Get(vk_url_authrequestreceived_requestid);
  Delete(HTML, 1, Pos('friendShownName'+ID, HTML));
  RequestID := TextBetween(HTML, 'processRequest(', ',');

  if TryStrToInt(RequestID, RequestIDint) then
    // GAP (?): we don't care about result as of now
    HTTP_NL_Get(Format(vk_url_authrequestreceivedallow, [StrToInt(RequestID)]), REQUEST_HEAD);
end;

// =============================================================================
// procedure to deny somebody's request to add us to their contact (friend's) list
// -----------------------------------------------------------------------------
procedure vk_AuthRequestReceivedDeny(ID: String);
var HTML: String;
    RequestID: String;
    RequestIDint: Integer;
begin
  // first we have to get request's id
  HTML := HTTP_NL_Get(vk_url_authrequestreceived_requestid);
  Delete(HTML, 1, Pos('friendShownName'+ID, HTML));
  RequestID := TextBetween(HTML, 'processRequest(', ',');

  if TryStrToInt(RequestID, RequestIDint) then
    // GAP (?): we don't care about result as of now
    HTTP_NL_Get(Format(vk_url_authrequestreceiveddeny, [RequestIDint]), REQUEST_HEAD);
end;

// =============================================================================
// function is called when user tries to add contact and requests authorization
// -----------------------------------------------------------------------------
function AuthRequestSend(wParam: wParam; lParam: lParam): Integer; cdecl;
var ccs_ar: PCCSDATA;
begin
  ccs_ar := PCCSDATA(lParam);
  // call function to send authorization request
  vk_AuthRequestSend(psreID, PChar(ccs_ar.lParam));
  Result := 0;
end;

// =============================================================================
// function to process received authorization request
// -----------------------------------------------------------------------------
function AuthRequestReceived(wParam: wParam; lParam: lParam): Integer; cdecl;
var ccs_ar: PCCSDATA;
    dbeo, dbei: TDBEVENTINFO; // varibables required to add auth request to Miranda DB
    pre: TPROTORECVEVENT;
    hEvent, hContact: THandle;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(AuthRequestReceived) New authorization request adding to DB...'));

  ccs_ar := PCCSDATA(lParam);
  pre := PPROTORECVEVENT(ccs_ar.lParam)^;

  // look for presence of the same request in db
  // if here - no need to add the same again
  hEvent := pluginLink^.CallService(MS_DB_EVENT_FINDLAST, 0, 0);
	while hEvent <> 0 do
  begin
    FillChar(dbei, SizeOf(dbei), 0);
    dbei.cbSize := SizeOf(dbei);
    dbei.cbBlob := PluginLink^.CallService(MS_DB_EVENT_GETBLOBSIZE, hEvent, 0);
    dbei.pBlob := AllocMem(dbei.cbBlob);
    PluginLink^.CallService(MS_DB_EVENT_GET, hEvent, windows.lParam(@dbei));
    Inc(dbei.pBlob, sizeof(DWord)); // skip id
    hContact := PHandle(dbei.pBlob)^;
    if (dbei.szModule = piShortName) and // potential BUG - logic may be incorrect
       (dbei.eventType = EVENTTYPE_AUTHREQUEST) and
       (hContact = ccs_ar^.hContact) Then
       begin // duplicate request
         Netlib_Log(vk_hNetlibUser, PChar('(AuthRequestReceived) ... duplicate authorization request'));
         Result := 0;
         Exit;
       end;
    hEvent := pluginLink^.CallService(MS_DB_EVENT_FINDPREV, hEvent, 0);
	end;


  FillChar(dbeo, SizeOf(dbeo), 0);
  With dbeo Do
  Begin
    cbSize   := SizeOf(dbeo);
    eventType := EVENTTYPE_AUTHREQUEST;    // auth request
    szModule := piShortName;
    pBlob    := PByte(pre.szMessage);      // data
    cbBlob   := pre.lParam;
    flags    := DBEF_UTF;
    timestamp := pre.timestamp;
  End;

  PluginLink^.CallService(MS_DB_EVENT_ADD, 0, dword(@dbeo));

  Result := 0;

  Netlib_Log(vk_hNetlibUser, PChar('(AuthRequestReceived) ... finished new authorization request adding to DB'));
end;


// =============================================================================
// function is called when somebody is looking for our authorization and
// we authorize him/her
// -----------------------------------------------------------------------------
function AuthRequestReceivedAllow(wParam: wParam; lParam: lParam): Integer; cdecl;
var dbei: TDBEVENTINFO;
    // nick: PChar;
    hContact: THandle;
begin
  // wParam : HDBEVENT
  // nick, firstname, lastName, e-mail, requestReason: ASCIIZ;
  FillChar(dbei, SizeOf(dbei), 0);
  dbei.cbSize := SizeOf(dbei);
  dbei.cbBlob := PluginLink^.CallService(MS_DB_EVENT_GETBLOBSIZE, wParam, 0);
  dbei.pBlob := AllocMem(dbei.cbBlob);
  PluginLink^.CallService(MS_DB_EVENT_GET, wParam, windows.lParam(@dbei));

  if (dbei.eventType <> EVENTTYPE_AUTHREQUEST) or // not auth request
    (StrComp(dbei.szModule, piShortName)<>0) then // not for our plugin
  begin
    result := 1;
    exit;
  end;

  Inc(dbei.pBlob, sizeof(DWord)); // skip id
  hContact := PHandle(dbei.pBlob)^;

  if hContact<>0 then
  begin
    // call function to accept authorization on site
    vk_AuthRequestReceivedAllow(IntToStr(DBGetContactSettingDword(hContact, piShortName, 'ID', 0)));
    // immediately add contact to our list (really we just show hidden contact)
    DBWriteContactSettingByte(hContact, 'CList', 'NotOnList', 0);
  	DBWriteContactSettingByte(hContact, 'CList', 'Hidden', 0);
  end;

  Result := 0;
end;

// =============================================================================
// function is called when somebody is looking for our authorization and
// we DON'T authorize him/her
// -----------------------------------------------------------------------------
function AuthRequestReceivedDeny(wParam: wParam; lParam: lParam): Integer; cdecl;
var dbei: TDBEVENTINFO;
    hContact: THandle;
begin
  // wParam : HDBEVENT
  // nick, firstname, lastName, e-mail, requestReason: ASCIIZ;
  FillChar(dbei, SizeOf(dbei), 0);
  dbei.cbSize := SizeOf(dbei);
  dbei.cbBlob := PluginLink^.CallService(MS_DB_EVENT_GETBLOBSIZE, wParam, 0);
  dbei.pBlob := AllocMem(dbei.cbBlob);
  PluginLink^.CallService(MS_DB_EVENT_GET, wParam, windows.lParam(@dbei));

  if (dbei.eventType <> EVENTTYPE_AUTHREQUEST) or // not auth request
    (StrComp(dbei.szModule, piShortName)<>0) then // not for our plugin
  begin
    result := 1;
    exit;
  end;

  Inc(dbei.pBlob, sizeof(DWord)); // skip id
  hContact := PHandle(dbei.pBlob)^;

  if hContact<>0 then
    // call function to deny authorization on site
    vk_AuthRequestReceivedDeny(IntToStr(DBGetContactSettingDword(hContact, piShortName, 'ID', 0)));

  Result := 0;
end;

// =============================================================================
// function to read Secure ID to request authorization
// (used only for contacts, which are already in contact list,
// for search another procedure is used)
// -----------------------------------------------------------------------------
function vk_GetSecureIDAuthRequest(UserID: Integer): String;
var HTML: String;
begin
  HTML := HTTP_NL_Get(Format(vk_url_searchbyid, [UserID]));
  Result := TextBetween(HTML, '&h=', '">Добавить в друзья');
end;

// =============================================================================
// procedure to request authorization - run in a separate thread
// -----------------------------------------------------------------------------
procedure AuthAsk(AuthRequest: TAuthRequest);
var SecureID: String;
begin
  SecureID := vk_GetSecureIDAuthRequest(AuthRequest.ID);
  if Trim(SecureID) <> '' then
    vk_AuthRequestSend(AuthRequest.ID, AuthRequest.MessageText);
end;

// =============================================================================
// Dialog function to ask Auth request text
// -----------------------------------------------------------------------------
function DlgAuthAsk(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
var
  str: WideString;  // temp variable for types conversion
  pc: PWideChar;    // temp variable for types conversion
  res: LongWord;
  AuthRequest: TAuthRequest;
begin
  Result := False;
  case Msg of
     WM_INITDIALOG:
       begin
         // translate all dialog texts
         TranslateDialogDefault(Dialog);
         AuthRequestID := DBGetContactSettingDWord(lParam, piShortName, 'ID', 0);
         SetFocus(GetDlgItem(Dialog, VK_AUTH_TEXT));
       end;
     WM_CLOSE:
       begin
         EndDialog(Dialog, 0);
         Result := True;
       end;
     WM_COMMAND:
       begin
         case wParam of
           VK_AUTH_OK:
             begin
               SetLength(Str, 2048);
               pc := PWideChar(Str);
               GetDlgItemTextW(Dialog, VK_AUTH_TEXT, pc, 2048);
               AuthRequest.MessageText := pc;
               AuthRequest.ID := AuthRequestID;
               // request authorization in a separate thread
               if AuthRequest.ID <> 0 then
                 CloseHandle(BeginThread(nil, 0, @AuthAsk, @AuthRequest, 0, res));
               EndDialog(Dialog, 0);
               Result := True;
             end;
           VK_AUTH_CANCEL:
             begin
               EndDialog(Dialog, 0);
               Result := True;
             end;
         end;
       end;
  end;
end;


// =============================================================================
// function to initiate authorization process support
// -----------------------------------------------------------------------------
procedure AuthInit();
begin
  vk_hAuthRequestSend := CreateProtoServiceFunction(piShortName, PSS_AUTHREQUEST, AuthRequestSend);
  vk_hAuthRequestReceived := CreateProtoServiceFunction(piShortName, PSR_AUTH, AuthRequestReceived);
  vk_hAuthRequestReceivedAllow := CreateProtoServiceFunction(piShortName, PS_AUTHALLOW, AuthRequestReceivedAllow);
  vk_hAuthRequestReceivedDeny := CreateProtoServiceFunction(piShortName, PS_AUTHDENY, AuthRequestReceivedDeny);
end;

// =============================================================================
// function to destroy authorization process support
// -----------------------------------------------------------------------------
procedure AuthDestroy();
begin
  pluginLink^.DestroyServiceFunction(vk_hAuthRequestSend);
  pluginLink^.DestroyServiceFunction(vk_hAuthRequestReceived);
  pluginLink^.DestroyServiceFunction(vk_hAuthRequestReceivedAllow);
  pluginLink^.DestroyServiceFunction(vk_hAuthRequestReceivedDeny);
end;



begin
end.
