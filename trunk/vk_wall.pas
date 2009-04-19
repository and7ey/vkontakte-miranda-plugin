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
 vk_wall.pas

 [ Description ]
 Module to work with VKontakte's wall

 [ Known Issues ]
 None

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

  Windows,
  Messages;

type
  PMsgDetails = ^TMsgDetails;
  TMsgDetails = record
    ID: Integer;
    MessageText: WideString;
    Wnd: HWnd;
  end;

  function DlgCaptcha(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
  function DlgWallPic(Dialog: HWnd; Msg: Cardinal; wParam, lParam: DWord): Boolean; stdcall;
  function vk_WallPostMessage(MsgDetails: PMsgDetails): TResultDetailed; overload;
  function vk_WallPostMessage(ID: Integer; const MessageText: WideString; Wnd: HWnd): TResultDetailed; overload;
  function vk_WallPostMessageDialog(MsgDetails: PMsgDetails): Integer;
  function vk_WallPostPicture(MsgDetails: PMsgDetails): Integer; overload;
  function vk_WallPostPicture(ID: Integer; const MessageText: WideString; Wnd: HWnd): Integer; overload;

  procedure vk_WallGetMessages(ID: Integer = 0);

implementation

uses
  vk_core, // module with core functions
  vk_msgs, // module to send/receive messages

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
	wall_status_posting_pic_sending_failed_unknown = 'Uploading failed due to uknown reason';
	wall_status_posting_pic_sending_failed_security = 'Uploading failed due to security violation';
  wall_status_posting_pic_id = 'Picture uploaded';
  wall_status_posting_pic_id_failed = 'Posting failed. Unable to get picture id';
  wall_status_posting_pic_posting = 'Posting of the picture...';
  wall_status_posting_pic_failed_unknown = 'Posting failed due to uknown reason';
  wall_status_posting_pic_succ = 'The picture has been posted successfully';


var
  bPictureSelected: Boolean;
  hBmp: THandle;
  sPicFileName: WideString;
  hBmpCaptcha: THandle;
  CaptchaValue: String;
  ContactID: Integer;
  EditFunctionOriginal: Pointer;

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
           ShellAPI.ShellExecute(0, 'open', PChar(Format(vk_url_wall_id, [ContactID])), nil, nil, 0);
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
                 CloseHandle(BeginThread(nil, 0, @vk_WallPostPicture, MsgDetails, 0, res));
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
                   rb.max_width := 272;
                   rb.max_height := 136;
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
  HTML := HTTP_NL_Get(Format(vk_url_wall_id, [ContactID]));
  if Trim(HTML) <> '' then
  begin
    StrTemp := TextBetween(HTML, '&id=', '">�������� �� �����');
    if not TryStrToInt64(StrTemp, Result) then
      Result := 0;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetFullID) ... full id of contact ' + IntToStr(ContactID) + ' identified as ' + IntToStr(Result)));
end;

// =============================================================================
// function to get hash to post message on the wall
// (full id is required for this)
// -----------------------------------------------------------------------------
function vk_WallGetHash(ContactFullID: Int64): String;

  // function to decode hash
  // converted from javascript function from wall.php
  function DecodeHash(Hash: string; z: String; Num: Integer): string;
    function Func1(x: Integer): String;
    begin
      while x < 48 do
        x := x + 75;
      while x > 122 do
        x := x - 75;
      Result := Chr(x);
    end;

    function Func2(x: String): Integer;
    begin
      Result := Ord(x[1]);
    end;

  var j: String;
      p: byte;
  begin
    j := '';

    for p := 1 to length(Hash) do
    begin
      j := j + Func1(Func2(z) + Num - Func2(Hash[p]));
      z := Hash[p];
    end;

    Result := j;
  end;

var
  HTML,
  Hash,
  HashDecodeSymbol,
  HashDecodeNumberStr,
  StrTemp: String;
  HashDecodeNumber: Integer;
begin
  Result := '';

  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) Getting hash of contact ' + IntToStr(ContactFullID) + '...'));

  // getting encoded wall hash
  HTML := HTTP_NL_Get(Format(vk_url_wall_hash, [ContactFullID]));
  if Trim(HTML) <> '' then
  begin
    Hash := Trim(TextBetween(HTML, 'name="wall_hash" value="', '"'));
    // tricky actions to decode hash -
    // reading data from javascript
    StrTemp :=  TextBetween(HTML, '="";var ', 'charAt(');
    HashDecodeSymbol := Trim(TextBetween(StrTemp, '="', '"'));
    HashDecodeNumberStr := TextBetween(StrTemp, ')+', '-');

    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) ... encoded hash of contact ' + IntToStr(ContactFullID) + ' is ' + Hash));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) ... hash symbol of contact ' + IntToStr(ContactFullID) + ' is ' + HashDecodeSymbol));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) ... hash number of contact ' + IntToStr(ContactFullID) + ' is ' + HashDecodeNumberStr));

    if (Hash <> '') and (HashDecodeSymbol <> '') and (TryStrToInt(HashDecodeNumberStr, HashDecodeNumber)) then
    begin // decode hash if everything is OK
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetHash) ... decoding hash of contact ' + IntToStr(ContactFullID) + '...'));
      Result := DecodeHash(Hash, HashDecodeSymbol, HashDecodeNumber);
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
  CaptchaId, CaptchaURL: String;
  TempDir, TempFile: String;
  Buf: array[0..1023] of Char;
  MsgTextOrig, MsgText: WideString;
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
  if Trim(Hash) <> '' then
  begin

    if (vk_Status = ID_STATUS_INVISIBLE) then
    begin
      if Dialog <> 0 then
        SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(TranslateW(wall_status_posting)));
      HTML := HTTP_NL_Get(Format(vk_url_wall_postmsg, [FullContactID, Hash, MsgText]), REQUEST_HEAD);
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... posting of the message on the wall of contact ' + IntToStr(ContactID) + ' finished. Unable to verify result fully due to Invisible mode, but trying'));
      HTML := HTTP_NL_Get(Format(vk_url_wall_id, [ContactID]));
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
      HTML := HTTP_NL_Get(Format(vk_url_wall_postmsg, [FullContactID, Hash, MsgText]));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... posting of the message on the wall of contact ' + IntToStr(ContactID) + ' done. Checking result...'));

      if Pos('r/id', HTML) > 0 then
      begin
        Result.Text := TranslateW(wall_status_succ);
        Result.Code := 0;
        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... message posted successfully'));
        if Dialog <> 0 then
          SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
        if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
      end
      else
        if Pos('������� ���:', HTML) > 0 then
        begin
          Result.Text := TranslateW(wall_status_captcha_required);
          Result.Code := 1; // not successful yet
          if Dialog <> 0 then
            SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
          if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... captcha input is required, getting it...'));
          CaptchaId := TextBetween(HTML, 'id="sid_captcha" value="', '"');
          CaptchaURL := TextBetween(HTML, 'captchaImg" src="', '"');
          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... captcha id is ' + CaptchaId));
          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... captcha URL is ' + CaptchaURL));
          if (CaptchaId <> '') and (CaptchaURL <> '') then
          begin
            CaptchaURL := vk_url + '/' + CaptchaURL;
            SetString(TempDir, Buf, GetTempPath(Sizeof(Buf)-1, Buf)); // getting path to Temp directory
            TempFile := TempDir + 'vk_captcha.jpg';
            if HTTP_NL_GetPicture(CaptchaURL, TempFile) then
            begin // file downloaded successfully
              Result.Text := TranslateW(wall_status_captcha_input);
              Result.Code := 1;
              if Dialog <> 0 then
                SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... captcha downloaded successfully and saved to ' + TempDir));
              // ask user to input the value
              DialogBoxParamW(hInstance, MAKEINTRESOURCEW(WideString('VK_CAPTCHA')), 0, @DlgCaptcha, Windows.lParam(TempFile));
              HTML := HTTP_NL_Get(Format(vk_url_wall_postmsg_captcha, [FullContactID, Hash, MsgText, CaptchaId, CaptchaValue]), REQUEST_GET);
              if Pos('userProfile', HTML) > 0 then
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
            end else
            begin
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostMessage) ... unable to download captcha'));
              Result.Text := TranslateW(wall_status_captcha_failed);
              Result.Code := 1;
              if Dialog <> 0 then
                SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(Result.Text));
              if PopupsShowStatus then ShowPopupMsg(0, Result.Text, 2, False);
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
// function to post picture on the wall
// called from the separate dialog only
// -----------------------------------------------------------------------------
function vk_WallPostPicture(MsgDetails: PMsgDetails): Integer; overload;
var
  ResultText: WideString;
  HTML: String;
  sFileName: String;
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
begin
  sFileName := MsgDetails^.MessageText;
  ContactID := MsgDetails^.ID;
  Dialog := MsgDetails^.Wnd;
  DialogLabel := GetDlgItem(Dialog, VK_WALL_STATUS);
  Dispose(MsgDetails);

	if Dialog <> 0 then
		SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(TranslateW(wall_status_posting_pic_started)));

  ResultText := '';
  Result := 1; // failed
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
      ResultText := TranslateW(wall_status_posting_pic_reading);
		  if Dialog <> 0 then
		     SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(ResultText));
		  PictureFile := TFileStream.Create(sFileName, fmOpenRead);
		  SetLength(szData, PictureFile.Size);
		  PictureFile.Read(szData[1], PictureFile.Size);
		  PictureFile.Free;

      if szData <> '' then
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... file has been read, generating base64 hash...'));
			  // generating Base64
        ResultText := TranslateW(wall_status_posting_pic_base64);
		    if Dialog <> 0 then
		       SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(ResultText));
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
          ResultText := TranslateW(wall_status_posting_pic_md5);
		      if Dialog <> 0 then
		         SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(ResultText));
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
            ResultText := TranslateW(wall_status_posting_pic_sending);
		        if Dialog <> 0 then
		           SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(ResultText));

					  HTML := HTTP_NL_PostPicture(Format(vk_url_wall_postpic_upload, [ContactID]), szDataFinal, Boundary);
            if Trim(HTML) <> '' then
            begin
              if HTML <> 'Security Breach. Sorry.' then
              begin
                Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... the file has been uploaded successfully, getting details...'));
                HTML := TextBetween(HTML, 'var params = {', '}');
                StrTemp := TextBetween(HTML, 'to_id: ''', '''');
                Hash := TextBetween(HTML, 'wall_hash: ''', '''');
                MsgID := TextBetween(HTML, 'message: ''', '''');
                Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... message details: grid '+MsgId+', hash '+Hash));

                ResultText := TranslateW(wall_status_posting_pic_id) + ' (' + MsgID + ')';
		            if Dialog <> 0 then
		              SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(ResultText));

                if TryStrToInt64(StrTemp, FullContactID) and (Trim(Hash) <> '') and (Trim(MsgID) <> '') then
                begin
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... posting picture id '+MsgID+'...'));
                  ResultText := TranslateW(wall_status_posting_pic_posting);
                  HTML := HTTP_NL_Get(Format(vk_url_wall_postpic, [MsgID, FullContactID, Hash, MsgID]));
                  if HTML <> '' then // contains some strange symbols, so assume if not empty, then OK
                  begin
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... posting successful'));
                    ResultText := TranslateW(wall_status_posting_pic_succ);
                    Result := 0; // successful
                  end
                  else
                  begin
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... posting of the picture failed'));
                    ResultText := TranslateW(wall_status_posting_pic_failed_unknown);
                  end;
                end
                else
                begin
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... uploading of the picture failed, unable to get details'));
                  ResultText := TranslateW(wall_status_posting_pic_id_failed);
                end;
              end
              else
              begin
                Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... uploading of the picture failed, security violation'));
                ResultText := TranslateW(wall_status_posting_pic_sending_failed_security);
              end;
            end
            else
            begin
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... uploading of the picture failed'));
              ResultText := TranslateW(wall_status_posting_pic_sending_failed_unknown);
            end;
          end
          else
          begin
            Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... unable to calculate md5, posting failed'));
            ResultText := TranslateW(wall_status_posting_pic_md5_failed);
          end;
        end
        else
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... unable to calculate base64 hash, posting failed'));
          ResultText := TranslateW(wall_status_posting_pic_base64_failed);
        end;
        FreeMem(PicBase64);
      end
      else
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... unable to read picture file, posting failed'));
        ResultText := TranslateW(wall_status_posting_pic_reading_failed);
      end;
    end
    else
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... picture file not found, posting failed'));
      ResultText := TranslateW(wall_status_posting_pic_failed_not_found);
    end;
  end
  else
  begin
    ResultText := TranslateW(wall_status_posting_pic_failed_incorrect_details);
  end;

  if PopupsShowStatus then
    if Result = 0 then
      ShowPopupMsg(0, ResultText, 1, False) // successful
    else
      ShowPopupMsg(0, ResultText, 2, False); // failed

  if Dialog <> 0 then
  begin
	  SendMessageW(DialogLabel, WM_SETTEXT, 0, Windows.lParam(ResultText));
    DlgWallPicEnable(Dialog); // enable all dialog elements
  end;

  If Trim(HTML) <> '' Then
	 Netlib_Log(vk_hNetlibUser, PChar('(vk_WallPostPicture) ... finished picture upload'));

end;

// =============================================================================
// function to post message on the wall
// (just another (overload) version of the function above)
// -----------------------------------------------------------------------------
function vk_WallPostPicture(ID: Integer; const MessageText: WideString; Wnd: HWnd): Integer; overload;
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
// -----------------------------------------------------------------------------
procedure vk_WallGetMessages(ID: Integer = 0);
var
  HTML: String;
  sWallPage,
  sWallPost,
  sSenderID,
  sMsgTime,
  sMsgID: String;
  sSenderName,
  sSenderNameFull,
  sMsgText: WideString;
  sTemp, sTemp2, sMsgAudioUrl: WideString;
  MsgDate: TDateTime;
  iSenderStatus,
  iSenderID,
  iMsgID,
  iURLPos: Integer;
  TempFriend: Integer;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) Getting wall messages for id ' + IntToStr(ID) + '...'));
  HTML := HTTP_NL_Get(Format(vk_url_wall_id, [ID]));
  if Trim(HTML) <> '' then
  begin
    sWallPage := TextBetweenTagsAttrInc(HTML, 'div', 'id', 'wallpage');
    if Trim(sWallPage) <> '' then
    begin
      while Pos('"wallpost"', sWallPage) > 0 do
      begin
        sWallPost := TextBetweenTagsAttrInc(sWallPage, 'table', 'class', 'wallpost');
        sMsgID := Trim(TextBetween(sWallPost, 'deletePost(', ',')); // post id - please note that it works when id = 0 only
        if (sWallPost <> '') and (TryStrToInt(sMsgID, iMsgID)) then
        begin
          // read other posts only if they are new
          if iMsgID > DBGetContactSettingDWord(0, piShortName, opt_WallLastPostID, 0) then
          begin
						sSenderID := TextBetween(sWallPost, 'href="/id', '"');
            sSenderName := Trim(HTMLDecodeW(TextBetween(sWallPost, 'style=''font-weight: bold;''>', '</a>')));
            if DBGetContactSettingByte(0, piShortName, opt_WallSeparateContactUse, 0) = 1 then
            begin // getting message in the separate contact, so get details of sender
          		sSenderNameFull := Trim(TextBetween(sWallPost, '<div class="header">', '<br />'));
              sSenderNameFull := StringReplace(sSenderNameFull, '"  style=''font-weight: bold;', '', [rfReplaceAll, rfIgnoreCase]);
              sSenderNameFull := ReplaceLink(sSenderNameFull);
              sSenderNameFull := Trim(HTMLRemoveTags(HTMLDecodeW(sSenderNameFull)));
            end;
            if Pos('<div style=''color:#aaa;margin:4px 0px 0px 10px;''>Online</div>', sWallPost) > 0 then
              iSenderStatus := ID_STATUS_ONLINE
            else
              iSenderStatus := ID_STATUS_OFFLINE;
						// message text
            sMsgText := TextBetweenTagsAttrInc(sWallPost, 'div', 'class', 'text');
            sMsgText := StringReplace(sMsgText, '<br>', ' ', [rfReplaceAll, rfIgnoreCase]);
            sMsgText := HTMLDecodeW(sMsgText);
            // - audio
						if Pos('"audioRowWall"', sMsgText) > 0 then
						begin
						  Insert(', ', sMsgText, Pos('<div class="duration">', sMsgText) - 1);
						  // operateWall(60833648,4210,6114921,'3c8680515484',249) -->
						  // http://cs4210.vkontakte.ru/u6114921/audio/3c8680515484.mp3
						  sTemp := TextBetween(sMsgText, 'operateWall(', ')');
						  sMsgAudioUrl := 'http://cs' +
										  TextBetween(sTemp, ',', ',') +
										  '.' + vk_url_host + '/u';
						  Delete(sTemp, 1, Pos(',', sTemp) + 1);
              sTemp2 := TextBetween(sTemp, ',', ',');
              while Length(sTemp2) < 5 do
                sTemp2 := '0' + sTemp2;
						  sMsgAudioUrl := sMsgAudioUrl +
										  sTemp2 +
										  '/audio/' +
										  TextBetween(sTemp, '''', '''') +
										  '.mp3';
              sMsgText := Trim(HTMLRemoveTags(sMsgText));
						  sMsgText := Trim(sMsgText) + ' (' + sMsgAudioUrl + ')';
              sMsgText := StringReplace(sMsgText, #$A, '', [rfReplaceAll, rfIgnoreCase]);
						end;
						// - video
						if Pos('"feedVideos"', sMsgText) > 0 then
						begin
						  sTemp := TextBetween(sMsgText, 'href="/video', '"');
						  sMsgText := sMsgText + ' (' + 'http://' + vk_url_host + '/video' + sTemp + ')';
						end;
						// - graffiti
						if Pos('''Graffiti''', sMsgText) > 0 then
						begin
						  sTemp := TextBetween(sMsgText, 'href=''/graffiti', '''');
						  sMsgText := Translate('Graffiti') + ' (' + 'http://' + vk_url_host + '/graffiti' + sTemp + ')';
						end;
						// - photo
						if Pos('"feedPhotos"', sMsgText) > 0 then
						begin
						  sTemp := TextBetween(sMsgText, 'href="/photo', '"');
						  sMsgText := sMsgText + ' (' + 'http://' + vk_url_host + '/photo' + sTemp + ')';
						end;
            // - contains url
            while Pos('away.php', sMsgText) > 0 do
            begin
              sTemp := URLDecode(TextBetween(sMsgText, 'away.php?to=', ''''));
              iURLPos := Pos('away.php', sMsgText);
              Insert(' (' + sTemp + ')', sMsgText, PosEx('</a>', sMsgText, iURLPos));
              Delete(sMsgText, Pos('away.php', sMsgText), 8);
            end;
						sMsgText := Trim(HTMLRemoveTags(sMsgText));

						sMsgTime := Trim(TextBetween(sWallPost, '<small>', '</small>'));

            try
              if DBGetContactSettingByte(0, piShortName, opt_WallUseLocalTime, 0) = 0 then
                MsgDate := RusDateToDateTime(sMsgTime, true)
              else
                MsgDate := Now; // use local time, if requested in the settings
             except
               MsgDate := Now;
             end;

						if (TryStrToInt(sSenderID, iSenderID)) and (TryStrToInt(sMsgID, iMsgID)) and (sMsgText <> '') and (sMsgTime <> '') then
						begin
              if DBGetContactSettingByte(0, piShortName, opt_WallSeparateContactUse, 0) = 1 then
              begin
                // messages should be added to a separate contact
								TempFriend := vk_AddFriend(DBGetContactSettingDWord(0, piShortName, opt_WallSeparateContactID, 666), // separate contact ID, 666 by default
														  DBReadUnicode(0, piShortName, opt_WallSeparateContactName, TranslateW('The wall')), // separate contact nick, translated 'The wall' by default
														  ID_STATUS_OFFLINE, // status
														  1); // friend = yes
                sMsgText := sSenderNameFull + ': ' + sMsgText;
              end
              else
              begin
                // message should be added in according contact
                sMsgText := WideString(TranslateW(DBReadUnicode(0, piShortName, opt_WallMessagesWord, 'wall:'))) + ' ' + sMsgText;
                // if message from unknown contact then
                // we add contact to our list temporary
							  TempFriend := GetContactByID(iSenderID);
							  If TempFriend = 0 Then
							  Begin
								Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) ... wall message id ' + sMsgID + ' received from unknown contact ' + sSenderID + ', adding him/her to the contact list temporarily'));
								// add sender to our contact list
								// now we don't read user's status, so it is added as offline
								TempFriend := vk_AddFriend(iSenderID, sSenderName, iSenderStatus, 0);
								// and make it as temporary contact
								DBWriteContactSettingByte(TempFriend, 'CList', 'NotOnList', 1);
								  DBWriteContactSettingByte(TempFriend, 'CList', 'Hidden', 1);
							  End;
              end;
              Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) ... adding wall message to miranda database...'));
              // everything seems to be OK, may add this message to Miranda DB
              vk_ReceiveMessage(TempFriend, sMsgText, MsgDate);
						end;
          end
          else
            break; // stop processing - all posts are received already
        end;
        Delete(sWallPage, 1, Pos('</table></div>', sWallPage)); // </table></div> identifies end of the post
      end;

      sMsgID := Trim(TextBetween(HTML, 'deletePost(', ',')); // last post id - please note that it works when id = 0 only
      if TryStrToInt(sMsgID, iMsgID) then
        DBWriteContactSettingDWord(0, piShortName, opt_WallLastPostID, iMsgID); // log id of last post

    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_WallGetMessages) ... getting wall messages for id ' + IntToStr(ID) + ' finished'));
end;

begin
end.
