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
procedure vk_AvatarGetAndSave(ID: integer; AvatarURL: string);
procedure vk_AvatarsGet();

implementation

uses
  m_globaldefs,
  m_api,
  vk_global, // module with global variables and constant used
  vk_common, // module with common functions
  vk_http,   // module to connect with the site
  htmlparse, // module to simplify html parsing

  uLkJSON,

  Windows,
  SysUtils,
  Classes;

var
  vk_hAvatarInfoGet, vk_hAvatarCapsGet, vk_hAvatarMyGet, vk_hAvatarMySet: THandle;

 // =============================================================================
 // procedure to verify whether update of avatar is required,
 // and, if required, to get updated avatar
 // -----------------------------------------------------------------------------
procedure vk_AvatarGetAndSave(ID: integer; AvatarURL: string);
var
  AvatarFileName:    string;
  hContact:          THandle;
  pai:               TPROTO_AVATAR_INFORMATION;
  bAvatarDownloaded: boolean;
  bAvatarChanged:    boolean;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) Getting avatar for id ' + IntToStr(ID)));

  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... avatar url: ' + AvatarURL));
  hContact := GetContactByID(ID);

  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... verifying whether avatar is changed or file is deleted'));

  bAvatarChanged := False;

  if ID = 0 then // user's avatar
  begin
    if (DBReadString(hContact, piShortName, 'AvatarURL', nil) <> AvatarURL) or
       (not FileExists(DBReadString(hContact, piShortName, 'AvatarFile', nil))) then
          bAvatarChanged := True;
  end else // contacts' avatars
  begin
    if (DBReadString(hContact, 'ContactPhoto', 'AvatarURL', nil) <> AvatarURL) or
       (not FileExists(DBReadString(hContact, 'ContactPhoto', 'File', nil))) then
          bAvatarChanged := True;
  end;

  if bAvatarChanged then
  begin
    AvatarFileName := FolderAvatars + '\' + IntToStr(ID) + '.jpg';
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... downloading avatar'));

    bAvatarDownloaded := False;
    if HTTP_NL_GetPicture(AvatarURL, AvatarFileName) then
    begin
      // write Avatar URL to DB
      if ID = 0 then
        DBWriteContactSettingString(hContact, piShortName, 'AvatarURL', PChar(AvatarURL))
      else
        DBWriteContactSettingString(hContact, 'ContactPhoto', 'AvatarURL', PChar(AvatarURL));
      bAvatarDownloaded := True;
    end;

    if bAvatarDownloaded then // downloaded successfully
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarGetAndSave) ... avatar downloaded successfully and saved to ' + string(AvatarFileName)));
      // write Avatar File Name to DB
      // DBWriteContactSettingString(hContact, 'ContactPhoto', 'File', PChar(AvatarFileName));
      // DBWriteContactSettingString(hContact, 'ContactPhoto', 'RFile', PChar(piShortName + '\' + ID + '.jpg'));
      if ID = 0 then
        DBWriteContactSettingString(hContact, piShortName, 'AvatarFile', PChar(AvatarFileName));

      FillChar(pai, sizeof(pai), 0);
      pai.cbSize := sizeof(pai);
      pai.hContact := hContact;
      pai.format := PA_FORMAT_JPEG; // vkontakte supports the following formats: JPG, GIF, PNG, TIF and BMP
      SetLength(AvatarFileName, (MAX_PATH) - 1);
      // BUG: if user chosen too big picture, Miranda resizes it automatically
      //      in result original filename is changed and next function doesn't work
      Move(AvatarFileName[1], pai.filename[0], Length(AvatarFileName));
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
var
  HTML:          string;
  ID, AvatarURL: string;
  intID:         integer;
begin
  HTML := HTTP_NL_Post(vk_url + vk_url_feed_friends, '', 'multipart/form-data', '');
  HTML := TextBetween(HTML, 'friends'':[', ']]');
  if Trim(HTML) <> '' then
  begin
    HTML := HTML + ']';
    while Pos('[', HTML) > 0 do
    begin
      // [1234567,"Name Surname","http:\/\/cs123.vkontakte.ru\/u1234567\/b_d919d26a.jpg",9,"","Евгении",0,1,0,"05"]
      ID := TextBetween(HTML, '[', ',');
      AvatarURL := TextBetween(HTML, '","', '"');
      AvatarURL := StringReplace(AvatarURL, '\/', '/', [rfReplaceAll]);
      Delete(HTML, 1, Pos(']', HTML));
      if (TryStrToInt(ID, intID)) and (AvatarURL <> 'images/question_b.gif') and (Trim(AvatarURL) <> '') then
        vk_AvatarGetAndSave(intID, AvatarURL); // update avatar for each contact
    end;

  end;
end;

 // =============================================================================
 // procedure to setup our avatar
 // -----------------------------------------------------------------------------
procedure vk_AvatarMySetup(AvatarFileName: WideString);
var
  sHTML:                  string;
  HTML:                   string;
  URLUpload:              string;
  AvatarFile:             TFileStream;
  szData:                 string;
  DelPhoto, DSubm, DHash: string;
  Boundary, FileHeader, FileTrailer, szDataFinal: string;
  jsoFeed, jsoFeedPhoto:  TlkJSONobject;
  sServer, sPhoto, sHash,
  sPhotoHash:             string;
begin
  if AvatarFileName <> '' then
  begin
    // now we should upload our picture to the server
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... getting server details to upload an avatar'));
    sHTML := HTTP_NL_Get(GenerateApiUrl(vk_url_api_photos_getProfileUploadServer));
    if Pos('upload_url', sHTML) > 0 then
    begin
      jsoFeed := TlkJSON.ParseText(sHTML) as TlkJSONobject;
      try
        URLUpload := jsoFeed.Field['response'].Field['upload_url'].Value;
        if URLUpload <> '' then
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... uploading our avatar to the server'));
          AvatarFile := TFileStream.Create(AvatarFileName, fmOpenRead);
          SetLength(szData, AvatarFile.Size);
          AvatarFile.Read(szData[1], AvatarFile.Size);
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

          sHTML := HTTP_NL_PostPicture(URLUpload, szDataFinal, Boundary);
          if Pos('photo', sHTML) > 0 then
          begin
            jsoFeedPhoto := TlkJSON.ParseText(sHTML) as TlkJSONobject;
            try
              sServer := jsoFeedPhoto.Field['server'].Value;
              sPhoto := jsoFeedPhoto.Field['photo'].Value;
              sHash := jsoFeedPhoto.Field['hash'].Value;
              if (sServer <> '') and (sPhoto <> '') and (sHash <> '') then
              begin
                sHTML := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_photos_saveProfilePhoto, [sServer, sPhoto, sHash])));
                sPhotoHash := TextBetween(sHTML, '"photo_hash":"', '"');
                if sHTML <> '' then
                begin
                  // html parsing is below since VK API doesn't support normal avatar upload process without IE usage
                  sPhoto := UrlEncode(sPhoto);
                  sHTML := HTTP_NL_Get(Format(vk_url + vk_url_photo_load_profile, [vk_api_appid, sPhotoHash]));
                  if sHTML <> '' then
                  begin
                    sHash := TextBetween(sHTML, 'hash: ''', '''');
                    sHTML := HTTP_NL_Get(Format(vk_url + vk_url_photo_save_profile, [vk_api_appid, sServer, sPhoto, sHash]));
                    DBWriteContactSettingUnicode(0, piShortName, 'AvatarFile', PWideChar(AvatarFileName));
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... avatar defined successfully'));
                  end;
                end;
              end else
                Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... failed to get server, photo or hash details'));
            finally
              jsoFeedPhoto.Free;
            end;
          end else
            Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... failed to upload an avatar'));
          AvatarFile.Free;
        end else
          Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) ... failed to get server to upload an avatar'));
      finally
        jsoFeed.Free;
      end;
    end;
  end
  else // delete existing avatar
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySetup) Deleting our avatar... '));
    HTML := HTTP_NL_Get(vk_url + vk_url_photo_my);
    DelPhoto := TextBetween(HTML, 'delPhoto', '</form>');
    DSubm := TextBetween(DelPhoto, 'id="subm" value="', '"');
    DHash := TextBetween(DelPhoto, 'id="hash" value="', '"');
    HTML := HTTP_NL_Get(Format(vk_url + vk_url_photo_my_delete, [DSubm, DHash]));
    DBDeleteContactSetting(0, piShortName, 'AvatarFile');
    DBDeleteContactSetting(0, piShortName, 'AvatarURL');
  end;
end;

 // =============================================================================
 // function to inform Miranda about avatar
 // -----------------------------------------------------------------------------
function AvatarInfoGet(wParam: wParam; lParam: lParam): integer; cdecl;
var
  pai:            TPROTO_AVATAR_INFORMATION;
  AvatarFileName: string;
begin
  if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsSupport, 0) = 0 then // don't support avatars
  begin
    Result := GAIR_NOAVATAR;
    Exit;
  end;

  FillChar(pai, SizeOf(pai), 0);
  pai.cbSize := SizeOf(pai);
  pai := PPROTO_AVATAR_INFORMATION(lParam)^;
  if pai.hContact = 0 then
    AvatarFileName := DBReadString(pai.hContact, piShortName, 'AvatarFile', nil)
  else
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
function AvatarCapsGet(wParam: wParam; lParam: lParam): integer; cdecl;
var
  size: PPoint;
begin
  case wParam of
    AF_MAXSIZE:  // avatar image max size
    begin
      size := PPoint(lParam);
      size.X := 200;
      size.Y := 200;
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
    else
      Result := 0;
  end;
end;

 // =============================================================================
 // function to inform Miranda about our avatar
 // -----------------------------------------------------------------------------
function AvatarMyGet(wParam: wParam; lParam: lParam): integer; cdecl;
var
  AvatarFileName: PChar;
begin
  if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsSupport, 0) = 0 then // don't support avatars
  begin
    Result := -2;
    Exit;
  end;

  if wParam = 0 then
  begin
    Result := -3;
    Exit;
  end;

  AvatarFileName := DBReadString(0, piShortName, 'AvatarFile', '');

  if AvatarFileName = '' then
  begin
    Result := -1;
    Exit;
  end;

  StrLCopy(PChar(wParam), AvatarFileName, integer(lParam));
  Result := 0;
end;

 // =============================================================================
 // function to set up our avatar
 // -----------------------------------------------------------------------------
function AvatarMySet(wParam: wParam; lParam: lParam): integer; cdecl;
var AvatarFileNameNew,
    AvatarMyFileName:  WideString;
    CopyResult:        longbool;
    res:               longword;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySet) Setting up our avatar... '));
  AvatarMyFileName := PChar(lParam);
  if AvatarMyFileName = '' then // delete avatar
  begin
    CloseHandle(BeginThread(nil, 0, @vk_AvatarMySetup, nil, 0, res));
  end else
  begin // set up new avatar
    Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySet)  ... avatar filename: ' + string(AvatarMyFileName)));
    // copy file to our avatars storage
    AvatarFileNameNew := IncludeTrailingPathDelimiter(FolderAvatars) + ExtractFileName(AvatarMyFileName);
    CopyResult := CopyFileW(PWideChar(AvatarMyFileName), PWideChar(AvatarFileNameNew), False); // overwrites existing file

    if CopyResult then
    begin
      AvatarMyFileName := AvatarFileNameNew;
      CloseHandle(BeginThread(nil, 0, @vk_AvatarMySetup, Pointer(AvatarMyFileName), 0, res));
        // ThrIDAvatarMySet := TThreadAvatarMySet.Create(False); // vk_AvatarMySetup(PChar(lParam));
    end
    else
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySet) ... not possible to create file: ' + string(AvatarFileNameNew)));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_AvatarMySet) ... setting up of our avatar failed'));
    end;
  end;
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

begin
end.
