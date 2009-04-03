// MessageBox(0, 'Just groovy, baby!', 'VKontakte', MB_OK);
library VKontakte;

uses
  m_globaldefs in 'api\m_globaldefs.pas',
  m_api in 'api\m_api.pas',

  vk_global, // module with global variables and constant used
  vk_http, // module to connect with the site
  vk_menu, // module to work with menus
  vk_auth, // module to support authorization process
  vk_avatars, // module to support avatars
  vk_xstatus, // module to support additional status
  vk_info, // module to get contact's info
  vk_folders, // module to support custom folders
  vk_msgs, // module to send/receive messages
  vk_core, // module with core functions
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
    // flags: UNICODE_AWARE;
    flags: 0;
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
    // flags: UNICODE_AWARE;
    flags: 0;
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

// Result := LoadImage(hInstance, MAKEINTRESOURCE('ICON_PROTO'), IMAGE_ICON, 16, 16, 0);
// Result := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(vk_icon_note));
// Result := LoadSkinnedIcon(SKINICON_OTHER_MIRANDA);
// Result := CopyIcon(CallService(MS_SKIN2_GETICONBYHANDLE, 0, (LPARAM)iconList[i].hIconLibItem));

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
  // if IsMirandaUnicode then
  //  PluginInfo.flags := UNICODE_AWARE;

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
  if DBReadString(0, piShortName, 'user/defaultgroup', nil) <> nil then
  begin
    DBWriteContactSettingString(0, piShortName, opt_UserDefaultGroup, PChar(DBReadString(0, piShortName, 'user/defaultgroup', nil)));
    DBDeleteContactSetting(0, piShortName, 'user/defaultgroup');
  end;
  if DBGetContactSettingByte(0, piShortName, 'UserDeleteFriendsFromTheServer', 0) <> 0 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserDontDeleteFriendsFromTheServer, DBGetContactSettingByte(0, piShortName, 'UserDeleteFriendsFromTheServer', 0));
    DBDeleteContactSetting(0, piShortName, 'UserDeleteFriendsFromTheServer');
  end;
  if DBReadString(0, piShortName, 'user/email', nil) <> nil then
  begin
    DBWriteContactSettingString(0, piShortName, opt_UserName, PChar(DBReadString(0, piShortName, 'user/email', nil)));
    DBDeleteContactSetting(0, piShortName, 'user/email');
  end;
  if DBReadString(0, piShortName, 'user/pass', nil) <> nil then
  begin
    DBWriteContactSettingString(0, piShortName, opt_UserPass, PChar(DBReadString(0, piShortName, 'user/pass', nil)));
    DBDeleteContactSetting(0, piShortName, 'user/pass');
  end;
  if DBGetContactSettingDWord(0, piShortName, 'user/keeponlinesecs', 255) <> 255 then
  begin
    DBWriteContactSettingDWord(0, piShortName, opt_UserKeepOnline, DBGetContactSettingDWord(0, piShortName, 'user/keeponlinesecs', 900));
    DBDeleteContactSetting(0, piShortName, 'user/keeponlinesecs');
  end;
  if DBGetContactSettingDWord(0, piShortName, 'user/newmessagessecs', 255) <> 255 then
  begin
    DBWriteContactSettingDWord(0, piShortName, opt_UserCheckNewMessages, DBGetContactSettingDWord(0, piShortName, 'user/newmessagessecs', 60));
    DBDeleteContactSetting(0, piShortName, 'user/newmessagessecs');
  end;
  if DBGetContactSettingDWord(0, piShortName, 'user/friendsstatussecs', 255) <> 255 then
  begin
    DBWriteContactSettingDWord(0, piShortName, opt_UserUpdateFriendsStatus, DBGetContactSettingDWord(0, piShortName, 'user/friendsstatussecs', 60));
    DBDeleteContactSetting(0, piShortName, 'user/friendsstatussecs');
  end;
  if DBGetContactSettingByte(0, piShortName, 'user/getmininfo', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserGetMinInfo, DBGetContactSettingByte(0, piShortName, 'user/getmininfo', 0));
    DBDeleteContactSetting(0, piShortName, 'user/getmininfo');
  end;
  if DBGetContactSettingByte(0, piShortName, 'user/removeemptysubject', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserRemoveEmptySubj, DBGetContactSettingByte(0, piShortName, 'user/removeemptysubject', 1));
    DBDeleteContactSetting(0, piShortName, 'user/removeemptysubject');
  end;
  if DBReadString(0, piShortName, 'User/DefaultGroup', nil) <> nil then
  begin
    DBWriteContactSettingString(0, piShortName, opt_UserDefaultGroup, PChar(DBReadString(0, piShortName, 'User/DefaultGroup', nil)));
    DBDeleteContactSetting(0, piShortName, 'User/DefaultGroup');
  end;
  if DBGetContactSettingByte(0, piShortName, 'user/updateadditionalstatus', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserUpdateAddlStatus, DBGetContactSettingByte(0, piShortName, 'user/updateadditionalstatus', 1));
    DBDeleteContactSetting(0, piShortName, 'user/updateadditionalstatus');
  end;
  if DBGetContactSettingByte(0, piShortName, 'user/avssupport', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserAvatarsSupport, DBGetContactSettingByte(0, piShortName, 'user/avssupport', 1));
    DBDeleteContactSetting(0, piShortName, 'user/avssupport');
  end;
  if DBGetContactSettingDWord(0, piShortName, 'user/avsupdatefreq', 255) <> 255 then
  begin
    DBWriteContactSettingDWord(0, piShortName, opt_UserAvatarsUpdateFreq, DBGetContactSettingDWord(0, piShortName, 'user/avsupdatefreq', 60));
    DBDeleteContactSetting(0, piShortName, 'user/avsupdatefreq');
  end;
  if DBGetContactSettingByte(0, piShortName, 'user/avsupdatewhengetinfo', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, DBGetContactSettingByte(0, piShortName, 'user/avsupdatewhengetinfo', 1));
    DBDeleteContactSetting(0, piShortName, 'user/avsupdatewhengetinfo');
  end;
  if DBGetContactSettingByte(0, piShortName, 'User/VKontakteURL', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserVKontakteURL, DBGetContactSettingByte(0, piShortName, 'User/VKontakteURL', 0));
    DBDeleteContactSetting(0, piShortName, 'User/VKontakteURL');
  end;
  if DBGetContactSettingByte(0, piShortName, 'User/AddlStatusForOffline', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, DBGetContactSettingByte(0, piShortName, 'User/AddlStatusForOffline', 0));
    DBDeleteContactSetting(0, piShortName, 'User/AddlStatusForOffline');
  end;
  if DBGetContactSettingByte(0, piShortName, 'User/UseLocalTimeForIncomingMessages', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserUseLocalTimeForIncomingMessages, DBGetContactSettingByte(0, piShortName, 'User/UseLocalTimeForIncomingMessages', 0));
    DBDeleteContactSetting(0, piShortName, 'User/UseLocalTimeForIncomingMessages');
  end;
  if DBGetContactSettingByte(0, piShortName, 'User/UseLocalTimeForIncomingMessages', 255) <> 255 then
  begin
    DBWriteContactSettingByte(0, piShortName, opt_UserUseLocalTimeForIncomingMessages, DBGetContactSettingByte(0, piShortName, 'User/UseLocalTimeForIncomingMessages', 0));
    DBDeleteContactSetting(0, piShortName, 'User/UseLocalTimeForIncomingMessages');
  end;
  DBDeleteContactSetting(0, piShortName, 'LastUpdateDateTimeMsgs');
  DBDeleteContactSetting(0, piShortName, 'LastUpdateDateTimeFriendsStatus');
  DBDeleteContactSetting(0, piShortName, 'LastUpdateDateTimeKeepOnline');
  DBDeleteContactSetting(0, piShortName, 'LastUpdateDateTimeAvatars');

  // ask to join plugin's group
  if DBGetContactSettingByte(0, piShortName, opt_GroupPluginJoined, 0) = 0 then // never asked before
    case MessageBox(0, Translate(qst_join_vk_group), Translate(piShortName), MB_YESNOCANCEL + MB_ICONQUESTION) of
      IDYES: DBWriteContactSettingByte(0, piShortName, opt_GroupPluginJoined, 2);
      IDNO:  DBWriteContactSettingByte(0, piShortName, opt_GroupPluginJoined, 1);
    end;

  Result:=0;
end;

// =============================================================================
// function is run, when miranda is asking whether each plugin is ok to exit
// -----------------------------------------------------------------------------
function OkToExit(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Result := 0;
end;

// =============================================================================
// function is run, when miranda is shutting down
// -----------------------------------------------------------------------------
function PreShutdown(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Result := 0;
end;

// =============================================================================
// function is run, when plugin is being unloaded
// -----------------------------------------------------------------------------
function Unload: int; cdecl;
begin
  // wait for thread completion
  if Assigned(ThrIDConnect) then
    WaitForSingleObject(ThrIDConnect.Handle, 5000);  // ThrIDConnect.WaitFor;

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

  Result := 0;
end;

exports
  MirandaPluginInfo, Load, Unload,
  MirandaPluginInterfaces, MirandaPluginInfoEx;

begin
end.
