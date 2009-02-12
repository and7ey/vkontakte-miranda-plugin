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

uses Windows,
     Messages,
     SysUtils,
     Commctrl,
     ShellAPI,

     m_globaldefs,
     m_api,

     vk_global, // module with global variables and constant used
     vk_common, // module with common functions
     vk_popup; // module to support popups

{$include res\dlgopt\i_const.inc} // contains list of ids used in dialogs

{$Resource dlgopt.res} // resource file with dialogs

function DlgProcOptionsAcc(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
function DlgProcOptionsAdv(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
function DlgProcOptionsAdv2(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
function DlgProcOptionsNews(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
function DlgProcOptionsPopup(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
function OnOptInitialise(wParam, lParam: DWord): Integer; cdecl;

implementation

function OnOptInitialise(wParam{addinfo}, lParam{0}: DWord): Integer; cdecl;
var
  odp:TOPTIONSDIALOGPAGE;
begin
  ZeroMemory(@odp, sizeof(odp));
  odp.cbSize := sizeof(odp);
  odp.Position := 900002000;
  odp.hInstance := hInstance;
  odp.szGroup.a := 'Network'; // identifies where plugin's options should appear
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

  Result:=0;
end;



function DlgProcOptionsAcc(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
var
  str: String;  // temp variable for types conversion
  pc: PChar;    // temp variable for types conversion
begin
  Result:=False;

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
        if trim(vk_o_pass) <> '' Then // decrypt password
          pluginLink^.CallService(MS_DB_CRYPT_DECODESTRING, SizeOf(vk_o_pass), Windows.lparam(vk_o_pass));
        SetDlgItemText(dialog, VK_OPT_PASS, PChar(vk_o_pass)); // password

        // send Changed message - make sure we can save the dialog
        SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

        Result:=True;
      end;
    // code is executed, when user clicks
    WM_COMMAND:
     begin
      case Word(wParam) of
         VK_OPT_NEWID: // create new account
            begin
              ShellAPI.ShellExecute(0, 'open', vk_url_register, nil, nil, 0);
              Result := True;
            end;
         VK_OPT_PASSLOST: // retrieve lost password
            begin
              ShellAPI.ShellExecute(0, 'open', vk_url_forgot, nil, nil, 0);
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
            DBWriteContactSettingString (0, piShortName, opt_UserName, pc);
            vk_o_login := pc;

            pc := PChar(Str);
            GetDlgItemText(dialog, VK_OPT_PASS, pc, 256);
            // encode password
            pluginLink^.CallService(MS_DB_CRYPT_ENCODESTRING, SizeOf(pc), Windows.lparam(pc));
            DBWriteContactSettingString(0, piShortName, opt_UserPass, pc);
            vk_o_pass := pc;

            Result:=True;
          end;
      end;
  end;
end;



function DlgProcOptionsAdv(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
var
  val: Integer;
begin
  Result:=False;

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

        // send Changed message - make sure we can save the dialog
        SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

        Result:=True;
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
            DBWriteContactSettingDWord (0, piShortName, opt_UserKeepOnline, val);

            val := GetDlgInt(dialog, VK_OPT_CHECKNEWMSG_SEC);
            DBWriteContactSettingDWord (0, piShortName, opt_UserCheckNewMessages, val);

            val := GetDlgInt(dialog, VK_OPT_CHECKFRSTATUS_SEC);
            DBWriteContactSettingDWord (0, piShortName, opt_UserUpdateFriendsStatus, val);

            DBWriteContactSettingByte (0, piShortName, opt_UserGetMinInfo, Byte(IsDlgButtonChecked(dialog, VK_OPT_GETMININFO)));

            DBWriteContactSettingByte (0, piShortName, opt_UserRemoveEmptySubj, Byte(IsDlgButtonChecked(dialog, VK_OPT_REMOVEEMTPYSUBJ)));

            DBWriteContactSettingByte (0, piShortName, opt_UserUpdateAddlStatus, Byte(IsDlgButtonChecked(dialog, VK_OPT_ADDLSTATUSSUPPORT)));

            DBWriteContactSettingByte (0, piShortName, opt_UserAvatarsSupport, Byte(IsDlgButtonChecked(dialog, VK_OPT_AVATARSSUPPORT)));

            val := GetDlgInt(dialog, VK_OPT_AVATARSUPD_SEC);
            DBWriteContactSettingDWord (0, piShortName, opt_UserAvatarsUpdateFreq, val);

            DBWriteContactSettingByte (0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, Byte(IsDlgButtonChecked(dialog, VK_OPT_AVATARSUPDWHENGETINFO)));

            Result:=True;
          end;
      end;
  end;
end;

function DlgProcOptionsAdv2(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
var
  val: Integer;
  str: String;  // temp variable for types conversion
  pc: PChar;    // temp variable for types conversion
begin
  Result:=False;

  case message of
    // code is executed, when options are initialized
    WM_INITDIALOG:
      begin
        // translate all dialog texts
        TranslateDialogDefault(Dialog);

        SetDlgItemText(dialog, VK_OPT_DEFAULT_GROUP, PChar(DBReadString(0, piShortName, opt_UserDefaultGroup, nil))); // default group

        val := DBGetContactSettingByte(0, piShortName, opt_UserVKontakteURL, 0);
        CheckDlgButton(dialog, VK_OPT_VKONTAKTE_URL, val);

        val := DBGetContactSettingByte(0, piShortName, opt_UserAddlStatusForOffline, 0);
        CheckDlgButton(dialog, VK_OPT_ADDLSTATUS_FOR_OFFLINE, val);

        val := DBGetContactSettingByte(0, piShortName, opt_UserUseLocalTimeForIncomingMessages, 0);
        CheckDlgButton(dialog, VK_OPT_LOCALTIME_FOR_INC_MSGS, val);

        // send Changed message - make sure we can save the dialog
        SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

        Result:=True;
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
            pc := PChar(Str);
            GetDlgItemText(dialog, VK_OPT_DEFAULT_GROUP, pc, 256);
            DBWriteContactSettingString (0, piShortName, opt_UserDefaultGroup, pc);

            DBWriteContactSettingByte (0, piShortName, opt_UserVKontakteURL, Byte(IsDlgButtonChecked(dialog, VK_OPT_VKONTAKTE_URL)));

            DBWriteContactSettingByte (0, piShortName, opt_UserAddlStatusForOffline, Byte(IsDlgButtonChecked(dialog, VK_OPT_ADDLSTATUS_FOR_OFFLINE)));

            DBWriteContactSettingByte (0, piShortName, opt_UserUseLocalTimeForIncomingMessages, Byte(IsDlgButtonChecked(dialog, VK_OPT_LOCALTIME_FOR_INC_MSGS)));

            Result:=True;
          end;
      end;
  end;
end;

function DlgProcOptionsNews(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
var
  val: Integer;
begin
  Result:=False;

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
        val := DBGetContactSettingByte(0, piShortName, opt_NewsFilterQuestions, 1);
        CheckDlgButton(dialog, VK_OPT_NEWS_FILTER_QUESTION, val);
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

        val := DBGetContactSettingByte(0, piShortName, opt_NewsLinks, 1);
        CheckDlgButton(dialog, VK_OPT_NEWS_SUPPORTLINKS, val);

        val := DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0);
        CheckDlgButton(dialog, VK_OPT_NEWS_SEPARATE_CONTACT, val);

        // send Changed message - make sure we can save the dialog
        SendMessage(GetParent(dialog), PSM_CHANGED, 0, 0);

        Result:=True;
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
            DBWriteContactSettingByte (0, piShortName, opt_NewsSupport, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWSSUPPORT)));

            val := GetDlgInt(dialog, VK_OPT_NEWS_SEC);
            DBWriteContactSettingDWord (0, piShortName, opt_NewsSecs, val);

            DBWriteContactSettingByte (0, piShortName, opt_NewsMin, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_MINIMAL)));

            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterPhotos, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_PHOTO)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterVideos, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_VIDEO)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterNotes, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_NOTE)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterQuestions, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_QUESTION)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterThemes, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_SUBJ)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterFriends, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_FRIEND)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterStatuses, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_STATUS)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterGroups, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_GROUP)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterMeetings, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_MEETING)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterAudio, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_AUDIO)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterPersonalData, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_PERSONAL)));
            DBWriteContactSettingByte (0, piShortName, opt_NewsFilterTags, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_FILTER_TAGS)));

            DBWriteContactSettingByte (0, piShortName, opt_NewsLinks, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_SUPPORTLINKS)));

            DBWriteContactSettingByte (0, piShortName, opt_NewsSeparateContact, Byte(IsDlgButtonChecked(dialog, VK_OPT_NEWS_SEPARATE_CONTACT)));

            Result:=True;
          end;
      end;
  end;
end;


function DlgProcOptionsPopup(Dialog: HWnd; Message, wParam, lParam: DWord): Boolean; cdecl;
var
  val: Integer;
  popupColorOption,
  popupDelayOption: Byte;
begin
  Result:=False;

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
          0: CheckDlgButton(dialog, VK_POPUPS_COLORDEF, BST_CHECKED);
          1: CheckDlgButton(dialog, VK_POPUPS_COLORWIN, BST_CHECKED);
          2:
            begin
              CheckDlgButton(dialog, VK_POPUPS_COLORCUST, BST_CHECKED);
              EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_BACK), true);
              EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_FORE), true);
              EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_BACK), true);
              EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_FORE), true);
            end;
        end;

        // delay
        val := DBGetContactSettingDWord(0, piShortName, opt_PopupsDelaySecs, 0);
        if val <> 0 then
          SetDlgItemText(dialog, VK_POPUPS_DELAY_SEC, PChar(IntToStr(val)));
        case DBGetContactSettingByte(0, piShortName, opt_PopupsDelayOption, 0) of
          0: CheckDlgButton(dialog, VK_POPUPS_DELAYDEF, BST_CHECKED);
          1: CheckDlgButton(dialog, VK_POPUPS_DELAYPERM, BST_CHECKED);
          2:
            begin
              CheckDlgButton(dialog, VK_POPUPS_DELAYCUST, BST_CHECKED);
              EnableWindow(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC), true);
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

        Result:=True;
      end;
    WM_COMMAND:
      begin
        if HiWord(wParam)=BN_CLICKED then
        begin
          case LoWord(wParam) of
            VK_POPUPS_TEST:
              begin
                // color
                if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORDEF) = BST_CHECKED then
                  popupColorOption := 0
                else if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORWIN) = BST_CHECKED then
                    popupColorOption := 1
                      else
                        popupColorOption := 2;
                // delay
                if IsDlgButtonChecked(Dialog, VK_POPUPS_DELAYDEF) = BST_CHECKED then
                  popupDelayOption := 0
                else if IsDlgButtonChecked(Dialog, VK_POPUPS_DELAYPERM) = BST_CHECKED then
                    popupDelayOption := 1
                      else
                        popupDelayOption := 2;

                Popup (
                        0, // hContact
                        'Test informational popup', // MsgText
                        1, // MsgType = info
                        popupDelayOption, // DelayOption
                        GetDlgInt(dialog, VK_POPUPS_DELAY_SEC), // DelaySecs
                        popupColorOption, // ColorOption
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_BACK, CPM_GETCOLOUR, 0, 0), // ColorInfBack
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_FORE, CPM_GETCOLOUR, 0, 0), // ColorInfFore
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_BACK, CPM_GETCOLOUR, 0, 0), // ColorErrorBack
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_FORE, CPM_GETCOLOUR, 0, 0) // ColorErrorFore
                       );
                Popup (
                        0, // hContact
                        'Test error popup', // MsgText
                        2, // MsgType = error
                        popupDelayOption, // DelayOption
                        GetDlgInt(dialog, VK_POPUPS_DELAY_SEC), // DelaySecs
                        popupColorOption, // ColorOption
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_BACK, CPM_GETCOLOUR, 0, 0), // ColorInfBack
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_INF_FORE, CPM_GETCOLOUR, 0, 0), // ColorInfFore
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_BACK, CPM_GETCOLOUR, 0, 0), // ColorErrorBack
                        SendDlgItemMessage(Dialog, VK_POPUPS_COLOR_ERR_FORE, CPM_GETCOLOUR, 0, 0) // ColorErrorFore
                       );

              end;
            VK_POPUPS_DELAYCUST:
              begin
                EnableWindow(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC), true);
                SetFocus(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC));
              end;
            VK_POPUPS_DELAYDEF, VK_POPUPS_DELAYPERM:
              EnableWindow(GetDlgItem(dialog, VK_POPUPS_DELAY_SEC), false);
            VK_POPUPS_COLORCUST:
              begin
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_BACK), true);
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_FORE), true);
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_BACK), true);
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_FORE), true);
              end;
            VK_POPUPS_COLORDEF, VK_POPUPS_COLORWIN:
              begin
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_BACK), false);
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_ERR_FORE), false);
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_BACK), false);
                EnableWindow(GetDlgItem(Dialog, VK_POPUPS_COLOR_INF_FORE), false);
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
            DBWriteContactSettingByte(0, piShortName, opt_PopupsEnabled, Byte(IsDlgButtonChecked(dialog, VK_POPUPS_ENABLED)));
            // color
            if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORDEF) = BST_CHECKED then
              DBWriteContactSettingByte(0, piShortName, opt_PopupsColorOption, 0)
            else if IsDlgButtonChecked(Dialog, VK_POPUPS_COLORWIN) = BST_CHECKED then
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
            else if IsDlgButtonChecked(Dialog, VK_POPUPS_DELAYPERM) = BST_CHECKED then
              DBWriteContactSettingByte(0, piShortName, opt_PopupsDelayOption, 1)
            else
            begin
              DBWriteContactSettingByte(0, piShortName, opt_PopupsDelayOption, 2);
              val := GetDlgInt(dialog, VK_POPUPS_DELAY_SEC);
              if val <> -1 then
                DBWriteContactSettingDWord (0, piShortName, opt_PopupsDelaySecs, val);
            end;

            Result := True;
          end;
      end;
  end;
end;

end.



