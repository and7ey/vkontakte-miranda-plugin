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
 vk_news.pas

 [ Description ]
 Module to receive news

 [ Known Issues ]
 None

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_news;

interface

procedure vk_GetNews();

implementation

uses
  m_globaldefs,
  m_api,
  vk_global,  // module with global variables and constant used
  vk_http,    // module to connect with the site
  vk_common,  // module with common functions
  vk_msgs,

  htmlparse, // module to simplify html parsing
  vk_core,   // module with core functions

  uLkJSON, // module to parse data from feed2.php (in JSON format)

  Windows,
  SysUtils;

type // type to keep news
  TNewsRecord = record
    NTime: integer;
    ID:    integer;
    NType: String;       // add_photo = photo
                         // movie = video
                         // add_item = Заметки
                         // q = Вопросы
                         // post = Темы
                         // plus = Друзья
                         // person = Статус
                         // group = Группы
                         // event = Встречи
                         // audio = Аудио
                         // record = Личные данные
    NText: WideString;
    FirstName: WideString;
    LastName: WideString;
  end;

type
  TNewsRecords = array of TNewsRecord;

function vk_GetNewsFull(): TNewsRecords; forward;

 // =============================================================================
 // procedure to get & display news
 // -----------------------------------------------------------------------------
procedure vk_GetNews();
var
  NewsAll:        TNewsRecords;
  CurrNews:       integer;
  NewsText:       WideString;
  ContactID:      THandle;
  sIgnoreList:    string;
begin
  NewsAll := vk_GetNewsFull();

  if High(NewsAll) > -1 then // received news
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) Verifying ' + IntToStr(High(NewsAll) + 1) + ' received news...'));
    try
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... last news received, date and time: '+FormatDateTime('dd/mm/yyyy, hh:nn:ss', UnixToDateTime(DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 0)))));
    except
    end;
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... current local date and time: ' + FormatDateTime('dd/mm/yyyy, hh:nn:ss', Now)));
    for CurrNews := High(NewsAll) downto 0 do
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... checking news ' + IntToStr(CurrNews + 1) + ' (of ' + IntToStr(High(NewsAll) + 1) + ')...'));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... news ' + IntToStr(CurrNews + 1) + ', date and time: ' + FormatDateTime('dd/mm/yyyy, hh:nn:ss', UnixToDateTime(NewsAll[CurrNews].NTime))));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... last news date and time: ' + FormatDateTime('dd/mm/yyyy, hh:nn:ss', UnixToDateTime(DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 0)))));
      sIgnoreList := DBReadString(0, piShortName, opt_NewsIgnoreFriends, '');
      sIgnoreList := StringReplace(sIgnoreList, ' ', '', [rfReplaceAll]);
      sIgnoreList := StringReplace(sIgnoreList, ';', ',', [rfReplaceAll]);
      sIgnoreList := ',' + sIgnoreList + ',';
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... ignore list: ' + sIgnoreList));
      // validate date & time of message (if never was shown before)
      // and contact is not added to the ignore list
      if (NewsAll[CurrNews].NTime > DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 1)) and
         (Pos(','+IntToStr(NewsAll[CurrNews].ID)+',', sIgnoreList) = 0) then
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... news ' + IntToStr(CurrNews + 1) + ' identified as not shown before'));
        // filter news, if not minimal news chosen
        NewsText := NewsAll[CurrNews].NText;

        if DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0) = 1 then
        begin // display news in a separate contact
          // add person's name
          NewsText := NewsAll[CurrNews].FirstName + ' ' +
                      NewsAll[CurrNews].LastName + ' ' +
                      NewsText;
          ContactID := vk_AddFriend(DBGetContactSettingDWord(0, piShortName, opt_NewsSeparateContactID, 1234567890), // separate contact ID, 1234567890 by default
            DBReadUnicode(0, piShortName, opt_NewsSeparateContactName, TranslateW('News')), // separate contact nick, translated 'News' by default
            ID_STATUS_OFFLINE, // status
            1);                // friend = yes
        end
        else // display news in according contact
        begin
          ContactID := GetContactById(NewsAll[CurrNews].ID);
        end;
        // display news
        vk_ReceiveMessage(ContactID, NewsText, NewsAll[CurrNews].NTime);
        if NewsAll[CurrNews].NTime > DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 0) then
          DBWriteContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, NewsAll[CurrNews].NTime);
      end;
    end;
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... verification of received news finished'));
  end;
end;

 // =============================================================================
 // procedure to get & display news
 // -----------------------------------------------------------------------------
function vk_GetNewsFull(): TNewsRecords;
var
  sHTML:              string;
  sFilters:           string;
  dwLastNewsDateTime: DWord;
  jsoFeed: TlkJSONobject;
  iNewsCount: integer;
  sNewsType: string;
  i, ii, iii: integer;
  iSourceId: integer;
  sNewsText: WideString;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) Receiving news...'));

  SetLength(Result, 0);

  // filtering news
  sFilters := '';
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterPhotos, 1) = 1 then
    sFilters := sFilters + 'photo,';
  {if DBGetContactSettingByte(0, piShortName, opt_NewsFilterVideos, 1) = 1 then
    Inc(iFilter, 16);}
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterNotes, 1) = 1 then
    sFilters := sFilters + 'note,';
  {if DBGetContactSettingByte(0, piShortName, opt_NewsFilterThemes, 1) = 1 then
    Inc(iFilter, 8192);}
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterFriends, 1) = 1 then
    sFilters := sFilters + 'friend,';
  {if DBGetContactSettingByte(0, piShortName, opt_NewsFilterStatuses, 1) = 1 then
    Inc(iFilter, 32);
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterGroups, 1) = 1 then
    Inc(iFilter, 128);
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterMeetings, 1) = 1 then
    Inc(iFilter, 512);
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterAudio, 1) = 1 then
    Inc(iFilter, 32768);}
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterTags, 1) = 1 then
    sFilters := sFilters + 'photo_tag,';
  {if DBGetContactSettingByte(0, piShortName, opt_NewsFilterApps, 1) = 1 then
    Inc(iFilter, 2048);
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterGifts, 1) = 1 then
    Inc(iFilter, 16384);
  if DBGetContactSettingByte(0, piShortName, opt_NewsFilterPersonalData, 1) = 1 then
    Inc(iFilter, 131072);}

  dwLastNewsDateTime := DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 0);
  sHTML := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_newsfeed_get, ['', URLEncode(sFilters), dwLastNewsDateTime])));

  if Pos('response', sHTML) > 0 then
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) Parsing news received...'));
    jsoFeed := TlkJSON.ParseText(sHTML) as TlkJSONobject;
    try
      iNewsCount := jsoFeed.Field['response'].Field['items'].Count;
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) News received: '+IntToStr(iNewsCount)));

      for i := 0 to iNewsCount - 1 do
      begin
        iSourceId := jsoFeed.Field['response'].Field['items'].Child[i].Field['source_id'].Value;

        if iSourceId > 0 then // skip group news - they have negative id
        begin
          sNewsText := '';
          sNewsType := jsoFeed.Field['response'].Field['items'].Child[i].Field['type'].Value;

          SetLength(Result, High(Result) + 2);
          Result[High(Result)].NTime := jsoFeed.Field['response'].Field['items'].Child[i].Field['date'].Value;
          Result[High(Result)].ID := jsoFeed.Field['response'].Field['items'].Child[i].Field['source_id'].Value;

          { // not supported currently
          if sNewsType = 'post' then
          begin
          end;
          }

          if sNewsType = 'photo' then
          begin
            sNewsText := WideString(TranslateW('added')) + ' ' +
                         IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['photos'].Count - 1) + ' ' +
                         WideString(TranslateW('photo(s):')) + ' ' +
                         Chr(13) + Chr(10);
            for ii := 1 to jsoFeed.Field['response'].Field['items'].Child[i].Field['photos'].Count - 1 do
            begin
              if PluginLink^.ServiceExists(MS_IEVIEW_WINDOW) <> 0 then
                sNewsText := sNewsText +
                             '[img]' +
                             jsoFeed.Field['response'].Field['items'].Child[i].Field['photos'].Child[ii].Field['src'].Value +
                             '[/img]' +
                             Chr(13) + Chr(10);

              sNewsText := sNewsText +
                           vk_url + '/photo' +
                           IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['photos'].Child[ii].Field['owner_id'].Value) + '_' +
                           IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['photos'].Child[ii].Field['pid'].Value) +
                           Chr(13) + Chr(10) + Chr(13) + Chr(10);
            end;
          end;

          if sNewsType = 'photo_tag' then
          begin
            sNewsText := WideString(TranslateW('was tagged in')) + ' ' +
                         IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['photo_tags'].Count - 1) + ' ' +
                         WideString(TranslateW('photo(s):')) + ' ' +
                         Chr(13) + Chr(10);
            for ii := 1 to jsoFeed.Field['response'].Field['items'].Child[i].Field['photo_tags'].Count - 1 do
            begin
              if PluginLink^.ServiceExists(MS_IEVIEW_WINDOW) <> 0 then
                sNewsText := sNewsText +
                             '[img]' +
                             jsoFeed.Field['response'].Field['items'].Child[i].Field['photo_tags'].Child[ii].Field['src'].Value +
                             '[/img]' +
                             Chr(13) + Chr(10);

              sNewsText := sNewsText +
                           vk_url + '/photo' +
                           IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['photo_tags'].Child[ii].Field['owner_id'].Value) + '_' +
                           IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['photo_tags'].Child[ii].Field['pid'].Value) +
                           Chr(13) + Chr(10) + Chr(13) + Chr(10);
            end;
          end;

          if sNewsType = 'friend' then
          begin
            sNewsText := WideString(TranslateW('added')) + ' ' +
                         IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['friends'].Count - 1) + ' ';
            if jsoFeed.Field['response'].Field['items'].Child[i].Field['friends'].Count - 1 = 1 then
              sNewsText := sNewsText +
                           WideString(TranslateW('friend:')) // одного друга
            else
              sNewsText := sNewsText +
                           WideString(TranslateW('friends:')); // друзей
            sNewsText := sNewsText + ' ' +
                         Chr(13) + Chr(10);
            for ii := 1 to jsoFeed.Field['response'].Field['items'].Child[i].Field['friends'].Count - 1 do
            begin
              // getting details of friends added
              for iii := 0 to jsoFeed.Field['response'].Field['profiles'].Count - 1 do
              begin
                if jsoFeed.Field['response'].Field['items'].Child[i].Field['friends'].Child[ii].Field['uid'].Value = jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['uid'].Value then
                begin
                  if PluginLink^.ServiceExists(MS_IEVIEW_WINDOW) <> 0 then
                    sNewsText := sNewsText +
                                 '[img]' +
                                 jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['photo'].Value +
                                 '[/img]' +
                                 Chr(13) + Chr(10);
                  sNewsText := sNewsText +
                               jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['first_name'].Value + ' ' +
                               jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['last_name'].Value + ' ' +
                               Chr(13) + Chr(10) +
                               vk_url + '/id' +
                               IntToStr(jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['uid'].Value) +
                               Chr(13) + Chr(10) + Chr(13) + Chr(10);
                  break;
                end;
              end;
            end;
          end;

          if sNewsType = 'note' then
          begin
            sNewsText := WideString(TranslateW('added')) + ' ' +
                         IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['notes'].Count - 1) + ' ';
            case jsoFeed.Field['response'].Field['items'].Child[i].Field['notes'].Count - 1 of
              1:    sNewsText := sNewsText + WideString(TranslateW('note:'));
              2..4: sNewsText := sNewsText + WideString(TranslateW('notes:'));
              else
                    sNewsText := sNewsText + WideString(TranslateW('notes: '));
            end;
            sNewsText := sNewsText + ' ' +
                         Chr(13) + Chr(10);
            for ii := 1 to jsoFeed.Field['response'].Field['items'].Child[i].Field['notes'].Count - 1 do
            begin
              sNewsText := sNewsText + ' ' +
                           jsoFeed.Field['response'].Field['items'].Child[i].Field['notes'].Child[ii].Field['title'].Value + ' (' +
                           vk_url + '/note' +
                           IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['notes'].Child[ii].Field['owner_id'].Value) + '_' +
                           IntToStr(jsoFeed.Field['response'].Field['items'].Child[i].Field['notes'].Child[ii].Field['nid'].Value) + ') ' +
                           Chr(13) + Chr(10);
            end;
          end;


          Result[High(Result)].NText := sNewsText;

          // getting details of user news belongs to
          for iii := 0 to jsoFeed.Field['response'].Field['profiles'].Count - 1 do
          begin
            if Result[High(Result)].ID = jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['uid'].Value then
            begin
              Result[High(Result)].FirstName := jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['first_name'].Value;
              Result[High(Result)].LastName := jsoFeed.Field['response'].Field['profiles'].Child[iii].Field['last_name'].Value;
              break;
            end;
          end;
        end;
      end;

    finally
      jsoFeed.Free;
    end;

    // DBWriteContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, NewsAll[CurrNews].NTime);
  end else
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) Failed to get news.'));
end;

begin
end.
