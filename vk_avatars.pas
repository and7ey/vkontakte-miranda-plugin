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
 vk_avatars.pas

 [ Description ]
 Module to support Avatars for VKontakte plugin

 [ Known Issues ]
 See the code

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_avatars;

interface

  procedure AvatarsInit();
  procedure AvatarsDestroy();
  procedure vk_AvatarGetAndSave(ID, AvatarURL: String);
  procedure vk_AvatarsGet();

implementation

uses
  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used
  vk_common, // module with common functions
  vk_http, // module to connect with the site
  htmlparse, // module to simplify html parsing

  Windows,
  SysUtils,
  Classes;

type
  TThreadAvatarMySet = class(TThread)
  private
    { Private declarations }
  protected
    procedure Execute; override;
  end;

var
  vk_hAvatarInfoGet,
  vk_hAvatarCapsGet,
  vk_hAvatarMyGet,
  vk_hAvatarMySet: THandle;

  AvatarMyFileName: WideString; // variable to keep our avatar filename

  ThrIDAvatarMySet: TThreadAvatarMySet;

// =============================================================================
// procedure to verify whether update of avatar is required,
// and, if required, to get updated avatar
// -----------------------------------------------------------------------------
procedure vk_AvatarGetAndSave(ID, AvatarURL: String);
var AvatarURLOrig: String;
    AvatarFileName: WideString;
    hContact: THandle;
    pai: TPROTO_AVATAR_INFORMATION;
    bAvatarDownloaded: Boolean;

begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) Getting avatar for id '+ ID));

  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... avatar url: '+ AvatarURL));
  hContact := GetContactByID(StrToInt(ID));

  // GAP: if only small avatar is used by contact, then plugin will not find it -
  //      picture with prefix b_ will not exist
  AvatarURLOrig := AvatarURL;
  AvatarURL := StringReplace(AvatarURL, '/c_', '/b_', [rfIgnoreCase]);
  AvatarURL := StringReplace(AvatarURL, '/a_', '/b_', [rfIgnoreCase]);

  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... verifying whether avatar is changed or file is deleted'));

  if (DBReadString(hContact, 'ContactPhoto', 'AvatarURL', nil) <> AvatarURL) or
  (not FileExists(DBReadUnicode(hContact, 'ContactPhoto', 'File', nil))) then
  begin
    AvatarFileName := FolderAvatars + '\' + ID + '.jpg';
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... downloading avatar'));

    bAvatarDownloaded := False;
    if HTTP_NL_GetPicture(AvatarURL, AvatarFileName) then // small avatar
    begin
      // write Avatar URL to DB
      DBWriteContactSettingString(hContact, 'ContactPhoto', 'AvatarURL', PChar(AvatarURL));
      bAvatarDownloaded := True;
    end
    else
      if HTTP_NL_GetPicture(AvatarURLOrig, AvatarFileName) then // big avatar
      begin
        // write Avatar URL to DB
        DBWriteContactSettingString(hContact, 'ContactPhoto', 'AvatarURL', PChar(AvatarURLOrig));
        bAvatarDownloaded := True;
      end;
    if bAvatarDownloaded then // downloaded successfully
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... avatar downloaded successfully and saved to '+ String(AvatarFileName)));
      // write Avatar File Name to DB
      // DBWriteContactSettingString(hContact, 'ContactPhoto', 'File', PChar(AvatarFileName));
      // DBWriteContactSettingString(hContact, 'ContactPhoto', 'RFile', PChar(piShortName + '\' + ID + '.jpg'));
      //
      FillChar(pai, sizeof(pai), 0);
      pai.cbSize := sizeof(pai);
      pai.hContact := hContact;
      pai.format := PA_FORMAT_JPEG; // vkontakte supports the following formats: JPG, GIF, PNG, TIF and BMP
      SetLength(AvatarFileName, (MAX_PATH)-1);
      // BUG: if user chosen too big picture, Miranda resizes it automatically
      //      in result original filename is changed and next function doesn't work
      Move(AvatarFileName[1],pai.filename[0], Length(AvatarFileName));
      // inform Miranda about our readiness
      ProtoBroadcastAck(piShortName, hContact, ACKTYPE_AVATAR, ACKRESULT_SUCCESS, THandle(@pai), 0);
    end;

  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... finished getting of avatar'));
end;

// =============================================================================
// procedure to get avatars for all contacts
// -----------------------------------------------------------------------------
procedure vk_AvatarsGet();
var HTML: String;
    ID, AvatarURL: String;
    intID: Integer;
begin
  HTML := HTTP_NL_Get(vk_url_friends_all);
  If Trim(HTML) <> '' Then
  begin

    HTML := TextBetween(HTML, 'list:[', ']]');
    while Pos('[', HTML)>0 do
    begin
      // list:[[123456, {f:'Мария', l:'Фамилия'},{p:'http://cs1058.vkontakte.ru/u123456/b_cf123456.jpg',uy:'07',uf:9302,fg:1,to:'Марии',r:74,f:0,u:326}],
      // [789012, {f:'Олег', l:'Фамилия'},{p:'http://cs1082.vkontakte.ru/u789012/b_7898dc4d.jpg',uy:'05',uf:9302,fg:1,to:'Олега',r:67,f:0,u:326}],
      // [345678, {f:'Андрей', l:'Фамилия'},{p:'http://cs13.vkontakte.ru/u345678/b_dc0124a.jpg',uy:'05',uf:1811,fg:1,to:'Андрея',r:72,f:0,u:326}],
      // [901234, {f:'Юлия', l:'Фамилия'},{p:'http://cs118.vkontakte.ru/u901234/b_49bee611.jpg',uy:'07',uf:9302,fg:1,to:'Юлии',r:66,f:0,u:326}],
      // ...
      // [5678901, {f:'Эльвира', l:'Фамилия'},{p:'http://cs1366.vkontakte.ru/u5678901/b_34567c4e.jpg',uy:'09',uf:1421,fg:1,to:'Эльвиры',r:72,f:0,u:326}]],
      ID := TextBetween(HTML, '[', ',');
      AvatarURL := TextBetween(HTML, 'p:''', '''');
      Delete(HTML, 1, Pos(']', HTML)+2);
      if (TryStrToInt(ID, intID)) and (AvatarURL <> 'images/question_b.gif') and (Trim(AvatarURL)<>'') then
        vk_AvatarGetAndSave(ID, AvatarURL); // update avatar for each contact
    end;

  end;
end;

// =============================================================================
// procedure to setup our avatar
// -----------------------------------------------------------------------------
procedure vk_AvatarMySetup(AvatarFileName: WideString);
var AvatarFileNameNew: WideString;
    CopyResult: LongBool;
    HTML: String;
    URLUpload: String;
    AvatarFile: TFileStream;
    szData: String;
    DelPhoto, DSubm, DHash: String;
    Boundary, FileHeader, FileTrailer, szDataFinal: String;
begin
  if AvatarFileName <> '' then
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) Setting up our avatar... '));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup)  ... avatar filename: ' + String(AvatarFileName)));
    // copy file to our avatars storage
    AvatarFileNameNew := IncludeTrailingPathDelimiter(FolderAvatars) + ExtractFileName(AvatarFileName);
    CopyResult := CopyFileW(PWideChar(AvatarFileName), PWideChar(AvatarFileNameNew), false); // overwrites existing file

    if CopyResult then
    begin
      DBWriteContactSettingUnicode(0, piShortName, 'AvatarFile', PWideChar(AvatarFileNameNew));
      // now we should upload our picture to the server
      Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... uploading our avatar to the server'));
      AvatarFile := TFileStream.Create(AvatarFileNameNew, fmOpenRead);
      SetLength(szData, AvatarFile.Size);
      AvatarFile.Read(szData[1], AvatarFile.Size);
      HTML := HTTP_NL_Get(vk_url_photo_my);
      If Trim(HTML) <> '' Then
      begin
        URLUpload := TextBetween(HTML, 'form enctype="multipart/form-data" method="post" action="', '"');
        If Trim(URLUpload) <> '' Then
        begin
				  Boundary := '-----------------------------30742771025321';
				  FileHeader :=
							  '--' + Boundary +
							  #10 +
							  'Content-Disposition: form-data; name="subm"' +
							  #10 + #10 +
							  '1' +
							  #10 +
							  '--' + Boundary +
							  #10 +
							  'Content-Disposition: form-data; name="photo"; filename="310927.jpg"' +
							  #10 +
							  'Content-Type: image/jpeg' +
							  #10 + #10;
				  FileTrailer := #10 + '--' + Boundary + '--';
				  szDataFinal := FileHeader + szData + FileTrailer;
          HTML := HTTP_NL_PostPicture(URLUpload, szDataFinal, Boundary);
          If Trim(HTML) <> '' Then
            Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... finished setting up of our avatar'));
        end;
      end;
      AvatarFile.Free;
    end
    else
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... not possible to create file: '+String(AvatarFileNameNew)));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... setting up of our avatar failed'));
    end;
  end
  else // delete existing avatar
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) Deleting our avatar... '));
    DBDeleteContactSetting(0, piShortName, 'AvatarFile');
    HTML := HTTP_NL_Get(vk_url_photo_my);
    DelPhoto := TextBetween(HTML, 'delPhoto', '</form>');
    DSubm := TextBetween(DelPhoto, 'id="subm" value="', '"');
    DHash := TextBetween(DelPhoto, 'id="hash" value="', '"');
    HTML := HTTP_NL_Get(Format(vk_url_photo_my_delete, [DSubm, DHash]));
  end;
end;

// =============================================================================
// function to inform Miranda about avatar
// -----------------------------------------------------------------------------
function AvatarInfoGet(wParam: wParam; lParam: lParam): Integer; cdecl;
var pai: TPROTO_AVATAR_INFORMATION;
    AvatarFileName: String;
begin
  if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsSupport, 0) = 0 then // don't support avatars
  begin
    Result := GAIR_NOAVATAR;
    Exit;
  end;

  FillChar(pai, SizeOf(pai), 0);
  pai.cbSize := SizeOf(pai);
  pai := PPROTO_AVATAR_INFORMATION(lParam)^;
  AvatarFileName := DBReadString(pai.hContact, 'ContactPhoto', 'File', nil);
  if Trim(AvatarFileName) = '' then
  begin
    Result := GAIR_NOAVATAR;
    Exit;
  end;

  pai.format := PA_FORMAT_JPEG;
  StrCopy(pai.filename, PChar(AvatarFileName));

  Result := GAIR_SUCCESS;
end;

// =============================================================================
// function to inform Miranda about avatars support functionality
// -----------------------------------------------------------------------------
function AvatarCapsGet(wParam: wParam; lParam: lParam): Integer; cdecl;
var size: PPoint;
begin
  Case wParam Of
    AF_MAXSIZE:  // avatar image max size
      begin
        size := PPoint(lParam);
        size.X := 128;
        size.Y := 128;
        Result := 0;
      end;
    AF_PROPORTION:
      begin
        Result := PIP_NONE; // keep original proportion of avatar
      end;
    AF_FORMATSUPPORTED:
      begin
        if lParam = PA_FORMAT_JPEG then // we support JPEG only
          Result := 1
        else
          Result := 0;
      end;
    AF_ENABLED:
      begin
        // if AvatarsEnabled in settings then
          Result := 1;
        // else
        //  Result := 0;
      end;
    AF_DONTNEEDDELAYS:
      begin
        Result := 1; // this protocol doesn't need delays for fetching contact avatars
      end;
    6: // AF_MAXFILESIZE
      begin
        Result := 5242880; // max avatar size = 5 Mb
      end;
    7: // AF_DELAYAFTERFAIL
      begin
        Result := 1 * 60 * 60 * 1000; // do not request avatar again if server gave an error for one hour
      end;
    Else
      Result := 0;
  End;
end;

// =============================================================================
// function to inform Miranda about our avatar
// -----------------------------------------------------------------------------
function AvatarMyGet(wParam: wParam; lParam: lParam): Integer; cdecl;
var AvatarFileName: PWideChar;
begin
  if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsSupport, 0) = 0 then // don't support avatars
  begin
    Result := -2;
    Exit;
  end;

  if wParam=0 then
  begin
    Result := -3;
    Exit;
  end;

  AvatarFileName := DBReadUnicode(0, piShortName, 'AvatarFile', '');

  if AvatarFileName='' then
  begin
    Result := -1;
    Exit;
  end;

  lstrcpynw(PWideChar(wParam), AvatarFileName, Integer(lParam));
  Result := 0;
end;

// =============================================================================
// function to set up our avatar
// -----------------------------------------------------------------------------
function AvatarMySet(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
 AvatarMyFileName := PChar(lParam);
 if not Assigned(ThrIDAvatarMySet) then
   ThrIDAvatarMySet := TThreadAvatarMySet.Create(False); // vk_AvatarMySetup(PChar(lParam));
 Result := 0;
end;

// =============================================================================
// function to initiate avatars support
// -----------------------------------------------------------------------------
procedure AvatarsInit();
begin
  // avatar related services
  vk_hAvatarInfoGet := CreateProtoServiceFunction(piShortName, PS_GETAVATARINFO, @AvatarInfoGet);
  vk_hAvatarCapsGet := CreateProtoServiceFunction(piShortName, PS_GETAVATARCAPS, @AvatarCapsGet);
  vk_hAvatarMyGet := CreateProtoServiceFunction(piShortName, PS_GETMYAVATAR, @AvatarMyGet);
  vk_hAvatarMySet := CreateProtoServiceFunction(piShortName, PS_SETMYAVATAR, @AvatarMySet);
end;

// =============================================================================
// function to destroy avatars support
// -----------------------------------------------------------------------------
procedure AvatarsDestroy();
begin
  pluginLink^.DestroyServiceFunction(vk_hAvatarInfoGet);
  pluginLink^.DestroyServiceFunction(vk_hAvatarCapsGet);
  pluginLink^.DestroyServiceFunction(vk_hAvatarMyGet);
  pluginLink^.DestroyServiceFunction(vk_hAvatarMySet);
end;


// =============================================================================
// setup avatar thread
// -----------------------------------------------------------------------------
procedure TThreadAvatarMySet.Execute;
var ThreadNameInfo: TThreadNameInfo;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(TThreadAvatarMySet) Thread started...'));

  ThreadNameInfo.FType := $1000;
  ThreadNameInfo.FName := 'TThreadAvatarsGet';
  ThreadNameInfo.FThreadID := $FFFFFFFF;
  ThreadNameInfo.FFlags := 0;
  try
    RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
  except
  end;

  vk_AvatarMySetup(AvatarMyFileName);
  ThrIDAvatarMySet := nil;

  Netlib_Log(vk_hNetlibUser, PChar('(TThreadAvatarMySet) ... thread finished'));
end;


begin
end.
