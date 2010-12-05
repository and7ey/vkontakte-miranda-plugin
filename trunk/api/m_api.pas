{
Miranda IM: the free IM client for Microsoft* Windows*

Copyright 2000-2003 Miranda ICQ/IM project,
all portions of this codebase are copyrighted to the people
listed in contributors.txt.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
}
{$A+,H+}
unit m_api;

interface

uses
  Windows,Messages;
  //,FreeImage;  // modified by LA

// RichEdit definitions
type
  PCHARRANGE = ^TCHARRANGE;
  TCHARRANGE = record
    cpMin:integer;
    cpMax:integer;
  end;

// C translations
type
  size_t   = integer;
  time_t   = DWORD;
  int      = Integer;
  uint     = Cardinal;
  pint     = ^int;
  WPARAM   = Integer;
  LPARAM   = Integer;

// My definitions
  TWNDPROC = function (Dialog:HWnd; hMessage,
                      wParam:WPARAM;lParam:LPARAM):integer; cdecl;

type
  TChar = record
    case boolean of
      false: (a:PChar);     // ANSI or UTF8
      true:  (w:PWideChar); // Unicode
  end;

{$include m_system.inc}
const
  mmi:TMM_INTERFACE=(
    cbSize :SizeOf(TMM_INTERFACE);
    malloc :nil;
    realloc:nil;
    free   :nil);

{-- start newpluginapi --}
const
  MAXMODULELABELLENGTH = 64;
  CALLSERVICE_NOTFOUND = $80000000;

const
  UNICODE_AWARE = 1;

type
  PPLUGININFO = ^TPLUGININFO;
  TPLUGININFO = record
    cbSize     :int;
    shortName  :PChar;
    version    :DWORD;
    description:PChar;
    author     :PChar;
    authorEmail:PChar;
    copyright  :PChar;
    homepage   :PChar;
    flags      :Byte;  // right now the only flag, UNICODE_AWARE, is recognized here
    { one of the DEFMOD_* consts in m_plugin or zero, if non zero, this will
    suppress loading of the specified builtin module }
    replacesDefaultModule: int;
  end;

{
 0.7+
   New plugin loader implementation
}
// The UUID structure below is used to for plugin UUID's and module type definitions
type
  PMUUID = ^TMUUID;
  MUUID  = TGUID;
  TMUUID = MUUID;
{
  MUUID = record
    a:cardinal;
    b:word;
    c:word;
    d:array [0..7] of byte;
  end;
}
// Used to define the end of the MirandaPluginInterface list
const MIID_LAST          :MUUID='{00000000-0000-0000-0000-000000000000}';

// Replaceable internal modules interface ids
const MIID_HISTORY       :MUUID='{5CA0CBC1-999A-4EA2-8B44-F8F67D7F8EBE}';
const MIID_UIFINDADD     :MUUID='{B22C528D-6852-48EB-A294-0E26A9161213}';
const MIID_UIUSERINFO    :MUUID='{570B931C-9AF8-48F1-AD9F-C4498C618A77}';
const MIID_SRURL         :MUUID='{5192445C-F5E8-46C0-8F9E-2B6D43E5C753}';
const MIID_SRAUTH        :MUUID='{377780B9-2B3B-405B-9F36-B3C4878E6F33}';
const MIID_SRAWAY        :MUUID='{5AB54C76-1B4C-4A00-B404-48CBEA5FEFE7}';
const MIID_SREMAIL       :MUUID='{D005B5A6-1B66-445A-B603-74D4D4552DE2}';
const MIID_SRFILE        :MUUID='{989D104D-ACB7-4EE0-B96D-67CE4653B695}';
const MIID_UIHELP        :MUUID='{F2D35C3C-861A-4CC3-A78F-D1F7850441CB}';
const MIID_UIHISTORY     :MUUID='{7F7E3D98-CE1F-4962-8284-968550F1D3D9}';
const MIID_AUTOAWAY      :MUUID='{9C87F7DC-3BD7-4983-B7FB-B848FDBC91F0}';
const MIID_USERONLINE    :MUUID='{130829E0-2463-4FF8-BBC8-CE73C0188442}';
const MIID_IDLE          :MUUID='{296F9F3B-5B6F-40E5-8FB0-A6496C18BF0A}';
const MIID_FONTSERVICE   :MUUID='{56F39112-E37F-4234-A9E6-7A811745C175}';
const MIID_UPDATENOTIFY  :MUUID='{4E68B12A-6B54-44DE-8637-F1120DB68140}';

// Common plugin interfaces (core plugins)
const MIID_DATABASE      :MUUID='{AE77FD33-E484-4DC7-8CBC-099FEDCCCFDD}';
const MIID_CLIST         :MUUID='{9D8DA8BF-665B-4908-9E61-9F7598AE330E}';
const MIID_CHAT          :MUUID='{23576A43-3A26-4357-9B1B-4A719E425D48}';
const MIID_SRMM          :MUUID='{58C7EEA6-F9DB-4DD9-8036-AE802BC0414C}';
const MIID_IMPORT        :MUUID='{5F3BCAD4-75F8-476E-B36B-2B307032490C}';
const MIID_IMGSERVICES   :MUUID='{F3974915-C9D5-4C87-8564-A0EBF9D25AA0}';
const MIID_TESTPLUGIN    :MUUID='{53B974F4-3C74-4DBA-8FC2-6F92FE013B8C}';

// Common plugin interfaces (non-core plugins)
const MIID_VERSIONINFO   :MUUID='{CFEB6325-334E-4052-A645-562193DFCC77}';
const MIID_FOLDERS       :MUUID='{CFEBEC29-39EF-4B62-AD38-9A652CA324ED}';
const MIID_BIRTHDAYNOTIFY:MUUID='{CFBA5784-3701-4D83-816A-199C00D4A67A}';
const MIID_BONSAI        :MUUID='{CFAAE811-30E1-4A4F-8784-153CCCB0037A}';
const MIID_EXCHANGE      :MUUID='{CFD79A89-9959-4E65-B076-413F98FE0D15}';
const MIID_MIRPY         :MUUID='{CFF91A5C-1786-41C1-8886-094B14281F15}';
const MIID_SERVICESLIST  :MUUID='{CF4BDF02-5D27-4241-99E5-1951AAB0C454}';
const MIID_TRANSLATOR    :MUUID='{CFB637B0-7217-4C1E-B22A-D922323A5D0B}';
const MIID_TOOLTIPS      :MUUID='{BCBDA043-2716-4404-B0FA-3D2D93819E03}';
const MIID_POPUPS        :MUUID='{33299069-1919-4FF8-B131-1D072178A766}';
const MIID_LOGWINDOW     :MUUID='{C53AFB90-FA44-4304-BC9D-6A841C3905F5}';
{
 Special exception interface for protocols.
   This interface allows more than one plugin to implement it at the same time
}
const MIID_PROTOCOL      :MUUID='{2A3C815E-A7D9-424B-BA30-02D083229085}';

type
  PPLUGININFOEX = ^TPLUGININFOEX;
  TPLUGININFOEX = record
    cbSize     :int;
    shortName  :PChar;
    version    :DWORD;
    description:PChar;
    author     :PChar;
    authorEmail:PChar;
    copyright  :PChar;
    homepage   :PChar;
    flags      :Byte;  // right now the only flag, UNICODE_AWARE, is recognized here
    { one of the DEFMOD_* consts in m_plugin or zero, if non zero, this will
    suppress loading of the specified builtin module }
    replacesDefaultModule: int;
    uuid       :MUUID; // Not required until 0.8.
  end;

{ modules.h is never defined -- no check needed }

  TMIRANDAHOOK    = function(wParam: WPARAM; lParam: LPARAM): int; cdecl;
  TMIRANDASERVICE = function(wParam: WPARAM; lParam: LPARAM): int; cdecl;
  TMIRANDASERVICEPARAM = function(wParam:WPARAM;lParam,lParam1:LPARAM):int; cdecl;

  //see modules.h tor what all this stuff is

  TCreateHookableEvent = function(const char: PChar): THandle; cdecl;
  TDestroyHookableEvent = function(Handle: THandle): int; cdecl;
  TNotifyEventHooks = function(Handle: THandle; wParam: WPARAM; lParam: LPARAM): int; cdecl;
  THookEvent  = function(const char: PChar; MIRANDAHOOK: TMIRANDAHOOK): THandle; cdecl;
  THookEventMessage = function(const char: PChar; Wnd: THandle; wMsg: Integer): THandle; cdecl;
  TUnhookEvent = function(Handle: THandle): int; cdecl;
  TCreateServiceFunction = function(const char: PChar; MIRANDASERVICE: TMIRANDASERVICE): THandle; cdecl;
  TCreateTransientServiceFunction = function(const char: PChar; MIRANDASERVICE: TMIRANDASERVICE): THandle; cdecl;
  TDestroyServiceFunction = function(Handle: THandle): int; cdecl;
  TCallService = function(const char: PChar; wParam: WPARAM; lParam: LPARAM): int; cdecl;
  TServiceExists = function(const char: PChar): int; cdecl;
  TCallServiceSync = function(const char: PChar;wParam: WPARAM; lParam: LPARAM):int; cdecl;    //v0.3.3+
  TCallFunctionAsync = function(ptr1,ptr2:pointer):int; cdecl; {stdcall;}  //v0.3.4+
  TSetHookDefaultForHookableEvent = function(Handle:THandle;MIRANDAHOOK: TMIRANDAHOOK):int; cdecl;// v0.3.4 (2004/09/15)
  // TCreateServiceFunctionParam = function(const char:PChar; MIRANDASERVICEPARAM:TMIRANDASERVICEPARAM): THandle; cdecl;
  // next line is corrected by LA
  TCreateServiceFunctionParam = function(const char:PChar; MIRANDASERVICEPARAM:TMIRANDASERVICEPARAM; lParam: lParam): THandle; cdecl;

  PPLUGINLINK = ^TPLUGINLINK;
  TPLUGINLINK = record
    CreateHookableEvent           : TCreateHookableEvent;
    DestroyHookableEvent          : TDestroyHookableEvent;
    NotifyEventHooks              : TNotifyEventHooks;
    HookEvent                     : THookEvent;
    HookEventMessage              : THookEventMessage;
    UnhookEvent                   : TUnhookEvent;
    CreateServiceFunction         : TCreateServiceFunction;
    CreateTransientServiceFunction: TCreateTransientServiceFunction;
    DestroyServiceFunction        : TDestroyServiceFunction;
    CallService                   : TCallService;
    ServiceExists                 : TServiceExists;     // v0.1.0.1+
    CallServiceSync               : TCallServiceSync;    // v0.3.3+
    CallFunctionAsync             : TCallFunctionAsync;  // v0.3.4+
    SetHookDefaultForHookableEvent: TSetHookDefaultForHookableEvent; // v0.3.4 (2004/09/15)
    CreateServiceFunctionParam    : TCreateServiceFunctionParam; // v0.7+ (2007/04/24)
  end;

  { Database plugin stuff  }

  // grokHeader() error codes
  const
     EGROKPRF_NOERROR   = 0;
     EGROKPRF_CANTREAD  = 1; // can't open the profile for reading
     EGROKPRF_UNKHEADER = 2; // header not supported, not a supported profile
     EGROKPRF_VERNEWER  = 3; // header correct, version in profile newer than reader/writer
     EGROKPRF_DAMAGED   = 4; // header/version fine, other internal data missing, damaged.
 // makeDatabase() error codes
     EMKPRF_CREATEFAILED = 1; // for some reason CreateFile() didnt like something

type
  PDATABASELINK = ^TDATABASELINK;
  TDATABASELINK = record
    cbSize : longint;
    {
      returns what the driver can do given the flag
    }
    getCapability : function (flag:longint):longint; cdecl;
    {
       buf: pointer to a string buffer
       cch: length of buffer
       shortName: if true, the driver should return a short but descriptive name, e.g. "3.xx profile"
       Affect: The database plugin must return a "friendly name" into buf and not exceed cch bytes,
         e.g. "Database driver for 3.xx profiles"
       Returns: 0 on success, non zero on failure
    }
    getFriendlyName : function (buf:PChar; cch:size_t; shortName:longint):longint; cdecl;
    {
      profile: pointer to a string which contains full path + name
      Affect: The database plugin should create the profile, the filepath will not exist at
        the time of this call, profile will be C:\..\<name>.dat
      Note: Do not prompt the user in anyway about this operation.
      Note: Do not initialise internal data structures at this point!
      Returns: 0 on success, non zero on failure - error contains extended error information, see EMKPRF_
    }
    makeDatabase : function (profile:Pchar; error:Plongint):longint; cdecl;
    {
      profile: [in] a null terminated string to file path of selected profile
      error: [in/out] pointer to an int to set with error if any
      Affect: Ask the database plugin if it supports the given profile, if it does it will
        return 0, if it doesnt return 1, with the error set in error -- EGROKPRF_  can be valid error
        condition, most common error would be [EGROKPRF_UNKHEADER]
      Note: Just because 1 is returned, doesnt mean the profile is not supported, the profile might be damaged
        etc.
      Returns: 0 on success, non zero on failure
    }
    grokHeader : function (profile:Pchar; error:Plongint):longint; cdecl;
    {
      Affect: Tell the database to create all services/hooks that a 3.xx legecy database might support into link,
        which is a PLUGINLINK structure
      Returns: 0 on success, nonzero on failure
    }
    Load : function (profile:Pchar; link:pointer):longint; cdecl;
    {
      Affect: The database plugin should shutdown, unloading things from the core and freeing internal structures
      Returns: 0 on success, nonzero on failure
      Note: Unload() might be called even if Load() was never called, wasLoaded is set to 1 if Load() was ever called.
    }
    Unload : function (wasLoaded:longint):longint; cdecl;
  end;

{-- end newpluginapi --}

var
  { this is now a pointer to a record of function pointers to match the C API,
  and to break old code and annoy you. }
  PLUGINLINK: PPLUGINLINK;
(*
  { has to be returned via MirandaPluginInfo and has to be statically allocated,
  this means only one module can return info, you shouldn't be merging them anyway! }
  PLUGININFO: TPLUGININFO;
*)
  {$include m_plugins.inc}
  {$include m_database.inc}
  {$include m_findadd.inc}
  {$include m_awaymsg.inc}
  {$include m_email.inc}
  {$include m_history.inc}
  {$include m_message.inc}
  {$include m_url.inc}
  {$include m_clui.inc}
  {$include m_ignore.inc}
  {$include m_skin.inc}
  {$include m_file.inc}
  {$include m_netlib.inc}
  {$include m_langpack.inc}
  {$include m_clist.inc}
  {$include m_clc.inc}
  {$include m_userinfo.inc}
  {$include m_protosvc.inc}
  {$include m_options.inc}
  {$include m_icq.inc}
  {$include m_protocols.inc}
  {$include m_protomod.inc}
  {$include m_utils.inc}
  {$include m_addcontact.inc}
  {$include statusmodes.inc}
  {$include m_contacts.inc}
  {$include m_genmenu.inc}
  {$include m_icolib.inc}
  {$include m_fontservice.inc}
  {$include m_chat.inc}
  {$include m_fingerprint.inc}
  {$include m_toptoolbar.inc}
  {$include m_updater.inc}
  {$include m_variables.inc}
  {$include m_cluiframes.inc}
  {$include m_popup.inc}
  {$include m_avatars.inc}
  {$include m_png.inc}
  {$include m_smileyadd.inc}
  {$include m_tipper.inc}
  {$include m_button.inc}
  {$include m_dbeditor.inc}
  {$include m_userinfoex.inc}
  // {$include m_imgsrvc.inc} // modified by LA
  {$include m_xml.inc} // modified by LA
  {$define M_API_UNIT}
  {$include m_helpers.inc}
  {$include m_ieview.inc} // modified by LA


procedure InitMMI;

implementation

{$undef M_API_UNIT}
  {$include m_helpers.inc}
 

procedure InitMMI;
begin
  PluginLink^.CallService(MS_SYSTEM_GET_MMI,0,Integer(@mmi));
end;

end.
