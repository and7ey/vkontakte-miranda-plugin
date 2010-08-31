(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (c) 2009-2010 Andrey Lukyanov

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
 vk_info.pas

 [ Description ]
 Module to receive info about contacts

 [ Known Issues ]
 See the code

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_info;

interface

uses
  Windows;

  procedure InfoInit();
  procedure InfoDestroy();
  function GetInfoAllProc(): LongWord;
  function GetInfoProc(hContact: lParam): LongWord;

implementation

uses
  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used
  vk_common, // module with common functions
  vk_http, // module to connect with the site
  vk_avatars, // module to support avatars
  htmlparse, // module to simplify html parsing
  vk_core, // module with core functions
  vk_popup, // module to support popups

  uLkJSON,

  StrUtils,
  SysUtils, DateUtils;

var
  vk_hGetInfo: THandle;


// =============================================================================
// procedure to get full information about contact
// -----------------------------------------------------------------------------
procedure vk_GetInfoFull(hContact: THandle);
var HTML, HTMLCity: AnsiString;
    ContactID: DWord;
    sTemp: WideString;
    sDOB: String;
    Age: Smallint;
    DOBM, DOBD: Byte;
    DOBY: Word;

   function GetInfo(sHTML: String; sFieldName: String): Variant;
   begin
     Result := GetJSONResponseChild0(sHTML, sFieldName);
   end;


   // bType identifies type of data expected:
   // 0 - widestring (default)
   // 1 - byte
   function GetAndSaveInfo(sHTML: String; iContact: Integer; sFieldName, sParmName: String; bType: Byte = 0; sSection: String = piShortName): Boolean;
   var FeedInfo: TlkJSONobject;
       sTemp: WideString;
   begin
     Result := false;
     try
       FeedInfo := TlkJSON.ParseText(sHTML) as TlkJSONobject;
       if Assigned(FeedInfo) then
       begin
         sTemp := FeedInfo.Field['response'].Child[0].Field[sFieldName].Value;
         sTemp := Trim(HTMLDecodeW(sTemp));
         case bType of
           0: DBWriteContactSettingUnicode(iContact, PChar(sSection), PChar(sParmName), PWideChar(sTemp));
           1: DBWriteContactSettingByte(iContact, PChar(sSection), PChar(sParmName), StrToInt(sTemp));
           2: DBWriteContactSettingString(iContact, PChar(sSection), PChar(sParmName), PChar(String(sTemp)));
         end;
         Result := true;
         FeedInfo.Free;
       end;
     except
     end;
   end;

begin
 ContactID := DBGetContactSettingDWord(hContact, piShortName, 'ID', 0);
 Netlib_Log(vk_hNetlibUser, PChar('(vk_GetInfoFull) Getting information about contact '+IntToStr(ContactID)+'...'));
 HTML := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_getprofiles, [IntToStr(ContactID),'first_name,last_name,nickname,sex,birthdate,city,country,photo_medium,education,contacts,online,domain'])));
 if (Trim(HTML) = '') or (HTML = '{"response":{}}') or (Pos('error', HTML) > 0) then   // empty response is returned for non-existing contacts like News or The Wall
 else
 begin
   GetAndSaveInfo(HTML, hContact, 'first_name', 'FirstName');
   GetAndSaveInfo(HTML, hContact, 'last_name', 'LastName');
   // nick
   sTemp := GetInfo(HTML, 'nickname');
   if sTemp <> '' then
     sTemp := DBReadUnicode(hContact, piShortName, 'FirstName', '') + WideString(' ') + sTemp + WideString(' ') + DBReadUnicode(hContact, piShortName, 'LastName', '')
   else
     sTemp := DBReadUnicode(hContact, piShortName, 'FirstName', '') + WideString(' ') + DBReadUnicode(hContact, piShortName, 'LastName', '');
   DBWriteContactSettingUnicode(hContact, piShortName, 'Nick', PWideChar(sTemp));
   // gender
   sTemp := GetInfo(HTML, 'sex');
   if sTemp <> '' then
     case StrToInt(sTemp) of // replace 1 and 2 with 70 and 77 accordingly
       1: DBWriteContactSettingByte(hContact, piShortName, 'Gender', 70); // �������
       2: DBWriteContactSettingByte(hContact, piShortName, 'Gender', 77); // �������
     end;
   // birthdate
   try
     sDOB := GetInfo(HTML, 'bdate');
     if sDOB <> '' then
     begin
       DBWriteContactSettingByte(hContact, piShortName, 'BirthDay', StrToInt(Copy(sDOB,0,Pos('.',sDOB)-1)));
       if LastPos('.', sDOB) > 3 then // year exists
       begin
         DBWriteContactSettingByte(hContact, piShortName, 'BirthMonth', StrToInt(TextBetween(sDOB, '.', '.')));
         DBWriteContactSettingWord(hContact, piShortName, 'BirthYear', StrToInt(Copy(sDOB, LastPos('.', sDOB)+1, 4)));
       end else // only day and month exist
       begin
         DBWriteContactSettingByte(hContact, piShortName, 'BirthMonth', StrToInt(Copy(sDOB, Pos('.',sDOB)+1, Length(sDOB)-Pos('.',sDOB))));
         DBDeleteContactSetting(hContact, piShortName, 'BirthYear');
       end;
     end;
   except
   end;
   // calculating age
   DBDeleteContactSetting(hContact, piShortName, 'Age');
   DOBY := DBGetContactSettingWord(hContact, piShortName, 'BirthYear', 0);
   DOBM := DBGetContactSettingByte(hContact, piShortName, 'BirthMonth', 0);
   DOBD := DBGetContactSettingByte(hContact, piShortName, 'BirthDay', 0);
   if (DOBY > 0) and (DOBY < 10000) and
      (DOBM > 0) and (DOBM <= 12) and
      (DOBD > 0) and (DOBD <= 31) then
   begin
     Age := CurrentYear - DOBY;
     if (MonthOf(Now) < DOBM) or
        ((MonthOf(Now) = DOBM) and (DayOf(Now) < DOBD)) then
          Age := Age - 1;
     if Age > 0 then
       DBWriteContactSettingWord(hContact, piShortName, 'Age', Age);
   end;

   // city
   sTemp := '';
   sTemp := GetInfo(HTML, 'city');
   HTMLCity := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_getcities, [sTemp])));
   GetAndSaveInfo(HTMLCity, hContact, 'name', 'City');
   // country
   sTemp := '';
   sTemp := GetInfo(HTML, 'country');
   HTMLCity := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_getcountries, [sTemp])));
   GetAndSaveInfo(HTMLCity, hContact, 'name', 'Country');
   // education - university
   DBWriteContactSettingUnicode(hContact, piShortName, 'Affiliation0', TranslateW(usr_dtl_education));
   GetAndSaveInfo(HTML, hContact, 'university_name', 'Affiliation0Text');
   // education - faculty
   DBWriteContactSettingUnicode(hContact, piShortName, 'Affiliation1', TranslateW(usr_dtl_faculty));
   GetAndSaveInfo(HTML, hContact, 'faculty_name', 'Affiliation1Text');
   // contacts
   GetAndSaveInfo(HTML, hContact, 'mobile_phone', 'MyPhone0', 0, 'UserInfo');
   GetAndSaveInfo(HTML, hContact, 'home_phone', 'MyPhone1', 0, 'UserInfo');

   // webpage
   // depending on the setting we put here either contact's vkontakte url
   // or nothing
   DBDeleteContactSetting(hContact, piShortName, 'Homepage');
   if DBGetContactSettingByte(0, piShortName, opt_UserVKontakteURL, 0) <> 0 then
   begin
     sTemp := '';
     sTemp := GetInfo(HTML, 'domain');
     if Trim(sTemp) <> '' then
     begin
       sTemp := vk_url_prefix + vk_url_host + '/' + sTemp;
       DBWriteContactSettingString(hContact, piShortName, 'Homepage', PChar(String(sTemp)));
     end;
   end;

   // if update of avatar is required
   if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, 0) = 1 then
   begin
     sTemp := GetInfo(HTML, 'photo_medium');
     if Trim(sTemp)<>'' then
       try
         vk_AvatarGetAndSave(IntToStr(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0)), sTemp); // update avatar for a contact
       except
       end;
   end;
 end;

 // inform miranda that all data is received
 ProtoBroadcastAck(piShortName,
     hContact,
     ACKTYPE_GETINFO,
     ACKRESULT_SUCCESS,
     1,
     0);


 Netlib_Log(vk_hNetlibUser, PChar('(vk_GetInfoFull) ... getting information about contact '+IntToStr(ContactID)+' completed'));

end;

// =============================================================================
// function to react on miranda's request to get details about contact
// -----------------------------------------------------------------------------
function GetInfo(wParam: wParam; lParam: lParam): Integer; cdecl;
var res: LongWord;
    hContact: THandle;
begin
  hContact := PCCSDATA(lParam).hContact;
  CloseHandle(BeginThread(nil, 0, @GetInfoProc, Pointer(hContact), 0, res));

  Result := 0;
end;

// =============================================================================
// function to initiate get info support
// -----------------------------------------------------------------------------
procedure InfoInit();
begin
  vk_hGetInfo := CreateProtoServiceFunction(piShortName, PSS_GETINFO, GetInfo);
end;

// =============================================================================
// function to destroy get info support
// -----------------------------------------------------------------------------
procedure InfoDestroy();
begin
  pluginLink^.DestroyServiceFunction(vk_hGetInfo);
end;


// =============================================================================
// get info function - run in a separate thread
// -----------------------------------------------------------------------------
function GetInfoProc(hContact: lParam): LongWord;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(GetInfoProc) Thread started...'));

  vk_GetInfoFull(hContact);

  Result := 0;

  Netlib_Log(vk_hNetlibUser, PChar('(GetInfoProc) ... thread finished'));
end;

// =============================================================================
// get info for all contacts function - run in a separate thread
// -----------------------------------------------------------------------------
function GetInfoAllProc(): LongWord;
var hContact: THandle;
    hContactID: String;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(GetInfoAllProc) Thread started...'));

  if (vk_Status = ID_STATUS_ONLINE) or (vk_Status = ID_STATUS_INVISIBLE) Then
  begin
    hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDFIRST, 0, 0);
	  while hContact <> 0 do
    begin
      if pluginLink^.CallService(MS_PROTO_ISPROTOONCONTACT, hContact, windows.lParam(PAnsiChar(piShortName))) <> 0 Then
      begin
        hContactID := IntToStr(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0));
        Netlib_Log(vk_hNetlibUser, PChar('(GetInfoAllProc) Updating of details of contact ID ' + hContactID + ' ...'));
        vk_GetInfoFull(hContact);
        Netlib_Log(vk_hNetlibUser, PChar('(GetInfoAllProc) ... updating of details of contact ID ' + hContactID + ' finished'));
      end;
      hContact := pluginLink^.CallService(MS_DB_CONTACT_FINDNEXT, hContact, 0);
	  end;
    ShowPopupMsg(0, conf_info_update_completed, 1);
  end;
  Result := 0;

  Netlib_Log(vk_hNetlibUser, PChar('(GetInfoAllProc) ... thread finished'));
end;


begin
end.
