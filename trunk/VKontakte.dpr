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

library VKontakte;

uses
  m_globaldefs in 'api\m_globaldefs.pas',
  m_api in 'api\m_api.pas',

  vk_global, // module with global variables and constant used
  vk_http, // module to connect with the site
  vk_core, // module with core functions
  vk_menu, // module to work with menus
  vk_msgs, // module to send/receive messages
  vk_auth, // module to support authorization process
  vk_avatars, // module to support avatars
  vk_xstatus, // module to support additional status
  vk_info, // module to get contact's info
  vk_folders, // module to support custom folders
  vk_search, // module to support search functionality
  vk_popup, // module to support popups
  vk_wall, // module to work with the wall

  vk_opts, // unit to work with options

  Windows,
  SysUtils,

  uLkJSON in 'inc\uLkJSON.pas'; // module to parse data from feed2.php (in JSON format)

const

  // constants to provide information about plugin
  // values defined in vk_opts
  PluginInfoEx: TPLUGININFOEX = (
    cbSize: SizeOf(TPLUGININFOEX);
    shortName: piShortName;
    version: piVersion;
    description: piDescription;
    author: piAuthor;
    authorEmail: piAuthorEmail;
    copyright: piCopyright;
    homepage: piHomepage;
    flags: UNICODE_AWARE;
    replacesDefaultModule: 0;
    uuid: '{75A5596C-3AD4-4B17-ABEF-5D45DEAA4A83}'
  );

  PluginInfo: TPLUGININFO = (
    cbSize: SizeOf(TPLUGININFO);
    shortName: piShortName;
    version: piVersion;
    description: piDescription;
    author: piAuthor;
    authorEmail: piAuthorEmail;
    copyright: piCopyright;
    homepage: piHomepage;
    flags: UNICODE_AWARE;
    replacesDefaultModule: 0;
  );


var
  vk_hGetCaps,
  vk_hGetName,
  vk_hGetStatus,
  vk_hSetStatus,
  vk_hLoadIcon,
  vk_hOnCreateAccMgrUI,

  vk_hkContactDeleted,
  vk_hkModulesLoad,
  vk_hkOptInitialise,
  vk_hkHookShutdown,
  vk_hkHookOkToExit: THandle;


  // ccs: PCCSDATA;

  PluginInterfaces:array [0..1] of MUUID;

// =============================================================================
// functions to provide information about plugin
// -----------------------------------------------------------------------------
function MirandaPluginInfo(mirandaVersion: DWORD): PPLUGININFO; cdecl;
begin
  Result := @PluginInfo;
end;

function MirandaPluginInfoEx(mirandaVersion:DWORD): PPLUGININFOEX; cdecl;
begin
  Result := @PluginInfoEx;
end;

function MirandaPluginInterfaces:PMUUID; cdecl;
begin
  PluginInterfaces[0] := PluginInfoEx.uuid;
  PluginInterfaces[1] := MIID_LAST;
  result := @PluginInterfaces;
end;

// declaration of the functions, which will be defined later
function OnModulesLoad(wParam,lParam:DWord): Integer; cdecl; forward;
function PreShutdown(wParam: wParam; lParam: lParam): Integer; cdecl; forward;
function OkToExit(wParam: wParam; lParam: lParam): Integer; cdecl; forward;

// =============================================================================
// function to identify list of functions supported by the plugin
// -----------------------------------------------------------------------------
function GetCaps(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Case wParam Of
    PFLAGNUM_1:
      Result :=
        PF1_AUTHREQ or // will get authorisation requests for some or all contacts
        PF1_BASICSEARCH or // supports a basic user searching facility
        PF1_SEARCHBYNAME or // protocol supports searching by nick/first/last names
        PF1_EXTSEARCH or // supports one or more protocol-specific extended search schemes
        PF1_EXTSEARCHUI or // has a dialog box to allow searching all the possible fields
        PF1_ADDSEARCHRES or // can add search results to the contact list
        PF1_IM or // supports IM sending & receiving
        PFLAGNUM_1 or // will get authorisation requests for some or all contacts
        // PF1_NUMERICUSERID or // the unique user IDs for this protocol are numeric
        PF1_SERVERCLIST; // contact lists are stored on the server, not locally

    PFLAGNUM_2:
      Result := PF2_ONLINE or PF2_INVISIBLE; // list of statuses supported, just online & offline is required

    // PFLAGNUM_3 :
    // Result := PF2_ONLINE or PF2_LONGAWAY;

   PFLAGNUM_4:
      Result := // $00000100 or // PF4_IMSENDOFFLINE; protocol is able to send offline messages - this cause problems in miranda 0.8 b27 and higher
                PF4_AVATARS; // avatars supported

   PFLAG_UNIQUEIDTEXT:
     Result := Integer(Translate('ID')); // returns a static buffer of text describing the unique field by which this protocol identifies users
                                         // this name will be used for ex. in BASIC SEARCH

    PFLAG_MAXLENOFMESSAGE:
      Result := 2000;  // maximum length of one message

    PFLAG_UNIQUEIDSETTING:
      Result := Integer(PChar('ID')); // returns the DB setting name that has the ID which makes this user unique on that system

  Else
    Result := 0;
  End;
end;

// =============================================================================
// function to copy the name of the protocole into lParam
// -----------------------------------------------------------------------------
function GetName(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  if lParam <> 0 then
    StrLCopy(PChar(lParam), Translate(piShortName), wParam);
  Result := 0;
end;


// =============================================================================
// function to change the status and notifies everybody
// -----------------------------------------------------------------------------
function SetStatus(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  result := vk_SetStatus(wParam);
end;

// =============================================================================
// function to return the current status
// -----------------------------------------------------------------------------
function GetStatus(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Result := vk_Status;
end;

// =============================================================================
// function loads
// the icon corresponding to the status
// called by the CList when the status changes.
// wParam: one of the following values:
// PLI_PROTOCOL | PLI_ONLINE | PLI_OFFLINE
// returns an HICON in which the icon has been loaded
// -----------------------------------------------------------------------------
function LoadIcon(wParam: wParam; lParam: lParam): Integer; cdecl;
var
  id: string; // to store id of icon to be loaded
  cx: int;
  cy: int;
begin
  // regardless of the code below, this function is called only when
  // wParam = PLI_PROTOCOL and it is required to display proto icon
  // in Miranda's main menu -> Status

  case (wParam and $ffff) of
      PLI_PROTOCOL: id := 'ICON_PROTO'; // icon representing protocol
      PLI_ONLINE: id := 'ICON_ONLINE'; // online state icon for the protocol
      PLI_OFFLINE: id := 'ICON_OFFLINE'; // offline state icon for the protocol
    else
      Result := 0;
      Exit;
  end;

 if (bool(wParam and PLIF_SMALL)) then
    begin
      // if small icon - 16x16 by default
      cx := SM_CXSMICON;
      cy := SM_CYSMICON;
    end
    else
    begin
      // if big icon - 32x32 by default
      cx := SM_CXICON;
      cy := SM_CYICON
    end;

  Result := Int(LoadImage(hInstance,
  MAKEINTRESOURCE(PChar(id)),
  IMAGE_ICON,
  GetSystemMetrics(cx),
  GetSystemMetrics(cy),
  0));
end;

// =============================================================================
// function identifies what should be done when plugin is being loaded
// -----------------------------------------------------------------------------
function Load(link: PPLUGINLINK): integer; cdecl;
var
  pd: TPROTOCOLDESCRIPTOR;
  szTemp: array [0..255] of AnsiChar;
begin
  // the following two lines are VERY VERY important, if it's not present, expect crashes
  pluginLink := Pointer(link);
  InitMMI;

  // register new protocol
  FillChar(pd, sizeof(pd), 0);
  pd.cbSize := sizeof(pd);
  pd.szName := piShortName;
  pd._type := PROTOTYPE_PROTOCOL;
  pluginLink^.CallService(MS_PROTO_REGISTERMODULE, 0, lParam(@pd));

  // register additional services required for protocol
  vk_hGetCaps := CreateProtoServiceFunction(piShortName, PS_GETCAPS, @GetCaps);
  vk_hGetName := CreateProtoServiceFunction(piShortName, PS_GETNAME, @GetName);
  vk_hSetStatus := CreateProtoServiceFunction(piShortName, PS_SETSTATUS, @SetStatus);
  vk_hGetStatus := CreateProtoServiceFunction(piShortName, PS_GETSTATUS, @GetStatus);
  vk_hLoadIcon := CreateProtoServiceFunction(piShortName, PS_LOADICON, @LoadIcon);
  vk_hOnCreateAccMgrUI := CreateProtoServiceFunction(piShortName, PS_CREATEACCMGRUI, OnCreateAccMgrUI); // for Miranda 0.8+ Account Manager support

  ConnectionErrorsCount := 0;

  // get miranda's version
  MirandaVersion := CallService(MS_SYSTEM_GETVERSION, 0, 0);
  // identify Unicode miranda
  if CallService(MS_SYSTEM_GETVERSIONTEXT, MAX_PATH, DWord(@szTemp)) = 0 then
    if StrPos(szTemp, 'Unicode') <> nil then
      bMirandaUnicode := True;

  // register functions to support popups
  PopupInit();

  // register functions required to send and receive messages
  MsgsInit();

  // register functions to support search
  SearchInit();

  AuthInit();

  InfoInit();

  SetStatusOffline(); // make all contacts offline

  // hook event when contact is deleted & delete contact from Friends list on the server
  vk_hkContactDeleted := pluginLink^.HookEvent(ME_DB_CONTACT_DELETED, @ContactDeleted);

  // identifies the function OnModulesLoad(), which will be run once all
  // modules are loaded
  vk_hkModulesLoad := pluginLink^.HookEvent(ME_SYSTEM_MODULESLOADED, @OnModulesLoad);

  // hook events when Miranda is being closed
  vk_hkHookOkToExit := pluginLink^.HookEvent(ME_SYSTEM_OKTOEXIT, @OkToExit);
  vk_hkHookShutdown := pluginLink^.HookEvent(ME_SYSTEM_PRESHUTDOWN, @PreShutdown);

  Result := 0;
end;

// =============================================================================
// function, which run once all modules are loaded
// -----------------------------------------------------------------------------
function OnModulesLoad(wParam{0}, lParam{0}: DWord): Integer; cdecl;
begin
  // code to identify Options function
  vk_hkOptInitialise := pluginLink^.HookEvent(ME_OPT_INITIALISE, @OnOptInitialise);

  // updater compatibility data
  if PluginLink^.ServiceExists(MS_UPDATE_REGISTER)<>0 then
  begin
    // 3730 - id of the plugin on addons.miranda-im.org - http://addons.miranda-im.org/details.php?action=viewfile&id=3730
    PluginLink^.CallService(MS_UPDATE_REGISTERFL, 3730, Windows.lParam(@PluginInfo));
  end;

  // initiate Additional Status support
  AddlStatusInit();

  MenuInit();

  // initiate internet connection
  HTTP_NL_Init();

  // register avatars folder for Folders plugin
  FoldersInit();

  AvatarsInit();

  // temp code - to be removed in the next versions
  if DBGetContactSettingDWord(0, piShortName, 'UserKeepOnlineFreqSecs', 900) <> 900 then
    DBWriteContactSettingDWord(0, piShortName, opt_UserKeepOnline, DBGetContactSettingDWord(0, piShortName, 'UserKeepOnlineFreqSecs', 900));
  DBDeleteContactSetting(0, piShortName, 'UserKeepOnlineFreqSecs');
  if DBGetContactSettingDWord(0, piShortName, 'UserFriendsStatusFreqSecs', 60) <> 60 then
    DBWriteContactSettingDWord(0, piShortName, opt_UserUpdateFriendsStatus, DBGetContactSettingDWord(0, piShortName, 'UserFriendsStatusFreqSecs', 60));
  DBDeleteContactSetting(0, piShortName, 'UserFriendsStatusFreqSecs');
  if DBGetContactSettingByte(0, piShortName, 'UserInfoMinimal', 0) <> 0 then
    DBWriteContactSettingByte(0, piShortName, opt_UserGetMinInfo, DBGetContactSettingByte(0, piShortName, 'UserInfoMinimal', 0));
  DBDeleteContactSetting(0, piShortName, 'UserInfoMinimal');
  if DBReadString(0, piShortName, 'UserFriendsDeleted', '') <> '' then
    DBWriteContactSettingString(0, piShortName, opt_UserGetMinInfo, DBReadString(0, piShortName, 'UserFriendsDeleted', nil));
  DBDeleteContactSetting(0, piShortName, 'UserFriendsDeleted');
  if DBGetContactSettingByte(0, piShortName, 'UserMsgIncRemoveEmptySubject', 1) <> 1 then
    DBWriteContactSettingByte(0, piShortName, opt_UserRemoveEmptySubj, DBGetContactSettingByte(0, piShortName, 'UserMsgIncRemoveEmptySubject', 1));
  DBDeleteContactSetting(0, piShortName, 'UserMsgIncRemoveEmptySubject');
  if DBReadString(0, piShortName, 'UserDefaultGroup', '') <> '' then
    DBWriteContactSettingUnicode(0, piShortName, opt_UserGetMinInfo, PWideChar(WideString(DBReadString(0, piShortName, 'UserDefaultGroup', nil))));
  DBDeleteContactSetting(0, piShortName, 'UserDefaultGroup');
  if DBGetContactSettingByte(0, piShortName, 'UserAddlStatusUpdate', 1) <> 1 then
    DBWriteContactSettingByte(0, piShortName, opt_UserUpdateAddlStatus, DBGetContactSettingByte(0, piShortName, 'UserAddlStatusUpdate', 1));
  DBDeleteContactSetting(0, piShortName, 'UserAddlStatusUpdate');
  if DBGetContactSettingByte(0, piShortName, 'UserAvatarsSupport', 1) <> 1 then
    DBWriteContactSettingByte(0, piShortName, opt_UserAvatarsSupport, DBGetContactSettingByte(0, piShortName, 'UserAvatarsSupport', 1));
  DBDeleteContactSetting(0, piShortName, 'UserAvatarsSupport');
  if DBGetContactSettingDWord(0, piShortName, 'UserAvatarsUpdateFreqSecs', 3600) <> 3600 then
    DBWriteContactSettingDWord(0, piShortName, opt_UserKeepOnline, DBGetContactSettingDWord(0, piShortName, 'UserAvatarsUpdateFreqSecs', 3600));
  DBDeleteContactSetting(0, piShortName, 'UserAvatarsUpdateFreqSecs');
  if DBGetContactSettingByte(0, piShortName, 'UserAvatarsUpdateWhenGetInfo', 1) <> 1 then
    DBWriteContactSettingByte(0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, DBGetContactSettingByte(0, piShortName, 'UserAvatarsUpdateWhenGetInfo', 1));
  DBDeleteContactSetting(0, piShortName, 'UserAvatarsUpdateWhenGetInfo');
  if DBGetContactSettingByte(0, piShortName, 'UserInfoVKontaktePageURL', 0) <> 0 then
    DBWriteContactSettingByte(0, piShortName, opt_UserVKontakteURL, DBGetContactSettingByte(0, piShortName, 'UserInfoVKontaktePageURL', 0));
  DBDeleteContactSetting(0, piShortName, 'UserInfoVKontaktePageURL');
  if DBGetContactSettingByte(0, piShortName, 'UserAddlStatusForOfflineContacts', 1) <> 1 then
    DBWriteContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, DBGetContactSettingByte(0, piShortName, 'UserAddlStatusForOfflineContacts', 1));
  DBDeleteContactSetting(0, piShortName, 'UserAddlStatusForOfflineContacts');
  if DBGetContactSettingByte(0, piShortName, 'UserMsgIncUseLocalTime', 0) <> 0 then
    DBWriteContactSettingByte(0, piShortName, opt_UserUseLocalTimeForIncomingMessages, DBGetContactSettingByte(0, piShortName, 'UserMsgIncUseLocalTime', 0));
  DBDeleteContactSetting(0, piShortName, 'UserMsgIncUseLocalTime');
  if DBGetContactSettingByte(0, piShortName, 'UserDontDeleteFriendsFromTheServer', 1) <> 1 then
    DBWriteContactSettingByte(0, piShortName, opt_UserDontDeleteFriendsFromTheServer, DBGetContactSettingByte(0, piShortName, 'UserDontDeleteFriendsFromTheServer', 1));
  DBDeleteContactSetting(0, piShortName, 'UserDontDeleteFriendsFromTheServer');
  if DBGetContactSettingByte(0, piShortName, 'UserNonFriendsStatusSupport', 0) <> 0 then
    DBWriteContactSettingByte(0, piShortName, opt_UserNonFriendsStatusSupport, DBGetContactSettingByte(0, piShortName, 'UserNonFriendsStatusSupport', 0));
  DBDeleteContactSetting(0, piShortName, 'UserNonFriendsStatusSupport');
  DBDeleteContactSetting(0, piShortName, 'UserNewMessagesFreqSecs');


  // ask to join plugin's group
  if DBGetContactSettingByte(0, piShortName, opt_GroupPluginJoined, 0) = 0 then // never asked before
    case MessageBoxW(0, TranslateW(qst_join_vk_group), TranslateW(piShortName), MB_YESNOCANCEL + MB_ICONQUESTION) of
      IDYES: DBWriteContactSettingByte(0, piShortName, opt_GroupPluginJoined, 2);
      IDNO:  DBWriteContactSettingByte(0, piShortName, opt_GroupPluginJoined, 1);
    end;

  Result:=0;
end;

// =============================================================================
// function is run, when miranda is asking whether each plugin is ok to exit
// miranda's shutdown sequence is the following:
// ME_SYSTEM_OKTOEXIT: 40072 (online), netlib works, MS_SYSTEM_TERMINATED returns False
// ME_SYSTEM_PRESHUTDOWN: 40071 (offline), netlib doesn't work, MS_SYSTEM_TERMINATED returns True
// Unload: 40071 (offline), netlib doesn't work, MS_SYSTEM_TERMINATED returns True
// -----------------------------------------------------------------------------
function OkToExit(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(OkToExit) Starting to exit miranda...'));
  Netlib_Log(vk_hNetlibUser, PChar('(OkToExit) ... finishing ThrIDConnect thread'));
  if Assigned(ThrIDConnect) then
    ThrIDConnect.Terminate; // just send a command to stop thread
  Netlib_Log(vk_hNetlibUser, PChar('(OkToExit) ... calling UpdateDataDestroy'));
  if Assigned(ThrIDDataUpdate) then
    ThrIDDataUpdate.Terminate;
  Netlib_Log(vk_hNetlibUser, PChar('(OkToExit) ... making all contacts offline'));
  SetStatusOffline(); // make all contacts offline
  vk_Logout(); // logout from the site

  Netlib_Log(vk_hNetlibUser, PChar('(OkToExit) ... ok to exit miranda'));
  Result := 0;
end;

// =============================================================================
// function is run, when miranda is shutting down
// -----------------------------------------------------------------------------
function PreShutdown(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(PreShutdown) Starting miranda pre-shutdown...'));
  Netlib_Log(vk_hNetlibUser, PChar('(PreShutdown) ... miranda pre-shutdown is completed'));
  Result := 0;
end;

// =============================================================================
// function is run, when plugin is being unloaded
// -----------------------------------------------------------------------------
function Unload: int; cdecl;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(Unload) Starting to unload plugin...'));
  // ask for thread completion
  if Assigned(ThrIDConnect) then
    ThrIDConnect.Terminate;

  // destroy services
  pluginLink^.DestroyServiceFunction(vk_hGetCaps);
  pluginLink^.DestroyServiceFunction(vk_hGetName);
  pluginLink^.DestroyServiceFunction(vk_hGetStatus);
  pluginLink^.DestroyServiceFunction(vk_hSetStatus);

  SearchDestroy();

  pluginLink^.DestroyServiceFunction(vk_hNetlibUser);
  pluginLink^.DestroyServiceFunction(vk_hkHookShutdown);
  pluginLink^.DestroyServiceFunction(vk_hkHookOkToExit);
  pluginLink^.DestroyServiceFunction(vk_hOnCreateAccMgrUI);

  PopupDestroy();

  MsgsDestroy();

  AvatarsDestroy();

  FoldersDestroy();

  AddlStatusDestroy();

  // unhook all events we hooked
  pluginLink^.UnhookEvent(vk_hkContactDeleted);
  pluginLink^.UnhookEvent(vk_hkModulesLoad);
  pluginLink^.UnhookEvent(vk_hkOptInitialise);

  Netlib_Log(vk_hNetlibUser, PChar('(Unload) ... unload plugin finished'));

  Result := 0;
end;

exports
  MirandaPluginInfo, Load, Unload,
  MirandaPluginInterfaces, MirandaPluginInfoEx;

begin
end.
