(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (c) 2010 Andrey Lukyanov, Artyom Zhurkin

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
 vk_captcha.pas

 [ Description ]
 Module to work with VKontakte's captcha

 [ Known Issues ]
 None

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_captcha;

interface

uses
  m_api,

  vk_global, // module with global variables and constant used
  vk_http, // module to connect with the site
  vk_common, // module with common functions

  Windows,
  Messages;

  function DlgCaptcha(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
  function ProcessCaptcha(CaptchaId: String; CaptchaURL: String = ''): String;

implementation

uses
  vk_core, // module with core functions
  SysUtils;

var
  hBmpCaptcha: THandle;
  EditFunctionOriginal: Pointer;
  CaptchaValue: String;

// =============================================================================
// Dialog function to display captcha
// -----------------------------------------------------------------------------
function DlgCaptcha(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;

  // new edit function for input box
  // allows only latin characters and digits, they are input regardless of user's
  // current keyboard layout/lang
  function EditFunctionNew(Wnd: HWnd; Msg, wParam, lParam: Integer): Integer; stdcall;

    // deletes the requested message from the queue, but throw back
    // any WM_QUIT msgs that PeekMessage may also return
    procedure KillMessage(Wnd: HWnd; Msg: Integer);
    var
      M: TMsg;
    begin
      M.Message := 0;
      if PeekMessage(M, Wnd, Msg, Msg, pm_Remove) and (M.Message = WM_QUIT) then
        PostQuitMessage(M.WParam);
    end;

  begin
    if (Msg = WM_KEYDOWN) then
    begin
      // codes - http://msdn.microsoft.com/en-us/library/dd375731(VS.85).aspx
      if not (LoWord(wParam) in [VK_LEFT, VK_RIGHT, VK_DELETE, VK_BACK, VK_HOME, VK_END, VK_TAB, VK_RETURN, VK_ESCAPE]) then
      begin
        KillMessage(Wnd, WM_CHAR);
        //if SendMessage(Wnd, WM_GETTEXTLENGTH, 0, 0) < 5 then // max 5 symbols are allowed
          case LoWord(wParam) of
            Ord('A')..Ord('Z'): PostMessage(Wnd, WM_CHAR, LoWord(wParam)+32, 0); // post lowercase latin symbol
            Ord('0')..Ord('9'): PostMessage(Wnd, WM_CHAR, LoWord(wParam), 0);
          end;
        Result := 0;
        Exit;
      end;
    end;
    // call original edit function
    Result := CallWindowProc(EditFunctionOriginal, Wnd, Msg, wParam, lParam);
  end;

// taken from m_imgsrvc.inc
const
  MS_IMG_LOAD = 'IMG/Load';
var
  rc: TRect;
  DC, BitmapDC : hDC;
  memBmp: THandle;
begin
  Result := False;
  case Msg of
     WM_INITDIALOG:
       begin
         // translate all dialog texts
         TranslateDialogDefault(Dialog);
         // assign window icon
         SendMessage(Dialog, WM_SETICON, ICON_BIG, LoadIcon(hInstance, 'ICON_PROTO'));
         // load picture, filename is passed in lParam during dialog creation
         hBmpCaptcha := pluginLink^.CallService(MS_IMG_LOAD, windows.wParam(lParam), 0);
         // delete our captcha file
         DeleteFile(String(lParam));
         SendMessage(GetDlgItem(Dialog, VK_CAPTCHA_CODE), EM_SETLIMITTEXT, 5, 0);
         // assign new procedure to work with VK_CAPTCHA_CODE edit control
         EditFunctionOriginal := Pointer(SetWindowLong(GetDlgItem(Dialog, VK_CAPTCHA_CODE), GWL_WNDPROC, Integer(@EditFunctionNew)));
         Result := True;
       end;
     WM_CLOSE:
       begin
         EndDialog(Dialog, 0);
       end;
     WM_DRAWITEM:
       begin
         DC := GetDC(GetDlgItem(Dialog, VK_CAPTCHA_PIC));
         // get size of our picture control
         GetClientRect(GetDlgItem(Dialog, VK_CAPTCHA_PIC), rc);
         // clear it
         FillRect(DC, rc, GetSysColorBrush(COLOR_BTNFACE));

         if hBmpCaptcha <> 0 then
         begin
           BitmapDC := CreateCompatibleDC(DC);
           memBmp := SelectObject(BitmapDC, hBmpCaptcha);
           BitBlt(DC,
                  (rc.Right - 130) div 2,
                  (rc.Bottom - 50) div 2,
                  130, // captcha picture width
                  50,  //                 height
                  BitmapDC, 0, 0, SRCCOPY);
           DeleteDC(BitmapDC);
           DeleteObject(memBmp);
         end;

         FrameRect(DC, rc, GetSysColorBrush(COLOR_BTNSHADOW));

         ReleaseDC(GetDlgItem(Dialog, VK_CAPTCHA_PIC), DC);

         Result := True;
       end;
     WM_COMMAND:
       begin
         case wParam of
           VK_CAPTCHA_OK:
             begin
               CaptchaValue := GetDlgString(dialog, VK_CAPTCHA_CODE);
               EndDialog(Dialog, 0);
               Result := True;
             end;
         end;
       end;
  end;
end;

function ProcessCaptcha(CaptchaId: String; CaptchaURL: String = ''): String;
var
  TempDir, TempFile: String;
  Buf: array[0..1023] of Char;
begin
  if CaptchaURL = '' then
    CaptchaURL := vk_url_prefix + vk_url_host + '/captcha.php?s=1&sid=' + CaptchaId;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_CaptchaProcessing) ... captcha ID is ' + CaptchaId));
  Netlib_Log(vk_hNetlibUser, PChar('(vk_CaptchaProcessing) ... captcha URL is ' + CaptchaURL));
  if (CaptchaId <> '') and (CaptchaURL <> '') then
  begin
    SetString(TempDir, Buf, GetTempPath(Sizeof(Buf)-1, Buf)); // getting path to Temp directory
    TempFile := TempDir + 'vk_captcha.jpg';
    if HTTP_NL_GetPicture(CaptchaURL, TempFile) then
    begin // file downloaded successfully
      Netlib_Log(vk_hNetlibUser, PChar('(vk_CaptchaProcessing) ... captcha downloaded successfully and saved to ' + TempDir));
      // ask user to input the value
      DialogBoxParamW(hInstance, MAKEINTRESOURCEW(WideString('VK_CAPTCHA')), 0, @DlgCaptcha, Windows.lParam(TempFile));
      Result := CaptchaValue;
    end else
      Result := 'captcha_download_failed';
  end;
end;

begin
end.