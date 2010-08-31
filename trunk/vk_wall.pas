(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (c) 2010 Andrey Lukyanov

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
 vk_wall.pas

 [ Description ]
 Module to work with VKontakte's wall

 [ Known Issues ]
 - video, audio etc. is not supported now in vk_WallGetMessages

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_wall;

interface

uses
  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used
  vk_opts, // unit to work with options
  vk_http, // module to connect with the site
  vk_popup, // module to support popups
  vk_common, // module with common functions
  htmlparse, // module to simplify html parsing
  uLkJSON,
  Windows,
  Messages;

type
  PMsgDetails = ^TMsgDetails;
  TMsgDetails = record
    ID: Integer;
    MessageText: WideString;
    Wnd: HWnd;
  end;

  function DlgWallPic(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;

  function vk_WallPostMessage(MsgDetails: PMsgDetails): TResultDetailed; overload;
  function vk_WallPostMessage(ID: Integer; const MessageText: WideString; Wnd: HWnd): TResultDetailed; overload;

  function vk_WallPostPicture(MsgDetails: PMsgDetails): TResultDetailed; overload;
  function vk_WallPostPicture(ID: Integer; const MessageText: WideString; Wnd: HWnd): TResultDetailed; overload;

  function vk_WallPostMessageDialog(MsgDetails: PMsgDetails): Integer;
  function vk_WallPostPictureDialog(MsgDetails: PMsgDetails): Integer;

  procedure vk_WallGetMessages(ID: Integer = 0);

implementation

uses
  vk_core, // module with core functions
  vk_msgs, // module to send/receive messages
  vk_captcha, // module to process captcha

  SysUtils,
  Classes, // to support TFileStream
  CommDlg,
  CommCtrl,
  ShellAPI;

const
	wall_status_posting_started = 'Posting of the message started...';
	wall_status_getting_hash = 'Getting contact''s hash...';
  wall_status_getting_hash_failed = 'Message posting failed. Unable to get the hash';
	wall_status_posting = 'Posting of the message...';
	wall_status_invisible_succ = 'Invisible mode: looks like the message has been posted successfully';
	wall_status_invisible_failed = 'Invisible mode: looks like the message posting has failed';
	wall_status_succ = 'The message has been posted successfully';
	wall_status_captcha_required = 'Security code (captcha) input is required for further processing...';
	wall_status_captcha_input = 'Please input the captcha in the separate window';
	wall_status_failed = 'Message posting failed (incorrect code?)';
	wall_status_captcha_failed = 'Message posting failed. Unable to get the captcha';

	wall_status_posting_pic_started = 'Uploading of the picture started...';
	wall_status_posting_pic_failed_incorrect_details = 'Uploading of the picture failed. Details are incorrect';
	wall_status_posting_pic_failed_not_found = 'Uploading failed. Original picture file not found';
	wall_status_posting_pic_reading = 'Reading of the original picture file...';
	wall_status_posting_pic_reading_failed = 'Uploading failed. Unable to read the original file';
	wall_status_posting_pic_base64 = 'Generating hash...';
	wall_status_posting_pic_base64_failed = 'Uploading failed. Unable to generate hash';
	wall_status_posting_pic_md5 = 'Generating signature...';
	wall_status_posting_pic_md5_failed = 'Uploading failed. Unable to generate signature';
	wall_status_posting_pic_sending = 'Uploading picture on the server...';
	wall_status_posting_pic_sending_failed_unknown = 'Uploading failed due to unknown reason';
	wall_status_posting_pic_sending_failed_security = 'Uploading failed due to security violation';
  wall_status_posting_pic_id = 'Picture uploaded';
  wall_status_posting_pic_id_failed = 'Posting failed. Unable to get picture id';
  wall_status_posting_pic_posting = 'Posting of the picture...';
  wall_status_posting_pic_failed_unknown = 'Posting failed due to unknown reason';
  wall_status_posting_pic_succ = 'The picture has been posted successfully';

  wall_status_posting_pic_size_failed = 'File size is too large! Reduce it or try another picture.';
  pic_max_size = 255; // max allowed file size of the picture
  pic_max_size_msg = 'Kb is maximum.';

var
  bPictureSelected: Boolean;
  hBmp: THandle;
  sPicFileName: WideString;
  ContactID: Integer;

// =============================================================================
// Dialog procedure to enable all elements
// -----------------------------------------------------------------------------
procedure DlgWallPicEnable(Dialog: HWnd);
begin
  EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_EDIT), true);
  EnableWindow(GetDlgItem(dialog, VK_WALL_PIC), true);
  EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_TEXT), true);
  EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_IMAGE), true);
  EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_SEND), true);
  SetWindowTextW(GetDlgItem(dialog, VK_WALL_PIC_SEND), TranslateW('&Send'));
  SetFocus(GetDlgItem(dialog, VK_WALL_PIC_EDIT));
end;


// =============================================================================
// Dialog function to ask the text/picture to be written/drawn on the wall
// -----------------------------------------------------------------------------
function DlgWallPic(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
// taken from m_imgsrvc.inc
const
  MS_IMG_LOAD = 'IMG/Load';
  MS_IMG_RESIZE = 'IMG/ResizeBitmap';
  RESIZEBITMAP_STRETCH          = 0;
  RESIZEBITMAP_KEEP_PROPORTIONS = 1;
  RESIZEBITMAP_CROP             = 2;
  RESIZEBITMAP_MAKE_SQUARE      = 3;
  RESIZEBITMAP_FLAG_DONT_GROW	= $1000;
type
  TResizeBitmap = record
    size      :size_t;   // sizeof(ResizeBitmap);
    hBmp      :HBITMAP;
    max_width :int;
    max_height:int;
    fit       :int;       // One of: RESIZEBITMAP_*
  end;

var
   str: WideString;  // temp variable for types conversion
   pc: PWideChar;    // temp variable for types conversion

   FileName: array [0..MAX_PATH] of AnsiChar;
   filter: array [0..256] of AnsiChar;
   ofn: OpenFileNameA;
   iFileSize: Cardinal;

   DC, BitmapDC : hDC;
   rb: TResizeBitmap;
   buf: Bitmap;
   var Blend: TBlendFunction;

   rc, rc_ret: TRect;
   hFont: THandle;
   memBmp: THandle;

   res: LongWord;
   MsgDetails: PMsgDetails;

begin
  Result := False;
  case Msg of
     WM_SYSCOMMAND:
       begin
         if wParam = WM_USER + 1 then // menu item is chosen
         begin
           ShellAPI.ShellExecute(0, 'open', PChar(Format(vk_url_prefix + vk_url_host + vk_url_wall_id, [ContactID])), nil, nil, 0);
           Result := True;
         end;
       end;
     WM_INITDIALOG:
       begin
         // translate all dialog texts
         TranslateDialogDefault(Dialog);
         // assign window icon
         SendMessage(Dialog, WM_SETICON, ICON_BIG, LoadIcon(hInstance, 'ICON_PROTO'));

         SetWindowTextW(Dialog, PWideChar(WideString(DBReadUnicode(lParam, piShortName, 'Nick', '') + ' - ' + TranslateW('write on the wall'))));
         ContactID := DBGetContactSettingDWord(lParam, piShortName, 'ID', 0); // remember contact's id

         ShowWindow(GetDlgItem(Dialog, VK_WALL_PIC), SW_HIDE);
         SendMessage(GetDlgItem(Dialog, VK_WALL_PIC_EDIT), EM_SETLIMITTEXT, 4096, 0); // set max allowed text length
         SetFocus(GetDlgItem(Dialog, VK_WALL_PIC_EDIT));

         // create new menu item
         AppendMenu(GetSystemMenu(Dialog, FALSE), MF_SEPARATOR, 0, '');
         AppendMenuW(GetSystemMenu(Dialog, FALSE), MF_STRING, WM_USER + 1, TranslateW('Contact''s &wall on site...'));
         bPictureSelected := False;
       end;
     WM_CLOSE:
       begin
         DeleteObject(hBmp);
         EndDialog(Dialog, 0);
       end;  
     WM_DRAWITEM:
       begin
         // picture mode is chosen
         if IsWindowVisible(GetDlgItem(Dialog, VK_WALL_PIC)) then
         begin
           if bPictureSelected then
           begin
             // get size of our picture control
             GetClientRect(GetDlgItem(Dialog, VK_WALL_PIC), rc);
             // get picture dimensions
             FillChar(buf, SizeOf(Bitmap), 0);
             GetObject(hBmp, SizeOf(Bitmap), @buf);

             // draw picture in the center
             DC := GetDC(GetDlgItem(Dialog, VK_WALL_PIC));
             FillRect(DC, rc, GetSysColorBrush(COLOR_BTNFACE));
             BitmapDC := CreateCompatibleDC(DC);
             memBmp := SelectObject(BitmapDC, hBmp);
             SetBkMode(DC, TRANSPARENT);
             SetBkColor(DC, COLOR_BTNFACE);
             with Blend do
             begin
               BlendOp := AC_SRC_OVER;
               BlendFlags := 0;
               SourceConstantAlpha := 255;
               AlphaFormat := Ord(buf.bmBitsPixel=32);
             end;
             AlphaBlend(DC,
                    (rc.Right - buf.bmWidth) div 2,
                    (rc.Bottom - buf.bmHeight) div 2,
                    buf.bmWidth,
                    buf.bmHeight,
                    BitmapDC, 0, 0, buf.bmWidth, buf.bmHeight, Blend);
             // draw frame
             FrameRect(DC, rc, GetSysColorBrush(COLOR_BTNSHADOW));
             // destroy objects
             DeleteDC(BitmapDC);
             ReleaseDC(GetDlgItem(Dialog, VK_WALL_PIC), DC);
             DeleteObject(memBmp);
           end
           else
           begin // picture hasn't been selected
             // write a text that picture should be chosen
             DC := GetDC(GetDlgItem(Dialog, VK_WALL_PIC));
             GetClientRect(GetDlgItem(Dialog, VK_WALL_PIC), rc);
             FillRect(DC, rc, GetSysColorBrush(COLOR_BTNFACE));
             FrameRect(DC, rc, GetSysColorBrush(COLOR_BTNSHADOW));
             SetBkMode(DC, Windows.TRANSPARENT); // transparent background for the text
             hFont := SelectObject(DC, GetStockObject(DEFAULT_GUI_FONT)); // default font
             rc.Top := rc.Top + 10;
             rc.Bottom := rc.Bottom - 10;
             rc.Left := rc.Left + 10;
             rc.Right := rc.Right - 10;
             // calculate text size
             rc_ret := rc;
             DrawTextW(DC, TranslateW('Click here to choose the picture'), -1, rc_ret, DT_WORDBREAK or DT_NOPREFIX or DT_CENTER or DT_CALCRECT);
             rc.Top := ((rc.Bottom - rc.Top) - (rc_ret.Bottom - rc_ret.Top)) div 2;
             rc.Bottom := rc.Top + (rc_ret.Bottom - rc_ret.Top);
             // write text
             DrawTextW(DC, TranslateW('Click here to choose the picture'), -1, rc, DT_WORDBREAK or DT_NOPREFIX or DT_CENTER);
             // destroy objects
             ReleaseDC(GetDlgItem(Dialog, VK_WALL_PIC), DC);
             DeleteObject(SelectObject(DC, hFont));
           end;
         end;
         
         Result := True;
       end;
     WM_COMMAND:
       begin
         case wParam of
           VK_WALL_PIC_SEND:
             begin
               // increase window size and display progress bar
               {GetWindowRect(Dialog, rc);
               SetWindowPos(Dialog, HWND_TOP, 0, 0, rc.Right-rc.Left, rc.Bottom-rc.Top+13, SWP_NOMOVE + SWP_NOZORDER);
               ShowWindow(GetDlgItem(Dialog, VK_WALL_PIC_PRGBAR), SW_SHOW);
               SendMessage(GetDlgItem(Dialog, VK_WALL_PIC_PRGBAR), PBM_SETRANGE, 0, MakeLParam(0, 100));
               SendMessage(GetDlgItem(Dialog, VK_WALL_PIC_PRGBAR), PBM_SETPOS, 50, 0);}
               // disable other elements while processing request
               EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_EDIT), false);
               EnableWindow(GetDlgItem(dialog, VK_WALL_PIC), false);
               EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_TEXT), false);
               EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_IMAGE), false);
               EnableWindow(GetDlgItem(dialog, VK_WALL_PIC_SEND), false);
               SetWindowTextW(GetDlgItem(dialog, VK_WALL_PIC_SEND), TranslateW('Sending...'));

               // preparing details required for further processing
               New(MsgDetails);
               MsgDetails^.ID := ContactID;
               MsgDetails^.Wnd := dialog; // passing handle of the dialog to control it from the thread

               // picture mode is chosen, sending picture
               if IsWindowVisible(GetDlgItem(Dialog, VK_WALL_PIC)) then
               begin
                 MsgDetails^.MessageText := sPicFileName; // passing picture file name as message text
                 // posting picture in a separate thread
                 CloseHandle(BeginThread(nil, 0, @vk_WallPostPictureDialog, MsgDetails, 0, res));
               end
               else
               begin // text mode is chosen, sending text
                 SetLength(Str, 4096); // 4096 - max allowed length
                 pc := PWideChar(Str);
                 GetDlgItemTextW(Dialog, VK_WALL_PIC_EDIT, pc, 4096);
                 MsgDetails^.MessageText := pc;

                 // posting message in a separate thread
                 CloseHandle(BeginThread(nil, 0, @vk_WallPostMessageDialog, MsgDetails, 0, res));
               end;
             end;
           VK_WALL_PIC_TEXT:
             begin
               SendMessageW(GetDlgItem(Dialog, VK_WALL_STATUS), WM_SETTEXT, 0, Windows.lParam(PChar('')));
               ShowWindow(GetDlgItem(Dialog, VK_WALL_PIC_EDIT), SW_SHOW);
               ShowWindow(GetDlgItem(Dialog, VK_WALL_PIC), SW_HIDE);
               SetFocus(GetDlgItem(dialog, VK_WALL_PIC_EDIT));
             end;
           VK_WALL_PIC_IMAGE:
             begin
               SendMessageW(GetDlgItem(Dialog, VK_WALL_STATUS), WM_SETTEXT, 0, Windows.lParam(PChar('')));
               ShowWindow(GetDlgItem(Dialog, VK_WALL_PIC), SW_SHOW);
               ShowWindow(GetDlgItem(Dialog, VK_WALL_PIC_EDIT), SW_HIDE);
               SetFocus(GetDlgItem(dialog, VK_WALL_PIC));
             end;
           VK_WALL_PIC:
             begin
               // show standard Open file dialog
               FillChar(ofn, SizeOf(ofn), 0);
               ofn.lStructSize := SizeOf(ofn);
               filter[0] := #0;
               pluginLink^.CallService(MS_UTILS_GETBITMAPFILTERSTRINGS, SizeOf(filter), windows.lParam(@filter));
               ofn.hwndOwner := 0;
               ofn.lpstrFile := FileName;
		           ofn.lpstrFilter := filter;
               ofn.nMaxFile := MAX_PATH;
               ofn.nMaxFileTitle := MAX_PATH;
               ofn.Flags := OFN_FILEMUSTEXIST or OFN_EXPLORER or OFN_ENABLESIZING or OFN_ENABLEHOOK;
               ofn.lpstrInitialDir := '.';
               FileName[0] := #0;
               ofn.lpstrDefExt := '';
               ofn.hInstance := hInstance;
               if GetOpenFileNameA(ofn) then
               begin
                 sPicFileName := FileName; // keep filename in the global variable
                 // clear picture area
                 DC := GetDC(GetDlgItem(Dialog, VK_WALL_PIC));
                 GetClientRect(GetDlgItem(Dialog, VK_WALL_PIC), rc);
                 FillRect(DC, rc, GetSysColorBrush(COLOR_BTNFACE));
                 FrameRect(DC, rc, GetSysColorBrush(COLOR_BTNSHADOW));
                 ReleaseDC(GetDlgItem(Dialog, VK_WALL_PIC), DC);
                 // load picture
                 hBmp := pluginLink^.CallService(MS_IMG_LOAD, windows.wParam(@FileName), 0);
                 if hBmp <> 0 then
                 begin
                   // display file size and dimension
                   iFileSize := GetFileSize_(FileName); // bytes
                   iFileSize := Round(iFileSize/1024); // kilobytes
                   FillChar(buf, SizeOf(Bitmap), 0);
                   GetObject(hBmp, SizeOf(Bitmap), @buf);
                   SendMessageW(GetDlgItem(Dialog, VK_WALL_STATUS), WM_SETTEXT, 0, Windows.lParam(WideString(IntToStr(iFileSize) + ' ' + TranslateW('Kb') + ' (' + IntToStr(buf.bmWidth) + 'x' + IntToStr(buf.bmHeight) + ')')));

                   // resize picture to 272x136 max
                   FillChar(rb, SizeOf(rb), 0);
                   rb.size := SizeOf(rb);
                   rb.hBmp := hBmp;
                   rb.max_width := 360;
                   rb.max_height := 293;
                   rb.fit := 0 {RESIZEBITMAP_KEEP_PROPORTIONS + RESIZEBITMAP_FLAG_DONT_GROW};
                   hBmp := pluginLink^.CallService(MS_IMG_RESIZE, windows.wParam(@rb), 0);

                   bPictureSelected := True;

                   // SendMessage(Dialog, WM_DRAWITEM, 0, 0);
                   InvalidateRect(Dialog, @rc, True);

                   Result := true;
                 end;
               end;
             end;
         end;
       end;
  end;
end;

// =============================================================================
// function to get full id required to post message on the wall
// -----------------------------------------------------------------------------
function vk_WallGetFullID(ContactID: Integer): Int64;
var
  HTML: String;
  StrTemp: String;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetFullID) Getting full id of contact ' + IntToStr(ContactID) + '...'));
  HTML := HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_wall_id, [ContactID]));
  if Trim(HTML) <> '' then
  begin
    StrTemp := TextBetween(HTML, '&id=', '">Написать на стене');
    if not TryStrToInt64(StrTemp, Result) then
      Result := 0;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetFullID) ... full id of contact ' + IntToStr(ContactID) + ' identified as ' + IntToStr(Result)));
end;

// function to decode wall hash
function DecodeWallHash(Hash: String): String;

  function Invert(S: String): String;
  var
    i: Integer;
  begin
    Result := '';
    for i := 0 to Length(S)-1 do Result := Result + S[Length(S) - i];
  end;

var
  leftStr,
  rightStr: String;

begin
  leftStr := Copy(hash, Length(hash)-4, 5);
  rightStr := Copy(hash, 5, Length(hash)-12);
  Result := Invert(leftStr + rightStr);
end;

// =============================================================================
// function to get hash to post message on the wall
// (full id is required for this)
// -----------------------------------------------------------------------------
function vk_WallGetHash(ContactFullID: Int64): String;
var
  HTML,
  Hash: String;
begin
  Result := '';

  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) Getting hash of contact ' + IntToStr(ContactFullID) + '...'));

  // getting encoded wall hash
  HTML := HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_wall_hash, [ContactFullID]));
  if Trim(HTML) <> '' then
  begin
    Hash := Trim(TextBetween(HTML, 'name="wall_hash" value="', '"'));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) ... encoded hash of contact ' + IntToStr(ContactFullID) + ' is ' + Hash));
    if Length(Hash) = 39 then
    begin // decode hash if everything is OK
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) ... decoding hash of contact ' + IntToStr(ContactFullID) + '...'));
      Result := DecodeWallHash(Hash);
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) ... decoded hash of contact ' + IntToStr(ContactFullID) + ' is ' + Result));
    end;
  end;

end;


// =============================================================================
// function to post message on the wall
// called directly from the main messages window
// -----------------------------------------------------------------------------
function vk_WallPostMessage(MsgDetails: PMsgDetails): TResultDetailed; overload;
var
  HTML: String;
  Hash: String;

  ContactID, FullContactID: Int64;
  CaptchaId, CaptchaValue: String;
  MsgTextOrig, MsgText: String;
  szDataFinal: String;
  Dialog, DialogLabel: HWnd; // handles of the dialog and dialog lable reflecting processing status
  PopupsShowStatus: Boolean;
  defTimeout1, defTimeout2: Integer;
begin
 // temporarily increase timeout periods for messages sending
 defTimeout1 := DBGetContactSettingDword(0, 'SRMM', 'MessageTimeout', 10000);
 defTimeout2 := DBGetContactSettingDword(0, 'SRMsg', 'MessageTimeout', 10000);
 DBWriteContactSettingDWord(0, 'SRMM', 'MessageTimeout', 60000);
 DBWriteContactSettingDWord(0, 'SRMsg', 'MessageTimeout', 60000);

 Result.Text := '';
 Result.Code := 1; // failed
  if DBGetContactSettingByte(0, piShortName, opt_PopupsWallShowStatus, 0) = 0 then // display status in popups?
    PopupsShowStatus := False
  else
    PopupsShowStatus := True;
  Dialog := MsgDetails^.Wnd;
  if Dialog <> 0 then // called from separate dialog?
  begin
    DialogLabel := GetDlgItem(Dialog, VK_WALL_STATUS);
    SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(TranslateW(wall_status_posting_started)));
  end else
    DialogLabel := 0; // useless, just to remove Variable '<element>' might not have been initialized message
  ContactID := MsgDetails^.ID;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) Posting message on the wall of contact ' + IntToStr(ContactID) + '...'));
  FullContactID := vk_WallGetFullID(ContactID);
  MsgTextOrig := MsgDetails^.MessageText;
  try
    MsgText := URLEncode(UTF8Encode(MsgTextOrig));
  except
    MsgText := '';
  end;
  Dispose(MsgDetails);

  if Dialog <> 0 then
    SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(TranslateW(wall_status_getting_hash)));
  if FullContactID <> 0 then
    Hash := vk_WallGetHash(FullContactID);

  if Length(Hash) = 32 then
  begin

    if (vk_Status = ID_STATUS_INVISIBLE) then
    begin
      if Dialog <> 0 then
        SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(TranslateW(wall_status_posting)));
      HTML := HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_wall + '?' + vk_url_wall_postmsg, [FullContactID, Hash, MsgText]), REQUEST_HEAD);
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... posting of the message on the wall of contact ' + IntToStr(ContactID) + ' finished. Unable to verify result fully due to Invisible mode, but trying'));
      HTML := HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_wall_id, [ContactID]));
      if Pos(MsgTextOrig, HTMLDecode(HTML)) > 0 then
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... posting of the message on the wall of contact ' + IntToStr(ContactID) + ' looks successful'));
        Result.Text := TranslateW(wall_status_invisible_succ);
        Result.Code := 0;
      end
      else
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... posting of the message on the wall of contact ' + IntToStr(ContactID) + ' seems failed'));
        Result.Text := TranslateW(wall_status_invisible_failed);
        Result.Code := 1;
      end;
      if Dialog <> 0 then
        SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
      if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
    end
    else
    begin // status = ONLINE
      if Dialog <> 0 then
        SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(TranslateW(wall_status_posting)));

      szDataFinal := Format(vk_url_wall_postmsg, [FullContactID, Hash, MsgText]);
      HTML := HTTP_NL_Post(vk_url_prefix + vk_url_host + vk_url_wall, szDataFinal, 'application/x-www-form-urlencoded','');
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... posting of the message on the wall of contact ' + IntToStr(ContactID) + ' done. Checking result...'));

      if Pos('r/id' + IntToStr(ContactID), HTML) > 0 then
      begin
        Result.Text := TranslateW(wall_status_succ);
        Result.Code := 0;
        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... message posted successfully'));
        if Dialog <> 0 then
          SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
        if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
      end
      else
        if Pos('captcha_sid', HTML) > 0 then // captcha!
        begin
          Result.Text := TranslateW(wall_status_captcha_required);
          Result.Code := 1; // not successful yet
          if Dialog <> 0 then
            SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
          if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... captcha input is required, getting it...'));
          CaptchaId := TextBetween(HTML, '"captcha_sid":"', '"');

          CaptchaValue := ProcessCaptcha(CaptchaId);

          // error - can't download captcha image
          if CaptchaValue = 'captcha_download_failed' then
          begin
            Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... unable to download captcha'));
            Result.Text := TranslateW(wall_status_captcha_failed);
            Result.Code := 1;
            if Dialog <> 0 then
              SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
            if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
          end
          else // ok
          begin
            szDataFinal := Format(vk_url_wall_postmsg_captcha, [FullContactID, Hash, MsgText, CaptchaId, CaptchaValue]);
            HTML := HTTP_NL_Post(vk_url_prefix + vk_url_host + vk_url_wall, szDataFinal, 'application/x-www-form-urlencoded','');
            if Pos('r/id' + IntToStr(ContactID), HTML) > 0 then
            begin
              Result.Text := TranslateW(wall_status_succ);
              Result.Code := 0;
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... message posted successfully'));
              if Dialog <> 0 then
                SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
              if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
            end
            else
            begin
              Result.Text := TranslateW(wall_status_failed);
              Result.Code := 1;
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... message posting failed'));
              if Dialog <> 0 then
                SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
              if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 1, False);
            end;
          end;
        end;
    end;
  end else
  begin
    Result.Text := TranslateW(wall_status_getting_hash_failed);
    Result.Code := 1;
    if Dialog <> 0 then
      SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
    if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
  end;
  if Dialog <> 0 then
    DlgWallPicEnable(Dialog); // enable all dialog elements

  // restore timeout periods
  DBWriteContactSettingDWord(0, 'SRMM', 'MessageTimeout', defTimeout1);
  DBWriteContactSettingDWord(0, 'SRMsg', 'MessageTimeout', defTimeout2);
end;

// =============================================================================
// function to post message on the wall
// (just another (overload) version of the function above)
// -----------------------------------------------------------------------------
function vk_WallPostMessage(ID: Integer; const MessageText: WideString; Wnd: HWnd): TResultDetailed; overload;
var
  MsgDetails: PMsgDetails;
begin
  New(MsgDetails);
  MsgDetails^.ID := ID;
  MsgDetails^.MessageText := MessageText;
  MsgDetails^.Wnd := Wnd;
  Result := vk_WallPostMessage(MsgDetails);
end;

// =============================================================================
// procedure to post message on the wall, just call another function
// called in the separate thread from the dialog
// separate procedure is created as BeginThread can not accept TResultDetailed
// as result of the function
// -----------------------------------------------------------------------------
function vk_WallPostMessageDialog(MsgDetails: PMsgDetails): Integer;
begin
  Result := vk_WallPostMessage(MsgDetails).Code;
end;

// =============================================================================
// procedure to post picture on the wall, just call another function
// called in the separate thread from the dialog
// separate procedure is created as BeginThread can not accept TResultDetailed
// as result of the function
// -----------------------------------------------------------------------------
function vk_WallPostPictureDialog(MsgDetails: PMsgDetails): Integer;
begin
  Result := vk_WallPostPicture(MsgDetails).Code;
end;

// =============================================================================
// function to post picture on the wall
// called from the separate dialog only
// -----------------------------------------------------------------------------
function vk_WallPostPicture(MsgDetails: PMsgDetails): TResultDetailed; overload;
var
  HTML: String;
  sFileName: String;
  iFileSize: Cardinal; // picture file size (max allowed = 255 Кб)
  Dialog, DialogLabel: HWnd; // handles of the dialog and dialog lable reflecting processing status
  PopupsShowStatus: Boolean;
  PictureFile: TFileStream;
  szData: String;
  Boundary, FileHeader, FileTrailer, szDataFinal: String;

  PicBase64: PChar; // variables to calculate Base64
  nbd: TNETLIBBASE64;

  mdi: TMD5_INTERFACE; // variables to calculate MD5
  md5hash: TMD5_Digest;
  md5Signature: String;
  i: byte;

  FullContactID: Int64;
  Hash, MsgID, StrTemp: String;

  CaptchaId, CaptchaValue: String;

begin
  sFileName := MsgDetails^.MessageText;
  ContactID := MsgDetails^.ID;
  Dialog := MsgDetails^.Wnd;
  DialogLabel := GetDlgItem(Dialog, VK_WALL_STATUS);
  Dispose(MsgDetails);

	if Dialog <> 0 then
		SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(TranslateW(wall_status_posting_pic_started)));

  Result.Text := '';
  Result.Code := 1; // failed
  if DBGetContactSettingByte(0, piShortName, opt_PopupsWallShowStatus, 0) = 0 then // display status in popups?
     PopupsShowStatus := False
   else
     PopupsShowStatus := True;

  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) Posting picture on the wall of contact ' + IntToStr(ContactID) + '...'));

  if (ContactID <> 0) and (sFileName <> '') then
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... looking for original file ' + sFileName + '...'));
    if FileExists(sFileName) then
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... picture file found, reading it...'));
		  // reading picture file
      Result.Text := TranslateW(wall_status_posting_pic_reading);
		  if Dialog <> 0 then
		     SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));


      // picture file size calculating & checking routine
      iFileSize := GetFileSize_(sFileName); // bytes
      iFileSize := Round(iFileSize/1024); // kilobytes

      if iFileSize <= pic_max_size then
      begin
  		  PictureFile := TFileStream.Create(sFileName, fmOpenRead);
	  	  SetLength(szData, PictureFile.Size);
		    PictureFile.Read(szData[1], PictureFile.Size);
		    PictureFile.Free;

        if szData <> '' then
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... file has been read, generating base64 hash...'));
			    // generating Base64
          Result.Text := TranslateW(wall_status_posting_pic_base64);
  		    if Dialog <> 0 then
	          SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
		      FillChar(nbd, SizeOf(nbd), 0);
  			  nbd.pbDecoded := PByte(PChar(szData));
	  		  nbd.cbDecoded := Length(szData)+1;
		  	  nbd.cchEncoded := Netlib_GetBase64EncodedBufferSize(nbd.cbDecoded);
			    GetMem(PicBase64, nbd.cchEncoded);
  			  nbd.pszEncoded := PicBase64;
	  		  PluginLink^.CallService(MS_NETLIB_BASE64ENCODE, 0, Windows.lParam(@nbd));

          if StrLen(PicBase64) > 0 then
          begin
            Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... base64 hash has been generated, calculating md5...'));
	  			  // generating MD5 for first 1024 bytes
            Result.Text := TranslateW(wall_status_posting_pic_md5);
		        if Dialog <> 0 then
		          SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
  				  FillChar(mdi, SizeOf(mdi), 0);
	  			  mdi.cbSize := SizeOf(mdi);
		  		  PluginLink^.CallService(MS_SYSTEM_GET_MD5I, 0, Windows.lParam(@mdi));
			  	  {FillChar(PicMD5, SizeOf(PicMD5), 0); // these 4 lines are just alternative to md5_hash,
  				  mdi.md5_init(PicMD5);                 // PicMD5: mir_md5_state_t;
	  			  mdi.md5_append(PicMD5, PicBase64^, 1024);
		  		  mdi.md5_finish(PicMD5, md5hash);}
			  	  if StrLen(PicBase64) > 1024 then // we need first 1024 bytes only
				  	  mdi.md5_hash(PicBase64^, 1024, md5hash)
  				  else
	  			   	mdi.md5_hash(PicBase64^, StrLen(PicBase64), md5hash);
		  		  // transforming array to string
			  	  md5Signature := '';
				    for i := 0 to 15 do
    					md5Signature := md5Signature + IntToHex(md5hash[i], 2);
		  	    md5Signature := LowerCase(md5Signature);

            if Trim(md5Signature) <> '' then
            begin
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... md5 has been calculated ('+md5Signature+'), uploading the file...'));
	  				  // generating header for our post request
		  			  Boundary := '--OLEG-ANDREEV-PAVEL-DUROV-GRAFFITI-POST';
			  		  FileHeader :=
				  	    '--' + Boundary +
					  	  #10 +
						    'Content-Disposition: form-data; name="Signature"' +
							  #10 + #10 +
							  md5Signature +
							  #10 +
  						  '--' + Boundary +
	  					  #10 +
                'Content-Disposition: form-data; name="Filedata"; filename="graffiti.png"' +
			  			  #10 +
				  		  'Content-Type: image/png' +
					  	  #10 + #10;
					    FileTrailer := #10 + '--' + Boundary + '--';
  					  szDataFinal := FileHeader + szData + FileTrailer;
              Result.Text := TranslateW(wall_status_posting_pic_sending);
		          if Dialog <> 0 then
              begin
                SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
              end;

  					  HTML := HTTP_NL_PostPicture(Format(vk_url_prefix + vk_url_host + vk_url_wall_postpic_upload, [ContactID]), szDataFinal, Boundary);

              // checking for error messages from server
              if Pos('413 Request Entity Too Large', HTML) > 0 then
              begin
                Result.Text := TranslateW(wall_status_posting_pic_size_failed);
                Result.Code := 1;
                Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... picture posting failed (file size limit is reached).'));
              end
              else if Trim(HTML) <> '' then
              begin
                if HTML <> 'Security Breach. Sorry.' then
                begin
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... the file has been uploaded successfully, getting details...'));
                  HTML := TextBetween(HTML, 'var params = {', '}');
                  StrTemp := TextBetween(HTML, 'to_id: ''', '''');
                  Hash := DecodeWallHash(TextBetween(HTML, 'wall_hash: decodehash(''', ''')'));
                  MsgID := TextBetween(HTML, 'message: ''', '''');
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... message details: grid '+MsgId+', hash '+Hash));

                  Result.Text := TranslateW(wall_status_posting_pic_id) + ' (' + MsgID + ')';
		              if Dialog <> 0 then
		                SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));

                  if TryStrToInt64(StrTemp, FullContactID) and (Length(Hash) = 32) and (Trim(MsgID) <> '') then
                  begin
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... posting picture id '+MsgID+'...'));
                    Result.Text := TranslateW(wall_status_posting_pic_posting);
                    HTML := HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_wall_postpic, [MsgID, FullContactID, Hash, MsgID]), REQUEST_GET);
                    if HTML <> '' then // contains some strange symbols, so assume if not empty, then OK
                    begin
                      if Pos('captcha_sid', HTML) > 0 then // captcha!
                      begin
                        Result.Text := TranslateW(wall_status_captcha_required);
                        Result.Code := 1; // not successful yet
                        if Dialog <> 0 then
                          SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
                        if PopupsShowStatus then
                          ShowPopupMsg(0, Result.Text, 2, False);
                        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... captcha input is required, getting it...'));
                        CaptchaId := TextBetween(HTML, '"captcha_sid":"', '"');

                        CaptchaValue := ProcessCaptcha(CaptchaId);

                        // error - can't download captcha image
                        if CaptchaValue = 'captcha_download_failed' then
                        begin
                          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... unable to download captcha'));
                          Result.Text := TranslateW(wall_status_captcha_failed);
                          Result.Code := 1;
                          if Dialog <> 0 then
                            SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
                          if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
                        end else // ok
                        begin
                          HTML := HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_url_wall_postpic_captcha, [MsgId, FullContactID, Hash, MsgId, CaptchaId, CaptchaValue]), REQUEST_GET);
                          if Pos('r/id' + IntToStr(ContactID), HTML) > 0 then
                          begin
                            Result.Text := TranslateW(wall_status_succ);
                            Result.Code := 0;
                            Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... picture posted successfully'));
                            if Dialog <> 0 then
                              SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
                            if PopupsShowStatus then
                              ShowPopupMsg(0, Result.Text, 2, False);
                          end
                          else
                          begin
                            Result.Text := TranslateW(wall_status_failed);
                            Result.Code := 1;
                            Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... picture posting failed'));
                            if Dialog <> 0 then
                              SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
                            if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 1, False);
                          end;
                        end;
                      end
                      else
                      begin
                        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... posting successful'));
                        Result.Text := TranslateW(wall_status_posting_pic_succ);
                        Result.Code := 0; // successful
                      end;
                    end
                    else
                    begin
                      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... posting of the picture failed'));
                      Result.Text := TranslateW(wall_status_posting_pic_failed_unknown);
                    end;
                  end
                  else
                  begin
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... uploading of the picture failed, unable to get details'));
                    Result.Text := TranslateW(wall_status_posting_pic_id_failed);
                  end;
                end
                else
                begin
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... uploading of the picture failed, security violation'));
                  Result.Text := TranslateW(wall_status_posting_pic_sending_failed_security);
                end;
              end
              else
              begin
                Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... uploading of the picture failed'));
                Result.Text := TranslateW(wall_status_posting_pic_sending_failed_unknown);
              end;
            end
            else
            begin
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... unable to calculate md5, posting failed'));
              Result.Text := TranslateW(wall_status_posting_pic_md5_failed);
            end;
          end
          else
          begin
            Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... unable to calculate base64 hash, posting failed'));
            Result.Text := TranslateW(wall_status_posting_pic_base64_failed);
          end;
          FreeMem(PicBase64);
        end
        else
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... unable to read picture file, posting failed'));
          Result.Text := TranslateW(wall_status_posting_pic_reading_failed);
        end;
      end
      else
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... picture posting failed (file size limit is reached).'));
        Result.Text := TranslateW(wall_status_posting_pic_size_failed);
        Result.Text := Result.Text + ' ' + IntToStr(pic_max_size) + ' ' + TranslateW(pic_max_size_msg);
      end;
    end
    else
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... picture file not found, posting failed'));
      Result.Text := TranslateW(wall_status_posting_pic_failed_not_found);
    end;
  end
  else
  begin
    Result.Text := TranslateW(wall_status_posting_pic_failed_incorrect_details);
  end;

  if PopupsShowStatus then
    if Result.Code = 0 then
      ShowPopupMsg(0, Result.Text, 1, False) // successful
    else
      ShowPopupMsg(0, Result.Text, 2, False); // failed

  if Dialog <> 0 then
  begin
	  SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
    DlgWallPicEnable(Dialog); // enable all dialog elements
  end;

  If Trim(HTML) <> '' Then
	 Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... finished picture upload'));

end;

// =============================================================================
// function to post message on the wall
// (just another (overload) version of the function above)
// -----------------------------------------------------------------------------
function vk_WallPostPicture(ID: Integer; const MessageText: WideString; Wnd: HWnd): TResultDetailed; overload;
var
  MsgDetails: PMsgDetails;
begin
  New(MsgDetails);
  MsgDetails^.ID := ID;
  MsgDetails^.MessageText := MessageText;
  MsgDetails^.Wnd := Wnd;
  Result := vk_WallPostPicture(MsgDetails);
end;

// =============================================================================
// procedure to get messages from the wall of given contact
// TODO: Add support of video, audio etc.
// -----------------------------------------------------------------------------
procedure vk_WallGetMessages(ID: Integer = 0);
var
  HTML: String;
  sSenderID,
  sMsgID: String;
  sSenderName,
  sSenderNameFull,
  sMsgText: WideString;
  MsgDate: TDateTime;
  iSenderStatus,
  iSenderID,
  iMsgDate,
  iMsgID: Integer;
  TempFriend: Integer;
  jsoFeed, jsoFeedProfile: TlkJSONobject;
  iWallMsgsCount: Integer;
  i: Byte;

begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) Getting wall messages for id ' + IntToStr(ID) + '...'));

  HTML := HTTP_NL_Get(GenerateApiUrl(vk_url_api_wall_get));
  if Trim(HTML) <> '' then
  begin
    jsoFeed := TlkJSON.ParseText(HTML) as TlkJSONobject;
    try
      iWallMsgsCount := jsoFeed.Field['response'].Count; // to be on the safe side, read messages count from the data downloaded
      for i:=iWallMsgsCount-1 downto 1 do
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... processing message ' + IntToStr(i) + ' started...'));
        iSenderID := jsoFeed.Field['response'].Child[i].Field['from_id'].Value;
        iMsgID := jsoFeed.Field['response'].Child[i].Field['id'].Value;
        iMsgDate := jsoFeed.Field['response'].Child[i].Field['date'].Value;
        MsgDate := UnixToDateTime(iMsgDate);
        sMsgText := jsoFeed.Field['response'].Child[i].Field['text'].Value;
        // sMsgText := StringReplace(sMsgText, '<br>', ' ', [rfReplaceAll, rfIgnoreCase]);
        iSenderStatus := jsoFeed.Field['response'].Child[i].Field['online'].Value;
        if iSenderStatus = 1 then
          iSenderStatus := ID_STATUS_ONLINE
        else
          iSenderStatus := ID_STATUS_OFFLINE;

        if (iMsgID > 0) and (iMsgDate > 0) and (iSenderID > 0) and (sMsgText <> '') then
        begin
          // add only new posts
          if iMsgDate > DBGetContactSettingDWord(0, piShortName, opt_WallLastPostID, 0) then
          begin
            if DBGetContactSettingByte(0, piShortName, opt_WallSeparateContactUse, 0) = 1 then
            begin // getting message in the separate contact, so getting details of a sender
              HTML := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_getprofiles, [IntToStr(iSenderID),'first_name,last_name,nickname,sex,online'])));
              if Pos('error', HTML) > 0 then
              begin
                Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '('+IntToStr(iMsgID)+'), unable to get name, error code: '+IntToStr(GetJSONError(HTML))));
                sSenderNameFull := 'id'+IntToStr(iSenderID); // define name with id instead
              end
              else
              begin
                // TODO: verify if it works properly with unicode symbols
                // HTMLInbox := HTMLDecodeW(iSenderID);
                jsoFeedProfile := TlkJSON.ParseText(HTML) as TlkJSONobject;
                try
                  sSenderNameFull := jsoFeedProfile.Field['response'].Child[0].Field['first_name'].Value + ' ' + jsoFeedProfile.Field['response'].Child[0].Field['last_name'].Value;
                finally
                  jsoFeedProfile.Free;
                end;
              end;

              TempFriend := vk_AddFriend(DBGetContactSettingDWord(0, piShortName, opt_WallSeparateContactID, 666), // separate contact ID, 666 by default
														  DBReadUnicode(0, piShortName, opt_WallSeparateContactName, TranslateW('The wall')), // separate contact nick, translated 'The wall' by default
														  ID_STATUS_ONLINE, // status
														  1); // friend = yes
              sMsgText := sSenderNameFull + ': ' + sMsgText;
            end
            else // no separate The Wall contact, message should be added in according contact
            begin
              sMsgText := WideString(TranslateW(DBReadUnicode(0, piShortName, opt_WallMessagesWord, 'wall:'))) + ' ' + sMsgText;
              // if message from unknown contact then
              // add contact to our list temporary
              TempFriend := GetContactByID(iSenderID);
              if TempFriend = 0 Then
              begin
								Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) ... wall message id ' + sMsgID + ' received from unknown contact ' + sSenderID + ', adding him/her to the contact list temporarily'));
								// add sender to our contact list
								TempFriend := vk_AddFriend(iSenderID, sSenderName, iSenderStatus, 0);
								// and make it as temporary contact
								DBWriteContactSettingByte(TempFriend, 'CList', 'NotOnList', 1);
                DBWriteContactSettingByte(TempFriend, 'CList', 'Hidden', 1);
              end;
            end;

            Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) ... adding wall message to miranda database...'));
            // everything seems to be OK, may add this message to Miranda DB
            vk_ReceiveMessage(TempFriend, sMsgText, MsgDate);
            DBWriteContactSettingDWord(0, piShortName, opt_WallLastPostID, iMsgDate); // log id (time and date) of last post

          end;

        end;
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... processing message ' + IntToStr(i) + ' completed'));
      end;

    finally
      jsoFeed.Free;
    end;
  end;

  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) ... getting wall messages for id ' + IntToStr(ID) + ' finished'));
end;

begin
end.
