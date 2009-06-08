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
 vk_xstatus.pas

 [ Description ]
 Module to support Additional Status (xStatus)

 [ Known Issues ]
 - See the code
 - This code doesn't synchronize additional status with the server (so, if
   status is changed on the server, it is not read by the plugin)

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_xstatus;

interface

uses
  m_globaldefs,
  m_api,
  Windows;

  procedure AddlStatusInit();
  procedure AddlStatusDestroy();
  procedure vk_StatusAdditionalGet();
  function MenuStatusAdditionalPrebuild(wParam: wParam; lParam: lParam): Integer; cdecl;

implementation

uses
  vk_global, // module with global variables and constant used
  vk_common, // module with common functions
  vk_http, // module to connect with the site
  vk_menu, // module to work with menus
  vk_popup, // module to support popups
  vk_opts, // unit to work with options

  htmlparse, // module to simplify html parsing

  CommCtrl,
  SysUtils,
  Messages;

const
  opt_AddlStatus: PChar = 'AddlStatus';   // List of settings in DB file

var
  vk_hkListStatusAdditionalPrebuild,
  vk_hkListStatusAdditionalImageApply,
  vk_hkIconsSkinReload: THandle;

  vk_hkMenuContactPrebuild: THandle;

  vk_hMenuContactStatusAdditionalRead,
  vk_hMenuStatus: THandle;   // handle of parent menu

  vk_hMenuStatusAddl: Array [1..13] of THandle;
  vk_hMenuStatusAddlSF: Array [1..13] of THandle;

  // declare procedures
  procedure MenuStatusAdditionalStatusUpdate(); forward;
  procedure StatusAddlSetIcon(hContact, hIcon: THandle); forward;
  function ThreadStatusSet(pwcStatusText: PWideChar): LongWord; forward;

// =============================================================================
// procedure to set up additional status message on the server
// -----------------------------------------------------------------------------
procedure vk_StatusAdditionalSet(StatusText: WideString);
var HTML: String;
    SecurityHash: String;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_StatusAdditionalSet) Assign new additional status...'));
  HTML := HTTP_NL_Get(vk_url_pda_setstatus_securityhash);
  SecurityHash := TextBetween(HTML, 'name="activityhash" value="','"');
  Netlib_Log(vk_hNetlibUser, PChar('(vk_StatusAdditionalSet) ... received security id: ' + SecurityHash));
  Netlib_Log(vk_hNetlibUser, PChar('(vk_StatusAdditionalSet) ... new additional status to be assigned: ' + String(StatusText)));
  if Trim(StatusText)<>'' Then
  begin
    StatusText := UTF8Encode(StatusText);
    StatusText := URLEncode(StatusText);
    HTTP_NL_Get(Format(vk_url_pda_setstatus, [SecurityHash, StatusText]), REQUEST_HEAD); // we don't care about result as of now
  end
  else
    HTTP_NL_Get(Format(vk_url_pda_statusdelete, [SecurityHash]), REQUEST_HEAD);
  Netlib_Log(vk_hNetlibUser, PChar('(vk_StatusAdditionalSet) ... new additional status assigned'));
end;

// =============================================================================
// procedure to get from the server additional status message of all contacts,
// updated today
// -----------------------------------------------------------------------------
procedure vk_StatusAdditionalGet();
var HTML: String; // html content of the pages received
    StrTemp: String;
    hContact: THandle;
    TempFriend: Integer;
    MsgID: String;
    MsgText: WideString;
    MsgDate: TDateTime;
    MsgSender: Integer;
    i: Integer;
    XStatusUpdateTemp: Boolean;
begin
 if DBGetContactSettingByte(0, piShortName, opt_UserUpdateAddlStatus, 1) = 1 then
 begin
   Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) Updating of contact''s additional status...'));

   Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... reading additional statuses from the server'));

   HTML := HTTP_NL_Get(vk_url_pda_news);
   HTML := UTF8Decode(HTML);
   
   If Trim(HTML) <> '' Then
   Begin
    XStatusUpdateTemp := True;

    // update status for online contacts only?
    if DBGetContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, 0) = 0 then
        if DBGetContactSettingWord(TempFriend, piShortName, 'Status', ID_STATUS_OFFLINE) = ID_STATUS_OFFLINE then
        XStatusUpdateTemp := False;

     While Pos('a href=''/id', HTML)<>0 Do
     Begin
       StrTemp := TextBetweenInc(HTML, '<a href=''/id', '<br/>');
       // <a href='id123456'>Surname Name</a> Status text <span class="stTime">11:46</span><br/>
       if (Pos('покинул',StrTemp)=0) and
          (Pos('добавил',StrTemp)=0) and
          (Pos('вступил',StrTemp)=0) and
          (Pos('новую тему',StrTemp)=0) and
          (Pos('открыл темы',StrTemp)=0) and
          (Pos('открыла темы',StrTemp)=0) and
          (Pos('вышла замуж за',StrTemp)=0) and
          (Pos('женился на',StrTemp)=0) and // does it exist?
          (Pos('примет участие во встрече',StrTemp)=0) and
          (Pos('начал встречаться с ',StrTemp)=0) and
          (Pos('начала встречаться с ',StrTemp)=0) and
          (Pos('примет участие во встречах ',StrTemp)=0) and
          (Pos('появилась подруга',StrTemp)=0) and
          (Pos('в активном поиске',StrTemp)=0) and
          (Pos('не будет участвовать во встрече ',StrTemp)=0) then
          begin
            MsgID := TextBetween(StrTemp, '<a href=''/id', '''>');
            MsgText := Trim(TextBetween(StrTemp, '</a> ', ' <span class="stTime">'));
            MsgText := StringReplace(MsgText, '<wbr/>', '', [rfReplaceAll, rfIgnoreCase]);
            MsgText := HTMLDecodeW(MsgText);

            if (TryStrToInt(MsgID, MsgSender)) and (MsgText<>'') then
            begin
              TempFriend := GetContactByID(MsgSender);
              StrTemp := TextBetween(StrTemp, '<span class="stTime">', '</span>');
              if (TempFriend <> 0) and (TryStrToTime(StrTemp, MsgDate)) then // read status for known contacts only
              begin
                if XStatusUpdateTemp then // this boolean variable is defined early
                  begin
                    DBWriteContactSettingByte(TempFriend, piShortName, 'XStatusUpdated', 1); // temp setting to identify that status just has been updated
                    if StrToTime(DBReadString(TempFriend, piShortName, 'XStatusTime', '00:00')) < MsgDate then
                    begin
                      DBWriteContactSettingString(TempFriend, piShortName, 'XStatusTime', PChar(StrTemp));
                      DBWriteContactSettingUnicode(TempFriend, piShortName, 'XStatusMsg', PWideChar(MsgText));
                      DBWriteContactSettingUnicode(TempFriend, piShortName, 'XStatusName', TranslateW('Current')); // required for clist_modern to display status

                      pluginLink^.NotifyEventHooks(he_StatusAdditionalChanged, Windows.WPARAM(TempFriend), 0); // inform other plugins that we've updated xstatus for a contact

                      MsgText := AnsiLowerCase(MsgText);
                      for i:=Low(xStatuses)+2 to High(xStatuses) do
                      // GAP (?): need to remove ... at the end of xStatuses[i].Text
                      begin
                        if (Pos(AnsiLowerCase(xStatuses[i].Text), MsgText)<>0) or
                             (Pos(AnsiLowerCase(String(TranslateW(PWideChar(xStatuses[i].Text)))), MsgText)<>0) then
                        begin
                          DBWriteContactSettingByte(TempFriend, piShortName, 'XStatusId', i);
                          StatusAddlSetIcon(TempFriend, xStatuses[i].IconExtraIndex);
                          break;
                        end;
                      end;
                    end;
                  end;
              end;
            end;
          end;
          Delete(HTML, 1, Pos('<span class="stTime">', HTML)+21);
     End;
   End;

   Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... deleting old additional statuses'));
   hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
   while hContact <> 0 do
   begin
     if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, lParam(PChar(piShortName))) <> 0 Then
     begin
       if DBGetContactSettingByte(hContact, piShortName, 'XStatusUpdated', 0) = 0 then
       begin
         // deleting old data
         DBDeleteContactSetting(hContact, piShortName, 'XStatusTime');
         DBDeleteContactSetting(hContact, piShortName, 'XStatusMsg');
         DBDeleteContactSetting(hContact, piShortName, 'XStatusName');
         DBDeleteContactSetting(hContact, piShortName, 'XStatusId');
         StatusAddlSetIcon(hContact, THandle(-1)); // delete icon
       end;
       DBDeleteContactSetting(hContact, piShortName, 'XStatusUpdated');
     end;
     hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
   end;

   Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... updating of contact''s additional status finished'));
 end;
end;


// =============================================================================
// procedure to define an icon in accordance with additional status
// -----------------------------------------------------------------------------
procedure StatusAddlSetIcon(hContact, hIcon: THandle);
var iec: TIconExtraColumn;
begin
  iec.cbSize := sizeof(iec);
  if DBGetContactSettingWord(hContact, piShortName, 'Status', ID_STATUS_OFFLINE) = ID_STATUS_ONLINE then // apply icon to online contacts only
    iec.hImage := hIcon
  else
    iec.hImage := THandle(-1);
  iec.ColumnType := EXTRA_ICON_ADV1;
  pluginLink^.CallService(MS_CLIST_EXTRA_SET_ICON, hContact, Windows.lParam(@iec));
end;

// =============================================================================
// Dialog function to ask Additional status text
// -----------------------------------------------------------------------------
function DlgAddlStatusAsk(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
var
  pc: PWideChar;    // temp variable for types conversion
begin
  Result := False;
  case Msg of
     WM_INITDIALOG:
       begin
         // translate all dialog texts
         TranslateDialogDefault(Dialog);
         SetFocus(GetDlgItem(Dialog, VK_ADDLSTATUS_TEXT));
         SetDlgItemTextW(Dialog, VK_ADDLSTATUS_TEXT, PWideChar(lParam));
         SetWindowLong(Dialog, GWL_USERDATA, lParam);
       end;
     WM_CLOSE:
       begin
         EndDialog(Dialog, 0);
         Result := True;
       end;
     WM_COMMAND:
       begin
         case wParam of
           VK_ADDLSTATUS_OK:
             begin
               pc := PWideChar(GetWindowLong(Dialog, GWL_USERDATA));
               GetDlgItemTextW(Dialog, VK_ADDLSTATUS_TEXT, pc, 2048);
               EndDialog(Dialog, 0);
               Result := True;
             end;
           VK_ADDLSTATUS_CANCEL:
             begin
               EndDialog(Dialog, 0);
               Result := True;
             end;
         end;
       end;
  end;
end;

// =============================================================================
// function is called when Status menu - Additional status item is chosen
// -----------------------------------------------------------------------------
function MenuStatusAdditionalStatus(wParam: wParam; lParam: lParam; lParam1: Integer): Integer; cdecl;
var smi, smiRoot: TCLISTMENUITEM;
    i: Byte;
    StatusText: WideString;
    pwcStatusText: PWideChar;
    res: LongWord;
begin
 if (vk_Status <> ID_STATUS_ONLINE) and (vk_Status <> ID_STATUS_INVISIBLE) Then
 begin
   Result := 0;
   Exit;
 end;

 FillChar(smi,sizeof(smi),0);
 smi.cbSize:=sizeof(smi);

 StatusText := ''; // no need to update status on the site by default

 if lParam1=200001 Then // 'Custom'
 Begin
   // the code below can display current status, if StatusText is updated here
   // with the current value
   // StatusText := 'some text';
   GetMem(pwcStatusText, (2048 + 1) * SizeOf(WideChar));
   lstrcpynw(pwcStatusText, PWideChar(StatusText), Length(StatusText) + 1);
   DialogBoxParamW(hInstance, MAKEINTRESOURCEW(WideString('VK_ADDLSTATUS')), 0, @DlgAddlStatusAsk, Windows.lParam(pwcStatusText));
   StatusText := WideString(pwcStatusText);
   FreeMem(pwcStatusText);

   if StatusText <> '' then
   Begin
     // save statuses in DB
     // first of 5 status is deleted
     for i:=5 downto 2 do
       DBWriteContactSettingUnicode(0, piShortName, PChar(opt_AddlStatus+IntToStr(i)), DBReadUnicode(0, piShortName, PChar(opt_AddlStatus+IntToStr(i-1)), ''));
     DBWriteContactSettingUnicode(0, piShortName, PChar(opt_AddlStatus+'1'), PWideChar(StatusText));
     // update list of additional statuses
     MenuStatusAdditionalStatusUpdate();
     // remove selection from all items
     for i:=1 to 13 do
     Begin
       smi.flags := CMIF_UNICODE + CMIM_FLAGS;
       pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuStatusAddl[i], Windows.lparam(@smi));
     End;
     // make first item selected
     smi.flags := CMIF_UNICODE + CMIM_FLAGS + CMIF_CHECKED;
     pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuStatusAddl[9], Windows.lparam(@smi));
   End;
 End Else // any other item selected
 Begin
   case lParam1 of
      200001..299999: StatusText := DBReadUnicode(0, piShortName, PChar(opt_AddlStatus+IntToStr(lParam1-200001)), nil);
      300000..399999: StatusText := TranslateW(PWideChar(xStatuses[lParam1-300000].Text));
   end;
   // remove selection from all items
   for i:=1 to 13 do
   Begin
     smi.flags := CMIF_UNICODE + CMIM_FLAGS;
     pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuStatusAddl[i], Windows.lparam(@smi));
   End;
   smi.flags := CMIF_UNICODE + CMIM_FLAGS + CMIF_CHECKED;
   pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, lParam, Windows.lparam(@smi));
 End;

 DBWriteContactSettingDWord(0, piShortName, 'XStatusSelectedItem', lParam1);

 // GAP: we need to update icon of root Additional Status menu
 //      but it doesn't work somehow
 FillChar(smiRoot,sizeof(smiRoot),0);
 smiRoot.cbSize:=sizeof(smiRoot);
 if (lParam1>=300000) and (lParam1<=399999) then
   begin
     DBWriteContactSettingByte(0, piShortName, 'XStatusId', lParam1-300000);
     smiRoot.hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(xStatuses[lParam1-300000].Name)))
   end
 else
   begin
     DBDeleteContactSetting(0, piShortName, 'XStatusId');
     smiRoot.hIcon := 0;
   end;
 smiRoot.flags := CMIF_UNICODE + CMIM_FLAGS + CMIM_ICON;
 pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuStatus, Windows.lparam(@smiRoot));

 GetMem(pwcStatusText, (Length(StatusText) + 1) * SizeOf(WideChar));
 lstrcpynw(pwcStatusText, PWideChar(StatusText), Length(StatusText) + 1);
 CloseHandle(BeginThread(nil, 0, @ThreadStatusSet, pwcStatusText, 0, res));

 Result := 0;
end;

// =============================================================================
// procedure to update list of available additional statuses
// -----------------------------------------------------------------------------
procedure MenuStatusAdditionalStatusUpdate();
var i: Byte;
    smi: TCLISTMENUITEM;
    srvFce: PChar;
begin
  FillChar(smi,sizeof(smi),0);
  smi.cbSize:=sizeof(smi);
  for i:=1 to 5 do
  begin
    if vk_hMenuStatusAddl[8+i]<>0 Then
     Begin // update menu item
       smi.flags := CMIF_UNICODE + CMIF_CHECKED + CMIM_NAME + CMIM_FLAGS;
       smi.szName.w := DBReadUnicode(0, piShortName, PChar(opt_AddlStatus+IntToStr(i)), nil);
       pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuStatusAddl[8+i], Windows.lparam(@smi));
     End Else
     Begin // add item
       if Trim(DBReadUnicode(0, piShortName, PChar(opt_AddlStatus+IntToStr(i)), nil))<>'' Then
       begin
         smi.flags := CMIF_UNICODE;
         smi.popupPosition := 990000;
         smi.szPopupName.w := TranslateW('Status');
         smi.Position := 200001+i;
         srvFce := PChar(Format('%s/MenuStatusAddlStatus%d', [piShortName, smi.Position]));
         vk_hMenuStatusAddlSF[8+i] := pluginLink^.CreateServiceFunctionParam(srvFce, @MenuStatusAdditionalStatus, smi.Position);
         smi.pszService := srvFce;
         smi.szName.w := DBReadUnicode(0, piShortName, PChar(opt_AddlStatus+IntToStr(i)), nil);
         smi.pszContactOwner := piShortName;
         vk_hMenuStatusAddl[8+i] := pluginLink^.CallService(MS_CLIST_ADDSTATUSMENUITEM, Windows.wParam(@vk_hMenuStatus), Windows.lparam(@smi));
       end;
     End;
  end;
end;

// =============================================================================
// function to read contact's additional status
// -----------------------------------------------------------------------------
function MenuContactAdditionalStatusRead(wParam: wParam; lParam: lParam): Integer; cdecl;
var MsgCaption: WideString;
begin
  MsgCaption := TranslateW('Additional status') + ', ' + WideString(DBReadString(wParam, piShortName, 'XStatusTime', '00:00')) + ': '+#10#13+
                DBReadUnicode(wParam, piShortName, 'XStatusMsg', '');
  ShowPopupMsg(wParam, MsgCaption, 1);

  Result := 0;
end;

// =============================================================================
// function to update list of Additional statuses, including chosen item
// we MUST have this service, without it when status menu re-build, our items
// dissapear
// -----------------------------------------------------------------------------
function MenuStatusAdditionalPrebuild(wParam: wParam; lParam: lParam): Integer; cdecl;
var smi: TCListMenuItem; // status menu item
    i: Byte;
    srvFce: PChar;
    smiRoot: TCLISTMENUITEM;
    SelectedItem: Integer;
begin
  SelectedItem := DBGetContactSettingDWord(0, piShortName, 'XStatusSelectedItem', 100001);

  // add Additional Statuses - status menu
  FillChar(smi, sizeof(smi), 0);
  smi.cbSize := sizeof(smi);
  smi.popupPosition := 990000;
  smi.szPopupName.w := TranslateW('Status');
  // standard statuses
  for i:=Low(xStatuses) to High(xStatuses) do
  begin
    Case i Of
      Low(xStatuses):   smi.Position := 100001;
      Low(xStatuses)+1: smi.Position := 200001;
      else
      begin
        smi.Position := i + 300000;
        smi.hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(xStatuses[i].Name)));
      end;
    End;
    if smi.Position=SelectedItem Then
      smi.flags := CMIF_UNICODE + CMIF_CHECKED // 'No' is selected by default
    Else
      smi.flags := CMIF_UNICODE + 0; // will change item name & flags in future
    srvFce := PChar(Format('%s/MenuStatusAddlStatus%d', [piShortName, smi.Position]));
    vk_hMenuStatusAddlSF[i] := pluginLink^.CreateServiceFunctionParam(srvFce, @MenuStatusAdditionalStatus, smi.Position);
    smi.pszService := srvFce;
    smi.szName.w := PWideChar(xStatuses[i].Text);
    smi.pszContactOwner := piShortName;
    vk_hMenuStatusAddl[i] := pluginLink^.CallService(MS_CLIST_ADDSTATUSMENUITEM, Windows.wParam(@vk_hMenuStatus),  Windows.lparam(@smi));
  end;

  // user's custom statuses
  // update list of additional statuses
  for i:=9 to 13 do
    vk_hMenuStatusAddl[i] := 0;
  MenuStatusAdditionalStatusUpdate();

 // we need to update icon of root Additional Status menu
 FillChar(smiRoot,sizeof(smiRoot),0);
 smiRoot.cbSize:=sizeof(smiRoot);
 if (SelectedItem>=300000) and (SelectedItem<=399999) then
   smiRoot.hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(xStatuses[SelectedItem-300000].Name)))
 else
   smiRoot.hIcon := 0;
 smiRoot.flags := CMIF_UNICODE + CMIM_FLAGS + CMIM_ICON;
 pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuStatus, Windows.lparam(@smiRoot));

  Result := 0;
end;

// =============================================================================
// function registers all icons in clist, so they become available for
// contacts (for usage in advanced clists, like clist_modern)
// -----------------------------------------------------------------------------
function ListStatusAdditionalPrebuild(wParam: wParam; lParam: lParam): Integer; cdecl;
var i: Byte;
    hIcon: THandle;
begin
 if PluginLink^.ServiceExists(MS_CLIST_EXTRA_ADD_ICON)=1 then
   for i:=Low(xStatuses)+2 to High(xStatuses) do
   begin
     hIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(xStatuses[i].Name)));
     xStatuses[i].IconExtraIndex := PluginLink^.CallService(MS_CLIST_EXTRA_ADD_ICON, hIcon, 0);
   end;

 Result := 0;
end;

// =============================================================================
// function updates contact's additional icons based on DB settings
// -----------------------------------------------------------------------------
function ListStatusAdditionalImageApply(wParam: wParam; lParam: lParam): Integer; cdecl;
var bXStatus: Byte;
begin
 if ((vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE)) And (PluginLink^.ServiceExists(MS_CLIST_EXTRA_SET_ICON)=1) Then
 Begin
   if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, wParam, Windows.lParam(PAnsiChar(piShortName))) <> 0 Then // only apply icons to our contacts, do not mess others
   begin
    bXStatus := DBGetContactSettingByte(wParam, piShortName, 'XStatusId', 0);
    if (bXStatus > 0) and (bXStatus <= High(xStatuses)) then
      StatusAddlSetIcon(wParam, xStatuses[bXStatus].IconExtraIndex)
    else
      StatusAddlSetIcon(wParam, THandle(-1));
   end;
 End;
 Result := 0;
end;

// =============================================================================
// function provides other plugins with additional status icon based
// on DB setting
// -----------------------------------------------------------------------------
function StatusIconAdvancedGet(wParam: wParam; lParam: lParam): Integer; cdecl;
var bXStatus: Byte;
begin
 Result := -1;
 if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
 Begin
   bXStatus := DBGetContactSettingByte(wParam, piShortName, 'XStatusId', 0);
   if bXStatus <> 0 then
     Result := Windows.MakeLong(xStatuses[bXStatus].IcoLibIndex, 0);
 End;
end;

// =============================================================================
//
// -----------------------------------------------------------------------------
function StatusIconXGet(wParam: wParam; lParam: lParam): Integer; cdecl;
var bXStatus: Byte;
begin
  Result := 0;
  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
  Begin
    bXStatus := DBGetContactSettingByte(wParam, piShortName, 'XStatusId', 0);
    if bXStatus <> 0 then
      if (lParam and LR_SHARED) <> 0 then
        Result := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(xStatuses[bXStatus].Name)))
      else
        Result := CopyIcon(PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(xStatuses[bXStatus].Name))));
  End;
End;

// =============================================================================
// function provides other plugins with our additional status text based
// on DB setting
// -----------------------------------------------------------------------------
function StatusAddlGet(wParam: wParam; lParam: lParam): Integer; cdecl;
var bXStatus: Byte;
begin
  Result := 0;
  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
  Begin
    bXStatus := DBGetContactSettingByte(0, piShortName, 'XStatusId', 0);
    if (bXStatus > 0) and (bXStatus <= High(xStatuses)) then
    begin
      if wParam<>0 then
        PPChar(wParam)^ := PChar('XStatusName');
      if lParam<>0 then
        PPChar(lParam)^ := PChar('XStatusMsg');
      Result := xStatuses[bXStatus].StatusID;
    end;
  End;
end;

// =============================================================================
// function defines our additional status
// -----------------------------------------------------------------------------
function StatusAddlSet(wParam: wParam; lParam: lParam): Integer; cdecl;
var bXStatus: Byte;
begin
  Result := 0;
  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
  Begin
    if wParam = 0 then // we should remove our status
    Begin
      DBDeleteContactSetting(0, piShortName, 'XStatusMsg');
      DBDeleteContactSetting(0, piShortName, 'XStatusName');
      DBDeleteContactSetting(0, piShortName, 'XStatusId');
    End
    Else
    Begin
      bXStatus := DBGetContactSettingByte(0, piShortName, 'XStatusId', 0);
      if (bXStatus > 0) and (bXStatus <= High(xStatuses)) then
      begin
        Result := xStatuses[bXStatus].StatusID;
        // here we should really set another status
        // in accordance with request from   wParam = (int)N   // custom status id (1-29)
      end;
    End;
  End;
end;

// =============================================================================
// function to reload icons
// -----------------------------------------------------------------------------
function IconsSkinReload(wParam: wParam; lParam: lParam): Integer; cdecl;
var hImageList: THandle;
    i: Byte;
begin
  hImageList := THandle(PluginLink^.CallService(MS_CLIST_GETICONSIMAGELIST, 0, 0));
  for i:=Low(xStatuses)+2 to High(xStatuses) do
      xStatuses[i].IcoLibIndex := ImageList_AddIcon(hImageList, PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lParam(xStatuses[i].name)));
  Result := 0;
end;

// =============================================================================
// function to prebuild contact's menu debending on the presence of
// additional status text
// -----------------------------------------------------------------------------
function MenuContactPrebuild(wParam: wParam; lParam: lParam): Integer; cdecl;
var cmi: TCListMenuItem;
    flags: DWord;
begin
  // Read Additional Status menu
  FillChar(cmi, sizeof(cmi), 0);
  cmi.cbSize := sizeof(cmi);
  // display addl. status for online contacts only?
  if DBGetContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, 0) = 0 then
     flags := CMIF_UNICODE + CMIM_FLAGS + CMIF_NOTOFFLINE // not show for offline
  else
     flags := CMIF_UNICODE + CMIM_FLAGS; // show for offline
  if DBReadUnicode(wParam, piShortName, 'XStatusMsg')<>'' then
    cmi.flags := CMIF_UNICODE + flags
  else
    cmi.flags := CMIF_UNICODE + flags + CMIF_HIDDEN; // + CMIF_NOTOFFLINE;
  pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuContactStatusAdditionalRead, Windows.lparam(@cmi));

  // Add permanently to contact list menu
  FillChar(cmi, sizeof(cmi), 0);
  cmi.cbSize := sizeof(cmi);
  // display menu item only for non-Friends, and when plugin is online/invisible
  if (DBGetContactSettingByte(wParam, piShortName, 'Friend', 1) = 0) and (vk_Status <> ID_STATUS_OFFLINE) then
     cmi.flags := CMIF_UNICODE + CMIM_FLAGS
  else
     cmi.flags := CMIF_UNICODE + CMIM_FLAGS + CMIF_HIDDEN; // hide for Friends
  pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuContactPages[1], Windows.lparam(@cmi));

  // display 'Write on the wall' menu item only when online
  FillChar(cmi, sizeof(cmi), 0);
  cmi.cbSize := sizeof(cmi);
  if (vk_Status <> ID_STATUS_OFFLINE) then
     cmi.flags := CMIF_UNICODE + CMIM_FLAGS
  else
     cmi.flags := CMIF_UNICODE + CMIM_FLAGS + CMIF_HIDDEN;
  pluginLink^.CallService(MS_CLIST_MODIFYMENUITEM, vk_hMenuContactPages[10], Windows.lparam(@cmi));

  Result := 0;
end;


// =============================================================================
// function to initiate additional status support
// -----------------------------------------------------------------------------
procedure AddlStatusInit();
var szFile: String;
    sid:TSKINICONDESC; // additional statuses icons
    hImageList: THandle;
    i: Byte;
    cmi: TCListMenuItem; // contact menu item
    srvFce: PChar;
begin
  // delete our additional status data
  DBDeleteContactSetting(0, piShortName, 'XStatusId');
  DBDeleteContactSetting(0, piShortName, 'XStatusSelectedItem');

  // load icons for Additional Statuses
  szFile := ExtractFilePath(ParamStr(0)) + 'Icons\' + piShortName + '_xstatus.dll';
  if not FileExists(szFile) then
    szFile := ExtractFilePath(ParamStr(0)) + 'Icons\' + 'xstatus_' + piShortName + '.dll';
  FillChar(sid, SizeOf(TSKINICONDESC), 0);
  sid.cbSize := SizeOf(TSKINICONDESC);
  sid.cx := 16;
  sid.cy := 16;
  sid.pszDefaultFile := PChar(szFile);
  sid.szSection.w := PWideChar(WideString(piShortName + '/Additional status'));   // identifies group of icons - protocol specific
  sid.flags := SIDF_UNICODE;
  for i:=Low(xStatuses)+2 to High(xStatuses) do
  begin
    sid.pszName         := PChar(xStatuses[i].Name);
    sid.iDefaultIndex   := -xStatuses[i].IconIndex;
    sid.szDescription.w := TranslateW(PWideChar(xStatuses[i].Text));
    {vk_hIconsStatusAddl[i] := }PluginLink^.CallService(MS_SKIN2_ADDICON, 0, dword(@sid));
  end;
  vk_hkListStatusAdditionalPrebuild := pluginLink^.HookEvent(ME_CLIST_EXTRA_LIST_REBUILD, @ListStatusAdditionalPrebuild);
  vk_hkListStatusAdditionalImageApply := pluginLink^.HookEvent(ME_CLIST_EXTRA_IMAGE_APPLY, @ListStatusAdditionalImageApply);

  // functions to support Additional Status in Clist Modern
  pluginLink^.CreateServiceFunction(PChar(piShortName + '/GetAdvancedStatusIcon'), @StatusIconAdvancedGet);
  pluginLink^.CreateServiceFunction(PChar(piShortName + '/GetXStatusIcon'), @StatusIconXGet);
  vk_hkIconsSkinReload := pluginLink^.HookEvent(ME_SKIN2_ICONSCHANGED, @IconsSkinReload);

  // add our additional status icons to IconImageList
  hImageList := THandle(PluginLink^.CallService(MS_CLIST_GETICONSIMAGELIST, 0, 0));
  for i:=Low(xStatuses)+2 to High(xStatuses) do
    xStatuses[i].IcoLibIndex := ImageList_AddIcon(hImageList, PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lParam(xStatuses[i].name)));

  // to inform other plugins, like xStatusNotify about additional status change
  he_StatusAdditionalChanged := pluginLink^.CreateHookableEvent(PChar(piShortName + '/XStatusChanged'));

  pluginLink^.CreateServiceFunction(PChar(piShortName + '/GetXStatus'), @StatusAddlGet);
  pluginLink^.CreateServiceFunction(PChar(piShortName + '/SetXStatus'), @StatusAddlSet);

  // add contact menu item to read additional status - hidden by default
  FillChar(cmi, sizeof(cmi), 0);
  cmi.cbSize := sizeof(cmi);
  // display addl. status for online contacts only?
  if DBGetContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, 0) = 0 then
    cmi.flags := CMIF_UNICODE + CMIF_HIDDEN + CMIF_NOTOFFLINE // not show for offline
  else
    cmi.flags := CMIF_UNICODE + CMIF_HIDDEN; // show for offline
  cmi.Position := -2000004999;
  srvFce := PChar(Format('%s/MenuContactReadAdditionalStatus', [piShortName]));
  pluginLink^.CreateServiceFunction(srvFce, @MenuContactAdditionalStatusRead);
  cmi.pszService := srvFce;
  cmi.szName.w := 'Read additional status';
  cmi.pszContactOwner := piShortName;
  vk_hMenuContactStatusAdditionalRead := pluginLink^.CallService(MS_CLIST_ADDCONTACTMENUITEM, 0,  Windows.lparam(@cmi));

  vk_hkMenuContactPrebuild := pluginLink^.HookEvent(ME_CLIST_PREBUILDCONTACTMENU, MenuContactPrebuild);
end;

// =============================================================================
// function to destroy additional status support
// -----------------------------------------------------------------------------
procedure AddlStatusDestroy();
var i: Byte;
begin
  for i:=1 to 13 do
  begin
    if vk_hMenuStatusAddl[i]<>0 then
      pluginLink^.DestroyServiceFunction(vk_hMenuStatusAddl[i]);
    if vk_hMenuStatusAddlSF[i]<>0 then
      pluginLink^.DestroyServiceFunction(vk_hMenuStatusAddlSF[i]);
  end;
  pluginLink^.DestroyServiceFunction(vk_hMenuContactStatusAdditionalRead);

  pluginLink^.UnhookEvent(vk_hkListStatusAdditionalPrebuild);
  pluginLink^.UnhookEvent(vk_hkListStatusAdditionalImageApply);
  pluginLink^.UnhookEvent(vk_hkIconsSkinReload);

  pluginLink^.DestroyHookableEvent(he_StatusAdditionalChanged);
end;

// =============================================================================
// additional status thread
// -----------------------------------------------------------------------------
function ThreadStatusSet(pwcStatusText: PWideChar): LongWord;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(ThreadStatusSet) Thread started...'));

  Result := 0;

  vk_StatusAdditionalSet(WideString(pwcStatusText)); // set new status on the server
  FreeMem(pwcStatusText);

  pluginLink^.NotifyEventHooks(he_StatusAdditionalChanged, 0, 0); // inform other plugins that we've changed our status

  Netlib_Log(vk_hNetlibUser, PChar('(ThreadStatusSet) ... thread finished'));
end;



begin
end.
