(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (С) 2008 Andrey Lukyanov

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

  procedure InfoInit();
  procedure InfoDestroy();

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

  StrUtils,
  Windows,
  SysUtils,
  Classes;

type
  TThreadGetInfo = class(TThread)
  private
    { Private declarations }
  protected
    procedure Execute; override;
  end;

var
  vk_hGetInfo: THandle;

  hContact_getinfo: THandle;

// =============================================================================
// procedure to get short information about contact
// -----------------------------------------------------------------------------
procedure vk_GetInfoMinimal(hContact: THandle);
var HTML: String;
    ContactFullName, ContactFirstName, ContactLastName: String;
    ContactFN: TFriendName;
    DOB: TDateTime;
    PhoneMobile, PhoneHome, Education: String;
    AvatarURL: String;

begin
  HTML := HTTP_NL_Get(Format(vk_url_pda_friend,[IntToStr(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0))]));

  ContactFullName := TextBetween(HTML,'<h3>', '</h3>');
  ContactFullName := HTMLDecode(ContactFullName);
  ContactFN := FullNameToNameSurnameNick(ContactFullName);
  ContactFirstName := ContactFN.FirstName;
  ContactLastName := ContactFN.LastName;

  DOB := RusDateToDateTime(TextBetween(HTML,'День рождения: ', '<br/>'), true);

  PhoneMobile := TextBetween(TextBetween(HTML,'Моб. тел.: ', '<br/>'),'>','<');

  PhoneHome := TextBetween(TextBetween(HTML,'Дом. тел.: ', '<br/>'),'>','<');

  Education := TextBetween(HTML,'ВУЗ: ', '<br/>');

  // if update of avatar is required
  if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, 0) = 1 then
  begin
    // <img class="pphoto" align="left" alt="фото" src="http://cs1425.vkontakte.ru/u1234567/c_44e12345.jpg"/>
    AvatarURL := TextBetweenInc(HTML,'pphoto', '/>');
    AvatarURL := TextBetween(AvatarURL,'src="', '"');
    if Trim(AvatarURL)<>'' then
      vk_AvatarGetAndSave(IntToStr(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0)), AvatarURL); // update avatar for a contact
  end;

  // write results into DB
  DBWriteContactSettingString(hContact, piShortName, 'FirstName', PChar(ContactFirstName));
  DBWriteContactSettingString(hContact, piShortName, 'LastName', PChar(ContactLastName));
  if Trim(PhoneMobile) <> '' Then
    DBWriteContactSettingString(hContact, 'UserInfo', 'MyPhone0', PChar(PhoneMobile));
  if Trim(PhoneHome) <> '' Then
    DBWriteContactSettingString(hContact, 'UserInfo', 'MyPhone1', PChar(PhoneHome));
  DBWriteContactSettingByte(hContact, piShortName, 'BirthDay', StrToInt(FormatDateTime('dd', DOB)));
  DBWriteContactSettingByte(hContact, piShortName, 'BirthMonth', StrToInt(FormatDateTime('mm', DOB)));
  DBWriteContactSettingWord(hContact, piShortName, 'BirthYear', StrToInt(FormatDateTime('yyyy', DOB)));
  if Trim(Education) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation0', PChar('Вуз'));
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation0Text', PChar(Education));
  End;

  // inform miranda that all data is received
  ProtoBroadcastAck(piShortName,
    hContact,
    ACKTYPE_GETINFO,
    ACKRESULT_SUCCESS,
    1,
    0);
end;

// =============================================================================
// procedure to get full information about contact
// -----------------------------------------------------------------------------
procedure vk_GetInfoFull(hContact: THandle);
var HTML: String;
    StrTemp, BasicInfo, ContactInfo, EduInfo, CareerInfo, PlaceInfo: String;
    ContactFN: TFriendName;
    DOB: TDateTime;
    BirthYear: Integer;
begin
  HTML := HTTP_NL_Get(Format(vk_url_friend,[DBGetContactSettingDWord(hContact, piShortName, 'ID', 0)]));

  // inform miranda that 1/4 data is received
  ProtoBroadcastAck(piShortName,
    hContact,
    ACKTYPE_GETINFO,
    ACKRESULT_SUCCESS,
    4,    // <-- count of replies to be received
    0);   // <-- current reply, starts from 0

  BasicInfo := TextBetween(HTML,'<div id="rightColumn">', 'div id="wall"');

  // name
  StrTemp := TextBetween(BasicInfo,'<div class="profileName">', '</div>');
  StrTemp := TextBetween(StrTemp,'<h2>', '</h2>');
  StrTemp := HTMLDecode(StrTemp);
  ContactFN := FullNameToNameSurnameNick(StrTemp);
  if Trim(ContactFN.FirstName) <> '' Then
    DBWriteContactSettingString(hContact, piShortName, 'FirstName', PChar(ContactFN.FirstName));
  if Trim(ContactFN.LastName) <> '' Then
    DBWriteContactSettingString(hContact, piShortName, 'LastName', PChar(ContactFN.LastName));

  // gender
  StrTemp := TextBetween(BasicInfo,'<td class="label">Пол:</td>', '</td>');
  StrTemp := TextBetween(StrTemp,'''>', '</a>');
  if StrTemp = 'мужской' then
    DBWriteContactSettingByte(hContact, piShortName, 'Gender', 77);
  if StrTemp = 'женский' then
    DBWriteContactSettingByte(hContact, piShortName, 'Gender', 70);

  // marital status
  {StrTemp := TextBetween(BasicInfo,'<td class="label">Семейное положение:</td>', '</td>');
  StrTemp := TextBetween(StrTemp,'''>', '</a>');}

  // birthday
  StrTemp := TextBetween(BasicInfo,'<td class="label">День рождения:</td>', '</td>');
  StrTemp := Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>'));
  StrTemp := HTMLRemoveTags(StrTemp);
  try
    if Trim(StrTemp) <> '' then
    begin
      if Not TryStrToInt(RightStr(StrTemp, 4), BirthYear) then
        StrTemp := StrTemp + ' 1900';
      if Length(StrTemp) = 4 then // only year is given
        DBWriteContactSettingWord(hContact, piShortName, 'BirthYear', StrToInt(StrTemp))
      else
      begin
        DOB := RusDateToDateTime(StrTemp, true);
        DBWriteContactSettingByte(hContact, piShortName, 'BirthDay', StrToInt(FormatDateTime('dd', DOB)));
        DBWriteContactSettingByte(hContact, piShortName, 'BirthMonth', StrToInt(FormatDateTime('mm', DOB)));
        if StrToInt(FormatDateTime('yyyy', DOB)) <> 1900 then
          DBWriteContactSettingWord(hContact, piShortName, 'BirthYear', StrToInt(FormatDateTime('yyyy', DOB)));
      end;
    end;
  except
  end;
  // origin city
  StrTemp := TextBetween(BasicInfo,'<td class="label">Родной город:</td>', '</td>');
  StrTemp := TextBetween(StrTemp,'''>', '</a>');
  if Trim(StrTemp) <> '' Then
    DBWriteContactSettingString(hContact, piShortName, 'OriginCity', PChar(StrTemp));

  // political
  {StrTemp := TextBetween(BasicInfo,'<td class="label">Полит. взгляды:</td>', '</td>');
  StrTemp := TextBetween(StrTemp,'''>', '</a>');}

  // religion
  {StrTemp := TextBetween(BasicInfo,'<td class="label">Религ. взгляды:</td>', '</td>');
  StrTemp := TextBetween(StrTemp,'''>', '</a>');}

  // inform miranda that 2/4 data is received
  ProtoBroadcastAck(piShortName,
    hContact,
    ACKTYPE_GETINFO,
    ACKRESULT_SUCCESS,
    4,
    1);

  ContactInfo := TextBetween(HTML,'<h4>Контактная информация', 'div id="wall"');

  // mobile phone
  StrTemp := TextBetween(ContactInfo,'<td class="label">Моб. телефон:</td>', '</td>');
  StrTemp := Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>'));
  if Trim(StrTemp) <> '' Then
    DBWriteContactSettingString(hContact, 'UserInfo', 'MyPhone0', PChar(StrTemp));

  // home phone
  StrTemp := TextBetween(ContactInfo,'<td class="label">Дом. телефон:</td>', '</td>');
  StrTemp := Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>'));
  if Trim(StrTemp) <> '' Then
    DBWriteContactSettingString(hContact, 'UserInfo', 'MyPhone1', PChar(StrTemp));

  // webpage
  // depending on the setting we put here either contact's page (read from
  // contact's page or just vkontakte's page url
  if DBGetContactSettingByte(0, piShortName, opt_UserVKontakteURL, 0) = 0 then
  begin
    StrTemp := TextBetween(ContactInfo,'<td class="label">Веб-сайт:</td>', '</td>');
    StrTemp := TextBetween(StrTemp,'''>', '</a>');
  end
  else
    StrTemp := Format(vk_url_friend,[DBGetContactSettingDWord(hContact, piShortName, 'ID', 0)]);
  if Trim(StrTemp) <> '' Then
    DBWriteContactSettingString(hContact, piShortName, 'Homepage', PChar(StrTemp));

  // business
  StrTemp := TextBetween(ContactInfo,'<td class="label">Деятельность:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest0Cat', PChar('Деятельность'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest0Text', PChar(StrTemp));
  End;

  // hobby
  StrTemp := TextBetween(ContactInfo,'<td class="label">Интересы:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest1Cat', PChar('Интересы'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest1Text', PChar(StrTemp));
  End;

  // music
  StrTemp := TextBetween(ContactInfo,'<td class="label">Любимая музыка:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest2Cat', PChar('Любимая музыка'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest2Text', PChar(StrTemp));
  End;

  // movies
  StrTemp := TextBetween(ContactInfo,'<td class="label">Любимые фильмы:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest3Cat', PChar('Любимые фильмы'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest3Text', PChar(StrTemp));
  End;

  // tv-show
  StrTemp := TextBetween(ContactInfo,'<td class="label">Любимые телешоу:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest4Cat', PChar('Любимые телешоу'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest4Text', PChar(StrTemp));
  End;

  // books
  StrTemp := TextBetween(ContactInfo,'<td class="label">Любимые книги:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest5Cat', PChar('Любимые книги'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest5Text', PChar(StrTemp));
  End;

  // games
  StrTemp := TextBetween(ContactInfo,'<td class="label">Любимые игры:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest6Cat', PChar('Любимые игры'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest6Text', PChar(StrTemp));
  End;

  // quotes
  StrTemp := TextBetween(ContactInfo,'<td class="label">Любимые цитаты:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Interest7Cat', PChar('Любимые цитаты'));
    DBWriteContactSettingString(hContact, piShortName, 'Interest7Text', PChar(StrTemp));
  End;


  // ICQ
  StrTemp := TextBetween(ContactInfo,'<td class="label">ICQ:</td>', '</td>');
  StrTemp := Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>'));
  StrTemp := HTMLRemoveTags(StrTemp);
  StrTemp := 'ICQ ' + StrTemp;
  if Trim(StrTemp) <> '' Then
    DBWriteContactSettingString(hContact, piShortName, 'About', PChar(StrTemp));

  // about
  StrTemp := TextBetween(ContactInfo,'<td class="label">О себе:</td>', '</td>');
  StrTemp := Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>'));
  StrTemp := StringReplace(StrTemp, '<br>', Chr(13) + Chr(10), [rfReplaceAll]);
  StrTemp := HTMLDecode(StrTemp);
  StrTemp := DBReadString(hContact, piShortName, 'About', '') + #13#10 + StrTemp;
  StrTemp := Trim(StrTemp);
  DBWriteContactSettingString(hContact, piShortName, 'About', PChar(StrTemp));

  // inform miranda that 3/4 data is received
  ProtoBroadcastAck(piShortName,
    hContact,
    ACKTYPE_GETINFO,
    ACKRESULT_SUCCESS,
    4,
    2);

  EduInfo := TextBetween(HTML, '<h2>Образование</h2>', 'div id="wall"');

  // higher education
  StrTemp := TextBetween(EduInfo,'<td class="label">Вуз:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation0', PChar('Вуз'));
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation0Text', PChar(StrTemp));
  End;

  StrTemp := TextBetween(EduInfo,'<td class="label">Факультет:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  StrTemp := Trim(StrTemp);
  if StrTemp <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation1', PChar('Факультет'));
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation1Text', PChar(StrTemp));
  End;

  StrTemp := TextBetween(EduInfo,'<td class="label">Кафедра:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation2', PChar('Кафедра'));
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation2Text', PChar(StrTemp));
  End;

  // college
  StrTemp := TextBetween(EduInfo,'<td class="label">Колледж:</td>', '</td>');
  StrTemp := Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>'));
  StrTemp := HTMLRemoveTags(StrTemp);
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation3', PChar('Колледж'));
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation3Text', PChar(StrTemp));
  End;

  // school
  StrTemp := TextBetween(EduInfo,'<td class="label">Школа:</td>', '</td>');
  StrTemp := Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>'));
  StrTemp := HTMLRemoveTags(StrTemp);
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
  Begin
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation4', PChar('Школа'));
    DBWriteContactSettingString(hContact, piShortName, 'Affiliation4Text', PChar(StrTemp));
  End;

  PlaceInfo := TextBetween(HTML,'div id="places"', 'div id="wall"');

  // address
  StrTemp := TextBetween(PlaceInfo,'<td class="label">Адрес:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
    DBWriteContactSettingString(hContact, piShortName, 'Street', PChar(StrTemp));

  CareerInfo := TextBetween(HTML,'div id="career"', 'div id="wall"');

  // company
  StrTemp := TextBetween(CareerInfo,'<td class="label">Место работы:</td>', '</td>');
  StrTemp := HTMLRemoveTags(Trim(TextBetween(StrTemp,'<div class="dataWrap">', '</div>')));
  StrTemp := HTMLDecode(StrTemp);
  if Trim(StrTemp) <> '' Then
    DBWriteContactSettingString(hContact, piShortName, 'Company', PChar(StrTemp));

  // if update of avatar is required
  if DBGetContactSettingByte(0, piShortName, opt_UserAvatarsUpdateWhenGetInfo, 0) = 1 then
  begin
    StrTemp := TextBetween(HTML,'div id="leftColumn"', '</div>');
    StrTemp := TextBetween(StrTemp,'SRC=', ' ');
    if Trim(StrTemp)<>'' then
      vk_AvatarGetAndSave(IntToStr(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0)), StrTemp); // update avatar for a contact
  end;


  // inform miranda that 4/4 (all!) data is received
  ProtoBroadcastAck(piShortName,
    hContact,
    ACKTYPE_GETINFO,
    ACKRESULT_SUCCESS,
    4,
    3);
end;

// =============================================================================
// function to react on miranda's request to get details about contact
// -----------------------------------------------------------------------------
function GetInfo(wParam: wParam; lParam: lParam): Integer; cdecl;
var ccs_getinfo: PCCSDATA;
begin
  ccs_getinfo := PCCSDATA(lParam);
  hContact_getinfo := ccs_getinfo.hContact;
  TThreadGetInfo.Create(False);

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
// get info thread
// -----------------------------------------------------------------------------
procedure TThreadGetInfo.Execute;
var ThreadNameInfo: TThreadNameInfo;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(TThreadGetInfo) Thread started...'));

  ThreadNameInfo.FType := $1000;
  ThreadNameInfo.FName := 'ThreadNameInfo';
  ThreadNameInfo.FThreadID := $FFFFFFFF;
  ThreadNameInfo.FFlags := 0;
  try
    RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
  except
  end;


  if (vk_Status = ID_STATUS_INVISIBLE) Then
    if MessageBox(0, PChar(qst_read_info), Translate(piShortName), MB_YESNO + MB_ICONQUESTION) = IDYES then
      vk_SetStatus(ID_STATUS_ONLINE);

  if (vk_Status = ID_STATUS_ONLINE) Then
  begin
    if DBGetContactSettingByte(0, piShortName, opt_UserGetMinInfo, 1) = 1 then
      vk_GetInfoMinimal(hContact_getinfo)
    else
      vk_GetInfoFull(hContact_getinfo);
  end
  else
  ProtoBroadcastAck(piShortName,
    hContact_getinfo,
    ACKTYPE_GETINFO,
    ACKRESULT_SUCCESS,
    1,
    0);

 Netlib_Log(vk_hNetlibUser, PChar('(TThreadGetInfo) ... thread finished'));
end;

begin
end.
