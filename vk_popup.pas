(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (c) 2009 Andrey Lukyanov

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
 vk_popup.pas

 [ Description ]
 Module to work with Popup plugin
 
 [ Known Issues ]
 None

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_popup;

interface

procedure PopupInit();
procedure PopupDestroy();
function Popup(hContact: THandle; MsgText: WideString; MsgType: byte; ProtoIcon: boolean; DelayOption: byte; DelaySecs: integer; ColorOption: byte; ColorInfBack, ColorInfFore, ColorErrorBack, ColorErrorFore: longword): integer;
procedure ShowPopupMsg(hContact: THandle; MsgText: WideString; MsgType: byte; ShowMsgBox: boolean = True);

implementation

uses
  m_globaldefs,
  m_api,
  vk_global, // module with global variables and constant used

  Windows,
  SysUtils;

 // =============================================================================
 // function to display popup
 // all settings should be provided
 // -----------------------------------------------------------------------------
function Popup(hContact: THandle; MsgText: WideString; MsgType: byte; ProtoIcon: boolean; DelayOption: byte; DelaySecs: integer; ColorOption: byte; ColorInfBack, ColorInfFore, ColorErrorBack, ColorErrorFore: longword): integer;
var
  ppd: TPOPUPDATAW;
begin
  FillChar(ppd, SizeOf(ppd), 0);
  ppd.icbSize := sizeof(ppd);
  ppd.lchContact := hContact;
  if ProtoIcon then
    ppd.lchIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar(piShortName + '_popups')))
  else
    case MsgType of
      1: // info
        ppd.lchIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('popup_notify')));
      2: // error
        ppd.lchIcon := PluginLink^.CallService(MS_SKIN2_GETICON, 0, Windows.lparam(PChar('popup_error')));
    end;
  if CallService(MS_POPUP_ISSECONDLINESHOWN, 0, 0) = 1 then // second line is shown
  begin
    lstrcpynw(ppd.lpwzContactName, TranslateW(piShortName), MAX_CONTACTNAME - 1);
    lstrcpynw(ppd.lpwzText, TranslateW(PWideChar(MsgText)), MAX_SECONDLINE - 1);
  end
  else
    lstrcpynw(ppd.lpwzContactName, TranslateW(PWideChar(MsgText)), MAX_CONTACTNAME - 1);
  ppd.PluginWindowProc := nil; // which procedure should be called when clicked?
  case DelayOption of
    0:
      ppd.iSeconds := 0; // default time
    1:
      ppd.iSeconds := -1; // forever
    2:
      ppd.iSeconds := DelaySecs;
  end;

  case ColorOption of
    0: // default colors
    begin
      ppd.colorBack := 0;
      ppd.colorText := 0;
    end;
    1: // system colors
    begin
      ppd.colorBack := GetSysColor(COLOR_BTNFACE);
      ppd.colorText := GetSysColor(COLOR_BTNTEXT);
    end;
    2: // custom colors
      case MsgType of
        1: // info
        begin
          ppd.colorBack := ColorInfBack;
          ppd.colorText := ColorInfFore;
        end;
        2: // error
        begin
          ppd.colorBack := ColorErrorBack;
          ppd.colorText := ColorErrorFore;
        end;
      end;
  end;

  Result := pluginLink^.CallService(MS_POPUP_ADDPOPUPW, Windows.wParam(@ppd), 0);

end;

 // =============================================================================
 // simplified function to display popup
 //  types: 1 - info; 2 - error
 // -----------------------------------------------------------------------------
procedure ShowPopupMsg(hContact: THandle; MsgText: WideString; MsgType: byte; ShowMsgBox: boolean = True);
begin
  // if plugin is installed and Popups option is enabled
  if (bPopupSupported) and (DBGetContactSettingByte(0, piShortName, opt_PopupsEnabled, 1) = 1) then
  begin
    if Popup(
      hContact, // hContact
      MsgText,  // MsgText
      MsgType,  // MsgType
      boolean(DBGetContactSettingByte(0, piShortName, opt_PopupsProtoIcon, 0)), // ProtoIcon
      DBGetContactSettingByte(0, piShortName, opt_PopupsDelayOption, 0), // DelayOption
      DBGetContactSettingDWord(0, piShortName, opt_PopupsDelaySecs, 0),  // DelaySecs
      DBGetContactSettingByte(0, piShortName, opt_PopupsColorOption, 0), // ColorOption
      DBGetContactSettingDWord(0, piShortName, opt_PopupsColorInfBackground, GetSysColor(COLOR_BTNFACE)), // ColorInfBack
      DBGetContactSettingDWord(0, piShortName, opt_PopupsColorInfForeground, GetSysColor(COLOR_BTNTEXT)), // ColorInfFore
      DBGetContactSettingDWord(0, piShortName, opt_PopupsColorErrorBackground, GetSysColor(COLOR_BTNFACE)), // ColorErrorBack
      DBGetContactSettingDWord(0, piShortName, opt_PopupsColorErrorForeground, GetSysColor(COLOR_BTNTEXT)) // ColorErrorFore
      ) = 0 then // popup displayed successfully
      Exit;
  end;
  // else display standard error
  if ShowMsgBox then
    case MsgType of
      // info
      1:
        MessageBoxW(0, TranslateW(PWideChar(MsgText)), TranslateW(piShortName), MB_OK + MB_ICONINFORMATION);
      // error
      2:
        MessageBoxW(0, TranslateW(PWideChar(MsgText)), TranslateW(piShortName), MB_OK + MB_ICONSTOP);
    end;

end;

 // =============================================================================
 // function to initiate popups support
 // -----------------------------------------------------------------------------
procedure PopupInit();
var
  sid: TSKINICONDESC;
begin
  if (PluginLink^.ServiceExists(MS_POPUP_ADDPOPUP) <> 0) or (PluginLink^.ServiceExists(MS_POPUP_ADDPOPUPW) <> 0) then
    bPopupSupported := True;

  //  pluginLink^.CallService(MS_POPUP_ADDCLASS, 0, Windows.lParam(PChar('VKontakte')));

  // register icon to be used in popups
  FillChar(sid, SizeOf(TSKINICONDESC), 0);
  sid.cbSize := SizeOf(TSKINICONDESC);
  sid.cx := 16;
  sid.cy := 16;
  sid.flags := SIDF_UNICODE;
  sid.hDefaultIcon := LoadImage(hInstance, MAKEINTRESOURCE('ICON_PROTO'), IMAGE_ICON, 16, 16, 0);
  sid.szSection.w := PWideChar(WideString(piShortName));   // identifies group of icons - protocol specific
  sid.pszName := PChar(piShortName + '_popups');
  sid.szDescription.w := TranslateW('Popups');
  PluginLink^.CallService(MS_SKIN2_ADDICON, 0, dword(@sid));
end;

 // =============================================================================
 // function to destroy popups support
 // -----------------------------------------------------------------------------
procedure PopupDestroy();
begin

end;


begin
end.
