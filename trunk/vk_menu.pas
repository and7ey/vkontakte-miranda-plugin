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

var
  vk_hMenuContactPages: array [1..10] of THandle;

implementation

uses
  m_globaldefs,
  m_api,
  vk_global,  // module with global variables and constant used
  vk_common,  // module with common functions
  vk_info,    // module to get contact's info
  htmlparse,  // module to simplify html parsing
  vk_opts,    // unit to work with options
  vk_auth,    // module to support authorization process
  vk_wall,    // module to work with VKontakte's wall
  vk_xstatus, // module to support additional status

  Messages,
  ShellAPI,
  Windows,
  SysUtils,
  Classes;

type
  TMenuItem = record
    Name:     string;
    URL:      string;
    Icon:     string;
    Position: integer;
    Proc:     TMIRANDASERVICEPARAM;
    flags:    DWord;
  end;

function MenuMainPages(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl; forward;
function MenuContactPages(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl; forward;
function MenuMainUpdateDetailsAllUsers(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl; forward;
function MenuContactAddPermanently(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl; forward;
function MenuContactWall(wParam: WPARAM; lParam: LPARAM; lParam1: integer): integer; cdecl; forward;

var
  // list of contact menu items
  MenuContactPagesItems: array [1..10] of TMenuItem;
  // list of main menu items
  MenuMainItems:         array [1..9] of TMenuItem;

  vk_hkMenuStatusPrebuild: THandle;
  vk_hMenuMain:            array [1..9] of THandle;
  vk_hMenuMainSF:          array [1..9] of THandle;

  vk_hMenuContactPagesSF: array [1..9] of THandle;

 // =============================================================================
 // procedure to init items of contact menu
 // -----------------------------------------------------------------------------
procedure MenuContactPagesItemsInit;
begin
  MenuContactPagesItems[1].Name := 'Request authorization';
  MenuContactPagesItems[1].URL := '';
  MenuContactPagesItems[1].Icon := 'ICON_PLUS';
  MenuContactPagesItems[1].Position := -2000003999;
  MenuContactPagesItems[1].Proc := MenuContactAddPermanently;
  MenuContactPagesItems[1].flags := CMIF_HIDDEN; // don't change id of this item! it is used in vk_xstatus

  MenuContactPagesItems[2].Name := '&Main page VKontakte...';
  MenuContactPagesItems[2].URL := vk_url + vk_url_friend;
  MenuContactPagesItems[2].Icon := 'ICON_PROTO';
  MenuContactPagesItems[2].Position := 400000;
  MenuContactPagesItems[2].Proc := MenuContactPages;

  MenuContactPagesItems[3].Name := '&Photos VKontakte...';
  MenuContactPagesItems[3].URL := vk_url + vk_url_photos;
  MenuContactPagesItems[3].Icon := 'ICON_PHOTOS';
  MenuContactPagesItems[3].Position := 500000;
  MenuContactPagesItems[3].Proc := MenuContactPages;

  MenuContactPagesItems[4].Name := '&Friends VKontakte...';
  MenuContactPagesItems[4].URL := vk_url + vk_url_friends;
  MenuContactPagesItems[4].Icon := 'ICON_FRIENDS';
  MenuContactPagesItems[4].Position := 500001;
  MenuContactPagesItems[4].Proc := MenuContactPages;

  MenuContactPagesItems[5].Name := 'The &wall VKontakte...';
  MenuContactPagesItems[5].URL := vk_url + vk_url_wall_id;
  MenuContactPagesItems[5].Icon := 'ICON_POST';
  MenuContactPagesItems[5].Position := 500002;
  MenuContactPagesItems[5].Proc := MenuContactPages;

  MenuContactPagesItems[6].Name := '&Groups VKontakte...';
  MenuContactPagesItems[6].URL := vk_url + vk_url_groups;
  MenuContactPagesItems[6].Icon := 'ICON_GROUPS';
  MenuContactPagesItems[6].Position := 500003;
  MenuContactPagesItems[6].Proc := MenuContactPages;

  MenuContactPagesItems[7].Name := '&Audio VKontakte...';
  MenuContactPagesItems[7].URL := vk_url + vk_url_audio;
  MenuContactPagesItems[7].Icon := 'ICON_SOUND';
  MenuContactPagesItems[7].Position := 500004;
  MenuContactPagesItems[7].Proc := MenuContactPages;

  MenuContactPagesItems[8].Name := '&Notes VKontakte...';
  MenuContactPagesItems[8].URL := vk_url + vk_url_notes;
  MenuContactPagesItems[8].Icon := 'ICON_NOTES';
  MenuContactPagesItems[8].Position := 500005;
  MenuContactPagesItems[8].Proc := MenuContactPages;

  MenuContactPagesItems[9].Name := '&Questions VKontakte...';
  MenuContactPagesItems[9].URL := vk_url + vk_url_questions;
  MenuContactPagesItems[9].Icon := 'ICON_QUESTIONS';
  MenuContactPagesItems[9].Position := 500006;
  MenuContactPagesItems[9].Proc := MenuContactPages;

  MenuContactPagesItems[10].Name := 'W&rite on the wall VKontakte...';
  MenuContactPagesItems[10].URL := vk_url + vk_url_wall_id;
  MenuContactPagesItems[10].Icon := 'ICON_POST';
  MenuContactPagesItems[10].Position := 600000;
  MenuContactPagesItems[10].Proc := MenuContactWall; // don't change id of this item! it is used in vk_xstatus

end;

 // =============================================================================
 // procedure to init items of main menu
 // -----------------------------------------------------------------------------
procedure MenuMainItemsInit;
begin
  MenuMainItems[1].Name := 'My &main page...';
  MenuMainItems[1].URL := vk_url + vk_url_friend;
  MenuMainItems[1].Icon := 'ICON_PROTO';
  MenuMainItems[1].Position := 000000;
  MenuMainItems[1].Proc := MenuMainPages;

  MenuMainItems[2].Name := 'My &photos...';
  MenuMainItems[2].URL := vk_url + vk_url_photos;
  MenuMainItems[2].Icon := 'ICON_PHOTOS';
  MenuMainItems[2].Position := 100000;
  MenuMainItems[2].Proc := MenuMainPages;

  MenuMainItems[3].Name := 'My &friends...';
  MenuMainItems[3].URL := vk_url + vk_url_friends;
  MenuMainItems[3].Icon := 'ICON_FRIENDS';
  MenuMainItems[3].Position := 100001;
  MenuMainItems[3].Proc := MenuMainPages;

  MenuMainItems[4].Name := 'My &wall...';
  MenuMainItems[4].URL := vk_url + vk_url_wall_id;
  MenuMainItems[4].Icon := 'ICON_POST';
  MenuMainItems[4].Position := 100002;
  MenuMainItems[4].Proc := MenuMainPages;

  MenuMainItems[5].Name := 'My &groups...';
  MenuMainItems[5].URL := vk_url + vk_url_groups;
  MenuMainItems[5].Icon := 'ICON_GROUPS';
  MenuMainItems[5].Position := 100003;
  MenuMainItems[5].Proc := MenuMainPages;

  MenuMainItems[6].Name := 'My &audio...';
  MenuMainItems[6].URL := vk_url + vk_url_audio;
  MenuMainItems[6].Icon := 'ICON_SOUND';
  MenuMainItems[6].Position := 100004;
  MenuMainItems[6].Proc := MenuMainPages;

  MenuMainItems[7].Name := 'My &notes...';
  MenuMainItems[7].URL := vk_url + vk_url_notes;
  MenuMainItems[7].Icon := 'ICON_NOTES';
  MenuMainItems[7].Position := 100005;
  MenuMainItems[7].Proc := MenuMainPages;

  MenuMainItems[8].Name := 'My &questions...';
  MenuMainItems[8].URL := vk_url + vk_url_questions;
  MenuMainItems[8].Icon := 'ICON_QUESTIONS';
  MenuMainItems[8].Position := 100006;
  MenuMainItems[8].Proc := MenuMainPages;

  MenuMainItems[9].Name := '&Update Details for all users';
  MenuMainItems[9].URL := '';
  MenuMainItems[9].Icon := 'ICON_INFO';
  MenuMainItems[9].Position := 200000;
  MenuMainItems[9].Proc := MenuMainUpdateDetailsAllUsers;

end;


 // =============================================================================
 // function to react on the plugin's main menu item to update details of all
 // users
 // -----------------------------------------------------------------------------
function MenuMainUpdateDetailsAllUsers(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl;
var
  res: longword;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(MenuMainUpdateDetailsAllUsers) Updating of details for all contacts started...'));

  CloseHandle(BeginThread(nil, 0, @GetInfoAllProc, nil, 0, res));

  Netlib_Log(vk_hNetlibUser, PChar('(MenuMainUpdateDetailsAllUsers) ... updating of details for all contacts finished'));
  Result := 0;
end;

 // =============================================================================
 // function to react on the plugin's contact menu items to open contact's pages,
 // used for main menu also
 // -----------------------------------------------------------------------------
function MenuContactPages(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl;
begin
  ShellAPI.ShellExecute(0, 'open', PChar(Format(MenuContactPagesItems[lParam1].URL, [DBGetContactSettingDWord(wParam, piShortName, 'ID', 0)])), nil, nil, 0);
  Result := 0;
end;

 // =============================================================================
 // function to react on the plugin's main menu items to open our pages
 // -----------------------------------------------------------------------------
function MenuMainPages(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl;
begin
  ShellAPI.ShellExecute(0, 'open', PChar(Format(MenuMainItems[lParam1].URL, [DBGetContactSettingDWord(wParam, piShortName, 'ID', 0)])), nil, nil, 0);
  Result := 0;
end;

 // =============================================================================
 // function to react on the plugin's contact menu item to add non-Friend
 // contact to our list permanently (=request authorization)
 // -----------------------------------------------------------------------------
function MenuContactAddPermanently(wParam: wParam; lParam: lParam; lParam1: integer): integer; cdecl;
begin
  // requesting authorization text
  Result := DialogBoxParamW(hInstance, MAKEINTRESOURCEW(WideString('VK_AUTHASK')), 0, @DlgAuthAsk, Windows.lParam(wParam));
end;

 // =============================================================================
 // function to react on the plugin's menu item - Open Webpage
 // this is called by Miranda, thus has to use the cdecl calling convention
 // all services and hooks need this.
 // -----------------------------------------------------------------------------
function MenuMainOpenWebpage(wParam: WPARAM; lParam: LPARAM): integer; cdecl;
begin
  ShellAPI.ShellExecute(0, 'open', PAnsiChar(vk_url), nil, nil, 0);
  Result := 0;
end;

 // =============================================================================
 // function to react on the plugin's contact menu items to write on the wall
 // -----------------------------------------------------------------------------
function MenuContactWall(wParam: WPARAM; lParam: LPARAM; lParam1: integer): integer; cdecl;
begin
  Result := DialogBoxParamW(hInstance, MAKEINTRESOURCEW(WideString('VK_WALL_PICTURE')), 0, @DlgWallPic, Windows.lParam(wParam));
end;

 // =============================================================================
 // TEST FUNCTION
 // -----------------------------------------------------------------------------
function MenuContactTest(wParam: WPARAM; lParam: LPARAM): integer; cdecl;
begin
  Result := 0;
end;

 // =============================================================================
 // function to update list of Status menu items
 // -----------------------------------------------------------------------------
function MenuStatusPrebuild(wParam: wParam; lParam: lParam): integer; cdecl;
begin
  MenuStatusAdditionalPrebuild(wParam, lParam); // update Additional Statuses

  Result := 0;
end;

 // =============================================================================
 // procedure to get short information about contact
 // -----------------------------------------------------------------------------
procedure MenuInit();
var
  mi:     TCListMenuItem; // main menu item
  cmi:    TCListMenuItem; // contact menu item
  i:      byte;
  srvFce: PChar;
begin

  MenuContactPagesItemsInit();
  MenuMainItemsInit();

  // creation of main menu
  FillChar(mi, sizeof(mi), 0);
  mi.cbSize := sizeof(mi);
  mi.popupPosition := 500000; // position above Options
  mi.szPopupName.a := piShortName;
  mi.flags := 0;
  for i := Low(MenuMainItems) to High(MenuMainItems) do
  begin
    //approx position on the menu. lower numbers go nearer the top
    //separator is on each 100000 position
    //please note that in case in Miranda settings, Customize-Menus there are some items hidden/moved
    //then by default miranda will place new menu item at bottom
    mi.Position := MenuMainItems[i].Position;
    // no need to separately register with MS_SKIN2_ADDICON all icons we use
    // icons used in menu are registered automatically
    if MenuMainItems[i].Icon <> '' then
      mi.hIcon := LoadImage(hInstance, MAKEINTRESOURCE(MenuMainItems[i].Icon), IMAGE_ICON, 16, 16, 0)
    else
      mi.hIcon := 0;
    srvFce := PChar(Format('%s/MenuMain%d', [piShortName, i]));
    vk_hMenuMainSF[i] := pluginLink^.CreateServiceFunctionParam(srvFce, @MenuMainItems[i].Proc, i);
    mi.pszService := srvFce;
    // WARNING: do not use Translate(TS) for p(t)szName or p(t)szPopupName as they
    // are translated by the core, which may lead to double translation.
    mi.szName.a := PChar(MenuMainItems[i].Name);
    vk_hMenuMain[i] := pluginLink^.CallService(MS_CLIST_ADDMAINMENUITEM, 0, Windows.lparam(@mi));
  end;

  // creation of contact menu items
  FillChar(cmi, sizeof(cmi), 0);
  cmi.cbSize := sizeof(cmi);
  for i := Low(MenuContactPagesItems) to High(MenuContactPagesItems) do
  begin
    cmi.Position := MenuContactPagesItems[i].Position;
    cmi.flags := MenuContactPagesItems[i].flags;
    if MenuContactPagesItems[i].Icon <> '' then
      cmi.hIcon := LoadImage(hInstance, MAKEINTRESOURCE(MenuContactPagesItems[i].Icon), IMAGE_ICON, 16, 16, 0)
    else
      cmi.hIcon := 0;
    srvFce := PChar(Format('%s/MenuContactPages%d', [piShortName, i]));
    vk_hMenuContactPagesSF[i] := pluginLink^.CreateServiceFunctionParam(srvFce, @MenuContactPagesItems[i].Proc, i);
    cmi.pszService := srvFce;
    cmi.szName.a := PChar(MenuContactPagesItems[i].Name);
    cmi.pszContactOwner := piShortName;
    vk_hMenuContactPages[i] := pluginLink^.CallService(MS_CLIST_ADDCONTACTMENUITEM, 0, Windows.lparam(@cmi));
    if cmi.hIcon <> 0 then
      DestroyIcon(cmi.hIcon);
  end;

  // 'Read Additional status' menu item is added in vk_xstatus

  // add one more, temp item
  cmi.flags := 0;
  cmi.Position := -100;
  srvFce := PChar(Format('%s/MenuContactTemp', [piShortName]));
  pluginLink^.CreateServiceFunction(srvFce, @MenuContactTest);
  cmi.pszService := srvFce;
  cmi.szName.a := 'Temp test function';
  cmi.pszContactOwner := piShortName;
  // pluginLink^.CallService(MS_CLIST_ADDCONTACTMENUITEM, 0,  Windows.lparam(@cmi));

  // creation of status menu items
  vk_hkMenuStatusPrebuild := pluginLink^.HookEvent(ME_CLIST_PREBUILDSTATUSMENU, @MenuStatusPrebuild);
  MenuStatusPrebuild(0, 0);

end;

procedure MenuDestroy();
var
  i: byte;
begin
  for i := Low(vk_hMenuContactPages) to High(vk_hMenuContactPages) do
  begin
    pluginLink^.DestroyServiceFunction(vk_hMenuContactPages[i]);
    pluginLink^.DestroyServiceFunction(vk_hMenuContactPagesSF[i]);
  end;

  for i := Low(vk_hMenuMain) to High(vk_hMenuMain) do
  begin
    pluginLink^.DestroyServiceFunction(vk_hMenuMain[i]);
    pluginLink^.DestroyServiceFunction(vk_hMenuMainSF[i]);
  end;

  pluginLink^.UnhookEvent(vk_hkMenuStatusPrebuild);

end;


begin
end.
