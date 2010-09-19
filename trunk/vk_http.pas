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
 vk_http.pas

 [ Description ]
 Module to support Internet connections for VKontakte plugin

 [ Known Issues ]
 - re-write HTTP_NL_GetSession function

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_http;

interface

uses
  m_globaldefs,
  m_api,
  vk_global, // module with global variables and constant used

  Windows,
  SysUtils,
  Classes;

procedure HTTP_NL_Init();
function HTTP_NL_Get(szUrl: string; szRequestType: integer = REQUEST_GET): string;
function HTTP_NL_GetSession(szUrl: string; szRequestType: integer = REQUEST_HEAD): string;
function HTTP_NL_GetSessionUserAPI(szUrl: string): string;
function HTTP_NL_Post(szUrl: string; szData: string; ContentType: string; Boundary: string; szHeaders: string = ''): string;
function HTTP_NL_PostPicture(szUrl: string; szData: string; Boundary: string): string;
function HTTP_NL_GetPicture(szUrl, szFileName: string): boolean;

implementation

uses
  vk_core, htmlparse, StrUtils; // module with core functions

 // =============================================================================
 // function initiliaze connection with internet
 // global var used: vk_hNetlibUser = contains handle to netlibuser created
 // -----------------------------------------------------------------------------
procedure HTTP_NL_Init();
var
  nlu: TNETLIBUSER;
begin
  FillChar(nlu, sizeof(nlu), 0);
  nlu.cbSize := sizeof(nlu);
  nlu.flags := NUF_OUTGOING or NUF_HTTPCONNS or NUF_NOHTTPSOPTION;
  nlu.szSettingsModule := piShortName;
  nlu.szDescriptiveName := Translate('VKontakte HTTP connections');
  vk_hNetlibUser := pluginLink^.CallService(MS_NETLIB_REGISTERUSER, 0, Windows.lparam(@nlu));
  Netlib_Log(vk_hNetlibUser, PChar('Netlib service registered.'));
end;

 // =============================================================================
 // function to download webpage from the internet
 // szUrl = URL of the webpage to be retrieved
 // szRequestType = type of request (REQUEST_GET, REQUEST_HEAD)
 // return value = HTML string
 // global var used: vk_hNetlibUser = contains handle to netlibuser created
 // -----------------------------------------------------------------------------
function HTTP_NL_Get(szUrl: string; szRequestType: integer = REQUEST_GET): string;
var
  nlhr:       TNETLIBHTTPREQUEST;
  nlhrReply:  PNETLIBHTTPREQUEST;
  szRedirUrl: string;
  i:          integer;
  szHost:     string;
  sCookies:   string;
begin
  Result := ' ';

  // create 'storage' for cookies
  if not Assigned(CookiesGlobal) then
  begin
    CookiesGlobal := TStringList.Create;
    CookiesGlobal.Sorted := True;
    CookiesGlobal.Duplicates := dupIgnore;
    CookiesGlobal.Delimiter := ' ';
  end;

  FillChar(nlhr, sizeof(nlhr), 0);
  nlhrReply := @nlhr;

  // initialize the netlib request
  nlhr.cbSize := sizeof(nlhr);
  nlhr.requestType := szRequestType; // passed from the function parameters, REQUEST_GET is default
  nlhr.flags := NLHRF_DUMPASTEXT or NLHRF_HTTP11;
  nlhr.szUrl := PChar(szUrl);

  nlhr.headersCount := 5;
  SetLength(nlhr.headers, 5);
  nlhr.headers[0].szName := 'User-Agent';
  nlhr.headers[0].szValue := 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';
  nlhr.headers[1].szName := 'Connection';
  nlhr.headers[1].szValue := 'Keep-Alive';
  nlhr.headers[2].szName := 'Cache-Control';
  nlhr.headers[2].szValue := 'no-cache';
  nlhr.headers[3].szName := 'Pragma';
  nlhr.headers[3].szValue := 'no-cache';
  sCookies := CookiesGlobal.DelimitedText;
  nlhr.headers[4].szName := 'Cookie';
  nlhr.headers[4].szValue := PChar(sCookies);

  while (Result = ' ') do
  begin

    // fast exit when Miranda terminating
    if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) then
    begin
      Result := '';
      Exit;
    end;

    Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_Get) Dowloading page: ' + szUrl));

    // download the page
    nlhrReply := PNETLIBHTTPREQUEST(PluginLink^.CallService(MS_NETLIB_HTTPTRANSACTION, Windows.WParam(vk_hNetlibUser), Windows.lParam(@nlhr)));
    Netlib_Log(vk_hNetlibUser, PChar('nlhrReply <> nil: ' + ifthen(nlhrReply <> nil, 'true', 'false')));
    if (nlhrReply <> nil) then
    begin
      // read cookies & store it
      for i := 0 to nlhrReply.headersCount - 1 do
      begin
        // read cookie
        if nlhrReply.headers[i].szName = 'Set-Cookie' then
          CookiesGlobal.Add(Copy(nlhrReply.headers[i].szValue, 0, Pos(';', nlhrReply.headers[i].szValue)));
      end;

      Netlib_Log(vk_hNetlibUser, PChar('nlhrReply.resultCode: ' + IntToStr(nlhrReply.resultCode)));
      case nlhrReply.resultCode of

        // if the receieved code is 200 OK
        200:
        begin
          ConnectionErrorsCount := 0;
          // save the retrieved data
          Result := nlhrReply.pData;
          if nlhrReply.dataLength = 0 then
            Result := ''; // DATA_EMPTY;
        end;

        // if the receieved code is 302 Moved, Found, etc
        // workaround for url forwarding
        302:
        begin
          Netlib_Log(vk_hNetlibUser, PChar('szRequestType <> REQUEST_HEAD:' + ifthen(szRequestType <> REQUEST_HEAD, 'true', 'false')));
          if szRequestType <> REQUEST_HEAD then  // no need to redirect if REQUEST_HEAD
          begin
            ConnectionErrorsCount := 0;
            // get the url for the new location and save it to szInfo
            // look for the reply header "Location"
            for i := 0 to nlhrReply.headersCount - 1 do
            begin
              Netlib_Log(vk_hNetlibUser, PChar('"' + nlhrReply.headers[i].szName + '"'));
              if nlhrReply.headers[i].szName = 'Location' then
              begin
                // gap: the code below will not work correctly in some cases
                // if location url doesn't contain host name, we should add it
                szHost := Copy(szUrl, Pos('://', szUrl) + 3, LastDelimiter('/', szUrl) - Pos('://', szUrl) - 3);
                if Pos(szHost, nlhrReply.headers[i].szValue) = 0 then
                begin
                  if (RightStr(szHost, 1) <> '/') and (LeftStr(nlhrReply.headers[i].szValue, 1) <> '/') then
                    szHost := szHost + '/';
                  szRedirUrl := 'http://' + szHost + nlhrReply.headers[i].szValue;
                end
                else
                  szRedirUrl := nlhrReply.headers[i].szValue;
                Netlib_Log(vk_hNetlibUser, PChar('RedirUrl: ' + szRedirUrl));

                nlhr.szUrl := PChar(szRedirUrl);

                if Pos('http://pda.vkontakte.ru/index', szRedirUrl) = 0 then // block this page to support invisible mode
                  Result := HTTP_NL_Get(szRedirUrl)                          // not the best solution
                else
                  Result := 'div class="menu2"';

                CallService(MS_NETLIB_FREEHTTPREQUESTSTRUCT, 0, lParam(nlhrReply));
                Exit;
              end;
            end;
          end
          else
          begin
            //alexei.emanov. Need to stop endless loop
            Result := '';
            Exit;
          end;
        end;

          // return error code if the receieved code is neither 200 OK nor 302 Moved
        else
        begin
          // change status of the protocol to offline
          Inc(ConnectionErrorsCount);
          if ConnectionErrorsCount = 2 then // disconnect only when second attemp unsuccessful
          begin
            ConnectionErrorsCount := 0;
            vk_SetStatus(ID_STATUS_OFFLINE);
          end;
          // store the error code
          Result := nlhrReply.pData;
        end;

      end;

    end
    // if the data does not downloaded successfully (ie. disconnected), then return error
    else
    begin
      // change status of the protocol to offline
      Inc(ConnectionErrorsCount);
      if ConnectionErrorsCount = 2 then // disconnect only when second attemp unsuccessful
      begin
        ConnectionErrorsCount := 0;
        vk_SetStatus(ID_STATUS_OFFLINE);
      end;
      // store the error code
      Result := 'NetLib error occurred!';
    end;
  end;
end;

 // =============================================================================
 // function to get Session details for vkontakte API
 // should be re-written
 // -----------------------------------------------------------------------------
function HTTP_NL_GetSession(szUrl: string; szRequestType: integer = REQUEST_HEAD): string;
var
  nlhr:       TNETLIBHTTPREQUEST;
  nlhrReply:  PNETLIBHTTPREQUEST;
  szRedirUrl: string;
  i:          integer;
  szHost:     string;
begin
  Result := ' ';

  // create 'storage' for cookies
  if not Assigned(CookiesGlobal) then
  begin
    CookiesGlobal := TStringList.Create;
    CookiesGlobal.Sorted := True;
    CookiesGlobal.Duplicates := dupIgnore;
    CookiesGlobal.Delimiter := ' ';
  end;

  FillChar(nlhr, sizeof(nlhr), 0);
  nlhrReply := @nlhr;

  // initialize the netlib request
  nlhr.cbSize := sizeof(nlhr);
  nlhr.requestType := szRequestType; // passed from the function parameters, REQUEST_GET is default
  nlhr.flags := NLHRF_DUMPASTEXT or NLHRF_HTTP11;
  nlhr.szUrl := PChar(szUrl);

  nlhr.headersCount := 5;
  SetLength(nlhr.headers, 5);
  nlhr.headers[0].szName := 'User-Agent';
  nlhr.headers[0].szValue := 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';
  nlhr.headers[1].szName := 'Connection';
  nlhr.headers[1].szValue := 'Keep-Alive';
  nlhr.headers[2].szName := 'Cache-Control';
  nlhr.headers[2].szValue := 'no-cache';
  nlhr.headers[3].szName := 'Pragma';
  nlhr.headers[3].szValue := 'no-cache';
  nlhr.headers[4].szName := 'Cookie';
  nlhr.headers[4].szValue := PChar(CookiesGlobal.DelimitedText);

  while (Result = ' ') do
  begin

    // fast exit when Miranda terminating
    if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) then
    begin
      Result := '';
      Exit;
    end;

    Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_Get) Dowloading page: ' + szUrl));

    // download the page
    nlhrReply := PNETLIBHTTPREQUEST(PluginLink^.CallService(MS_NETLIB_HTTPTRANSACTION, Windows.WParam(vk_hNetlibUser), Windows.lParam(@nlhr)));
    if (nlhrReply <> nil) then
    begin
      // read cookies & store it
      for i := 0 to nlhrReply.headersCount - 1 do
      begin
        // read cookie
        if nlhrReply.headers[i].szName = 'Set-Cookie' then
          CookiesGlobal.Add(Copy(nlhrReply.headers[i].szValue, 0, Pos(';', nlhrReply.headers[i].szValue)));
      end;

      case nlhrReply.resultCode of

        // if the receieved code is 200 OK
        200:
        begin
          ConnectionErrorsCount := 0;
          // save the retrieved data
          Result := nlhrReply.pData;
          if nlhrReply.dataLength = 0 then
            Result := ''; // DATA_EMPTY;
        end;

        // if the receieved code is 302 Moved, Found, etc
        // workaround for url forwarding
        302:
        begin
          ConnectionErrorsCount := 0;
          // get the url for the new location and save it to szInfo
          // look for the reply header "Location"
          for i := 0 to nlhrReply.headersCount - 1 do
          begin
            if nlhrReply.headers[i].szName = 'Location' then
            begin
              // gap: the code below will not work correctly in some cases
              // if location url doesn't contain host name, we should add it
              szHost := Copy(szUrl, Pos('://', szUrl) + 3, LastDelimiter('/', szUrl) - Pos('://', szUrl) - 3);
              if Pos(szHost, nlhrReply.headers[i].szValue) = 0 then
              begin
                if (RightStr(szHost, 1) <> '/') and (LeftStr(nlhrReply.headers[i].szValue, 1) <> '/') then
                  szHost := szHost + '/';
                szRedirUrl := 'http://' + szHost + nlhrReply.headers[i].szValue;
              end
              else
                szRedirUrl := nlhrReply.headers[i].szValue;

              nlhr.szUrl := PChar(szRedirUrl);

              if Pos('session', szRedirUrl) > 0 then
              begin
                vk_id := TextBetween(szRedirUrl, 'mid%22%3A', '%2C'); // extract user's id
                vk_secret := TextBetween(szRedirUrl, 'secret%22%3A%22', '%22'); // extract user's id
                vk_session_id := TextBetween(szRedirUrl, 'sid%22%3A%22', '%22'); // extract session's id
                Result := vk_session_id;
              end;

              CallService(MS_NETLIB_FREEHTTPREQUESTSTRUCT, 0, lParam(nlhrReply));
              Exit;
            end;
          end;
        end;

          // return error code if the receieved code is neither 200 OK nor 302 Moved
        else
        begin
          // change status of the protocol to offline
          Inc(ConnectionErrorsCount);
          if ConnectionErrorsCount = 2 then // disconnect only when second attemp unsuccessful
          begin
            ConnectionErrorsCount := 0;
            vk_SetStatus(ID_STATUS_OFFLINE);
          end;
          // store the error code
          Result := nlhrReply.pData;
        end;

      end;

    end
    // if the data does not downloaded successfully (ie. disconnected), then return error
    else
    begin
      // change status of the protocol to offline
      Inc(ConnectionErrorsCount);
      if ConnectionErrorsCount = 2 then // disconnect only when second attemp unsuccessful
      begin
        ConnectionErrorsCount := 0;
        vk_SetStatus(ID_STATUS_OFFLINE);
      end;
      // store the error code
      Result := 'NetLib error occurred!';
    end;
  end;
end;


 // =============================================================================
 // function to get Signature for UserAPI
 // -----------------------------------------------------------------------------
function HTTP_NL_GetSessionUserAPI(szUrl: string): string;
var
  nlhr:      TNETLIBHTTPREQUEST;
  nlhrReply: PNETLIBHTTPREQUEST;
  i:         integer;
begin
  Result := '';


  FillChar(nlhr, sizeof(nlhr), 0);
  // nlhrReply := @nlhr;

  // initialize the netlib request
  nlhr.cbSize := sizeof(nlhr);
  nlhr.requestType := REQUEST_GET;
  nlhr.flags := NLHRF_DUMPASTEXT or NLHRF_HTTP11;
  nlhr.szUrl := PChar(szUrl);

  nlhr.headersCount := 4;
  SetLength(nlhr.headers, 4);
  nlhr.headers[0].szName := 'User-Agent';
  nlhr.headers[0].szValue := 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';
  nlhr.headers[1].szName := 'Connection';
  nlhr.headers[1].szValue := 'Keep-Alive';
  nlhr.headers[2].szName := 'Cache-Control';
  nlhr.headers[2].szValue := 'no-cache';
  nlhr.headers[3].szName := 'Pragma';
  nlhr.headers[3].szValue := 'no-cache';

  // fast exit when Miranda terminating
  if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) then
  begin
    Result := '';
    Exit;
  end;

  Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_GetSessionUserAPI) Dowloading page: ' + szUrl));

  // download the page
  nlhrReply := PNETLIBHTTPREQUEST(PluginLink^.CallService(MS_NETLIB_HTTPTRANSACTION, Windows.WParam(vk_hNetlibUser), Windows.lParam(@nlhr)));
  if (nlhrReply <> nil) then
  begin
    if nlhrReply.resultCode = 302 then
    begin
      // look for the reply header "Location" with session id
      for i := 0 to nlhrReply.headersCount - 1 do
        if nlhrReply.headers[i].szName = 'Location' then
        begin
          if Pos('sid', nlhrReply.headers[i].szValue) > 0 then
          begin
            Result := TextBetween(nlhrReply.headers[i].szValue + ' ', 'sid=', ' ');
            Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_GetSessionUserAPI) Session id received: ' + Result));
          end;
        end;
    end;
  end;
  CallService(MS_NETLIB_FREEHTTPREQUESTSTRUCT, 0, lParam(@nlhr));
  CallService(MS_NETLIB_FREEHTTPREQUESTSTRUCT, 0, lParam(nlhrReply));
end;

 // =============================================================================
 // function to post data to the site
 // szUrl = URL of the webpage to be retrieved
 // szData = data to be posted
 // return value = HTML string
 // global var used: vk_hNetlibUser = contains handle to netlibuser created

 // TODO: enable usage of szHeaders value
 //       re-write usage of Boundary (in to order just to pass values)
 // -----------------------------------------------------------------------------
function HTTP_NL_Post(szUrl: string; szData: string; ContentType: string; Boundary: string; szHeaders: string = ''): string;
var
  nlhr:       TNETLIBHTTPREQUEST;
  nlhrReply:  PNETLIBHTTPREQUEST;
  szRedirUrl: string;
  szHost:     string;
  i:          integer;
begin
  Result := ' ';

  // create 'storage' for cookies
  if not Assigned(CookiesGlobal) then
  begin
    CookiesGlobal := TStringList.Create;
    CookiesGlobal.Sorted := True;
    CookiesGlobal.Duplicates := dupIgnore;
    CookiesGlobal.Delimiter := ' ';
  end;

  FillChar(nlhr, sizeof(nlhr), 0);
  nlhrReply := @nlhr;

  // initialize the netlib request
  nlhr.cbSize := sizeof(nlhr);
  nlhr.requestType := REQUEST_POST;
  nlhr.flags := NLHRF_DUMPASTEXT or NLHRF_HTTP11;
  nlhr.szUrl := PChar(szUrl);

  nlhr.pData := PChar(szData);
  nlhr.dataLength := Length(szData) + 1;

  nlhr.headersCount := 6;
  SetLength(nlhr.headers, 6);
  nlhr.headers[0].szName := 'User-Agent';
  nlhr.headers[0].szValue := 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';
  nlhr.headers[1].szName := 'Connection';
  nlhr.headers[1].szValue := 'keep-alive';
  nlhr.headers[2].szName := 'Keep-Alive';
  nlhr.headers[2].szValue := '300';
  nlhr.headers[3].szName := 'Cookie';
  nlhr.headers[3].szValue := PChar(CookiesGlobal.DelimitedText);
  nlhr.headers[4].szName := 'Content-Type';
  nlhr.headers[4].szValue := PChar(ContentType + '; boundary=' + Boundary);
  nlhr.headers[5].szName := 'X-Requested-With';
  nlhr.headers[5].szValue := 'XMLHttpRequest';

  while (Result = ' ') do
  begin

    // fast exit when Miranda terminating
    if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) then
      Exit;

    Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_Post) Dowloading page: ' + szUrl));
    // download the page
    nlhrReply := PNETLIBHTTPREQUEST(PluginLink^.CallService(MS_NETLIB_HTTPTRANSACTION, Windows.WParam(vk_hNetlibUser), Windows.lParam(@nlhr)));
    if (nlhrReply <> nil) then
    begin
      // read cookies & store it
      for i := 0 to nlhrReply.headersCount - 1 do
      begin
        // read cookie
        if nlhrReply.headers[i].szName = 'Set-Cookie' then
          CookiesGlobal.Add(Copy(nlhrReply.headers[i].szValue, 0, Pos(';', nlhrReply.headers[i].szValue)));
      end;

      case nlhrReply.resultCode of

        // if the receieved code is 200 OK
        200:
        begin
          // save the retrieved data
          Result := nlhrReply.pData;
          if nlhrReply.dataLength = 0 then
            Result := ''; // DATA_EMPTY;
        end;

        // if the receieved code is 302 Moved, Found, etc
        // workaround for url forwarding
        302:
        begin
          // get the url for the new location and save it to szInfo
          // look for the reply header "Location"
          for i := 0 to nlhrReply.headersCount - 1 do
          begin
            if nlhrReply.headers[i].szName = 'Location' then
            begin
              // if location url doesn't contain host name, we should add it
              szHost := Copy(szUrl, Pos('://', szUrl) + 3, LastDelimiter('/', szUrl) - Pos('://', szUrl) - 3);
              if Pos(szHost, nlhrReply.headers[i].szValue) = 0 then
              begin
                if (RightStr(szHost, 1) <> '/') and (LeftStr(nlhrReply.headers[i].szValue, 1) <> '/') then
                  szHost := szHost + '/';
                szRedirUrl := 'http://' + szHost + nlhrReply.headers[i].szValue;
              end
              else
                szRedirUrl := nlhrReply.headers[i].szValue;
              nlhr.szUrl := PChar(szRedirUrl);

              Result := HTTP_NL_Get(szRedirUrl);
              CallService(MS_NETLIB_FREEHTTPREQUESTSTRUCT, 0, lParam(nlhrReply));
              Exit;
            end;
          end;
        end;

          // return error code if the receieved code is neither 200 OK nor 302 Moved
        else
        begin
          // store the error code
          Result := nlhrReply.pData;
        end;

      end;

    end
    // if the data does not downloaded successfully (ie. disconnected), then return 1000 as error code
    else
    begin
      // store the error code
      Result := 'NetLib error occurred!';
    end;
  end;
end;

 // =============================================================================
 // function to post picture to the site
 // szUrl = URL of the webpage to be retrieved
 // szData = data to be posted
 // return value = HTML string
 // global var used: vk_hNetlibUser = contains handle to netlibuser created
 // -----------------------------------------------------------------------------
function HTTP_NL_PostPicture(szUrl: string; szData: string; Boundary: string): string;
var
  nlhr:       TNETLIBHTTPREQUEST;
  nlhrReply:  PNETLIBHTTPREQUEST;
  szRedirUrl: string;
  szHost:     string;
  i:          integer;
begin
  Result := ' ';

  // create 'storage' for cookies
  if not Assigned(CookiesGlobal) then
  begin
    CookiesGlobal := TStringList.Create;
    CookiesGlobal.Sorted := True;
    CookiesGlobal.Duplicates := dupIgnore;
    CookiesGlobal.Delimiter := ' ';
  end;

  FillChar(nlhr, sizeof(nlhr), 0);
  nlhrReply := @nlhr;

  // initialize the netlib request
  nlhr.cbSize := sizeof(nlhr);
  nlhr.requestType := REQUEST_POST;
  nlhr.flags := NLHRF_DUMPASTEXT or NLHRF_HTTP11;
  nlhr.szUrl := PChar(szUrl);

  nlhr.pData := PChar(szData);
  nlhr.dataLength := Length(szData) + 1;

  nlhr.headersCount := 5;
  SetLength(nlhr.headers, 5);
  nlhr.headers[0].szName := 'User-Agent';
  nlhr.headers[0].szValue := 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';
  nlhr.headers[1].szName := 'Connection';
  nlhr.headers[1].szValue := 'keep-alive';
  nlhr.headers[2].szName := 'Keep-Alive';
  nlhr.headers[2].szValue := '300';
  nlhr.headers[3].szName := 'Cookie';
  nlhr.headers[3].szValue := PChar(CookiesGlobal.DelimitedText);
  nlhr.headers[4].szName := 'Content-Type';
  nlhr.headers[4].szValue := PChar('multipart/form-data; boundary=' + Boundary);

  while (Result = ' ') do
  begin

    // fast exit when Miranda terminating
    if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) then
      Exit;

    Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_Post) Dowloading page: ' + szUrl));
    // download the page
    nlhrReply := PNETLIBHTTPREQUEST(PluginLink^.CallService(MS_NETLIB_HTTPTRANSACTION, Windows.WParam(vk_hNetlibUser), Windows.lParam(@nlhr)));
    if (nlhrReply <> nil) then
    begin
      // read cookies & store it
      for i := 0 to nlhrReply.headersCount - 1 do
      begin
        // read cookie
        if nlhrReply.headers[i].szName = 'Set-Cookie' then
          CookiesGlobal.Add(Copy(nlhrReply.headers[i].szValue, 0, Pos(';', nlhrReply.headers[i].szValue)));
      end;

      case nlhrReply.resultCode of

        // if the receieved code is 200 OK
        200:
        begin
          if nlhrReply.dataLength = 0 then
            // DATA_EMPTY
            Result := ''
          else
            // save the retrieved data
            Result := nlhrReply.pData;
        end;

        // if the receieved code is 302 Moved, Found, etc
        // workaround for url forwarding
        302:
        begin
          Netlib_Log(vk_hNetlibUser, PChar('Code302: ' + szRedirUrl));
          // get the url for the new location and save it to szInfo
          // look for the reply header "Location"
          for i := 0 to nlhrReply.headersCount - 1 do
          begin
            if nlhrReply.headers[i].szName = 'Location' then
            begin
              // if location url doesn't contain host name, we should add it
              szHost := Copy(szUrl, Pos('://', szUrl) + 3, LastDelimiter('/', szUrl) - Pos('://', szUrl) - 3);
              if Pos(szHost, nlhrReply.headers[i].szValue) = 0 then
              begin
                if (RightStr(szHost, 1) <> '/') and (LeftStr(nlhrReply.headers[i].szValue, 1) <> '/') then
                  szHost := szHost + '/';
                szRedirUrl := 'http://' + szHost + nlhrReply.headers[i].szValue;
              end
              else
                szRedirUrl := nlhrReply.headers[i].szValue;

              nlhr.szUrl := PChar(szRedirUrl);

              Result := HTTP_NL_Get(szRedirUrl);
              CallService(MS_NETLIB_FREEHTTPREQUESTSTRUCT, 0, lParam(nlhrReply));
              Exit;
            end;
          end;
        end;

          // return error code if the receieved code is neither 200 OK nor 302 Moved
        else
        begin
          // store the error code
          Result := nlhrReply.pData;
        end;

      end;

    end
    // if the data does not downloaded successfully (ie. disconnected), then return 1000 as error code
    else
    begin
      // store the error code
      Result := 'NetLib error occurred!';
    end;
  end;
end;


 // =============================================================================
 // function to download a picture and save it to the file
 // szUrl = URL of the picture to be retrieved
 // szFileName = result file
 // return value = result of download (true/false)
 // global var used: vk_hNetlibUser = contains handle to netlibuser created
 // -----------------------------------------------------------------------------
function HTTP_NL_GetPicture(szUrl, szFileName: string): boolean;
var
  nlhr:         TNETLIBHTTPREQUEST;
  nlhrReply:    PNETLIBHTTPREQUEST;
  hFile:        THandle;
  BytesWritten: DWord;
begin
  Result := False;

  // create 'storage' for cookies
  if not Assigned(CookiesGlobal) then
  begin
    CookiesGlobal := TStringList.Create;
    CookiesGlobal.Sorted := True;
    CookiesGlobal.Duplicates := dupIgnore;
    CookiesGlobal.Delimiter := ' ';
  end;

  FillChar(nlhr, sizeof(nlhr), 0);
  nlhrReply := @nlhr;

  // initialize the netlib request
  nlhr.cbSize := sizeof(nlhr);
  nlhr.requestType := REQUEST_GET;
  nlhr.flags := NLHRF_NODUMP and NLHRF_GENERATEHOST and NLHRF_SMARTAUTHHEADER;
  nlhr.szUrl := PChar(szUrl);

  nlhr.headersCount := 5;
  SetLength(nlhr.headers, 5);
  nlhr.headers[0].szName := 'User-Agent';
  nlhr.headers[0].szValue := 'Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.1)';
  nlhr.headers[1].szName := 'Connection';
  nlhr.headers[1].szValue := 'Keep-Alive';
  nlhr.headers[2].szName := 'Cache-Control';
  nlhr.headers[2].szValue := 'no-cache';
  nlhr.headers[3].szName := 'Pragma';
  nlhr.headers[3].szValue := 'no-cache';
  nlhr.headers[4].szName := 'Cookie';
  nlhr.headers[4].szValue := PChar(CookiesGlobal.DelimitedText);

  // fast exit when Miranda terminating
  if (PluginLink^.CallService(MS_SYSTEM_TERMINATED, 0, 0) = 1) then
    Exit;

  Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_GetPicture) Dowloading file: ' + szUrl));
  // download the page
  nlhrReply := PNETLIBHTTPREQUEST(PluginLink^.CallService(MS_NETLIB_HTTPTRANSACTION, Windows.WParam(vk_hNetlibUser), Windows.lParam(@nlhr)));
  if (nlhrReply <> nil) then
  begin
    if (nlhrReply.resultCode = 200) then
    begin

      if nlhrReply.dataLength > 0 then // not empty
      begin
        // create directory first
        Windows.CreateDirectory(PChar(ExtractFileDir(szFileName)), nil);
        // write file
        hFile := Windows.CreateFile(PChar(szFileName),
          GENERIC_WRITE,
          FILE_SHARE_WRITE,
          nil,
          CREATE_ALWAYS, // overwrite file, if exists
          FILE_ATTRIBUTE_NORMAL, 0);
        if hFile <> INVALID_HANDLE_VALUE then
        begin
          Windows.WriteFile(hFile, nlhrReply.pData^, nlhrReply.dataLength, BytesWritten, nil);
          CloseHandle(hFile);
          Netlib_Log(vk_hNetlibUser, PChar('(HTTP_NL_GetPicture) ... file ' + szFileName + ' saved successfully'));
        end;
        Result := True;
      end;
    end;
    CallService(MS_NETLIB_FREEHTTPREQUESTSTRUCT, 0, lParam(nlhrReply));
  end;
end;

begin
end.
