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
 vk_opts.pas

 [ Description ]
 Module to support Options dialogs for VKontakte plugin

 [ Known Issues ]
 - Apply button becomes enabled even when no changes are done
 - If changes are done on one page and then OK or Apply is pressed, changes
   done on another page are not applied and not saved
 - If 'avatars support' checkbox is unchecked, according avatar settings don't
   become disable
 - Changes done in timings are affected only after plugin restart


 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_opts;

interface

uses 
  m_globaldefs,
  m_api,
  
  vk_common, // module with common functions
  vk_global, // module with global variables and constant used
  vk_popup,  // module to support popups

  Commctrl,
  Messages,
  ShellAPI,
  SysUtils,
  Windows;
             

{$include res\dlgopt\i_const.inc}// contains list of ids used in dialogs

{$resource dlgopt.res}// resource file with dialogs

function DlgProcOptionsAcc(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function DlgProcOptionsAdv(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function DlgProcOptionsAdv2(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function DlgProcOptionsNews(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function DlgProcOptionsGroups(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function DlgProcOptionsComments(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function DlgProcOptionsPopup(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function DlgProcOptionsIgnore(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
function OnOptInitialise(wParam, lParam: DWord): integer; cdecl;

implementation

const
  IGNOREEVENT_MAX = 7;
  //  ignoreIdToPf1: array[0..IGNOREEVENT_MAX-1] of DWord = (PF1_IMRECV,PF1_URLRECV,PF1_FILERECV,-1,-1,-1,-1);
  //  ignoreIdToPf4: array[0..IGNOREEVENT_MAX-1] of DWord = (-1,-1,-1,-1,-1,-1,PF4_SUPPORTTYPING);
  ignoreIdToPf1: array[0..IGNOREEVENT_MAX - 1] of integer = (-1, -1, -1, -1, -1, -1, -1);
  ignoreIdToPf4: array[0..IGNOREEVENT_MAX - 1] of integer = (-1, -1, -1, -1, -1, -1, -1);

var
  TempNilArray: array of integer;

function OnOptInitialise(wParam{addinfo}, lParam{0}: DWord): integer; cdecl;
var
  odp: TOPTIONSDIALOGPAGE;
begin
  ZeroMemory(@odp, sizeof(odp));
  odp.cbSize := sizeof(odp);
  odp.flags := ODPF_BOLDGROUPS;
  odp.Position := 900002000;
  odp.hInstance := hInstance;
  odp.szGroup.a := 'Network';              // identifies where plugin's options should appear
  odp.szTitle.a := Translate(piShortName); // // translate plugin's title

  odp.szTab.a := 'Account';
  odp.pszTemplate := 'SETTINGS_LOGIN'; // identifies template from res file
  odp.pfnDlgProc := @DlgProcOptionsAcc;
  PluginLink.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));

  odp.szTab.a := 'Advanced';
  odp.pszTemplate := 'SETTINGS_ADVANCED'; // identifies template from res file
  odp.pfnDlgProc := @DlgProcOptionsAdv;
  PluginLink.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));

  odp.szTab.a := 'Advanced (continued)';
  odp.pszTemplate := 'SETTINGS_ADVANCED2';
  odp.pfnDlgProc := @DlgProcOptionsAdv2;
  PluginLink.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));

  odp.szTab.a := 'News';
  odp.pszTemplate := 'SETTINGS_NEWS'; // identifies template from res file
  odp.pfnDlgProc := @DlgProcOptionsNews;
  PluginLink.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));

  odp.szTab.a := 'Groups';
  odp.pszTemplate := 'SETTINGS_GROUPS'; // identifies template from res file
  odp.pfnDlgProc := @DlgProcOptionsGroups;
  PluginLink.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));

  odp.szTab.a := 'Comments';
  odp.pszTemplate := 'SETTINGS_COMMENTS'; // identifies template from res file
  odp.pfnDlgProc := @DlgProcOptionsComments;
  PluginLink.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));

  odp.szTab.a := 'Ignore';
  odp.pszTemplate := 'SETTINGS_IGNORE'; // identifies template from res file
  odp.pfnDlgProc := @DlgProcOptionsIgnore;
  // PluginLink.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));


  // popups
  if bPopupSupported then
  begin
    odp.szTab.a := nil;
    odp.Position := 900004000;
    odp.szGroup.a := 'PopUps';
    odp.pszTemplate := 'SETTINGS_POPUP';
    odp.pfnDlgProc := @DlgProcOptionsPopup;
    PluginLink^.CallService(MS_OPT_ADDPAGE, wParam, dword(@odp));
  end;

  Result := 0;
end;

function GetMask(hContact: THandle): DWord;
var
  mask: DWord;
begin
  mask := DBGetContactSettingDWord(hContact, piShortName, 'IgnoreMask', 0);
  if mask = 0 then
    if hContact = 0 then
      mask := 0;
  Result := mask;
end;

procedure SetListGroupIcons(hwndList: THandle; hFirstItem: THandle; hParentItem: THandle; var groupChildCount: array of integer);
var
  typeOfFirst:       integer;
  iconOn:            array[0..IGNOREEVENT_MAX - 1] of integer; // = (1,1,1,1,1,1,1);
  childCount:        array[0..IGNOREEVENT_MAX - 1] of integer; // = (0,0,0,0,0,0,0);
  i:                 integer;
  iImage:            integer;
  hItem, hChildItem: THandle;
begin
  for i := 0 to IGNOREEVENT_MAX - 1 do
  begin
    iconOn[i] := 1;
    childCount[i] := 0;
  end;
  typeOfFirst := SendMessage(hwndList, CLM_GETITEMTYPE, Windows.wParam(hFirstItem), 0);
  // check groups
  if (typeOfFirst = CLCIT_GROUP) then
    hItem := hFirstItem
  else
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTGROUP, Windows.lParam(hFirstItem)));
  while hItem <> 0 do
  begin
    hChildItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_CHILD, Windows.lParam(hItem)));
    if hChildItem <> 0 then
      SetListGroupIcons(hwndList, hChildItem, hItem, childCount);
    for i := Low(iconOn) to High(iconOn) do
      if (iconOn[i] <> 0) and (SendMessage(hwndList, CLM_GETEXTRAIMAGE, Windows.wParam(hItem), i) = 0) then
        iconOn[i] := 0;
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTGROUP, Windows.lParam(hItem)));
  end;
  // check contacts
  if (typeOfFirst = CLCIT_CONTACT) then
    hItem := hFirstItem
  else
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTCONTACT, Windows.lParam(hFirstItem)));
  while hItem <> 0 do
  begin
    for i := Low(iconOn) to High(iconOn) do
    begin
      iImage := SendMessage(hwndList, CLM_GETEXTRAIMAGE, Windows.wParam(hItem), i);
      if (iconOn[i] <> 0) and (iImage = 0) then
        iconOn[i] := 0;
      if (iImage <> $FF) then
        Inc(childCount[i]);
    end;
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTCONTACT, Windows.lParam(hItem)));
  end;
  //set icons
  for i := Low(iconOn) to High(iconOn) do
  begin
    SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hParentItem), MAKELPARAM(i, IfThen(childCount[i] <> 0, IfThen(iconOn[i] <> 0, i + 3, 0), $FF)));
    if (Length(groupChildCount) > 0) then
      groupChildCount[i] := groupChildCount[i] + childCount[i];
    // if(groupChildCount) groupChildCount[i]+=childCount[i];
  end;
  SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hParentItem), MAKELPARAM(IGNOREEVENT_MAX, 1));
  SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hParentItem), MAKELPARAM(IGNOREEVENT_MAX + 1, 2));
end;


procedure SetAllChildIcons(hwndList: THandle; hFirstItem: THandle; iColumn: integer; iImage: integer);
var
  typeOfFirst, iOldIcon: integer;
  hItem, hChildItem:     THandle;
begin
  typeOfFirst := SendMessage(hwndList, CLM_GETITEMTYPE, Windows.wParam(hFirstItem), 0);
  // check groups
  if (typeOfFirst = CLCIT_GROUP) then
    hItem := hFirstItem
  else
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTGROUP, Windows.lParam(hFirstItem)));
  while hItem <> 0 do
  begin
    hChildItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_CHILD, Windows.lParam(hItem)));
    if (hChildItem <> 0) then
      SetAllChildIcons(hwndList, hChildItem, iColumn, iImage);
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTGROUP, Windows.lParam(hItem)));
  end;
  // check contacts
  if (typeOfFirst = CLCIT_CONTACT) then
    hItem := hFirstItem
  else
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTCONTACT, Windows.lParam(hFirstItem)));
  while hItem <> 0 do
  begin
    iOldIcon := SendMessage(hwndList, CLM_GETEXTRAIMAGE, Windows.wParam(hItem), iColumn);
    if (iOldIcon <> $FF) and (iOldIcon <> iImage) then
      SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(iColumn, iImage));
    hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_NEXTCONTACT, Windows.lParam(hItem)));
  end;
end;


procedure ResetListOptions(hwndList: THandle);
var
  i: integer;
begin
  SendMessage(hwndList, CLM_SETBKBITMAP, 0, Windows.lParam(HBitmap(0)));
  SendMessage(hwndList, CLM_SETBKCOLOR, GetSysColor(COLOR_WINDOW), 0);
  SendMessage(hwndList, CLM_SETGREYOUTFLAGS, 0, 0);
  SendMessage(hwndList, CLM_SETLEFTMARGIN, 4, 0);
  SendMessage(hwndList, CLM_SETINDENT, 10, 0);
  SendMessage(hwndList, CLM_SETHIDEEMPTYGROUPS, 1, 0);
  for i := 0 to FONTID_MAX do
    SendMessage(hwndList, CLM_SETTEXTCOLOR, i, GetSysColor(COLOR_WINDOWTEXT));
end;


procedure SetIconsForColumn(hwndList: THandle; hItem: THandle; hItemAll: THandle; iColumn: integer; iImage: integer);
var
  itemType:  integer;
  oldiImage: integer;
begin
  itemType := SendMessage(hwndList, CLM_GETITEMTYPE, Windows.wParam(hItem), 0);
  if (itemType = CLCIT_CONTACT) then
  begin
    oldiImage := SendMessage(hwndList, CLM_GETEXTRAIMAGE, Windows.wParam(hItem), iColumn);
    if (oldiImage <> $FF) and (oldiImage <> iImage) then
      SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(iColumn, iImage));
  end
  else
    if (itemType = CLCIT_INFO) then
    begin
      if (hItem = hItemAll) then
        SetAllChildIcons(hwndList, hItem, iColumn, iImage)
      else
        SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(iColumn, iImage)); //hItemUnknown
    end
    else
      if (itemType = CLCIT_GROUP) then
      begin
        hItem := THandle(SendMessage(hwndList, CLM_GETNEXTITEM, CLGN_CHILD, Windows.lParam(hItem)));
        if hItem <> 0 then
          SetAllChildIcons(hwndList, hItem, iColumn, iImage);
      end;
end;


procedure InitialiseItem(hwndList: THandle; hContact: THandle; hItem: THandle; proto1Caps: DWord; proto4Caps: DWord);
var
  mask: DWord;
  i:    integer;
begin
  mask := GetMask(hContact);
  for i := 0 to IGNOREEVENT_MAX - 1 do
    if ((ignoreIdToPf1[i] = -1) and (ignoreIdToPf4[i] = -1)) or (((proto1Caps <> 0) and (ignoreIdToPf1[i] <> 0)) or ((proto4Caps <> 0) and (ignoreIdToPf4[i] <> 0))) then
      SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(i, IfThen((mask and (1 shl i)) <> 0, i + 3, 0)));
  SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(IGNOREEVENT_MAX, 1));
  SendMessage(hwndList, CLM_SETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(IGNOREEVENT_MAX + 1, 2));
end;


procedure SaveItemMask(hwndList: THandle; hContact: THandle; hItem: THandle; const pszSetting: PChar);
var
  mask:      DWord;
  i, iImage: integer;
begin
  mask := 0;
  for i := 0 to IGNOREEVENT_MAX - 1 do
  begin
    iImage := SendMessage(hwndList, CLM_GETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(i, 0));
    if (iImage and iImage <> $FF) then
      mask := mask and (1 shl i);
  end;
  DBWriteContactSettingDWord(hContact, piShortName, 'IgnoreMask', mask);
end;

procedure SetAllContactIcons(hwndList: THandle);
var
  hContact, hItem:        THandle;
  proto1Caps, proto4Caps: DWord;
  szProto:                PChar;
begin
  hContact := THandle(pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0));
  while hContact <> 0 do
  begin
    hItem := THandle(SendMessage(hwndList, CLM_FINDCONTACT, Windows.wParam(hContact), 0));
    if (hItem <> 0) and (SendMessage(hwndList, CLM_GETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(IGNOREEVENT_MAX, 0)) = $FF) then
    begin
      szProto := PChar(pluginLink^.CallService(MS_PROTO_GETCONTACTBASEPROTO, Windows.wParam(hContact), 0));
      if szProto = nil then
      begin
        proto1Caps := 0;
        proto4Caps := 0;
      end
      else
      begin
        proto1Caps := CallProtoService(szProto, PS_GETCAPS, PFLAGNUM_1, 0);
        proto4Caps := CallProtoService(szProto, PS_GETCAPS, PFLAGNUM_4, 0);
      end;
      InitialiseItem(hwndList, hContact, hItem, proto1Caps, proto4Caps);
      { unmark hidden contacts
        if(!DBGetContactSettingByte(hContact,"CList","Hidden",0))
   SendMessage(hwndList,CLM_SETCHECKMARK,(WPARAM)hItem,1);
      }
    end;
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
  end;
end;


function DlgProcOptionsIgnore(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  hIml:                   HImageList;
  i:                      integer;
  hIcon:                  THandle;
  hIcons:                 array[0..IGNOREEVENT_MAX + 2] of THandle;
  hItemAll, hItemUnknown: THandle;
  cii:                    TCLCINFOITEM;
  hItem:                  THandle;
  nm:                     PNMCLISTCONTROL;
  hitFlags:               DWord;
  iImage:                 integer;
  hContact:               THandle;
begin
  Result := False;

  case message of
    WM_INITDIALOG:
    begin
      TranslateDialogDefault(Dialog);

      hIml := ImageList_Create(GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), ILC_COLOR32 + ILC_MASK, 3 + IGNOREEVENT_MAX, 3 + IGNOREEVENT_MAX);
      // ImageList_AddIcon_IconLibLoaded(hIml, SKINICON_OTHER_SMALLDOT);
      // temp!!
      // hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(piShortName + '_small_dot')));
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_24')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_25')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_26')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_27')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_28')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_29')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_30')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('core_main_31')));
      ImageList_AddIcon(hIml, hIcon);
      hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(piShortName + '_popups')));
      ImageList_AddIcon(hIml, hIcon);
      ImageList_AddIcon(hIml, hIcon);
      SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_SETEXTRAIMAGELIST, 0, Windows.lParam(hIml));
      for i := Low(hIcons) to High(hIcons) do
        hIcons[i] := ImageList_GetIcon(hIml, 1 + i, ILD_NORMAL);
      SendDlgItemMessage(Dialog, VK_OPT_IGNORE_PIC1, STM_SETICON, Windows.wParam(hIcons[0]), 0);
      SendDlgItemMessage(Dialog, VK_OPT_IGNORE_PIC2, STM_SETICON, Windows.wParam(hIcons[1]), 0);
      ResetListOptions(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST));
      SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_SETEXTRACOLUMNS, IGNOREEVENT_MAX + 2, 0);

      ZeroMemory(@cii, sizeof(cii));
      cii.cbSize := sizeof(cii);
      cii.flags := CLCIIF_GROUPFONT;
      cii.pszText.w := TranslateW('** All contacts **');
      hItemAll := THandle(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_ADDINFOITEM, 0, Windows.lParam(@cii)));
      cii.pszText.w := TranslateW('** Unknown contacts **');
      hItemUnknown := THandle(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_ADDINFOITEM, 0, Windows.lParam(@cii)));
      // InitialiseItem(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), 0, hItemUnknown, -1, -1);
      SetAllContactIcons(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST));
      SetListGroupIcons(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), THandle(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_GETNEXTITEM, CLGN_ROOT, 0)), hItemAll, TempNilArray);

      Result := True;
      Exit;
    end;
    WM_DESTROY:
    begin
      for i := Low(hIcons) to High(hIcons) do
        DestroyIcon(hIcons[i]);
      hIml := HImageList(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_GETEXTRAIMAGELIST, 0, 0));
      ImageList_Destroy(hIml);
      Result := True;
      Exit;
    end;
    WM_SETFOCUS:
    begin
      SetFocus(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST));
    end;
    WM_NOTIFY:
    begin
      case PNMHdr(lParam)^.idFrom of
        VK_OPT_IGNORE_LIST:
        begin
          case PNMHdr(lParam)^.code of
            CLN_LISTREBUILT:
              SetAllContactIcons(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST));
            CLN_CONTACTMOVED:
            begin
              SetListGroupIcons(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), THandle(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_GETNEXTITEM, CLGN_ROOT, 0)), hItemAll, TempNilArray);
            end;
            CLN_OPTIONSCHANGED:
            begin
              ResetListOptions(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST));
            end;
            CLN_CHECKCHANGED:
            begin
              SendMessage(GetParent(Dialog), PSM_CHANGED, 0, 0);
            end;
            NM_CLICK:
            begin
              nm := PNMCLISTCONTROL(lParam);
              if (nm.iColumn = -1) then
                Exit;
              hItem := THandle(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_HITTEST, Windows.wParam(@hitFlags), MAKELPARAM(nm.pt.x, nm.pt.y)));
              if (hItem = 0) then
                Exit;
              if (hitFlags and CLCHT_ONITEMEXTRA) = 0 then
                Exit;
              if nm.iColumn = IGNOREEVENT_MAX then   // ignore all
              begin
                for iImage := 0 to IGNOREEVENT_MAX - 1 do
                  SetIconsForColumn(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), hItem, hItemAll, iImage, iImage + 3);
              end
              else
                if nm.iColumn = IGNOREEVENT_MAX + 1 then // ignore none
                begin
                  for iImage := 0 to IGNOREEVENT_MAX - 1 do
                    SetIconsForColumn(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), hItem, hItemAll, iImage, 0);
                end
                else
                begin
                  iImage := SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_GETEXTRAIMAGE, Windows.wParam(hItem), MAKELPARAM(nm.iColumn, 0));
                  if iImage = 0 then
                    iImage := nm.iColumn + 3
                  else
                    if iImage <> $FF then
                      iImage := 0;
                  SetIconsForColumn(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), hItem, hItemAll, nm.iColumn, iImage);
                end;
              SetListGroupIcons(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), THandle(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_GETNEXTITEM, CLGN_ROOT, 0)), hItemAll, TempNilArray);
              SendMessage(GetParent(Dialog), PSM_CHANGED, 0, 0);
            end;
          end;
        end;
        0:
        begin
          case PNMHdr(lParam)^.code of
            PSN_APPLY:
            begin
              hContact := THandle(CallService(MS_DB_CONTACT_FINDFIRST, 0, 0));
              while hContact <> 0 do
              begin
                hItem := THandle(SendDlgItemMessage(Dialog, VK_OPT_IGNORE_LIST, CLM_FINDCONTACT, Windows.wParam(hContact), 0));
                if (hItem <> 0) then
                  SaveItemMask(GetDlgItem(Dialog, VK_OPT_IGNORE_LIST), hContact, hItem, 'Mask1');
                // hide not marked contacts
                // if(SendDlgItemMessage(hwndDlg,VK_OPT_IGNORE_LIST,CLM_GETCHECKMARK,(WPARAM)hItem,0))
                // DBDeleteContactSetting(hContact,"CList","Hidden");
                // else
                //DBWriteContactSettingByte(hContact,"CList","Hidden",1);

                hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
              end;
              Result := True;
              Exit;
            end;
          end;
        end;
      end;
    end;
  end;
end;


function DlgProcOptionsAcc(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  str: string;   // temp variable for types conversion
  pc:  PChar;    // temp variable for types conversion
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
    begin
      // translate all dialog texts
      TranslateDialogDefault(Dialog);

      // load options - define text of each item in the options by their ids, given in res file
      vk_o_login := DBReadString(0, piShortName, opt_UserName, nil);
      SetDlgItemText(dialog, VK_OPT_EMAIL, PChar(vk_o_login)); // e-mail

      vk_o_pass := DBReadString(0, piShortName, opt_UserPass, nil);
      if trim(vk_o_pass) <> '' then // decrypt password
        pluginLink^.CallService(MS_DB_CRYPT_DECODESTRING, SizeOf(vk_o_pass), Windows.lparam(vk_o_pass));
      SetDlgItemText(dialog, VK_OPT_PASS, PChar(vk_o_pass)); // password


      // send Changed message - make sure we can save the dialog
      SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

      Result := True;
    end;
    // code is executed, when user clicks
    WM_COMMAND:
    begin
      case word(wParam) of
        VK_OPT_NEWID: // create new account
        begin
          ShellAPI.ShellExecute(0, 'open', PAnsiChar(vk_url_prefix + vk_url_host + vk_url_register), nil, nil, 0);
          Result := True;
        end;
        VK_OPT_PASSLOST: // retrieve lost password
        begin
          ShellAPI.ShellExecute(0, 'open', PAnsiChar(vk_url_prefix + vk_url_host + vk_url_forgot), nil, nil, 0);
          Result := True;
        end;
      end;
      SendMessage(GetParent(dialog), PSM_CHANGED, dialog, 0);
    end;
    // code is executed, when user pressed OK or Apply
    WM_NOTIFY:
    begin
      // if user pressed Apply
      if PNMHdr(lParam)^.code = PSN_APPLY then
      begin
        SetLength(Str, 256);
        pc := PChar(Str);
        GetDlgItemText(dialog, VK_OPT_EMAIL, pc, 256);
        DBWriteContactSettingString(0, piShortName, opt_UserName, pc);
        vk_o_login := pc;

        pc := PChar(Str);
        GetDlgItemText(dialog, VK_OPT_PASS, pc, 256);
        // encode password
        pluginLink^.CallService(MS_DB_CRYPT_ENCODESTRING, SizeOf(pc), Windows.lparam(pc));
        DBWriteContactSettingString(0, piShortName, opt_UserPass, pc);
        vk_o_pass := pc;

        Result := True;
      end;
    end;
  end;
end;


function DlgProcOptionsAdv(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  val: integer;
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
    begin
      // translate all dialog texts
      TranslateDialogDefault(Dialog);

      val := DBGetContactSettingDWord(0, piShortName, opt_UserKeepOnline, 900);
      SetDlgItemText(dialog, VK_OPT_KEEPONLINE_SEC, PChar(IntToStr(val))); // send online msg each ... secs

      val := DBGetContactSettingDWord(0, piShortName, opt_UserCheckNewMessages, 60);
      SetDlgItemText(dialog, VK_OPT_CHECKNEWMSG_SEC, PChar(IntToStr(val))); // check for new msgs each ... secs

      val := DBGetContactSettingDWord(0, piShortName, opt_UserUpdateFriendsStatus, 60);
      SetDlgItemText(dialog, VK_OPT_CHECKFRSTATUS_SEC, PChar(IntToStr(val))); // update friend's status each ... secs

      val := DBGetContactSettingByte(0, piShortName, opt_UserGetMinInfo, 0);
      CheckDlgButton(dialog, VK_OPT_GETMININFO, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserRemoveEmptySubj, 1);
      CheckDlgButton(dialog, VK_OPT_REMOVEEMTPYSUBJ, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserUpdateAddlStatus, 1);
      CheckDlgButton(dialog, VK_OPT_ADDLSTATUSSUPPORT, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserAvatarsSupport, 1);
      CheckDlgButton(dialog, VK_OPT_AVATARSSUPPORT, val);

      val := DBGetContactSettingDWord(0, piShortName, opt_UserAvatarsUpdateFreq, 3600); // update friend's avatars each ... secs
      SetDlgItemText(dialog, VK_OPT_AVATARSUPD_SEC, PChar(IntToStr(val)));

      val := DBGetContactSettingByte(0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, 1);
      CheckDlgButton(dialog, VK_OPT_AVATARSUPDWHENGETINFO, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserPreferredHost, 1); // choose preferred VK host
      case val of
        1:
          CheckRadioButton(dialog, VK_OPT_HOSTRU, VK_OPT_HOSTCOM, VK_OPT_HOSTRU);
        2:
          CheckRadioButton(dialog, VK_OPT_HOSTRU, VK_OPT_HOSTCOM, VK_OPT_HOSTCOM);
        else
          CheckRadioButton(dialog, VK_OPT_HOSTRU, VK_OPT_HOSTCOM, VK_OPT_HOSTRU);
      end;

      // send Changed message - make sure we can save the dialog
      SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

      Result := True;
    end;
    // code is executed, when user clicks on link in the Options
    WM_COMMAND:
    begin
      SendMessage(GetParent(dialog), PSM_CHANGED, dialog, 0);
    end;
    // code is executed, when user pressed OK or Apply
    WM_NOTIFY:
    begin
      // if user pressed Apply
      if PNMHdr(lParam)^.code = PSN_APPLY then
      begin
        val := GetDlgInt(dialog, VK_OPT_KEEPONLINE_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_UserKeepOnline, val);

        val := GetDlgInt(dialog, VK_OPT_CHECKNEWMSG_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_UserCheckNewMessages, val);

        val := GetDlgInt(dialog, VK_OPT_CHECKFRSTATUS_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_UserUpdateFriendsStatus, val);

        DBWriteContactSettingByte(0, piShortName, opt_UserGetMinInfo, byte(IsDlgButtonChecked(dialog, VK_OPT_GETMININFO)));

        DBWriteContactSettingByte(0, piShortName, opt_UserRemoveEmptySubj, byte(IsDlgButtonChecked(dialog, VK_OPT_REMOVEEMTPYSUBJ)));

        DBWriteContactSettingByte(0, piShortName, opt_UserUpdateAddlStatus, byte(IsDlgButtonChecked(dialog, VK_OPT_ADDLSTATUSSUPPORT)));

        DBWriteContactSettingByte(0, piShortName, opt_UserAvatarsSupport, byte(IsDlgButtonChecked(dialog, VK_OPT_AVATARSSUPPORT)));

        val := GetDlgInt(dialog, VK_OPT_AVATARSUPD_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_UserAvatarsUpdateFreq, val);

        DBWriteContactSettingByte(0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, byte(IsDlgButtonChecked(dialog, VK_OPT_AVATARSUPDWHENGETINFO)));

        if IsDlgButtonChecked(dialog, VK_OPT_HOSTCOM) = BST_CHECKED then
        begin
          DBWriteContactSettingDWord(0, piShortName, opt_UserPreferredHost, 2);  // vk.com
          vk_url_host := 'vk.com';
        end
        else
        begin
          DBWriteContactSettingDWord(0, piShortName, opt_UserPreferredHost, 1); // vkontakte.ru
          vk_url_host := 'vkontakte.ru';
        end;

        Result := True;
      end;
    end;
  end;
end;

function DlgProcOptionsAdv2(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  val: integer;
  str: string;       // temp variable for types conversion
  pc:  PWideChar;    // temp variable for types conversion
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
    begin
      // translate all dialog texts
      TranslateDialogDefault(Dialog);

      SetDlgItemTextW(dialog, VK_OPT_DEFAULT_GROUP, PWideChar(DBReadUnicode(0, piShortName, opt_UserDefaultGroup, nil))); // default group

      val := DBGetContactSettingByte(0, piShortName, opt_UserVKontakteURL, 0);
      CheckDlgButton(dialog, VK_OPT_VKONTAKTE_URL, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, 0);
      CheckDlgButton(dialog, VK_OPT_ADDLSTATUS_FOR_OFFLINE, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserUseLocalTimeForIncomingMessages, 0);
      CheckDlgButton(dialog, VK_OPT_LOCALTIME_FOR_INC_MSGS, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserDontDeleteFriendsFromTheServer, 0);
      CheckDlgButton(dialog, VK_OPT_DONT_DELETE_CONTACTS, val);

      val := DBGetContactSettingByte(0, piShortName, opt_UserNonFriendsStatusSupport, 0);
      CheckDlgButton(dialog, VK_OPT_UPDATE_STATUS_NONFRIENDS, val);

      val := DBGetContactSettingByte(0, piShortName, opt_WallReadSupport, 1);
      CheckDlgButton(dialog, VK_OPT_WALLSUPPORT, val);

      SetDlgItemInt(dialog, VK_OPT_WALLUPD_SEC, DBGetContactSettingDWord(0, piShortName, opt_WallUpdateFreq, 7200), True);

      val := DBGetContactSettingByte(0, piShortName, opt_WallSeparateContactUse, 0);
      CheckDlgButton(dialog, VK_OPT_WALL_SEPARATECONTACT, val);

      val := DBGetContactSettingByte(0, piShortName, opt_WallUseLocalTime, 0);
      CheckDlgButton(dialog, VK_OPT_WALL_USELOCALTIME, val);

      // send Changed message - make sure we can save the dialog
      SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

      Result := True;
    end;
    // code is executed, when user clicks on link in the Options
    WM_COMMAND:
    begin
      SendMessage(GetParent(dialog), PSM_CHANGED, dialog, 0);
    end;
    // code is executed, when user pressed OK or Apply
    WM_NOTIFY:
    begin
      // if user pressed Apply
      if PNMHdr(lParam)^.code = PSN_APPLY then
      begin
        SetLength(Str, 256);
        pc := PWideChar(WideString(Str));
        GetDlgItemTextW(dialog, VK_OPT_DEFAULT_GROUP, pc, 256);
        DBWriteContactSettingUnicode(0, piShortName, opt_UserDefaultGroup, pc);

        DBWriteContactSettingByte(0, piShortName, opt_UserVKontakteURL, byte(IsDlgButtonChecked(dialog, VK_OPT_VKONTAKTE_URL)));

        DBWriteContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, byte(IsDlgButtonChecked(dialog, VK_OPT_ADDLSTATUS_FOR_OFFLINE)));

        DBWriteContactSettingByte(0, piShortName, opt_UserUseLocalTimeForIncomingMessages, byte(IsDlgButtonChecked(dialog, VK_OPT_LOCALTIME_FOR_INC_MSGS)));

        DBWriteContactSettingByte(0, piShortName, opt_UserDontDeleteFriendsFromTheServer, byte(IsDlgButtonChecked(dialog, VK_OPT_DONT_DELETE_CONTACTS)));

        DBWriteContactSettingByte(0, piShortName, opt_UserNonFriendsStatusSupport, byte(IsDlgButtonChecked(dialog, VK_OPT_UPDATE_STATUS_NONFRIENDS)));

        DBWriteContactSettingByte(0, piShortName, opt_WallReadSupport, byte(IsDlgButtonChecked(dialog, VK_OPT_WALLSUPPORT)));

        DBWriteContactSettingByte(0, piShortName, opt_WallUseLocalTime, byte(IsDlgButtonChecked(dialog, VK_OPT_WALL_USELOCALTIME)));

        DBWriteContactSettingByte(0, piShortName, opt_WallSeparateContactUse, byte(IsDlgButtonChecked(dialog, VK_OPT_WALL_SEPARATECONTACT)));

        val := GetDlgInt(dialog, VK_OPT_WALLUPD_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_WallUpdateFreq, val);

        Result := True;
      end;
    end;
  end;
end;

function DlgProcOptionsNews(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  val: integer;
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
    begin
      // translate all dialog texts
      TranslateDialogDefault(Dialog);

      val := DBGetContactSettingByte(0, piShortName, opt_NewsSupport, 1);
      CheckDlgButton(dialog, VK_OPT_NEWSSUPPORT, val);

      val := DBGetContactSettingDWord(0, piShortName, opt_NewsSecs, 300);
      SetDlgItemText(dialog, VK_OPT_NEWS_SEC, PChar(IntToStr(val))); // check news each ... secs

      val := DBGetContactSettingByte(0, piShortName, opt_NewsMin, 0);
      CheckDlgButton(dialog, VK_OPT_NEWS_MINIMAL, val);

      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterPhotos, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_PHOTO, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterVideos, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_VIDEO, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterNotes, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_NOTE, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterThemes, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_SUBJ, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterFriends, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_FRIEND, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterStatuses, 0);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_STATUS, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterGroups, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_GROUP, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterMeetings, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_MEETING, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterAudio, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_AUDIO, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterPersonalData, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_PERSONAL, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterTags, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_TAGS, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterGifts, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_GIFTS, val);
      val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterApps, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_APPS, val);

      val := DBGetContactSettingByte(0, piShortName, opt_NewsLinks, 1);
      CheckDlgButton(dialog, VK_OPT_NEWS_SUPPORTLINKS, val);

      val := DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0);
      CheckDlgButton(dialog, VK_OPT_NEWS_SEPARATE_CONTACT, val);

      // send Changed message - make sure we can save the dialog
      SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

      Result := True;
    end;
    // code is executed, when user clicks on link in the Options
    WM_COMMAND:
    begin
      SendMessage(GetParent(dialog), PSM_CHANGED, dialog, 0);
    end;
    // code is executed, when user pressed OK or Apply
    WM_NOTIFY:
    begin
      // if user pressed Apply
      if PNMHdr(lParam)^.code = PSN_APPLY then
      begin
        // save settings
        DBWriteContactSettingByte(0, piShortName, opt_NewsSupport, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWSSUPPORT)));

        val := GetDlgInt(dialog, VK_OPT_NEWS_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_NewsSecs, val);

        DBWriteContactSettingByte(0, piShortName, opt_NewsMin, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_MINIMAL)));

        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterPhotos, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_PHOTO)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterVideos, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_VIDEO)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterNotes, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_NOTE)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterThemes, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_SUBJ)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterFriends, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_FRIEND)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterStatuses, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_STATUS)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterGroups, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_GROUP)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterMeetings, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_MEETING)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterAudio, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_AUDIO)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterPersonalData, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_PERSONAL)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterTags, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_TAGS)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterApps, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_APPS)));
        DBWriteContactSettingByte(0, piShortName, opt_NewsFilterGifts, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_GIFTS)));

        DBWriteContactSettingByte(0, piShortName, opt_NewsLinks, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_SUPPORTLINKS)));

        DBWriteContactSettingByte(0, piShortName, opt_NewsSeparateContact, byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_SEPARATE_CONTACT)));

        Result := True;
      end;
    end;
  end;
end;

function DlgProcOptionsGroups(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  val: integer;
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
    begin
      // translate all dialog texts
      TranslateDialogDefault(Dialog);

      val := DBGetContactSettingByte(0, piShortName, opt_GroupsSupport, 0);
      CheckDlgButton(dialog, VK_OPT_GROUPSSUPPORT, val);

      val := DBGetContactSettingDWord(0, piShortName, opt_GroupsSecs, 300);
      SetDlgItemText(dialog, VK_OPT_GROUPS_SEC, PChar(IntToStr(val))); // check news each ... secs

      val := DBGetContactSettingByte(0, piShortName, opt_GroupsFilterPhotos, 1);
      CheckDlgButton(dialog, VK_OPT_GROUPS_FILTER_PHOTO, val);
      val := DBGetContactSettingByte(0, piShortName, opt_GroupsFilterVideos, 1);
      CheckDlgButton(dialog, VK_OPT_GROUPS_FILTER_VIDEO, val);
      val := DBGetContactSettingByte(0, piShortName, opt_GroupsFilterNews, 1);
      CheckDlgButton(dialog, VK_OPT_GROUPS_FILTER_NEWS, val);
      val := DBGetContactSettingByte(0, piShortName, opt_GroupsFilterThemes, 1);
      CheckDlgButton(dialog, VK_OPT_GROUPS_FILTER_SUBJ, val);
      val := DBGetContactSettingByte(0, piShortName, opt_GroupsFilterAudio, 1);
      CheckDlgButton(dialog, VK_OPT_GROUPS_FILTER_AUDIO, val);

      val := DBGetContactSettingByte(0, piShortName, opt_GroupsLinks, 1);
      CheckDlgButton(dialog, VK_OPT_GROUPS_SUPPORTLINKS, val);

      // send Changed message - make sure we can save the dialog
      SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

      Result := True;
    end;
    // code is executed, when user clicks on link in the Options
    WM_COMMAND:
    begin
      SendMessage(GetParent(dialog), PSM_CHANGED, dialog, 0);
    end;
    // code is executed, when user pressed OK or Apply
    WM_NOTIFY:
    begin
      // if user pressed Apply
      if PNMHdr(lParam)^.code = PSN_APPLY then
      begin
        // save settings
        DBWriteContactSettingByte(0, piShortName, opt_GroupsSupport, byte(IsDlgButtonChecked(dialog, VK_OPT_GROUPSSUPPORT)));

        val := GetDlgInt(dialog, VK_OPT_GROUPS_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_GroupsSecs, val);

        DBWriteContactSettingByte(0, piShortName, opt_GroupsFilterPhotos, byte(IsDlgButtonChecked(dialog, VK_OPT_GROUPS_FILTER_PHOTO)));
        DBWriteContactSettingByte(0, piShortName, opt_GroupsFilterVideos, byte(IsDlgButtonChecked(dialog, VK_OPT_GROUPS_FILTER_VIDEO)));
        DBWriteContactSettingByte(0, piShortName, opt_GroupsFilterNews, byte(IsDlgButtonChecked(dialog, VK_OPT_GROUPS_FILTER_NEWS)));
        DBWriteContactSettingByte(0, piShortName, opt_GroupsFilterThemes, byte(IsDlgButtonChecked(dialog, VK_OPT_GROUPS_FILTER_SUBJ)));
        DBWriteContactSettingByte(0, piShortName, opt_GroupsFilterAudio, byte(IsDlgButtonChecked(dialog, VK_OPT_GROUPS_FILTER_AUDIO)));

        DBWriteContactSettingByte(0, piShortName, opt_GroupsLinks, byte(IsDlgButtonChecked(dialog, VK_OPT_GROUPS_SUPPORTLINKS)));

        Result := True;
      end;
    end;
  end;
end;

function DlgProcOptionsComments(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  val: integer;
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
    begin
      // translate all dialog texts
      TranslateDialogDefault(Dialog);

      val := DBGetContactSettingByte(0, piShortName, opt_CommentsSupport, 0);
      CheckDlgButton(dialog, VK_OPT_COMMENTSSUPPORT, val);

      val := DBGetContactSettingDWord(0, piShortName, opt_CommentsSecs, 300);
      SetDlgItemText(dialog, VK_OPT_COMMENTS_SEC, PChar(IntToStr(val))); // check news each ... secs

      val := DBGetContactSettingByte(0, piShortName, opt_CommentsFilterPhotos, 1);
      CheckDlgButton(dialog, VK_OPT_COMMENTS_FILTER_PHOTO, val);
      val := DBGetContactSettingByte(0, piShortName, opt_CommentsFilterVideos, 1);
      CheckDlgButton(dialog, VK_OPT_COMMENTS_FILTER_VIDEO, val);
      val := DBGetContactSettingByte(0, piShortName, opt_CommentsFilterNotes, 1);
      CheckDlgButton(dialog, VK_OPT_COMMENTS_FILTER_NOTES, val);
      val := DBGetContactSettingByte(0, piShortName, opt_CommentsFilterThemes, 1);
      CheckDlgButton(dialog, VK_OPT_COMMENTS_FILTER_SUBJ, val);

      val := DBGetContactSettingByte(0, piShortName, opt_CommentsLinks, 1);
      CheckDlgButton(dialog, VK_OPT_COMMENTS_SUPPORTLINKS, val);

      // send Changed message - make sure we can save the dialog
      SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

      Result := True;
    end;
    // code is executed, when user clicks on link in the Options
    WM_COMMAND:
    begin
      SendMessage(GetParent(dialog), PSM_CHANGED, dialog, 0);
    end;
    // code is executed, when user pressed OK or Apply
    WM_NOTIFY:
    begin
      // if user pressed Apply
      if PNMHdr(lParam)^.code = PSN_APPLY then
      begin
        // save settings
        DBWriteContactSettingByte(0, piShortName, opt_CommentsSupport, byte(IsDlgButtonChecked(dialog, VK_OPT_COMMENTSSUPPORT)));

        val := GetDlgInt(dialog, VK_OPT_COMMENTS_SEC);
        DBWriteContactSettingDWord(0, piShortName, opt_CommentsSecs, val);

        DBWriteContactSettingByte(0, piShortName, opt_CommentsFilterPhotos, byte(IsDlgButtonChecked(dialog, VK_OPT_COMMENTS_FILTER_PHOTO)));
        DBWriteContactSettingByte(0, piShortName, opt_CommentsFilterVideos, byte(IsDlgButtonChecked(dialog, VK_OPT_COMMENTS_FILTER_VIDEO)));
        DBWriteContactSettingByte(0, piShortName, opt_CommentsFilterNotes, byte(IsDlgButtonChecked(dialog, VK_OPT_COMMENTS_FILTER_NOTES)));
        DBWriteContactSettingByte(0, piShortName, opt_CommentsFilterThemes, byte(IsDlgButtonChecked(dialog, VK_OPT_COMMENTS_FILTER_SUBJ)));

        DBWriteContactSettingByte(0, piShortName, opt_CommentsLinks, byte(IsDlgButtonChecked(dialog, VK_OPT_COMMENTS_SUPPORTLINKS)));

        Result := True;
      end;
    end;
  end;
end;

function DlgProcOptionsPopup(Dialog: HWnd; Message, wParam, lParam: DWord): boolean; cdecl;
var
  val: integer;
  popupColorOption, popupDelayOption: byte;
begin
  Result := False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
    begin
      // translate all dialog texts
      TranslateDialogDefault(Dialog);

      val := DBGetContactSettingByte(0, piShortName, opt_PopupsEnabled, 1);
      CheckDlgButton(dialog, VK_POPUPS_ENABLED, val);

      // color
      case DBGetContactSettingByte(0, piShortName, opt_PopupsColorOption, 0) of
        0:
          CheckDlgButton(dialog, VK_POPUPS_COLORDEF, BST_CHECKED);
        1:
          CheckDlgButton(dialog, VK_POPUPS_COLORWIN, BST_CHECKED);
        2:
        begin
          CheckDlgButton(dialog, VK_POPUPS_COLORCUST, BST_CHECKED);
          EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_BACK), True);
          EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_FORE), True);
          EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_BACK), True);
          EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_FORE), True);
        end;
      end;

      // delay
      val := DBGetContactSettingDWord(0, piShortName, opt_PopupsDelaySecs, 0);
      if val <> 0 then
        SetDlgItemText(dialog, VK_POPUPS_DELAY_SEC, PChar(IntToStr(val)));
      case DBGetContactSettingByte(0, piShortName, opt_PopupsDelayOption, 0) of
        0:
          CheckDlgButton(dialog, VK_POPUPS_DELAYDEF, BST_CHECKED);
        1:
          CheckDlgButton(dialog, VK_POPUPS_DELAYPERM, BST_CHECKED);
        2:
        begin
          CheckDlgButton(dialog, VK_POPUPS_DELAYCUST, BST_CHECKED);
          EnableWindow(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC), True);
        end;
      end;

      val := DBGetContactSettingDWord(0, piShortName, opt_PopupsColorErrorBackground, GetSysColor(COLOR_BTNFACE));
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_ERR_BACK, CPM_SETCOLOUR, 0, val);
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_ERR_BACK, CPM_SETDEFAULTCOLOUR, 0, GetSysColor(COLOR_BTNFACE));
      val := DBGetContactSettingDWord(0, piShortName, opt_PopupsColorErrorForeground, GetSysColor(COLOR_BTNTEXT));
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_ERR_FORE, CPM_SETCOLOUR, 0, val);
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_ERR_FORE, CPM_SETDEFAULTCOLOUR, 0, GetSysColor(COLOR_BTNTEXT));
      val := DBGetContactSettingDWord(0, piShortName, opt_PopupsColorInfBackground, RGB(223, 227, 230)); // GetSysColor(COLOR_BTNFACE));
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_INF_BACK, CPM_SETCOLOUR, 0, val);
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_INF_BACK, CPM_SETDEFAULTCOLOUR, 0, GetSysColor(COLOR_BTNFACE));
      val := DBGetContactSettingDWord(0, piShortName, opt_PopupsColorInfForeground, RGB(20, 85, 214)); // GetSysColor(COLOR_BTNTEXT));
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_INF_FORE, CPM_SETCOLOUR, 0, val);
      SendDlgItemMessage(dialog, VK_POPUPS_COLOR_INF_FORE, CPM_SETDEFAULTCOLOUR, 0, GetSysColor(COLOR_BTNTEXT));

      val := DBGetContactSettingByte(0, piShortName, opt_PopupsProtoIcon, 1);
      CheckDlgButton(dialog, VK_POPUPS_PROTO_ICON, val);

      Result := True;
    end;
    WM_COMMAND:
    begin
      if HiWord(wParam) = BN_CLICKED then
      begin
        case LoWord(wParam) of
          VK_POPUPS_TEST:
          begin
            // color
            if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORDEF) = BST_CHECKED then
              popupColorOption := 0
            else
              if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORWIN) = BST_CHECKED then
                popupColorOption := 1
              else
                popupColorOption := 2;
            // delay
            if IsDlgButtonChecked(Dialog, VK_POPUPS_DELAYDEF) = BST_CHECKED then
              popupDelayOption := 0
            else
              if IsDlgButtonChecked(Dialog, VK_POPUPS_DELAYPERM) = BST_CHECKED then
                popupDelayOption := 1
              else
                popupDelayOption := 2;

            Popup(
              0,                          // hContact
              'Test informational popup', // MsgText
              1,                          // MsgType = info
              (IsDlgButtonChecked(Dialog, VK_POPUPS_PROTO_ICON) = BST_CHECKED), // ProtoIcon
              popupDelayOption,                       // DelayOption               
              GetDlgInt(Dialog, VK_POPUPS_DELAY_SEC), // DelaySecs
              popupColorOption,                       // ColorOption
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_BACK, CPM_GETCOLOUR, 0, 0), // ColorInfBack
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_FORE, CPM_GETCOLOUR, 0, 0), // ColorInfFore
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_BACK, CPM_GETCOLOUR, 0, 0), // ColorErrorBack
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_FORE, CPM_GETCOLOUR, 0, 0) // ColorErrorFore
              );
            Popup(
              0,                  // hContact
              'Test error popup', // MsgText
              2,                  // MsgType = error
              (IsDlgButtonChecked(Dialog, VK_POPUPS_PROTO_ICON) = BST_CHECKED), // ProtoIcon
              popupDelayOption,                       // DelayOption
              GetDlgInt(dialog, VK_POPUPS_DELAY_SEC), // DelaySecs
              popupColorOption,                       // ColorOption
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_BACK, CPM_GETCOLOUR, 0, 0), // ColorInfBack
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_FORE, CPM_GETCOLOUR, 0, 0), // ColorInfFore
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_BACK, CPM_GETCOLOUR, 0, 0), // ColorErrorBack
              SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_FORE, CPM_GETCOLOUR, 0, 0) // ColorErrorFore
              );

          end;
          VK_POPUPS_DELAYCUST:
          begin
            EnableWindow(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC), True);
            SetFocus(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC));
          end;
          VK_POPUPS_DELAYDEF, VK_POPUPS_DELAYPERM:
            EnableWindow(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC), False);
          VK_POPUPS_COLORCUST:
          begin
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_BACK), True);
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_FORE), True);
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_BACK), True);
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_FORE), True);
          end;
          VK_POPUPS_COLORDEF, VK_POPUPS_COLORWIN:
          begin
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_BACK), False);
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_FORE), False);
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_BACK), False);
            EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_FORE), False);
          end;
        end;
      end;
      SendMessage(GetParent(Dialog), PSM_CHANGED, 0, 0);
      Result := False;
    end;
    // code is executed, when user pressed OK or Apply
    WM_NOTIFY:
    begin
      // if user pressed Apply
      if PNMHdr(lParam)^.code = PSN_APPLY then
      begin
        DBWriteContactSettingByte(0, piShortName, opt_PopupsEnabled, byte(IsDlgButtonChecked(dialog, VK_POPUPS_ENABLED)));
        // color
        if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORDEF) = BST_CHECKED then
          DBWriteContactSettingByte(0, piShortName, opt_PopupsColorOption, 0)
        else
          if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORWIN) = BST_CHECKED then
            DBWriteContactSettingByte(0, piShortName, opt_PopupsColorOption, 1)
          else
          begin
            DBWriteContactSettingByte(0, piShortName, opt_PopupsColorOption, 2);
            DBWriteContactSettingDWord(0, piShortName, opt_PopupsColorErrorBackground, SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_BACK, CPM_GETCOLOUR, 0, 0));
            DBWriteContactSettingDWord(0, piShortName, opt_PopupsColorErrorForeground, SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_FORE, CPM_GETCOLOUR, 0, 0));
            DBWriteContactSettingDWord(0, piShortName, opt_PopupsColorInfBackground, SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_BACK, CPM_GETCOLOUR, 0, 0));
            DBWriteContactSettingDWord(0, piShortName, opt_PopupsColorInfForeground, SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_FORE, CPM_GETCOLOUR, 0, 0));
          end;
        // delay
        if IsDlgButtonChecked(Dialog, VK_POPUPS_DELAYDEF) = BST_CHECKED then
          DBWriteContactSettingByte(0, piShortName, opt_PopupsDelayOption, 0)
        else
          if IsDlgButtonChecked(Dialog, VK_POPUPS_DELAYPERM) = BST_CHECKED then
            DBWriteContactSettingByte(0, piShortName, opt_PopupsDelayOption, 1)
          else
          begin
            DBWriteContactSettingByte(0, piShortName, opt_PopupsDelayOption, 2);
            val := GetDlgInt(dialog, VK_POPUPS_DELAY_SEC);
            if val <> -1 then
              DBWriteContactSettingDWord(0, piShortName, opt_PopupsDelaySecs, val);
          end;
        DBWriteContactSettingByte(0, piShortName, opt_PopupsProtoIcon, byte(IsDlgButtonChecked(dialog, VK_POPUPS_PROTO_ICON)));

        Result := True;
      end;
    end;
  end;
end;

end.
