  (*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (С) 2008-2009 Andrey Lukyanov

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
 See the code

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_msgs;

interface

  procedure MsgsInit();
  procedure MsgsDestroy();
  procedure vk_GetMsgsFriendsEtc();
  procedure vk_GetNews();

implementation

uses
  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used
  vk_http, // module to connect with the site
  vk_common, // module with common functions
  vk_wall, // module to work with the wall

  htmlparse, // module to simplify html parsing
  vk_core, // module with core functions

  MSHTML_TLB, // module to parse html
  uLkJSON, // module to parse data from feed2.php (in JSON format)

  ComObj,
  ActiveX,
  Variants,
  Windows,
  SysUtils,
  Classes;

  {$include api/m_folders.inc}

type
  TThreadSendMsg = class(TThread)
  private
    { Private declarations }
  protected
    procedure Execute; override;
  end;


type // type to keep news
  TNewsRecord = record
    NTime    : TDateTime;
    ID       : Integer;
    NType    : String;       // add_photo = Фотографии
                             // movie = Видео
                             // add_item = Заметки
                             // q = Вопросы
                             // post = Темы
                             // plus = Друзья
                             // person = Статус
                             // group = Группы
                             // event = Встречи
                             // audio = Аудио
                             // record = Личные данные
    NText    : String;
  end;

type TNewsRecords = array of TNewsRecord;

var
  vk_hProtoMessageSend,
  vk_hProtoMessageSendW,
  vk_hProtoMessageReceive: THandle;

  hContact_sendmessage: THandle; // variable to provide separate thread
  MsgText_sendmessage: String;   // with message data
  trx_id: Integer;

  ThrIDSendMsg: TThreadSendMsg;


// =============================================================================
// function to send message
// (it is called from separate thread, so minimum number of WRITE global variables is used)
// -----------------------------------------------------------------------------
function vk_SendMessage(ToID: Integer; Text: String): Byte;
// 0 - successful
// 1 - not successful (unknown reason)
// 2 - msgs sent two often
var SecureId: String; // temp variable to keep secure id needed for msg sending
    HTML: String; // html content of the page received

    iHTTP: IHTMLDocument2; // these 2 variables required for
    v: Variant;            // String -> IHTMLDocument2 conversions

begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) Sending new message to id '+ IntToStr(ToID) +', message text: '+Text));
  Result := 1;
  if ToID > 0 Then
  Begin
    CoInitialize(nil);  // since this function is called in a separate thread,
                        // this code is mandatory for CreateComObject function

    // we need to get secure id first, otherwise it is not possible to send msg
    Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... getting secure id'));
    HTML := HTTP_NL_Get(Format(vk_url_pda_sendmsg_secureid, [ToID]));
    try
      iHTTP := CreateComObject(Class_HTMLDocument) as IHTMLDocument2;
      v := VarArrayCreate([0,0], VarVariant);
      v[0] := HTML;
      iHTTP.Write(PSafeArray(System.TVarData(v).VArray));
    except
      iHTTP := nil;
    end;

    If Assigned(iHTTP) Then
    Begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... page with secure id downloaded successfully'));
      // SecureId := TextBetween(getElementsByAttr(iHTTP, 'input', 'name', 'chas')[0], 'value=', ' '); // <input type="hidden" name="secure" value="272c812340fd0d5aaa4e"/>
      SecureId := TextBetween(HTML, 'name="chas"', '/>');
      SecureId := TextBetween(SecureId, 'value="', '"');
      Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... secure id received: '+SecureId));
      // now the message can be sent
      Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... sending message'));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... message text: ' + Text));
      if Trim(UTF8Decode(Text))='' then // if text is not unicode, the encode it
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... message text identified as not unicode, changing to UTF8'));
        Text := UTF8Encode(Text);
        Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... message text changed to: '+ Text));
      end;
      if Trim(Text)<>'' Then // not empty message
      begin
        Text := URLEncode(Text); // encode all Russian and other characters
        HTML := HTTP_NL_Get(Format(vk_url_pda_sendmsg, [ToID, SecureID, Text]))
      end
      else
        HTML := '';

      // verify if user tries to send messages too often and inform
      // him about it - http://pda.vkontakte.ru/blank
      if Pos('Вы попытались загрузить более одной однотипной страницы в секунду', HTML) > 0 then
      Begin
        Result := 2;
      End;

      // verify whether msg is delivered or not
      if Pos('Сообщение отправлено', HTML) > 0 then
      Begin
        Result := 0;
        Netlib_Log(vk_hNetlibUser, PChar('(vk_SendMessage) ... message sent successfully'));
      End;
    End;

    CoUninitialize();
  End;
end;

// =============================================================================
// function to add received message into Miranda's DB
// -----------------------------------------------------------------------------
function vk_ReceiveMessage(FromID: THandle; MsgText: String; MsgDate: TDateTime): Boolean;
var
  ccs_chain: TCCSDATA;
  pre: TPROTORECVEVENT; // varibable required to add message to Miranda
begin
  Result := False;
  FillChar(pre, SizeOf(pre), 0);
  pre.flags := PREF_UTF;
  pre.szMessage := pChar(MsgText);
  // Trunc((DateTime-UnixTimeStart) * SecondsPerDay);
  // UnixTimeStart = 25569; = 1970-01-01 00:00:00 in TDateTime
  // SecondsPerDay = 60*24*60; = 86400;
  // ----
  // Local time is used on the server, so, we need to convert it to GMT
  pre.timestamp := Trunc((MsgDate-25569)*86400)*2 - PluginLink.CallService(MS_DB_TIME_TIMESTAMPTOLOCAL,Trunc((MsgDate-25569)*86400),0);
 	pre.lParam := 0;

  // now we need to initiate incoming message event
  // we can add message without this event (with usage of MS_DB_EVENT_ADD directly),
  // but in this case some plugins will not able to filter message (for ex.,
  // to ignore them)
  FillChar(ccs_chain, SizeOf(ccs_chain), 0);
  ccs_chain.szProtoService := PSR_MESSAGE;  // so, ProtoMessageReceive will be called,
  ccs_chain.hContact := FromID; // if filtering is passed
	ccs_chain.wParam := 0;
  ccs_chain.flags := 0; // we say it is not utf8 message, otherwise flag should be = PREF_UTF
 	ccs_chain.lParam := Windows.lParam(@pre);
  PluginLink^.CallService(MS_PROTO_CHAINRECV, 0, Windows.lParam(@ccs_chain));

end;

// =============================================================================
// function to receive new messages
// (it is called from separate thread, so minimum number of WRITE global variables is used)
// -----------------------------------------------------------------------------
procedure vk_GetMsgsFriendsEtc();
var HTML: AnsiString; // html content of the pages received
    MsgsCount: Integer; // temp variable to keep number of new msgs received
    FriendsCount: Integer; // temp variable to keep number of new authorization requests received
    MsgID: String;
    MsgUrl: String;
    MsgText: String;
    MsgSenderName: String;
    i, ii, temppos: Integer;
    MsgDate: TDateTime;
    MsgSender: Integer;
  	ccs_chain: TCCSDATA;

    pCurBlob: PChar;

    TempFriend: Integer; // id of temp contact if msg received from unknown contact

    pre: TPROTORECVEVENT; // varibable required to add message to Miranda

    FeedRoot, FeedMsgs, FeedMsgsItems: TlkJSONobject; // objects to keep parsed JSON data

begin
 Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) Checking for new incoming messages, new authorization requests (friends) etc...'));

 CoInitialize(nil);  // since this function is called in a separate thread,
                      // this code is mandatory for CreateComObject function

  // check for presence of new messages, friends etc. via the feed
 HTML := HTTP_NL_Get(vk_url_feed2);

 // correct json text
 for i:=1 to length(HTML)-2 do // don't check first and last symbols
 begin
  if HTML[i]='{' then
    if (HTML[i+1]<>'"') and (HTML[i-1]=':') then
      Insert('"', HTML, i+1);

  if (HTML[i]=',') then
    if (HTML[i+1]<>'"') and (HTML[i-1]='"') then
      Insert('"', HTML, i+1);

  if (HTML[i]=':') and (HTML[i+1]='"') then
    if HTML[i-1]<>'"' then
      Insert('"', HTML, i);
 end;

 If Trim(HTML) <> '' Then
 Begin
   // to support Russian characters, we need to utf8 encode html text
   FeedRoot := TlkJSON.ParseText(UTF8Encode(HTML)) as TlkJSONobject;
   if Assigned(FeedRoot) Then
   Begin
     Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking messages count'));
     FeedMsgs := FeedRoot.Field['messages'] as TlkJSONobject;
     if Assigned(FeedMsgs) Then
       MsgsCount := FeedMsgs.getInt('count');
     Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... ' + IntToStr(MsgsCount) + ' message(s) received'));

     if MsgsCount > 0 Then // got new messages!
     Begin
       Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... getting message(s) details'));
       FeedMsgsItems := FeedMsgs.Field['items'] as TlkJSONobject;
       for i:=(MsgsCount-1) downto 0 do // now processing all msgs one-by-one
       Begin
          Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', getting id'));
          MsgID := FeedMsgsItems.NameOf[i];
          If MsgID <> '' Then
          Begin
            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', id: '+MsgID));
            MsgUrl := Format(vk_url_pda_msg, [StrToInt(MsgID)]);
            // get msg details
            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', getting details'));
            HTML := HTTP_NL_Get(MsgUrl);
            // date of message
            if DBGetContactSettingByte(0, piShortName, opt_UserUseLocalTimeForIncomingMessages, 0) = 0 then
              MsgDate := RusDateToDateTime(TextBetween(HTML, '<span class="label">Дата:</span> ', '<br/>'), false)
            else
              MsgDate := Now; // use local time, if requested in the settings
            // from
            If Not TryStrToInt(TextBetween(HTML, 'name="to_id" value="', '"/>'), MsgSender) Then
             Exit;
            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', from id: '+IntToStr(MsgSender)));
            // from - Name (needed for not-friends)
            MsgSenderName := TextBetween(HTML, 'От кого:', '/a>');
            MsgSenderName := HTMLDecode(TextBetween(MsgSenderName, '">', '<'));
            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', from person: '+MsgSenderName));

            // subject and message
            MsgText := TextBetween(HTML, '<span class="label">Тема:</span> ', '<span class="label">Ответить:');
            if DBGetContactSettingByte(0, piShortName, opt_UserRemoveEmptySubj, 1) = 1 then
            begin
              // remove empty subject, if user would like to
              Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', removing empty subject'));
              MsgText := StringReplace(MsgText, 'Re:  ...', '', []);
              MsgText := StringReplace(MsgText, ' ... ', '', []);
              if (MsgText[1] = 'R') and (MsgText[2] = 'e') and (MsgText[3] = '(') then
              begin
                ii := 4;
                while (MsgText[ii] in ['0'..'9']) and (ii <= length(MsgText)-1) do
              	  Inc(ii);
                temppos := PosEx('):  ...', MsgText);
                if (temppos = ii) then
            	    Delete(MsgText, 1, temppos + 6);
              end;
            end;
            MsgText := StringReplace(MsgText, '<br/><br/>', Chr(13) + Chr(10), [rfReplaceAll, rfIgnoreCase]);
            MsgText := StringReplace(MsgText, '<br/>', Chr(13) + Chr(10), [rfReplaceAll, rfIgnoreCase]);
            MsgText := StringReplace(MsgText, Chr(9), '', [rfReplaceAll, rfIgnoreCase]);
            MsgText := HTMLDecode(MsgText);
            MsgText := Trim(MsgText);
            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', text: '+MsgText));

            // if message from unknown contact then
            // we add contact to our list temporary
            TempFriend := GetContactByID(MsgSender);
            If TempFriend = 0 Then
            Begin
              Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ' received from unknown contact, adding him/her to the contact list temporarily'));
              // add sender to our contact list
              // now we don't read user's status, so it is added as offline
              TempFriend := vk_AddFriend(MsgSender, MsgSenderName, ID_STATUS_OFFLINE, 0);
              // and make it as temporary contact
              DBWriteContactSettingByte(TempFriend, 'CList', 'NotOnList', 1);
         		  DBWriteContactSettingByte(TempFriend, 'CList', 'Hidden', 1);
            End;

            Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... message ' + IntToStr(i+1) + ', adding to miranda database'));
            // everything seems to be OK, may add this message to Miranda DB
            vk_ReceiveMessage(TempFriend, MsgText, MsgDate);
          End;
       End;
     End; // receiving of new messages completed
     Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking for new incoming messages finished'));


     Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking new authorization requests count'));
     FeedMsgs := FeedRoot.Field['friends'] as TlkJSONobject;
     if Assigned(FeedMsgs) Then
       FriendsCount := FeedMsgs.getInt('count');
     Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... ' + IntToStr(MsgsCount) + ' new authorization request(s) received'));
     if FriendsCount > 0 Then // got new authorization request(s)!
     Begin
       Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... getting new authorization request(s) details'));
       FeedMsgsItems := FeedMsgs.Field['items'] as TlkJSONobject;
       For i:=0 to FriendsCount-1 Do // now processing all authorization requests one-by-one
       Begin
         Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i+1) + ', getting id and name'));
         MsgID := FeedMsgsItems.NameOf[i];
         MsgSenderName := HTMLDecode(FeedMsgsItems.getString(FeedMsgsItems.NameOf[i]));
         Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i+1) + ', from id: '+MsgID));
         Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i+1) + ', from person: '+MsgSenderName));
         if (Trim(MsgID)<>'') and (TryStrToInt(MsgID, MsgSender)) {and (Trim(MsgSenderName)<>'')} Then
         Begin
           // everything seems to be OK, may proceed
           // temporary add contact if required
           TempFriend := GetContactByID(MsgSender);
           If TempFriend = 0 Then
           Begin
             Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... temporary add contact to our list'));
             // add sender to our contact list
             // now we don't read user's status, so it is added as offline
             TempFriend := vk_AddFriend(MsgSender, MsgSenderName, ID_STATUS_OFFLINE, 0);
             // and make it as temporary contact
             DBWriteContactSettingByte(TempFriend, 'CList', 'NotOnList', 1);
             DBWriteContactSettingByte(TempFriend, 'CList', 'Hidden', 1);
           End;

           Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... new authorization request ' + IntToStr(i+1) + ', adding to miranda database'));

           FillChar(pre, SizeOf(pre), 0);
           pre.flags := 0;
           MsgDate := Now;
           pre.timestamp := Trunc((MsgDate-25569)*86400)*2 - PluginLink.CallService(MS_DB_TIME_TIMESTAMPTOLOCAL,Trunc((MsgDate-25569)*86400),0);

           //blob is: uin( DWORD ), hContact( HANDLE ), nick( ASCIIZ ), first( ASCIIZ ), last( ASCIIZ ), email( ASCIIZ ), reason( ASCIIZ )
           MsgText := '(text of authorization request is not supported currently)';
           pre.lParam := sizeof(DWORD) + sizeof(THANDLE) + Length(MsgSenderName) + Length(MsgID) + Length(MsgText) + 8;
           pCurBlob := AllocMem(pre.lParam);
           pre.szMessage := pCurBlob;
           PDWORD(pCurBlob)^ := 0;
           Inc(pCurBlob, sizeof(DWORD));
           PHANDLE (pCurBlob)^ := TempFriend;
           Inc(pCurBlob, sizeof(THANDLE));
           StrCopy(pCurBlob, PChar(MsgSenderName));
           Inc(pCurBlob, Length(MsgSenderName)+1);
           pCurBlob^ := #0;            //firstName
           Inc(pCurBlob);
           pCurBlob^ := #0;            //lastName
           Inc(pCurBlob);
           pCurBlob^ := #0;            //e-mail
           Inc(pCurBlob);
           StrCopy(pCurBlob, PChar(MsgText)); //reason

           FillChar(ccs_chain, SizeOf(ccs_chain), 0);
           ccs_chain.szProtoService := PSR_AUTH; // so, AuthRequestReceived will be called,
           ccs_chain.hContact := TempFriend;     // if filtering is passed
           ccs_chain.wParam := 0;
           ccs_chain.flags := 0;
         	 ccs_chain.lParam := Windows.lParam(@pre);
           PluginLink^.CallService(MS_PROTO_CHAINRECV, 0, Windows.lParam(@ccs_chain));
         End;
       End;
     End;

   FeedRoot.Free;

   End;
 End;

 CoUninitialize();
 Netlib_Log(vk_hNetlibUser, PChar('(vk_GetMsgsFriendsEtc) ... checking for new authorization requests finished'));

end;

// =============================================================================
// function to send message
// called when text contains English characters only
// -----------------------------------------------------------------------------
function ProtoMessageSend(wParam: wParam; lParam: lParam): Integer; cdecl;
var ccs: PCCSDATA;
begin
  ccs := PCCSDATA(lParam);
  hContact_sendmessage := ccs.hContact;
  MsgText_sendmessage := PChar(ccs.lParam);

  Netlib_Log(vk_hNetlibUser, PChar('(ProtoMessageSend) Sending message, text: '+PChar(ccs.lParam)));

  trx_id := StrToInt(FormatDateTime('nnsszzz', Now)); // generate trx (message) number
  SleepEx(10, True);

  // call separate thread to send the msg
  ThrIDSendMsg := TThreadSendMsg.Create(False);

  // return the transaction id we've assigned to the trx
  Result := trx_id;
end;

// =============================================================================
// function to send message
// called when text contains English & non-English characters
// -----------------------------------------------------------------------------
function ProtoMessageSendW(wParam: wParam; lParam: lParam): Integer; cdecl;
begin
  Result := ProtoMessageSend(wParam, lParam);
end;


// =============================================================================
// function to receive messages
// -----------------------------------------------------------------------------
function ProtoMessageReceive(wParam: wParam; lParam: lParam): Integer; cdecl;
var ccs_sm: PCCSDATA;
    dbeo: TDBEVENTINFO; // varibable required to add message to Miranda
    pre: TPROTORECVEVENT;
begin

  ccs_sm := PCCSDATA(lParam);
  pre := PPROTORECVEVENT(ccs_sm.lParam)^;

  FillChar(dbeo, SizeOf(dbeo), 0);
  With dbeo Do
  Begin
    cbSize   := SizeOf(dbeo);         
    eventType := EVENTTYPE_MESSAGE;        // message
    szModule := piShortName;
    pBlob    := PByte(pre.szMessage);      // data
    cbBlob   := Length(pre.szMessage) + 1; // SizeOf(pBlob);
    flags    := 0;
    timestamp := pre.timestamp;
  End;
  PluginLink^.CallService(MS_DB_EVENT_ADD, ccs_sm.hContact, dword(@dbeo));
  // SkinPlaySound('VKontakte\MsgIncoming');

  Result := 0;
end;


// =============================================================================
// function to initiate support of messages sending and receiving
// -----------------------------------------------------------------------------
procedure MsgsInit();
begin
  vk_hProtoMessageSend := CreateProtoServiceFunction(piShortName, PSS_MESSAGE, ProtoMessageSend);
  vk_hProtoMessageSendW := CreateProtoServiceFunction(piShortName, PSS_MESSAGEW, ProtoMessageSendW);
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
procedure TThreadSendMsg.Execute;
var trx_id_temp: Integer;
    hContact_temp: THandle;
    MsgText: String;
    ThreadNameInfo: TThreadNameInfo;
    ResultTemp: TResultDetailed;
    bPostingOnTheWall: Boolean;
    sWord: String;
    iWordLength: Byte;
begin
 Netlib_Log(vk_hNetlibUser, PChar('(TThreadSendMsg) Thread started...'));

 ThreadNameInfo.FType := $1000;
 ThreadNameInfo.FName := 'TThreadSendMsg';
 ThreadNameInfo.FThreadID := $FFFFFFFF;
 ThreadNameInfo.FFlags := 0;
 try
   RaiseException( $406D1388, 0, sizeof(ThreadNameInfo) div sizeof(LongWord), @ThreadNameInfo);
 except
 end;

 // to be on the safe side (we work with threads!), put values from global
 // variables to temp variables, then only these temp variable will be used
 trx_id_temp := trx_id;
 hContact_temp := hContact_sendmessage;
 MsgText := MsgText_sendmessage;

 if vk_Status = ID_STATUS_OFFLINE Then // if offline - send failed ack
 Begin
    ProtoBroadcastAck(piShortName, hContact_temp, ACKTYPE_MESSAGE, ACKRESULT_FAILED, THandle(trx_id_temp), windows.lParam(Translate(err_sendmgs_offline)));
    Exit;
 End;

  // verifying if the message should be posted on the wall
  // (in this case it should be started with 'wall:' (or user defined value) or
  // with translated equivalent
  bPostingOnTheWall := False;
  sWord := DBReadString(0, piShortName, opt_WallMessagesWord, 'wall:');
  iWordLength := Length(Translate(PChar(sWord))) - 1;
  if (Copy(MsgText, 0, iWordLength) = Translate(PChar(sWord))) then
    bPostingOnTheWall := True
  else
  begin
    sWord := String(Translate(PChar(sWord)));
    iWordLength := Length(sWord);
	  if (Copy(MsgText, 0, iWordLength) = sWord) then
		  bPostingOnTheWall := True;
  end;

  if bPostingOnTheWall then
  begin // posting message on the wall
    MsgText := Copy(MsgText, iWordLength + 1, Length(MsgText) - iWordLength);
    ResultTemp := vk_WallPostMessage(DBGetContactSettingDword(hContact_temp, piShortName, 'ID', 0),
                                 Trim(MsgText),
                                 0);
    case ResultTemp.Code of
      0: // 0 - successful
         ProtoBroadcastAck(piShortName, hContact_temp, ACKTYPE_MESSAGE, ACKRESULT_SUCCESS, THandle(trx_id_temp), 0);
      1: // 1 - failed
         ProtoBroadcastAck(piShortName, hContact_temp, ACKTYPE_MESSAGE, ACKRESULT_FAILED, THandle(trx_id_temp), windows.lParam(ResultTemp.Text));
    end;  
  end
  else // calling function to send normal message
  case vk_SendMessage(DBGetContactSettingDword(hContact_temp, piShortName, 'ID', 0), MsgText) of
     0: // 0 - successful
        // the ACK contains reference (thandle) to the trx number
        ProtoBroadcastAck(piShortName, hContact_temp, ACKTYPE_MESSAGE, ACKRESULT_SUCCESS, THandle(trx_id_temp), 0);
     1: // 1 - not successful (unknown reason)
        ProtoBroadcastAck(piShortName, hContact_temp, ACKTYPE_MESSAGE, ACKRESULT_FAILED, THandle(trx_id_temp), 0);
     2: // 2 - msgs sent two often
        ProtoBroadcastAck(piShortName, hContact_temp, ACKTYPE_MESSAGE, ACKRESULT_FAILED, THandle(trx_id_temp), windows.lParam(Translate(err_sendmgs_freq)));
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
var NewsPosStart, DayWrapPosStart: Integer;
    HTML, HTMLDay: String;

    nNType, nText, nIDstr, nNTimestr : String;
    nID: Integer;
    nNTime: TDateTime;

    fSettings: TFormatSettings;

begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsMinimal) Receiving minimal news...'));

  HTML := HTTP_NL_Get(vk_url_pda_news);

  If Trim(HTML) <> '' Then
  begin
    DayWrapPosStart := Pos('stRows', HTML);
    if DayWrapPosStart > 0 then
    begin
      HTMLDay := TextBetweenTagsAttrInc(HTML, 'div', 'class', 'stRows');
      NewsPosStart := Pos('<div>', HTMLDay);
      while NewsPosStart > 0 do
      begin
        nNType := 'unknown';
        nIDstr := TextBetween(HTMLDay, 'a href=''id', '''');
        nText := TextBetweenInc(HTMLDay, '<a', '<span class="stTime">');
        nText := StringReplace(nText, #10, '', [rfReplaceAll]);
        nText := StringReplace(nText, Chr(9), '', [rfReplaceAll]);
        nText := StringReplace(nText, '<br/>', ' ', [rfReplaceAll, rfIgnoreCase]);
        nText := Trim(HTMLDecode(nText));
        nNTimestr := TextBetweenInc(HTMLDay, '<span class="stTime">', '</span>');
        nNTimestr := Trim(HTMLRemoveTags(nNTimestr));
        GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, fSettings);
        fSettings.TimeSeparator := ':';

        if (nText <> '') and (nNType <> '') and (TryStrToInt(nIDstr, nID)) and (TryStrToTime(nNTimestr, nNTime, fSettings)) then
        begin
          // data seems to be correct
          nNTime := Date + nNTime;
          SetLength(Result, High(Result)+2);
          Result[High(Result)].NTime := nNTime;
          Result[High(Result)].ID := nID;
          Result[High(Result)].NType := nNType;
          Result[High(Result)].NText := nText;
        end;

        Delete(HTMLDay, 1, Pos('</div>', HTMLDay)+5);
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
var DayWrapPosStart, feedTablePosStart: Integer;
    DayTime: TDateTime;
    HTML, HTMLDay, HTMLNews, HTMLDate: String;

    nNType, nText, nIDstr, nNTimestr : String;
    nID: Integer;
    nNTime: TDateTime;

    ImgStart, ImgEnd: Integer;

    fSettings: TFormatSettings;

begin
  Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNewsFull) Receiving news...'));

  HTML := HTTP_NL_Get(vk_url_news);

  If Trim(HTML) <> '' Then
  begin

    DayWrapPosStart := Pos('feedDayWrap', HTML);
    While DayWrapPosStart > 0 Do
    Begin
      HTMLDate := TextBetween(HTML, '<div class=''feedDay''>', '</div>');
      if HTMLDate = 'Сегодня' then DayTime := Date else
        if HTMLDate = 'Вчера' then DayTime := Date - 1 else
           DayTime := RusDateToDateTime(HTMLDate, true);

      HTMLDay := TextBetweenTagsAttrInc(HTML, 'div', 'style', 'padding:10px 10px 20px 10px;');
      feedTablePosStart := Pos('<table class="feedTable"', HTMLDay);
      While feedTablePosStart > 0 Do
      Begin
        HTMLNews := TextBetweenTagsAttrInc(HTMLDay, 'table', 'class', 'feedTable');
        nNType := TextBetween(HTMLNews, 'images/icons/', '_icon.gif"');
        nIDstr := TextBetween(HTMLNews, 'a href=''/id', '''');
        nText := TextBetweenInc(HTMLNews, '<td class="feedStory', '</td>');
        // remove images
        ImgStart := Pos('<div class=''feedFriendImg''>', nText);
        while ImgStart > 0 do
        begin
          ImgEnd := PosEx('</div>', nText, ImgStart) + 6;
          Delete(nText, ImgStart, ImgEnd-ImgStart+1);
          ImgStart := Pos('<div class=''feedFriendImg''>', nText);
        end;
        nText := StringReplace(nText, #10, '', [rfReplaceAll]);
        nText := StringReplace(nText, Chr(9), '', [rfReplaceAll]);
        nText := StringReplace(nText, '<br/>', ' ', [rfReplaceAll, rfIgnoreCase]);
        nText := Trim(HTMLDecode(nText));
        // remove extra spaces (when contact added more than 1 friend)
        nText := StringReplace(nText, '</small></a>       </div></div><div class=''feedFriend''>', '</small></a>       </div></div>, <div class=''feedFriend''>', [rfReplaceAll]);
        nText := StringReplace(nText, '       ', ' ', [rfReplaceAll]);

        // nText := LeftStr(nText, Length(nText)-1); // remove trailing dot - doesn't work correctly when contact added more than 1 friend
        nNTimestr := TextBetweenInc(HTMLNews, '<td class="feedTime', '</td>');
        nNTimestr := Trim(HTMLRemoveTags(nNTimestr));
        GetLocaleFormatSettings(LOCALE_SYSTEM_DEFAULT, fSettings);
        fSettings.TimeSeparator := ':';

        if (nText <> '') and (nNType <> '') and (TryStrToInt(nIDstr, nID)) and (TryStrToTime(nNTimestr, nNTime, fSettings)) then
        begin
          // data seems to be correct
          nNTime := DayTime + nNTime;
          SetLength(Result, High(Result)+2);
          Result[High(Result)].NTime := nNTime;
          Result[High(Result)].ID := nID;
          Result[High(Result)].NType := nNType;
          Result[High(Result)].NText := nText;
        end;

        feedTablePosStart := Pos('<table class="feedTable"', HTMLDay);
        Delete(HTMLDay, 1, feedTablePosStart + 1);
        feedTablePosStart := Pos('<table class="feedTable"', HTMLDay);

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
var NewsAll: TNewsRecords;
    CurrNews: Integer;
    ValidNews: Boolean;
    NewsText: String;
    ContactID: THandle;
begin
  if DBGetContactSettingByte(0, piShortName, opt_NewsMin, 0) = 1 then
    NewsAll := vk_GetNewsMinimal()
  else
    NewsAll := vk_GetNewsFull;

  if High(NewsAll) > -1 then // received news
  begin
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) Verifying '+IntToStr(High(NewsAll))+' received news...'));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... last news received, date and time: '+FormatDateTime('dd-mmm-yyyy, hh:nn:ss', FileDateToDateTime(DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 539033600)))));
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... current local date and time: '+FormatDateTime('dd-mmm-yyyy, hh:nn:ss', Now)));
    for CurrNews:=0 to High(NewsAll)-1 do
    begin
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... checking news '+IntToStr(CurrNews+1)+' (from '+IntToStr(High(NewsAll))+')...'));
      Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... news ' +IntToStr(CurrNews+1)+', date and time: '+FormatDateTime('dd-mmm-yyyy, hh:nn:ss', NewsAll[CurrNews].NTime)));
      // validate date & time of message (if never was shown before)
      if DateTimeToFileDate(NewsAll[CurrNews].NTime) > DBGetContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, 539033600) then
      begin
        Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... news ' +IntToStr(CurrNews+1)+' identified as not shown before'));
        ValidNews := True;
        // filter news, if not minimal news chosen
        if DBGetContactSettingByte(0, piShortName, opt_NewsMin, 0) = 0 then
        begin
          if (NewsAll[CurrNews].NType = 'add_photo') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterPhotos, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'movie') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterVideos, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'add_item') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterNotes, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'q') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterQuestions, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'post') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterThemes, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'plus') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterFriends, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'person') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterStatuses, 0) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'group') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterGroups, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'event') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterMeetings, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'audio') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterAudio, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'record') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterPersonalData, 1) = 0) Then
            ValidNews := False;
          if (NewsAll[CurrNews].NType = 'add_tag') And (DBGetContactSettingByte(0, piShortName, opt_NewsFilterTags, 1) = 0) Then
            ValidNews := False;
        end;
        if ValidNews then
        begin
          NewsText := NewsAll[CurrNews].NText;

          if DBGetContactSettingByte(0, piShortName, opt_NewsSeparateContact, 0) = 1 then
          begin // display news in a separate contact
            ContactID := vk_AddFriend(DBGetContactSettingDWord(0, piShortName, opt_NewsSeparateContactID, 1234), // separate contact ID, 1234 by default
                                      DBReadString(0, piShortName, opt_NewsSeparateContactName, Translate('News')), // separate contact nick, translated 'News' by default
                                      ID_STATUS_OFFLINE, // status
                                      1); // friend = yes
          end
          else // display news in according contact
          begin
            // remove person name
            Delete(NewsText, 1, Pos('</a>', NewsText)+4);
            ContactID := GetContactById(NewsAll[CurrNews].ID);
          end;
          // re-format news text
          if DBGetContactSettingByte(0, piShortName, opt_NewsLinks, 1) = 1 then
          begin
            NewsText := ReplaceLink(NewsText);
            NewsText := RemoveDuplicates(NewsText);
          end;
          NewsText := HTMLRemoveTags(NewsText);
          // display news
          vk_ReceiveMessage(ContactID, NewsText, NewsAll[CurrNews].NTime);
        end;
      end;
    end;
    Netlib_Log(vk_hNetlibUser, PChar('(vk_GetNews) ... verification of received news finished'));
    // write into DB date of last news we've received (in order to not display the same news
    // with next update)
    DBWriteContactSettingDWord(0, piShortName, opt_NewsLastNewsDateTime, DateTimeToFileDate(NewsAll[0].NTime));
  end;
end;


begin
end.
