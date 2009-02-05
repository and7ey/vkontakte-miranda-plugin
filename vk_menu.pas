(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (Ñ) 2008 Andrey Lukyanov

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
 vk_menu.pas

 [ Description ]
 Module to support menus (except additional status menu, see vk_xstatus.pas)

 [ Known Issues ]
 See the code

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_menu;

interface

  procedure MenuInit();
  procedure MenuDestroy();

implementation

uses
  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used
  vk_common, // module with common functions
  vk_info, // module to get contact's info
  htmlparse, // module to simplify html parsing

  ShellAPI,
  Windows,
  SysUtils,
  Classes;

type
  TMenuItem = record
    Name: String;
    URL: String;
    Icon: String;
    Position: Integer;
    Proc: TMIRANDASERVICEPARAM;
  end;

function MenuContactPages(wParam: wParam; lParam: lParam; lParam1: Integer): Integer; cdecl; forward;
function MenuMainUpdateDetailsAllUsers(wParam: wParam; lParam: lParam; lParam1: Integer): Integer; cdecl; forward;

const
  // list of contact menu items
  MenuContactPagesItems: Array [1..8] of TMenuItem = (
    (Name:'&Main page VKontakte...'; URL:vk_url_friend; Icon:'ICON_PROTO'; Position:400000),
    (Name:'&Photos VKontakte...'; URL:vk_url_photos; Icon:'ICON_PHOTOS'; Position:500000),
    (Name:'&Friends VKontakte...'; URL:vk_url_friends; Icon:'ICON_FRIENDS'; Position:500001),
    (Name:'The &wall VKontakte...'; URL:vk_url_wall; Icon:'ICON_POST'; Position:500002),
    (Name:'&Groups VKontakte...'; URL:vk_url_groups; Icon:'ICON_GROUPS'; Position:500003),
    (Name:'&Audio VKontakte...'; URL:vk_url_audio; Icon:'ICON_SOUND'; Position:500004),
    (Name:'&Notes VKontakte...'; URL:vk_url_notes; Icon:'ICON_NOTES'; Position:500005),
    (Name:'&Questions VKontakte...'; URL:vk_url_questions; Icon:'ICON_QUESTIONS'; Position:500006)
    );

  // list of main menu items
  MenuMainItems: Array [1..9] of TMenuItem = (
    (Name:'My &main page VKontakte...'; URL:vk_url_friend; Icon:'ICON_PROTO'; Position:000000; Proc: MenuContactPages),
    (Name:'My &photos VKontakte...'; URL:vk_url_photos; Icon:'ICON_PHOTOS'; Position:100000; Proc: MenuContactPages),
    (Name:'My &friends VKontakte...'; URL:vk_url_friends; Icon:'ICON_FRIENDS'; Position:100001; Proc: MenuContactPages),
    (Name:'My &wall VKontakte...'; URL:vk_url_wall; Icon:'ICON_POST'; Position:100002; Proc: MenuContactPages),
    (Name:'My &groups VKontakte...'; URL:vk_url_groups; Icon:'ICON_GROUPS'; Position:100003; Proc: MenuContactPages),
    (Name:'My &audio VKontakte...'; URL:vk_url_audio; Icon:'ICON_SOUND'; Position:100004; Proc: MenuContactPages),
    (Name:'My &notes VKontakte...'; URL:vk_url_notes; Icon:'ICON_NOTES'; Position:100005; Proc: MenuContactPages),
    (Name:'My &questions VKontakte...'; URL:vk_url_questions; Icon:'ICON_QUESTIONS'; Position:100006; Proc: MenuContactPages),
    (Name:'&Update Details for all users'; URL:''; Icon:'ICON_INFO'; Position:200000; Proc: MenuMainUpdateDetailsAllUsers)
    );

var
  vk_hMenuMain: Array [1..8] of THandle;
  vk_hMenuMainSF: Array [1..8] of THandle;

  vk_hMenuContactPages: Array [1..8] of THandle;
  vk_hMenuContactPagesSF: Array [1..8] of THandle;



// =============================================================================
// function to react on the plugin's main menu item to update details of all
// users
// -----------------------------------------------------------------------------
function MenuMainUpdateDetailsAllUsers(wParam: wParam; lParam: lParam; lParam1: Integer): Integer; cdecl;
var hContact: THandle;
    res: LongWord;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(MenuMainUpdateDetailsAllUsers) Updating of details for all contacts started...'));
  hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
	while hContact <> 0 do
  begin
    if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, windows.lParam(PAnsiChar(piShortName))) <> 0 Then
    begin
      CloseHandle(BeginThread(nil, 0, @GetInfoProc, Pointer(hContact), 0, res));
    end;
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
	end;
  Netlib_Log(vk_hNetlibUser, PChar('(MenuMainUpdateDetailsAllUsers) ... updating of details for all contacts finished'));
  Result := 0;
end;

// =============================================================================
// function to react on the plugin's contact menu items to open contact's pages,
// used for main menu also
// -----------------------------------------------------------------------------
function MenuContactPages(wParam: wParam; lParam: lParam; lParam1: Integer): Integer; cdecl;
begin
  ShellAPI.ShellExecute(0, 'open', PChar(Format(MenuContactPagesItems[lParam1].URL, [DBGetContactSettingDword(wParam, piShortName, 'ID', 0)])), nil, nil, 0);
  Result := 0;
end;

// =============================================================================
// function to react on the plugin's menu item - Open Webpage
// this is called by Miranda, thus has to use the cdecl calling convention
// all services and hooks need this.
// -----------------------------------------------------------------------------
function MenuMainOpenWebpage(wParam: WPARAM; lParam: LPARAM): Integer; cdecl;
begin
  ShellAPI.ShellExecute(0, 'open', vk_url, nil, nil, 0);
  Result := 0;
end;

// =============================================================================
// TEST FUNCTION
// -----------------------------------------------------------------------------
function MenuContactTest(wParam: WPARAM; lParam: LPARAM): Integer; cdecl;
var iec: TIconExtraColumn;
begin
  iec.cbSize := sizeof(iec);
  if DBGetContactSettingWord(wParam, piShortName, 'Status', ID_STATUS_OFFLINE) = ID_STATUS_ONLINE then // apply icon to online contacts only
    iec.hImage := xStatuses[1].IconExtraIndex
  else
    iec.hImage := THandle(-1);
  iec.ColumnType := EXTRA_ICON_ADV2;
  pluginLink^.CallService(MS_CLIST_EXTRA_SET_ICON, wParam, Windows.lParam(@iec));
  Result := 0;
end;

// =============================================================================
// procedure to get short information about contact
// -----------------------------------------------------------------------------
procedure MenuInit();
var
  mi: TCListMenuItem; // main menu item
  cmi: TCListMenuItem; // contact menu item
  i: Byte;
  srvFce: PChar;
begin
  // creation of main menu
  FillChar(mi, sizeof(mi), 0);
  mi.cbSize := sizeof(mi);
  mi.popupPosition := 500000; // position above Options
  mi.szPopupName.a := piShortName;
  mi.flags := 0;
  for i:=Low(MenuMainItems) to High(MenuMainItems) do
  begin
    //approx position on the menu. lower numbers go nearer the top
    //separator is on each 100000 position
    //please note that in case in Miranda settings, Customize-Menus there are some items hidden/moved
    //then by default miranda will place new menu item at bottom
    mi.Position := MenuMainItems[i].Position;
    // no need to separately register with MS_SKIN2_ADDICON all icons we use
    // icons used in menu are registered automatically
    if MenuMainItems[i].Icon<>'' then
      mi.hIcon := LoadImage(hInstance, MAKEINTRESOURCE(MenuMainItems[i].Icon), IMAGE_ICON, 16, 16, 0)
    else
      mi.hIcon := 0;
    srvFce := PChar(Format('%s/MenuMain%d', [piShortName, i]));
    // vk_hMenuMainSF[i] := pluginLink^.CreateServiceFunctionParam(srvFce, @MenuContactPages, i);
    vk_hMenuMainSF[i] := pluginLink^.CreateServiceFunctionParam(srvFce, @MenuMainItems[i].Proc, i);
    mi.pszService := srvFce;
    // WARNING: do not use Translate(TS) for p(t)szName or p(t)szPopupName as they
    // are translated by the core, which may lead to double translation.
    mi.szName.a := PChar(MenuMainItems[i].Name);
    vk_hMenuMain[i] := pluginLink^.CallService(MS_CLIST_ADDMAINMENUITEM, 0,  Windows.lparam(@mi));
  end;

  // creation of contact menu items
  FillChar(cmi, sizeof(cmi), 0);
  cmi.cbSize := sizeof(cmi);
  cmi.flags := 0;
  for i:=Low(MenuContactPagesItems) to High(MenuContactPagesItems) do
  begin
    cmi.Position := MenuContactPagesItems[i].Position;
    if MenuContactPagesItems[i].Icon<>'' then
      cmi.hIcon := LoadImage(hInstance, MAKEINTRESOURCE(MenuContactPagesItems[i].Icon), IMAGE_ICON, 16, 16, 0)
    else
      cmi.hIcon := 0;
    srvFce := PChar(Format('%s/MenuContactPages%d', [piShortName, i]));
    vk_hMenuContactPagesSF[i] := pluginLink^.CreateServiceFunctionParam(srvFce, @MenuContactPages, i);
    cmi.pszService := srvFce;
    cmi.szName.a := PChar(MenuContactPagesItems[i].Name);
    cmi.pszContactOwner := piShortName;
    vk_hMenuContactPages[i] := pluginLink^.CallService(MS_CLIST_ADDCONTACTMENUITEM, 0,  Windows.lparam(@cmi));
    if cmi.hIcon<>0 then DestroyIcon(cmi.hIcon);
  end;
  // add Read Additional status item, hidden by default

  // add one more, temp item
  cmi.flags := 0;
  cmi.Position := -100;
  srvFce := PChar(Format('%s/MenuContactTemp', [piShortName]));
  pluginLink^.CreateServiceFunction(srvFce, @MenuContactTest);
  cmi.pszService := srvFce;
  cmi.szName.a := 'Temp test function';
  cmi.pszContactOwner := piShortName;
  // pluginLink^.CallService(MS_CLIST_ADDCONTACTMENUITEM, 0,  Windows.lparam(@cmi));

end;

procedure MenuDestroy();
var i: Byte;
begin
  for i:=Low(vk_hMenuContactPages) to High(vk_hMenuContactPages) do
  begin
    pluginLink^.DestroyServiceFunction(vk_hMenuContactPages[i]);
    pluginLink^.DestroyServiceFunction(vk_hMenuContactPagesSF[i]);
  end;

  for i:=Low(vk_hMenuMain) to High(vk_hMenuMain) do
  begin
    pluginLink^.DestroyServiceFunction(vk_hMenuMain[i]);
    pluginLink^.DestroyServiceFunction(vk_hMenuMainSF[i]);
  end;

end;


begin
end.
