(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (c) 2008-2010 Andrey Lukyanov

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
 vk_msgs.pas

 [ Description ]
 Module to send and receive messages

 [ Known Issues ]
 None

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_msgs;

interface

procedure MsgsInit();
procedure MsgsDestroy();
procedure vk_GetMsgsFriendsEtc();
procedure vk_GetNews();
procedure vk_GetGroupsNews();
procedure vk_GetCommentsNews();
function vk_ReceiveMessage(FromID: THandle; MsgText: WideString; MsgDate: TDateTime): boolean;

implementation

uses
  m_globaldefs,
  m_api,

  vk_global,  // module with global variables and constant used
  vk_http,    // module to connect with the site
  vk_common,  // module with common functions
  vk_core,   // module with core functions
  vk_wall,    // module to work with the wall
  vk_captcha, // module to process captcha

  htmlparse, // module to simplify html parsing

  uLkJSON, // module to parse data from feed2.php (in JSON format)

  SysUtils, Windows;

  {$include api/m_folders.inc}

const
  msg_status_captcha_required = 'Security code (captcha) input is required for further processing...';
  msg_status_captcha_input    = 'Please input the captcha in the separate window';
  msg_status_failed           = 'Message sending failed (incorrect code?)';
  msg_status_captcha_failed   = 'Message sending failed. Unable to get the captcha';

type // type to keep news
  TNewsRecord = record
    NTime: TDateTime;
    ID:    integer;
    NType: string;       // add_photo = photo
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
  end;

type
  TNewsRecords = array of TNewsRecord;

type
  TNewsRecords2 = array of TNewsRecord;

type
  VK_PCCSDATA = ^VK_TCCSDATA;

  VK_TCCSDATA = record
    ccsData: TCCSDATA;
    trx_id:  integer;
  end;

var
  vk_hProtoMessageSend, vk_hProtoMessageSendW, vk_hProtoMessageReceive: THandle;

  CaptchaId, CaptchaUrl, CaptchaValue: string;

function MessageSendThread(ccs: VK_PCCSDATA): longword; forward;

 // =============================================================================
 // function to send message
// (it is called from separate thread, so minimum number of WRITE global variables is used)
// -----------------------------------------------------------------------------
function vk_SendMessage(ToID: integer; Text: WideString; sCaptcha: string = ''): integer;
  // 0 - successful
  // 1 - not successful (unknown reason)
  // 2 - msgs sent two often
var
  HTML:    string; // html content of the page received
  sText:   string;
  jsoFeed: TlkJSONobject;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) Sending new message to id ' + IntToStr(ToID) + ', message text: ' + ansistring(Text)));
  Result := 1; // Unknown error occured
  if ToID > 0 then
  begin
    sText := UTF8Encode(Text);
    sText := URLEncode(sText);
    HTML := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_messages_send, [ToID, sText]) + sCaptcha));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... sending of the message to contact ' + IntToStr(ToID) + ' done. Checking result...'));
    if Trim(HTML) <> '' then
    begin
      if Pos('error', HTML) > 0 then
        Result := GetJSONError(HTML)
      else
        Result := GetJSONResponse(HTML);
      Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... sending of the message to contact ' + IntToStr(ToID) + ' finished with result: ' + IntToStr(Result)));
      case Result of
        0..9, 100: ; // error occured
        14:          // captcha needed
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... captcha input is required, getting it...'));
          jsoFeed := TlkJSON.ParseText(HTML) as TlkJSONobject;
          try
            CaptchaId := jsoFeed.Field['error'].Field['captcha_sid'].Value;
            CaptchaUrl := jsoFeed.Field['error'].Field['captcha_img'].Value;

            CaptchaValue := ProcessCaptcha(CaptchaId, CaptchaUrl);
            if CaptchaValue = 'captcha_download_failed' then // error - can't download captcha image
              Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... unable to download captcha'))
            else // ok
            begin
              Result := vk_SendMessage(ToID, Text, '^' + Format(vk_url_api_captcha_addition, [CaptchaId, CaptchaValue]));
            end;
          finally
            jsoFeed.Free;
          end;
        end;
        else // successful
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... message sent successfully'));
        end;
      end;

    end;

  end;
end;

 // =============================================================================
 // function to add received message into Miranda's DB
 // -----------------------------------------------------------------------------
function vk_ReceiveMessage(FromID: THandle; MsgText: WideString; MsgDate: TDateTime): boolean;
var
  ccs_chain: TCCSDATA;
  pre:       TPROTORECVEVENT; // varibable required to add message to Miranda
begin
  Result := False;
  FillChar(pre, SizeOf(pre), 0);
  pre.flags := PREF_UTF;
  pre.szMessage := PChar(UTF8Encode(MsgText)); // encode msg to utf8
  pre.timestamp := DateTimeToUnix(MsgDate);
  pre.lParam := 0;
  // now we need to initiate incoming message event
  // we can add message without this event (with usage of MS_DB_EVENT_ADD directly),
  // but in this case some plugins will not able to filter message (for ex.,
  // to ignore them)
  FillChar(ccs_chain, SizeOf(ccs_chain), 0);
  ccs_chain.szProtoService := PSR_MESSAGE;  // so, ProtoMessageReceive will be called,
  ccs_chain.hContact := FromID;             // if filtering is passed
  ccs_chain.wParam := 0;
  ccs_chain.flags := PREF_UTF; // it is utf8 message
  ccs_chain.lParam := Windows.lParam(@pre);
  if PluginLink^.CallService(MS_PROTO_CHAINRECV, 0, Windows.lParam(@ccs_chain)) = 0 then // successful?
    Result := True;
end;

 // =============================================================================
 // function to receive new messages
// (it is called from separate thread, so minimum number of WRITE global variables is used)
// -----------------------------------------------------------------------------
procedure vk_GetMsgsFriendsEtc();
var
  HTML, HTMLInbox, HTMLAttachment:   string; // html content of the pages received
  MsgsCount:                         integer; // temp variable to keep number of new msgs received
  FriendsCount:                      integer; // temp variable to keep number of new authorization requests received
  MsgID:                             string;
  iMsgID:                            integer;
  iLevel:                            integer;
  MsgText, MsgTitle, MsgAttachment:  WideString;
  MsgSenderName:                     WideString;
  i, ii, temppos:                    integer;
  iMsgDate:                          integer;
  MsgDate:                           TDateTime;
  MsgSender:                         integer;
  ccs_chain:                         TCCSDATA;
  pCurBlob:                          PChar;
  TempFriend:                        integer; // id of temp contact if msg received from unknown contact
  pre:                               TPROTORECVEVENT; // varibable required to add message to Miranda
  FeedRoot, FeedMsgs, FeedMsgsItems: TlkJSONobject; // objects to keep parsed JSON data
  FeedMRoot, FeedProfile:            TlkJSONobject; // objects to keep messages received in JSON format
  jsoFeedAttachment:                 TlkJSONobject;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) Checking for new incoming messages, new authorization requests (friends) etc...'));

  // check for presence of new messages, friends etc. via the feed
  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_feed2);

  // correct json text
  for i := 1 to length(HTML) - 2 do // don't check first and last symbols
  begin
    if HTML[i] = '{' then
      if (HTML[i + 1] <> '"') and (HTML[i - 1] = ':') then
        Insert('"', HTML, i + 1);

    if (HTML[i] = ',') then
      if (HTML[i + 1] <> '"') and (HTML[i - 1] = '"') then
        Insert('"', HTML, i + 1);

    if (HTML[i] = ':') and (HTML[i + 1] = '"') then
      if HTML[i - 1] <> '"' then
        Insert('"', HTML, i);
  end;

  if Trim(HTML) <> '' then
  begin
    // to support Russian characters, we need to utf8 encode html text
    FeedRoot := TlkJSON.ParseText(Utf8Encode(HTML)) as TlkJSONobject;
    if Assigned(FeedRoot) then
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking messages count'));
      FeedMsgs := FeedRoot.Field['messages'] as TlkJSONobject;
      if Assigned(FeedMsgs) then
        MsgsCount := FeedMsgs.getInt('count')
      else
        MsgsCount := 0;

      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... ' + IntToStr(MsgsCount) + ' message(s) received'));

      if MsgsCount > 0 then // got new messages!
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... getting message(s) details'));

        HTMLInbox := HTTP_NL_Get(GenerateApiUrl(vk_url_api_messages_get));
        if Trim(HTMLInbox) <> '' then
        begin
          FeedMRoot := TlkJSON.ParseText(HTMLInbox) as TlkJSONobject;
          if Assigned(FeedMRoot) then
          begin
            try
              MsgsCount := FeedMRoot.Field['response'].Count; // to be on the safe side, read messages count from the data downloaded
              for i := MsgsCount - 1 downto 1 do
              begin
                Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... processing message ' + IntToStr(i)));
                iMsgID := FeedMRoot.Field['response'].Child[i].Field['mid'].Value;
                iMsgDate := FeedMRoot.Field['response'].Child[i].Field['date'].Value;
                MsgDate := UnixToDateTime(iMsgDate);
                MsgSender := FeedMRoot.Field['response'].Child[i].Field['uid'].Value;
                Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), from id: ' + IntToStr(MsgSender) + ', sent on ' + IntToStr(iMsgDate)));
                MsgText := FeedMRoot.Field['response'].Child[i].Field['body'].Value;
                MsgTitle := FeedMRoot.Field['response'].Child[i].Field['title'].Value;
                Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), title: ' + string(MsgTitle) + ', text ' + string(MsgText)));
                iLevel := 2;
                if Pos('attachments', GenerateReadableText(FeedMRoot.Field['response'].Child[i], iLevel)) > 0 then
                begin
                  if Trim(MsgText) <> '' then
                    MsgText := MsgText + Chr(13) + Chr(10) + Chr(13) + Chr(10);
                  // only 1 attachment can be now
                  // for ia := 0 to FeedMRoot.Field['response'].Child[i].Field['attachments'].Count-1 do
                  MsgAttachment := FeedMRoot.Field['response'].Child[i].Field['attachments'].Child[0].Value;
                  if Pos('audio', MsgAttachment) > 0 then // audio is attached to the message
                  begin
                    MsgAttachment := TextBetween(MsgAttachment, '[[audio', ']]');
                    HTMLAttachment := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_audio_getbyid, [MsgAttachment])));
                    jsoFeedAttachment := TlkJSON.ParseText(HTMLAttachment) as TlkJSONobject;
                    try
                      MsgText := MsgText +
                        TranslateW('audio') + ': ' +
                        jsoFeedAttachment.Field['response'].Child[0].Field['artist'].Value + ' - ' +
                        jsoFeedAttachment.Field['response'].Child[0].Field['title'].Value + Chr(13) + Chr(10) +
                        jsoFeedAttachment.Field['response'].Child[0].Field['url'].Value;
                    finally
                      jsoFeedAttachment.Free;
                    end;
                  end
                  else
                    if Pos('photo', MsgAttachment) > 0 then // photo is attached to the message
                    begin
                      MsgAttachment := TextBetween(MsgAttachment, '[[photo', ']]');
                      HTMLAttachment := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_photos_getbyid, [MsgAttachment])));
                      jsoFeedAttachment := TlkJSON.ParseText(HTMLAttachment) as TlkJSONobject;
                      try
                        MsgText := MsgText +
                          TranslateW('photo') + ': ' + Chr(13) + Chr(10) +
                          jsoFeedAttachment.Field['response'].Child[0].Field['src'].Value;
                      finally
                        jsoFeedAttachment.Free;
                      end;
                    end
                    else
                      if Pos('video', MsgAttachment) > 0 then // video is attached to the message
                      begin
                        MsgAttachment := TextBetween(MsgAttachment, '[[video', ']]');
                        HTMLAttachment := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_video_get, [MsgAttachment])));
                        jsoFeedAttachment := TlkJSON.ParseText(HTMLAttachment) as TlkJSONobject;
                        try
                          MsgText := MsgText +
                            TranslateW('video') + ': ' +
                            jsoFeedAttachment.Field['response'].Child[1].Field['title'].Value + Chr(13) + Chr(10) +
                            jsoFeedAttachment.Field['response'].Child[1].Field['description'].Value + Chr(13) + Chr(10) +
                            vk_url_prefix + vk_url_host + '/video' +
                            MsgAttachment;
                        finally
                          jsoFeedAttachment.Free;
                        end;
                      end;
                end;

                if (iMsgID > 0) and (iMsgDate > 0) and (MsgSender > 0) and (MsgText <> '') then
                begin
                  // remove empty subject, if user would like to
                  if DBGetContactSettingByte(0, piShortName, opt_UserRemoveEmptySubj, 1) = 1 then
                  begin
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), removing empty subject'));
                    MsgTitle := StringReplaceW(MsgTitle, 'Re:  ...', '', []);
                    MsgTitle := StringReplaceW(MsgTitle, ' ... ', '', []);
                    if Length(MsgTitle) > 4 then
                      if (MsgTitle[1] = 'R') and (MsgTitle[2] = 'e') and (MsgTitle[3] = '(') then
                      begin
                        ii := 4;
                        while (MsgTitle[ii] in [widechar('0')..widechar('9')]) and (ii <= Length(MsgTitle) - 1) do
                          Inc(ii);
                        temppos := PosEx('):  ...', MsgTitle);
                        if (temppos = ii) then
                          Delete(MsgTitle, 1, temppos + 6);
                      end;
                  end;
                  if Trim(MsgTitle) <> '' then
                    MsgText := MsgTitle + ': <br><br>' + MsgText;
                  MsgText := StringReplaceW(MsgText, '<br>', Chr(13) + Chr(10), [rfReplaceAll, rfIgnoreCase]);
                  MsgText := HTMLDecodeW(MsgText);
                  MsgText := Trim(MsgText);
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), re-formatted text: ' + string(MsgText)));

                  // if message from unknown contact then
                  // we add contact to our list temporary
                  TempFriend := GetContactByID(MsgSender);
                  if TempFriend = 0 then
                  begin
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + ') received from unknown contact, adding him/her to the contact list temporarily'));
                    // add sender to our contact list
                    // now we don't read user's status, so it is added as offline - field online doesn't work in VK API

                    // getting MsgSenderName
                    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), getting name of unknown contact...'));
                    HTMLInbox := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_getprofiles, [IntToStr(MsgSender), 'first_name,last_name,nickname,sex,online'])));
                    if Pos('error', HTMLInbox) > 0 then
                    begin
                      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), unable to get name, error code: ' + IntToStr(GetJSONError(HTMLInbox))));
                      MsgSenderName := 'id' + IntToStr(MsgSender); // define name with id instead
                    end
                    else
                    begin
                      // TODO: verify if it works properly with unicode symbols
                      HTMLInbox := HTMLDecodeW(HTMLInbox);
                      FeedProfile := TlkJSON.ParseText(HTMLInbox) as TlkJSONobject;
                      try
                        MsgSenderName := FeedProfile.Field['response'].Child[0].Field['first_name'].Value + ' ' + FeedProfile.Field['response'].Child[0].Field['last_name'].Value;
                      finally
                        FeedProfile.Free;
                      end;
                    end;

                    TempFriend := vk_AddFriend(MsgSender, MsgSenderName, ID_STATUS_OFFLINE, 0);
                    // and make it as temporary contact
                    DBWriteContactSettingByte(TempFriend, 'CList', 'NotOnList', 1);
                    DBWriteContactSettingByte(TempFriend, 'CList', 'Hidden', 1);
                  end; // if temp friend end
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), adding to miranda database'));
                  // everything seems to be OK, may add this message to Miranda DB
                  if vk_ReceiveMessage(TempFriend, MsgText, MsgDate) = True then // true - if message added successfully
                  begin
                    // mark message as read on the site
                    // GAP: Result is not validated
                    HTMLInbox := HTTP_NL_Get(GenerateApiUrl(Format(vk_url_api_messages_markasread, [IntToStr(iMsgID)])));
                  end;

                end
                else
                  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i) + '(' + IntToStr(iMsgID) + '), error in parsing, skipped'));
              end;
            finally
              FeedMRoot.Free;
            end;
          end;
        end;

      end; // receiving of new messages completed
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking for new incoming messages finished'));

      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking new authorization requests count'));
      FeedMsgs := FeedRoot.Field['friends'] as TlkJSONobject;
      if Assigned(FeedMsgs) then
        FriendsCount := FeedMsgs.getInt('count')
      else
        FriendsCount := 0;
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... ' + IntToStr(MsgsCount) + ' new authorization request(s) received'));
      if FriendsCount > 0 then // got new authorization request(s)!
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... getting new authorization request(s) details'));
        FeedMsgsItems := FeedMsgs.Field['items'] as TlkJSONobject;
        for i := 0 to FriendsCount - 1 do // now processing all authorization requests one-by-one
        begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i + 1) + ', getting id and name'));
          MsgID := FeedMsgsItems.NameOf[i];
          MsgSenderName := HTMLDecodeW(FeedMsgsItems.getWideString(i));
          // {"user":{"id":123456},"friends":{"count":2,"items":{"1234567":"Петр &#9793; Ф-Ф &#9793; Владимиров","26322232":"Даниил Петров"}},"messages":{"count":0},"events":{"count":0},"groups":{"count":0},"photos":{"count":0},"videos":{"count":0},"notes":{"count":0},"opinions":{"count":0},"questions":{"count":0},"gifts":{"count":0},"lang":{"id":"0","p_id":0},"activity":{"updated":0}}
          Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i + 1) + ', from id: ' + MsgID));
          Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i + 1) + ', from person: ' + string(MsgSenderName)));
          if (Trim(MsgID) <> '') and (TryStrToInt(MsgID, MsgSender)) {and (Trim(MsgSenderName)<>'')} then
          begin
            // everything seems to be OK, may proceed
            // temporary add contact if required
            TempFriend := GetContactByID(MsgSender);
            if TempFriend = 0 then
            begin
              Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... temporary add contact to our list'));
              // add sender to our contact list
              // now we don't read user's status, so it is added as offline
              TempFriend := vk_AddFriend(MsgSender, MsgSenderName, ID_STATUS_OFFLINE, 0);
              // and make it as temporary contact
              DBWriteContactSettingByte(TempFriend, 'CList', 'NotOnList', 1);
              DBWriteContactSettingByte(TempFriend, 'CList', 'Hidden', 1);
            end;

            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i + 1) + ', adding to miranda database'));

            FillChar(pre, SizeOf(pre), 0);
            pre.flags := PREF_UTF;
            MsgDate := Now;
            pre.timestamp := DateTimeToUnix(MsgDate);

            // GAP(?): use AnsiStrings below, as unicode not supported
            //blob is: uin( DWORD ), hContact( HANDLE ), nick( ASCIIZ ), first( ASCIIZ ), last( ASCIIZ ), email( ASCIIZ ), reason( ASCIIZ )
            MsgText := '(text of authorization request is not supported currently)';
            pre.lParam := sizeof(DWORD) + sizeof(THANDLE) + Length(ansistring(MsgSenderName)) + Length(MsgID) + Length(ansistring(MsgText)) + 8;
            pCurBlob := AllocMem(pre.lParam);
            pre.szMessage := PChar(pCurBlob);
            PDWORD(pCurBlob)^ := 0;
            Inc(pCurBlob, sizeof(DWORD));
            PHANDLE(pCurBlob)^ := TempFriend;
            Inc(pCurBlob, sizeof(THANDLE));
            StrCopy(pCurBlob, PChar(ansistring(MsgSenderName)));
            // lstrcpyw(pCurBlob, PWideChar(MsgSenderName));
            Inc(pCurBlob, Length(ansistring(MsgSenderName)) + 1);
            pCurBlob^ := #0;            //firstName
            Inc(pCurBlob);
            pCurBlob^ := #0;            //lastName
            Inc(pCurBlob);
            pCurBlob^ := #0;            //e-mail
            Inc(pCurBlob);
            StrCopy(pCurBlob, PChar(ansistring(MsgText))); //reason
            // lstrcpyw(pCurBlob, PWideChar(MsgText));

            FillChar(ccs_chain, SizeOf(ccs_chain), 0);
            ccs_chain.szProtoService := PSR_AUTH; // so, AuthRequestReceived will be called,
            ccs_chain.hContact := TempFriend;     // if filtering is passed
            ccs_chain.wParam := 0;
            ccs_chain.flags := 0;
            ccs_chain.lParam := Windows.lParam(@pre);
            PluginLink^.CallService(MS_PROTO_CHAINRECV, 0, Windows.lParam(@ccs_chain));
          end;
        end;
      end;

      FeedRoot.Free;

    end;
  end;

  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking for new authorization requests finished'));

end;

 // =============================================================================
 // function to send message
 // -----------------------------------------------------------------------------
function ProtoMessageSend(wParam: wParam; lParam: lParam): integer; cdecl;
var
  ccs: VK_PCCSDATA;
  res: longword;
begin
  New(ccs);
  ccs^.ccsData := PCCSDATA(lParam)^;
  ccs^.trx_id := StrToInt(FormatDateTime('nnsszzz', Now)); // generate trx (message) number

  Netlib_Log(vk_hNetlibUser, PChar('(ProtoMessageSend) Sending message, text: ' + PWideChar(ccs^.ccsData.lParam + lstrlen(PChar(ccs^.ccsData.lParam)) + 1)));

  SleepEx(10, True);

  // call separate thread to send the msg
  CloseHandle(BeginThread(nil, 0, @MessageSendThread, ccs, 0, res));

  // return the transaction id we've assigned to the trx
  Result := ccs^.trx_id;
end;


 // =============================================================================
 // function to receive messages
 // -----------------------------------------------------------------------------
function ProtoMessageReceive(wParam: wParam; lParam: lParam): integer; cdecl;
var
  ccs_sm: PCCSDATA;
  dbeo:   TDBEVENTINFO; // varibable required to add message to Miranda
  pre:    TPROTORECVEVENT;
begin

  ccs_sm := PCCSDATA(lParam);
  pre := PPROTORECVEVENT(ccs_sm.lParam)^;

  FillChar(dbeo, SizeOf(dbeo), 0);
  with dbeo do
  begin
    cbSize := SizeOf(dbeo);
    eventType := EVENTTYPE_MESSAGE;        // message
    szModule := piShortName;
    pBlob := PByte(pre.szMessage);       // data
    cbBlob := Length(pre.szMessage) + 1; // SizeOf(pBlob);
    flags := DBEF_UTF;
    timestamp := pre.timestamp;
  end;
  PluginLink^.CallService(MS_DB_EVENT_ADD, ccs_sm.hContact, dword(@dbeo));

  Result := 0;
end;


 // =============================================================================
 // function to initiate support of messages sending and receiving
 // -----------------------------------------------------------------------------
procedure MsgsInit();
begin
  vk_hProtoMessageSend := CreateProtoServiceFunction(piShortName, PSS_MESSAGE, ProtoMessageSend);
  vk_hProtoMessageSendW := CreateProtoServiceFunction(piShortName, PSS_MESSAGEW, ProtoMessageSend);
  vk_hProtoMessageReceive := CreateProtoServiceFunction(piShortName, PSR_MESSAGE, ProtoMessageReceive);
  // no need to support PSR_MESSAGEW - it is not used by new versions of Miranda
  // vk_hProtoMessageReceive := CreateProtoServiceFunction(piShortName, PSR_MESSAGEW, ProtoMessageReceive);
end;

 // =============================================================================
 // function to destroy support of messages sending and receiving
 // -----------------------------------------------------------------------------
procedure MsgsDestroy();
begin
  pluginLink^.DestroyServiceFunction(vk_hProtoMessageSend);
  pluginLink^.DestroyServiceFunction(vk_hProtoMessageSendW);
  pluginLink^.DestroyServiceFunction(vk_hProtoMessageReceive);
end;


 // =============================================================================
 // thread to send message
 // -----------------------------------------------------------------------------
function MessageSendThread(ccs: VK_PCCSDATA): longword;
var
  trx_id:            integer;
  hContact:          THandle;
  MsgText:           WideString;
  ResultTemp:        TResultDetailed;
  iResult:           integer;
  bPostingOnTheWall: boolean;
  sWord:             WideString;
  iWordLength:       byte;
begin
  Result := 0;

  Netlib_Log(vk_hNetlibUser, PChar('(MessageSendThread) Thread started...'));

  trx_id := ccs^.trx_id;
  hContact := ccs^.ccsData.hContact;
  if (ccs^.ccsData.wParam and PREF_UTF) <> 0 then
    MsgText := PChar(ccs^.ccsData.lParam) // GAP: not checked
  else
    if (ccs^.ccsData.wParam and PREF_UNICODE) <> 0 then
      MsgText := PWideChar(ccs^.ccsData.lParam + lstrlen(PChar(ccs^.ccsData.lParam)) + 1)
    else
      MsgText := PChar(ccs^.ccsData.lParam); // GAP: not checked
  Dispose(ccs);

  if vk_Status = ID_STATUS_OFFLINE then // if offline - send failed ack
  begin
    ProtoBroadcastAck(piShortName, hContact, ACKTYPE_MESSAGE, ACKRESULT_FAILED, THandle(trx_id), Windows.lParam(Translate(err_sendmgs_offline)));
    Exit;
  end;

  // verifying if the message should be posted on the wall
  // (in this case it should be started with 'wall:' (or user defined value) or
  // with translated equivalent
  bPostingOnTheWall := False;
  sWord := DBReadUnicode(0, piShortName, opt_WallMessagesWord, 'wall:');
  iWordLength := Length(TranslateW(PWideChar(sWord))) - 1;
  if (Copy(MsgText, 0, iWordLength) = TranslateW(PWideChar(sWord))) then
    bPostingOnTheWall := True
  else
  begin
    iWordLength := Length(sWord);
    if (Copy(MsgText, 0, iWordLength) = sWord) then
      bPostingOnTheWall := True;
  end;

  if bPostingOnTheWall then
  begin // posting message on the wall
    MsgText := Copy(MsgText, iWordLength + 1, Length(MsgText) - iWordLength);
    ResultTemp := vk_WallPostMessage(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0),
      Trim(MsgText),
      0);
    case ResultTemp.Code of
      0: // 0 - successful
        ProtoBroadcastAck(piShortName, hContact, ACKTYPE_MESSAGE, ACKRESULT_SUCCESS, THandle(trx_id), 0);
      1: // 1 - failed
        ProtoBroadcastAck(piShortName, hContact, ACKTYPE_MESSAGE, ACKRESULT_FAILED, THandle(trx_id), Windows.lParam(ResultTemp.Text));
    end;
  end
  else // calling function to send normal message
  begin
    iResult := vk_SendMessage(DBGetContactSettingDWord(hContact, piShortName, 'ID', 0), MsgText);
    case iResult of
      0..10: // not successful
        ProtoBroadcastAck(piShortName, hContact, ACKTYPE_MESSAGE, ACKRESULT_FAILED, THandle(trx_id), Windows.lParam(Translate(PChar(err_messages_send[iResult]))));
      else // successful
           // the ACK contains reference (thandle) to the trx number
        ProtoBroadcastAck(piShortName, hContact, ACKTYPE_MESSAGE, ACKRESULT_SUCCESS, THandle(trx_id), 0);

    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(TThreadSendMsg) ... thread finished'));
end;


 // *****************************************************************************
 // *****************************************************************************
 // News support part
 // -----------------------------------------------------------------------------
 // -----------------------------------------------------------------------------

 // =============================================================================
 // procedure to get minimal news
 // -----------------------------------------------------------------------------
function vk_GetNewsMinimal(): TNewsRecords;
var
  NewsPosStart, DayWrapPosStart: integer;
  HTML, HTMLDay:                 string;
  nNType, nIDstr, nNTimestr:     string;
  nText:                         WideString;
  nID:                           integer;
  nNTime:                        TDateTime;
  fSettings:                     TFormatSettings;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsMinimal) Receiving minimal news...'));

  HTML := HTTP_NL_Get(vk_url_pda_news);
  HTML := UTF8Decode(HTML);

  if Trim(HTML) <> '' then
  begin
    DayWrapPosStart := Pos('stRows', HTML);
    if DayWrapPosStart > 0 then
    begin
      HTMLDay := TextBetweenTagsAttrInc(HTML, 'div', 'class', 'stRows');
      NewsPosStart := Pos('<div>', HTMLDay);
      while NewsPosStart > 0 do
      begin
        nNType := 'unknown';
        nIDstr := TextBetween(HTMLDay, 'href="/id', '">');
        nText := TextBetweenInc(HTMLDay, '<a', '<span class="stTime">');
        nText := StringReplace(nText, #10, '', [rfReplaceAll]);
        nText := StringReplace(nText, Chr(9), '', [rfReplaceAll]);
        nText := StringReplace(nText, '<br/>', ' ', [rfReplaceAll, rfIgnoreCase]);
        nText := Trim(HTMLDecodeW(nText));
        nNTimestr := TextBetweenInc(HTMLDay, '<span class="stTime">', '</span>');
        nNTimestr := Trim(HTMLRemoveTags(nNTimestr));
        GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, fSettings);
        fSettings.TimeSeparator := ':';

        if (nText <> '') and (nNType <> '') and (TryStrToInt(nIDstr, nID)) and (TryStrToTime(nNTimestr, nNTime, fSettings)) then
        begin
          // data seems to be correct
          nNTime := Date + nNTime;
          SetLength(Result, High(Result) + 2);
          Result[High(Result)].NTime := nNTime;
          Result[High(Result)].ID := nID;
          Result[High(Result)].NType := nNType;
          Result[High(Result)].NText := nText;
        end;

        Delete(HTMLDay, 1, Pos('</div>', HTMLDay) + 5);
        NewsPosStart := Pos('<div>', HTMLDay);
      end;
    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsMinimal) ... receiving minimal news finished'));
end;

 // =============================================================================
 // procedure to get full version of news
 // -----------------------------------------------------------------------------
function vk_GetNewsFull(): TNewsRecords;
var
  DayWrapPosStart, feedTablePosStart: integer;
  DayTime:          TDateTime;
  HTML, HTMLDay, HTMLNews, HTMLDate: string;
  nNType, nIDstr, nNTimestr: string;
  nText:            WideString;
  nID:              integer;
  nNTime:           TDateTime;
  ImgStart, ImgEnd: integer;
  fSettings:        TFormatSettings;
  HasNews:          boolean;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) Receiving news...'));

  // get user lang id
  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_feed2);
  vk_UserLangId := TextBetween(HTML, '"lang":{"id":"', '","p_id":');
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) LangId is: ' + vk_UserLangId));
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) LangHash is: ' + vk_UserLangHash));

  if vk_UserLangId <> '0' then // change lang to Russian for correct parsing
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) Temporary changing site lang to Russian for parsing...'));
    HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_lang_change, ['0', vk_UserLangHash]));
  end;

  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_news);

  if vk_UserLangId <> '0' then // return user default lang
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) Now getting back user default site lang...'));
    HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_lang_change, [vk_UserLangId, vk_UserLangHash]));
  end;

  if Trim(HTML) <> '' then
  begin

    HasNews := True;

    DayWrapPosStart := Pos('feedDayWrap', HTML);
    while HasNews and (DayWrapPosStart > 0) do
    begin
      HTMLDate := TextBetween(HTML, '<div class="feedDay">', '</div>');
      HTMLDate := Trim(HTMLRemoveTags(HTMLDate));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) HTMLDate: ' + HTMLDate));
      ;
      if (Pos('сегодня', HTMLDate) > 0) or (Pos('сьогодні', HTMLDate) > 0) then
        DayTime := Date
      else
        if (Pos('вчера', HTMLDate) > 0) or (Pos('вчора', HTMLDate) > 0) then
          DayTime := Date - 1
        else
          DayTime := RusDateToDateTime(HTMLDate, True);

      HTMLDay := TextBetweenTagsAttrInc(HTML, 'div', 'class', 'items_wrap');
      feedTablePosStart := Pos('<table class="feedTable', HTMLDay);
      while HasNews and (feedTablePosStart > 0) do
      begin
        HTMLNews := TextBetweenTagsInc(HTMLDay, 'table');
        // support of new icon names
        nNType := TextBetween(HTMLNews, 'images/icons/', '_s.gif?2"');
        // support of old icon names
        if nNType = '' then
          nNType := TextBetween(HTMLNews, 'images/icons/', '_icon.gif?2"');
        // support of apps icons
        if Pos('x.gif', HTMLNews) > 0 then
          nNType := 'apps';
        nIDstr := TextBetween(HTMLNews, 'href="/id', '">');
        nText := TextBetweenInc(HTMLNews, '<td class="feedStory', '</td>');
        // remove images
        ImgStart := Pos('<div class="feedFriendImg">', nText);
        while ImgStart > 0 do
        begin
          ImgEnd := PosEx('</div>', nText, ImgStart) + 6;
          Delete(nText, ImgStart, ImgEnd - ImgStart + 1);
          ImgStart := Pos('<div class="feedFriendImg">', nText);
        end;
        nText := StringReplace(nText, #10, '', [rfReplaceAll]);
        nText := StringReplace(nText, Chr(9), '', [rfReplaceAll]);
        nText := StringReplace(nText, '<br/>', ' ', [rfReplaceAll, rfIgnoreCase]);
        // remove extra spaces (when contact added more than 1 friend)
        nText := StringReplace(nText, '<div class="feedFriend">    <div class="feedFriendText">    ', '<div class="feedFriend"><div class="feedFriendText">', [rfReplaceAll]);
        nText := Trim(HTMLDecodeW(nText));
        if nNType = 'people' then
          nText := TranslateW(DBReadUnicode(0, piShortName, opt_NewsStatusWord, TranslateW('Status:'))) + WideString(' ') + nText;

        // nText := LeftStr(nText, Length(nText)-1); // remove trailing dot - doesn't work correctly when contact added more than 1 friend
        nNTimestr := TextBetweenInc(HTMLNews, '<td class="feedTime', '</td>');
        nNTimestr := Trim(HTMLRemoveTags(nNTimestr));
        GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, fSettings);
        fSettings.TimeSeparator := ':';

        if (nText <> '') and (nNType <> '') and (TryStrToInt(nIDstr, nID)) and (TryStrToTime(nNTimestr, nNTime, fSettings)) then
        begin
          // data seems to be correct
          nNTime := DayTime + nNTime;
          SetLength(Result, High(Result) + 2);
          Result[High(Result)].NTime := nNTime;
          Result[High(Result)].ID := nID;
          Result[High(Result)].NType := nNType;
          Result[High(Result)].NText := nText;
        end;

        // small optimization trick: checking if we have news or not
        if DateTimeToFileDate(nNTime) > DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 539033600) then
          HasNews := True
        else
          HasNews := False;

        feedTablePosStart := Pos('<table class="feedTable ', HTMLDay);
        Delete(HTMLDay, 1, feedTablePosStart + 1);
        feedTablePosStart := Pos('<table class="feedTable ', HTMLDay);

      end;
      DayWrapPosStart := Pos('feedDayWrap', HTML);
      Delete(HTML, 1, DayWrapPosStart + 1);
      DayWrapPosStart := Pos('feedDayWrap', HTML);
      Delete(HTML, 1, DayWrapPosStart - 1);
    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) ... receiving news finished'));
end;


 // =============================================================================
 // procedure to get & display news
 // -----------------------------------------------------------------------------
procedure vk_GetNews();
var
  NewsAll:        TNewsRecords;
  CurrNews:       integer;
  ValidNews:      boolean;
  NewsText:       WideString;
  ContactID:      THandle;
  dtDateTimeNews: TDateTime;
begin
  if DBGetContactSettingByte(0, piShortName, opt_NewsMin, 0) = 1 then
    NewsAll := vk_GetNewsMinimal()
  else
    NewsAll := vk_GetNewsFull();

  if High(NewsAll) > -1 then // received news
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) Verifying ' + IntToStr(High(NewsAll) + 1) + ' received news...'));
    // Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... last news received, date and time: '+FormatDateTime('dd-mmm-yyyy, hh:nn:ss', FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 539033600)))));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... current local date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', Now)));
    for CurrNews := 0 to High(NewsAll) do
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... checking news ' + IntToStr(CurrNews + 1) + ' (of ' + IntToStr(High(NewsAll) + 1) + ')...'));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... news ' + IntToStr(CurrNews + 1) + ', date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', NewsAll[CurrNews].NTime)));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... last news date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 539033600)))));
      // validate date & time of message (if never was shown before)
      if DateTimeToFileDate(NewsAll[CurrNews].NTime) > DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 539033600) then
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... news ' + IntToStr(CurrNews + 1) + ' identified as not shown before'));
        ValidNews := True;
        // filter news, if not minimal news chosen
        if DBGetContactSettingByte(0, piShortName, opt_NewsMin, 0) = 0 then
        begin
          if (NewsAll[CurrNews].NType = 'photos') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterPhotos, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'video') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterVideos, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'notesplus') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterNotes, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'topics') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterThemes, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'friends') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterFriends, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'people') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterStatuses, 0) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'groups') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterGroups, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'events') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterMeetings, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'audio') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterAudio, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'pages') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterPersonalData, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'tags') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterTags, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'apps') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterApps, 1) = 0) then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'gifts') and (DBGetContactSettingByte(0, piShortName, opt_NewsFilterGifts, 1) = 0) then
            ValidNews := False;
        end;
        if ValidNews then
        begin
          NewsText := NewsAll[CurrNews].NText;

          if DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0) = 1 then
          begin // display news in a separate contact
            ContactID := vk_AddFriend(DBGetContactSettingDWord(0, piShortName, opt_NewsSeparateContactID, 1234567890), // separate contact ID, 1234567890 by default
              DBReadUnicode(0, piShortName, opt_NewsSeparateContactName, TranslateW('News')), // separate contact nick, translated 'News' by default
              ID_STATUS_OFFLINE, // status
              1);                // friend = yes
          end
          else // display news in according contact
          begin
            // remove person name
            Delete(NewsText, 1, Pos('</a>', NewsText) + 4);
            ContactID := GetContactById(NewsAll[CurrNews].ID);
          end;
          // re-format news text
          if DBGetContactSettingByte(0, piShortName, opt_NewsLinks, 1) = 1 then
          begin
            NewsText := ReplaceLink(NewsText);
            NewsText := RemoveDuplicates(NewsText);
          end;
          NewsText := HTMLRemoveTags(NewsText);
          // cleanup NewsText - remove leading spaces
          while NewsText[1] = ' ' do
            Delete(NewsText, 1, 1);
          // use local time for news
          dtDateTimeNews := UnixToDateTime(DateTimeToUnix(NewsAll[CurrNews].NTime) * 2 - PluginLink.CallService(MS_DB_TIME_TIMESTAMPTOLOCAL, DateTimeToUnix(NewsAll[CurrNews].NTime), 0));
          // display news
          vk_ReceiveMessage(ContactID, NewsText, dtDateTimeNews);
        end;
      end;
    end;
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... verification of received news finished'));
    // write into DB date of last news we've received (in order to not display the same news
    // with next update)
    DBWriteContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, DateTimeToFileDate(NewsAll[0].NTime));
  end;
end;

 // =============================================================================
 // procedure to parse groups news
 // -----------------------------------------------------------------------------
function vk_ParseGroupsNews(): TNewsRecords;
var
  DayWrapPosStart, feedTablePosStart: integer;
  DayTime:   TDateTime;
  HTML, HTMLDay, HTMLNews, HTMLDate: string;
  nNType, nNTimestr: string;
  nText:     WideString;
  nID:       integer;
  nNTime:    TDateTime;
  fSettings: TFormatSettings;
  HasNews:   boolean;
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseGroupsNews) Receiving groups news...'));

  // get user lang id
  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_feed2);
  vk_UserLangId := TextBetween(HTML, '"lang":{"id":"', '","p_id":');
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseGroupsNews) LangId is: ' + vk_UserLangId));
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseGroupsNews) LangHash is: ' + vk_UserLangHash));

  if vk_UserLangId <> '0' then // change lang to Russian for correct parsing
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseGroupsNews) Temporary changing site lang to Russian for parsing...'));
    HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_lang_change, ['0', vk_UserLangHash]));
  end;

  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_news_groups);

  if vk_UserLangId <> '0' then // return user default lang
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseGroupsNews) Now getting back user default site lang...'));
    HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_lang_change, [vk_UserLangId, vk_UserLangHash]));
  end;

  if Trim(HTML) <> '' then
  begin

    HasNews := True;

    DayWrapPosStart := Pos('feedDayWrap', HTML);
    while HasNews and (DayWrapPosStart > 0) do
    begin
      HTMLDate := TextBetween(HTML, '<div class="feedDay">', '</div>');
      if Pos('сегодня', HTMLDate) > 0 then
        DayTime := Date
      else
        if Pos('вчера', HTMLDate) > 0 then
          DayTime := Date - 1
        else
          DayTime := RusDateToDateTime(HTMLDate, True);

      HTMLDay := TextBetweenTagsAttrInc(HTML, 'div', 'class', 'items_wrap');

      feedTablePosStart := Pos('<table class="feedTable', HTMLDay);
      while HasNews and (feedTablePosStart > 0) do
      begin
        HTMLNews := TextBetweenTagsInc(HTMLDay, 'table');
        nNType := TextBetween(HTMLNews, 'images/icons/', '_s.gif?2"');
        nText := TextBetweenInc(HTMLNews, '<td class="feedStory', '</td>');
        nText := StringReplace(nText, #10, '', [rfReplaceAll]);
        nText := StringReplace(nText, Chr(9), '', [rfReplaceAll]);
        nText := StringReplace(nText, '<br/>', ' ', [rfReplaceAll, rfIgnoreCase]);
        nText := Replace(nText, '<br><br>', #10#10);
        nText := Replace(nText, '<br>', #10);
        nText := Trim(HTMLDecodeW(nText));
        nNTimestr := TextBetweenInc(HTMLNews, '<td class="feedTime', '</td>');
        nNTimestr := Trim(HTMLRemoveTags(nNTimestr));
        GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, fSettings);
        fSettings.TimeSeparator := ':';

        nID := 0;

        if (nText <> '') and (nNType <> '') and (TryStrToTime(nNTimestr, nNTime, fSettings)) then
        begin
          // data seems to be correct
          nNTime := DayTime + nNTime;
          SetLength(Result, High(Result) + 2);
          Result[High(Result)].NTime := nNTime;
          Result[High(Result)].ID := nID;
          Result[High(Result)].NType := nNType;
          Result[High(Result)].NText := nText;
        end;

        // small optimization trick: checking if we have news or not
        if DateTimeToFileDate(nNTime) > DBGetContactSettingDWord(0, piShortName, opt_GroupsLastNewsDateTime, 539033600) then
          HasNews := True
        else
          HasNews := False;

        feedTablePosStart := Pos('<table class="feedTable ', HTMLDay);
        Delete(HTMLDay, 1, feedTablePosStart + 1);
        feedTablePosStart := Pos('<table class="feedTable ', HTMLDay);

      end;
      DayWrapPosStart := Pos('feedDayWrap', HTML);
      Delete(HTML, 1, DayWrapPosStart + 1);
      DayWrapPosStart := Pos('feedDayWrap', HTML);
      Delete(HTML, 1, DayWrapPosStart - 1);
    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseGroupsNews) ... receiving groups news finished'));
end;

 // =============================================================================
 // procedure to get & display groups news
 // -----------------------------------------------------------------------------
procedure vk_GetGroupsNews();
var
  NewsAll:   TNewsRecords;
  CurrNews:  integer;
  ValidNews: boolean;
  NewsText:  WideString;
  ContactID: THandle;
begin
  NewsAll := vk_ParseGroupsNews();

  if High(NewsAll) > -1 then // received news
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetGroupsNews) Verifying ' + IntToStr(High(NewsAll) + 1) + ' received groups news...'));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetGroupsNews) ... last groups news received, date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_GroupsLastNewsDateTime, 539033600)))));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetGroupsNews) ... current local date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', Now)));
    for CurrNews := 0 to High(NewsAll) do
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetGroupsNews) ... checking groups news ' + IntToStr(CurrNews + 1) + ' (of ' + IntToStr(High(NewsAll) + 1) + ')...'));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetGroupsNews) ... groups news ' + IntToStr(CurrNews + 1) + ', date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', NewsAll[CurrNews].NTime)));
      // validate date & time of message (if never was shown before)
      if DateTimeToFileDate(NewsAll[CurrNews].NTime) > DBGetContactSettingDWord(0, piShortName, opt_GroupsLastNewsDateTime, 539033600) then
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetGroupsNews) ... groups news ' + IntToStr(CurrNews + 1) + ' identified as not shown before'));

        ValidNews := True;

        if (NewsAll[CurrNews].NType = 'photos') and (DBGetContactSettingByte(0, piShortName, opt_GroupsFilterPhotos, 1) = 0) then
          ValidNews := False;
        if (NewsAll[CurrNews].NType = 'video') and (DBGetContactSettingByte(0, piShortName, opt_GroupsFilterVideos, 1) = 0) then
          ValidNews := False;
        if (NewsAll[CurrNews].NType = 'topics') and (DBGetContactSettingByte(0, piShortName, opt_GroupsFilterThemes, 1) = 0) then
          ValidNews := False;
        if (NewsAll[CurrNews].NType = 'audio') and (DBGetContactSettingByte(0, piShortName, opt_GroupsFilterAudio, 1) = 0) then
          ValidNews := False;
        if (NewsAll[CurrNews].NType = 'pages') and (DBGetContactSettingByte(0, piShortName, opt_GroupsFilterNews, 1) = 0) then
          ValidNews := False;

        if ValidNews then
        begin
          NewsText := NewsAll[CurrNews].NText;

          // display news in a separate contact
          ContactID := vk_AddFriend(DBGetContactSettingDWord(0, piShortName, opt_NewsSeparateContactID, 1234567890), // separate contact ID, 1234567890 by default
            DBReadUnicode(0, piShortName, opt_NewsSeparateContactName, TranslateW('News')), // separate contact nick, translated 'News' by default
            ID_STATUS_OFFLINE, // status
            1);                // friend = yes

          // re-format news text
          if DBGetContactSettingByte(0, piShortName, opt_GroupsLinks, 1) = 1 then
          begin
            NewsText := ReplaceLink(NewsText);
            NewsText := RemoveDuplicates(NewsText);
          end;
          NewsText := HTMLRemoveTags(NewsText);
          // cleanup NewsText - remove leading spaces
          while NewsText[1] = ' ' do
            Delete(NewsText, 1, 1);
          // display news
          vk_ReceiveMessage(ContactID, NewsText, NewsAll[CurrNews].NTime);
        end;
      end;
    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetGroupsNews) ... verification of received groups news finished'));
  // write into DB date of last news we've received (in order to not display the same news
  // with next update)
  DBWriteContactSettingDWord(0, piShortName, opt_GroupsLastNewsDateTime, DateTimeToFileDate(NewsAll[0].NTime));
end;

 // =============================================================================
 // procedure to parse comments news
 // -------------------------------3----------------------------------------------
function vk_ParseCommentsNews(): TNewsRecords;
var
  DayWrapPosStart, feedTablePosStart, commentItemPosStart: integer;
  DayTime:                           TDateTime;
  HTML, HTMLDay, HTMLNews, HTMLDate: string;
  nNType, nNTimestr:                 string;
  nTitle:                            string;
  nText:                             WideString;
  nID:                               integer;
  nNTime:                            TDateTime;
  ImgStart, ImgEnd:                  integer;
  fSettings:                         TFormatSettings;
  HasNews:                           boolean; // will be true if we have got some news, else false
  dtStamp:                           TDateTime; // DateTime stamp of very *NEW* news (to get rid of dublicates)
begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseCommentsNews) Receiving comments news...'));

  // get user lang id
  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_feed2);
  vk_UserLangId := TextBetween(HTML, '"lang":{"id":"', '","p_id":');
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseCommentsNews) LangId is: ' + vk_UserLangId));
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseCommentsNews) LangHash is: ' + vk_UserLangHash));

  if vk_UserLangId <> '0' then // change lang to Russian for correct parsing
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseCommentsNews) Temporary changing site lang to Russian for parsing...'));
    HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_lang_change, ['0', vk_UserLangHash]));
  end;

  HTML := HTTP_NL_Get(vk_url_prefix + vk_url_host + vk_url_news_comments);

  if vk_UserLangId <> '0' then // return user default lang
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseCommentsNews) Now getting back user default site lang...'));
    HTTP_NL_Get(Format(vk_url_prefix + vk_url_host + vk_lang_change, [vk_UserLangId, vk_UserLangHash]));
  end;

  if Trim(HTML) <> '' then
  begin

    HasNews := True;
    dtStamp := FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_CommentsLastNewsDateTime, 539033600));

    DayWrapPosStart := Pos('feedDayWrap', HTML);
    while HasNews and (DayWrapPosStart > 0) do
    begin
      HTMLDate := TextBetween(HTML, '<div class="feedDay">', '</div>');
      HTMLDate := Trim(HTMLRemoveTags(HTMLDate));
      if HTMLDate = 'сегодня' then
        DayTime := Date
      else
        if HTMLDate = 'вчера' then
          DayTime := Date - 1
        else
          DayTime := RusDateToDateTime(HTMLDate, True);

      HTMLDay := TextBetweenTagsAttrInc(HTML, 'div', 'class', 'items_wrap');

      feedTablePosStart := Pos('<div class=''feedTable ', HTMLDay);
      while HasNews and (feedTablePosStart > 0) do
      begin
        HTMLNews := TextBetweenInc(HTMLDay, '<div class=''feedTable', '<div class=''feedSeparator');
        nNType := TextBetween(HTMLNews, 'images/icons/', '_s.gif?2"');
        nTitle := TextBetweenInc(HTMLNews, '<td class="feedStory', '</td>');
        nTitle := Trim(HTMLDecodeW(nTitle));

        commentItemPosStart := Pos('<table class="commentItem">', HTMLNews);
        while HasNews and (commentItemPosStart > 0) do
        begin
          nText := TextBetweenTagsAttrInc(HTMLNews, 'table', 'class', 'commentItem');
          // remove images
          ImgStart := Pos('<div class="userpic">', nText);
          while ImgStart > 0 do
          begin
            ImgEnd := PosEx('</div>', nText, ImgStart) + 5;
            Delete(nText, ImgStart, ImgEnd - ImgStart + 1);
            ImgStart := Pos('<div class="userpic">', nText);
          end;
          nText := StringReplace(nText, #10, '', [rfReplaceAll]);
          nText := StringReplace(nText, Chr(9), '', [rfReplaceAll]);
          nText := StringReplace(nText, '<br/>', ' ', [rfReplaceAll, rfIgnoreCase]);
          nText := StringReplace(nText, '  <div class="commentBody">', '<div class="commentBody">', [rfReplaceAll, rfIgnoreCase]);
          nText := Replace(nText, '<br><br>', #10#10);
          nText := Replace(nText, '<br>', #10);
          nText := Trim(HTMLDecodeW(nText));
          nNTimestr := TextBetweenTagsAttrInc(nText, 'div', 'class', 'commentHeader');
          nNTimestr := Trim(HTMLRemoveTags(nNTimestr));

          if nNTimestr[Length(nNTimestr) - 4] = ' ' then
            nNTimestr := Copy(nNTimestr, Length(nNTimestr) - 3, 4)
          else
            nNTimestr := Copy(nNTimestr, Length(nNTimestr) - 4, 5);

          GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, fSettings);
          fSettings.TimeSeparator := ':';

          nID := 0;

          nTitle := ReplaceLink(nTitle);
          nTitle := Trim(HTMLRemoveTags(nTitle));
          nText := Replace(nText, ' в ' + nNTimestr, ':' + #10);

          if (nText <> '') and (nNType <> '') and (TryStrToTime(nNTimestr, nNTime, fSettings)) then
          begin
            // data seems to be correct
            nNTime := DayTime + nNTime;
            SetLength(Result, High(Result) + 2);
            Result[High(Result)].NTime := nNTime;
            Result[High(Result)].ID := nID;
            Result[High(Result)].NType := nNType;
            Result[High(Result)].NText := nTitle + nText;
          end;

          if dtStamp < nNTime then
            dtStamp := nNTime;

          commentItemPosStart := Pos('<table class="commentItem">', HTMLNews);
          Delete(HTMLNews, 1, commentItemPosStart + 1);
          commentItemPosStart := Pos('<table class="commentItem">', HTMLNews);
        end;

        // small optimization trick: checking if we have news or not
        if DateTimeToFileDate(dtStamp) > DBGetContactSettingDWord(0, piShortName, opt_CommentsLastNewsDateTime, 539033600) then
          HasNews := True
        else
          HasNews := False;

        feedTablePosStart := Pos('<div class=''feedTable ', HTMLDay);
        Delete(HTMLDay, 1, feedTablePosStart + 1);
        feedTablePosStart := Pos('<div class=''feedTable ', HTMLDay);

      end;
      DayWrapPosStart := Pos('feedDayWrap', HTML);
      Delete(HTML, 1, DayWrapPosStart + 1);
      DayWrapPosStart := Pos('feedDayWrap', HTML);
      Delete(HTML, 1, DayWrapPosStart - 1);
    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_ParseCommentsNews) ... receiving comments news finished'));
end;


 // =============================================================================
 // procedure to get & display comments news
 // -----------------------------------------------------------------------------
procedure vk_GetCommentsNews();
var
  NewsAll:   TNewsRecords;
  CurrNews:  integer;
  ValidNews: boolean;
  NewsText:  WideString;
  ContactID: THandle;
  dtStamp:   TDateTime; // DateTime stamp of very *NEW* news (to get rid of dublicates)
begin
  NewsAll := vk_ParseCommentsNews();
  dtStamp := FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_CommentsLastNewsDateTime, 539033600));

  if High(NewsAll) > -1 then // received news
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetCommentsNews) Verifying ' + IntToStr(High(NewsAll) + 1) + ' received comments news...'));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetCommentsNews) ... last comments news received, date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_CommentsLastNewsDateTime, 539033600)))));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetCommentsNews) ... current local date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', Now)));
    for CurrNews := 0 to High(NewsAll) do
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetCommentsNews) ... checking comments news ' + IntToStr(CurrNews + 1) + ' (of ' + IntToStr(High(NewsAll) + 1) + ')...'));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetCommentsNews) ... comments news ' + IntToStr(CurrNews + 1) + ', date and time: ' + FormatDateTime('dd-mmm-yyyy, hh:nn:ss', NewsAll[CurrNews].NTime)));
      // validate date & time of message (if never was shown before)
      if DateTimeToFileDate(NewsAll[CurrNews].NTime) > DBGetContactSettingDWord(0, piShortName, opt_CommentsLastNewsDateTime, 539033600) then
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetCommentsNews) ... groups news ' + IntToStr(CurrNews + 1) + ' identified as not shown before'));

        if dtStamp < NewsAll[CurrNews].NTime then
          dtStamp := NewsAll[CurrNews].NTime;
        ValidNews := True;

        if (NewsAll[CurrNews].NType = 'photos') and (DBGetContactSettingByte(0, piShortName, opt_CommentsFilterPhotos, 1) = 0) then
          ValidNews := False;
        if (NewsAll[CurrNews].NType = 'video') and (DBGetContactSettingByte(0, piShortName, opt_CommentsFilterVideos, 1) = 0) then
          ValidNews := False;
        if (NewsAll[CurrNews].NType = 'topics') and (DBGetContactSettingByte(0, piShortName, opt_CommentsFilterThemes, 1) = 0) then
          ValidNews := False;
        if (NewsAll[CurrNews].NType = 'notes') and (DBGetContactSettingByte(0, piShortName, opt_CommentsFilterNotes, 1) = 0) then
          ValidNews := False;

        if ValidNews then
        begin
          NewsText := NewsAll[CurrNews].NText;

          // display news in a separate contact
          ContactID := vk_AddFriend(DBGetContactSettingDWord(0, piShortName, opt_NewsSeparateContactID, 1234567890), // separate contact ID, 1234567890 by default
            DBReadUnicode(0, piShortName, opt_NewsSeparateContactName, TranslateW('News')), // separate contact nick, translated 'News' by default
            ID_STATUS_OFFLINE, // status
            1);                // friend = yes

          // re-format news text
          if DBGetContactSettingByte(0, piShortName, opt_CommentsLinks, 1) = 1 then
            NewsText := ReplaceLink(NewsText);
          NewsText := HTMLRemoveTags(NewsText);
          // cleanup NewsText - remove leading spaces
          while NewsText[1] = ' ' do
            Delete(NewsText, 1, 1);
          // use local time for news
          NewsAll[CurrNews].NTime := DateTimeToUnix(NewsAll[CurrNews].NTime) * 2 - PluginLink.CallService(MS_DB_TIME_TIMESTAMPTOLOCAL, DateTimeToUnix(NewsAll[CurrNews].NTime), 0);
          // display news
          vk_ReceiveMessage(ContactID, NewsText, NewsAll[CurrNews].NTime);
        end;
      end;
    end;
  end;
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetCommentsNews) ... verification of received comments news finished'));
  // write into DB date of last news we've received (in order to not display the same news
  // with next update)
  DBWriteContactSettingDWord(0, piShortName, opt_CommentsLastNewsDateTime, DateTimeToFileDate(dtStamp));
end;

begin
end.
