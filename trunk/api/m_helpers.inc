{$ifdef M_API_UNIT}

function CreateVersionString(version:dword;buf:PChar):PChar;
function CreateVersionStringPlugin(pluginInfo:PPluginInfo;buf:PChar):PChar;

{$else}

function CreateVersionString(version:dword;buf:PChar):PChar;
var
  vers:array [0..3] of integer;
begin
  vers[0]:=(version shr 24) and $FF;
  vers[1]:=(version shr 16) and $FF;
  vers[2]:=(version shr  8) and $FF;
  vers[3]:=version and $FF;
  wvsprintf(buf,'%d.%d.%d.%d',@vers);
	result:=buf;
end;

function CreateVersionStringPlugin(pluginInfo:PPluginInfo;buf:PChar):PChar;
begin
	result:=CreateVersionString(pluginInfo^.version,buf);
end;

{$endif}

{$ifdef M_API_UNIT}

function PLUGIN_MAKE_VERSION(a,b,c,d: Cardinal): int;
function PLUGIN_CMP_VERSION(verA: LongInt; verB: LongInt): int;

{$else}

function PLUGIN_MAKE_VERSION(a,b,c,d: Cardinal): int;
begin
  Result := (a shl 24) or (b shl 16) or (c shl 8) or d;
end;

function PLUGIN_CMP_VERSION(verA: LongInt; verB: LongInt): int;
begin
  Result := 0;
  { could be used to compare for severity of age for positive values, if a<b
  results are minus values, 0 for equal, positive if a is newer }
  Inc(Result, (verA and $FF) - (verB and $FF));
  Inc(Result, (verA and $FF00) - (verB and $FF00));
  Inc(Result, (verA and $FF0000) - (verB and $FF0000));
  Inc(Result, (verA and $FF000000) - (verB and $FF000000));
end;

{$endif}

{$ifdef M_SYSTEM}
  {$ifdef M_API_UNIT}

function CallService(const szService: PChar; wParam: WPARAM; lParam: LPARAM): int;
function HookEvent(const szHook: PChar; hook_proc: TMIRANDAHOOK): int;
function CreateServiceFunction(const szName: PChar; const MirandaService: TMIRANDASERVICE): int;

  {$else}

function CallService(const szService: PChar; wParam: WPARAM; lParam: lParam): int;
begin
  Result := PluginLink^.CallService(szService, wParam, lParam);
end;

function HookEvent(const szHook: PChar; hook_proc: TMIRANDAHOOK): int;
begin
  Result := PluginLink^.HookEvent(szHook, @hook_proc);
end;

function CreateServiceFunction(const szName: PChar; const MirandaService: TMIRANDASERVICE): int;
begin
  Result := PluginLink^.CreateServiceFunction(szName, @MirandaService);
end;

  {$endif}

{$endif}


{$ifdef M_DATABASE}

  {$ifdef M_API_UNIT}

function DBGetContactSettingByte(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; errorValue: Integer): Integer;
function DBGetContactSettingWord(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; errorValue: Integer): Integer;
function DBGetContactSettingDword(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; errorValue: Integer): Integer;
function DBGetContactSetting(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; dbv: PDBVARIANT): Integer;
function DBGetContactSettingStr(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; dbv: PDBVARIANT): Integer;

function DBReadStringLength(hContact:THANDLE;szModule:PChar;szSetting:PChar):integer;
function DBReadString (hContact:THANDLE;szModule:PChar;szSetting:PChar;
         default:PChar=nil;enc:integer=DBVT_ASCIIZ):PChar;
function DBReadUnicode(hContact:THANDLE;szModule:PAnsiChar;szSetting:PAnsiChar;default:PWideChar=nil):PWideChar; // added by LA

function DBFreeVariant(dbv: PDBVARIANT): integer;
function DBDeleteContactSetting(hContact: THandle; const szModule: PChar; const szSetting: PChar): Integer;
function DBWriteContactSettingByte(hContact: THandle; const szModule: PChar; const szSetting: PChar; val: Byte): Integer;
function DBWriteContactSettingWord(hContact: THandle; const szModule: PChar; const szSetting: PChar; val: Word): Integer;
function DBWriteContactSettingDWord(hContact: THandle; const szModule: PChar; const szSetting: PChar; val: LongInt): Integer;
function DBWriteContactSettingString(hContact: THandle; const szModule: PChar; const szSetting: PChar; const val: PChar): Integer;
function DBWriteContactSettingUnicode(hContact: THandle; const szModule: PChar; const szSetting: PChar; const val: PWideChar): Integer;
// added by LA
function DBWriteContactSettingBlob(hContact: THandle; const szModule: PChar; const szSetting: PChar; const val: PChar; const cbVal:Integer): Integer;

  {$else}

function DBGetContactSettingByte(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; errorValue: Integer): Integer;
var
  dbv: TDBVARIANT;
  cgs: TDBCONTACTGETSETTING;
begin
  cgs.szModule  := szModule;
  cgs.szSetting := szSetting;
  cgs.pValue    := @dbv;
  If PluginLink^.CallService(MS_DB_CONTACT_GETSETTING, hContact, lParam(@cgs)) <> 0 then
    Result := ErrorValue
  else
    Result := dbv.bVal;
end;

function DBGetContactSettingWord(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; errorValue: Integer): Integer;
var
  dbv: TDBVARIANT;
  cgs: TDBCONTACTGETSETTING;
begin
  cgs.szModule  := szModule;
  cgs.szSetting := szSetting;
  cgs.pValue    := @dbv;
  If PluginLink^.CallService(MS_DB_CONTACT_GETSETTING, hContact, lParam(@cgs)) <> 0 then
    Result := ErrorValue
  else
    Result := dbv.wVal;
end;

function DBGetContactSettingDword(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; errorValue: Integer): Integer;
var
  dbv: TDBVARIANT;
  cgs: TDBCONTACTGETSETTING;
begin
  cgs.szModule  := szModule;
  cgs.szSetting := szSetting;
  cgs.pValue    := @dbv;
  If PluginLink^.CallService(MS_DB_CONTACT_GETSETTING, hContact, lParam(@cgs)) <> 0 then
    Result := ErrorValue
  else
    Result := dbv.dVal;
end;

function DBGetContactSetting(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; dbv: PDBVARIANT): Integer;
var
  cgs: TDBCONTACTGETSETTING;
begin
  cgs.szModule  := szModule;
  cgs.szSetting := szSetting;
  cgs.pValue    := dbv;
  Result := PluginLink^.CallService(MS_DB_CONTACT_GETSETTING, hContact, lParam(@cgs));
end;

function DBGetContactSettingStr(hContact: THandle;
    const szModule: PChar; const szSetting: PChar; dbv: PDBVARIANT): Integer;
var
  cgs: TDBCONTACTGETSETTING;
begin
  cgs.szModule  := szModule;
  cgs.szSetting := szSetting;
  cgs.pValue    := dbv;
  Result := PluginLink^.CallService(MS_DB_CONTACT_GETSETTING_STR, hContact, lParam(@cgs));
end;

{* the following function taken from dbsettings.pas }
function DBReadStringLength(hContact:THANDLE;szModule:PChar;szSetting:PChar):integer;
var
  cgs:TDBCONTACTGETSETTING;
  dbv:TDBVARIANT;
  i:integer;
begin
  cgs.szModule :=szModule;
  cgs.szSetting:=szSetting;
  cgs.pValue   :=@dbv;
  i:=PluginLink^.CallService(MS_DB_CONTACT_GETSETTING_STR,hContact,lParam(@cgs));
  if (i<>0) or (dbv.szVal.a=nil) or (dbv.szVal.a^=#0) then
    result:=0
  else
    result:=lstrlen(dbv.szVal.a);
  if i=0 then
    DBFreeVariant(@dbv);
end;

function DBReadString(hContact:THANDLE;szModule:PChar;szSetting:PChar;
         default:PChar=nil;enc:integer=DBVT_ASCIIZ):PChar;
var
  cgs:TDBCONTACTGETSETTING;
  dbv:TDBVARIANT;
  i:integer;
begin
  cgs.szModule :=szModule;
  cgs.szSetting:=szSetting;
  cgs.pValue   :=@dbv;
  dbv._type    :=enc;
  i:=PluginLink^.CallService(MS_DB_CONTACT_GETSETTING_STR,hContact,lParam(@cgs));
  if i=0 then
    default:=dbv.szVal.a;
  if (default=nil) or (default^=#0) then
    result:=nil
  else
  begin
    result:=mmi.malloc(lstrlen(default)+1);
    if result<>nil then
      lstrcpy(result,default);
  end;
  if i=0 then
    DBFreeVariant(@dbv);
end;

function DBReadUnicode(hContact:THANDLE;szModule:PAnsiChar;szSetting:PAnsiChar;default:PWideChar=nil):PWideChar;
var
  cgs:TDBCONTACTGETSETTING;
  dbv:TDBVARIANT;
  i:integer;
begin
  cgs.szModule :=szModule;
  cgs.szSetting:=szSetting;
  cgs.pValue   :=@dbv;
  dbv._type    :=DBVT_WCHAR;
  i:=PluginLink^.CallService(MS_DB_CONTACT_GETSETTING_STR,hContact,lParam(@cgs));
  if i=0 then
    default:=dbv.szVal.w;
  if (default=nil) or (default^=#0) then
    result:=nil
  else
  begin
    result:=mmi.malloc((lstrlenw(default)+1)*SizeOf(WideChar));
    if result<>nil then
      lstrcpyw(result,default);
  end;
  if i=0 then
    DBFreeVariant(@dbv);
end;
{* functions above taken from dbsettings.pas file} 

function DBFreeVariant(dbv: PDBVARIANT): Integer;
begin
  Result := PluginLink^.CallService(MS_DB_CONTACT_FREEVARIANT, 0, lParam(dbv));
end;

function DBDeleteContactSetting(hContact: THandle; const szModule: PChar; const szSetting: PChar): Integer;
var
  cgs: TDBCONTACTGETSETTING;
begin
  cgs.szModule  := szModule;
  cgs.szSetting := szSetting;
  Result := PluginLink^.CallService(MS_DB_CONTACT_DELETESETTING, hContact, lParam(@cgs));
end;

function DBWriteContactSettingByte(hContact: THandle; const szModule: PChar; const szSetting: PChar; val: Byte): Integer;
var
  cws: TDBCONTACTWRITESETTING;
begin
  cws.szModule    := szModule;
  cws.szSetting   := szSetting;
  cws.value._type := DBVT_BYTE;
  cws.value.bVal  := Val;
  Result := PluginLink^.CallService(MS_DB_CONTACT_WRITESETTING, hContact, lParam(@cws));
end;

function DBWriteContactSettingWord(hContact: THandle; const szModule: PChar; const szSetting: PChar; val: Word): Integer;
var
  cws: TDBCONTACTWRITESETTING;
begin
  cws.szModule    := szModule;
  cws.szSetting   := szSetting;
  cws.value._type := DBVT_WORD;
  cws.value.wVal  := Val;
  Result := PluginLink^.CallService(MS_DB_CONTACT_WRITESETTING, hContact, lParam(@cws));
end;

function DBWriteContactSettingDWord(hContact: THandle; const szModule: PChar; const szSetting: PChar; val: LongInt): Integer;
var
  cws: TDBCONTACTWRITESETTING;
begin
  cws.szModule    := szModule;
  cws.szSetting   := szSetting;
  cws.value._type := DBVT_DWORD;
  cws.value.dVal  := Val;
  Result := PluginLink^.CallService(MS_DB_CONTACT_WRITESETTING, hContact, lParam(@cws));
end;

function DBWriteContactSettingString(hContact: THandle; const szModule: PChar; const szSetting: PChar; const val: PChar): Integer;
var
  cws: TDBCONTACTWRITESETTING;
begin
  cws.szModule     := szModule;
  cws.szSetting    := szSetting;
  cws.value._type  := DBVT_ASCIIZ;
  cws.value.szVal.a:= Val;
  Result := PluginLink^.CallService(MS_DB_CONTACT_WRITESETTING, hContact, lParam(@cws));
end;

function DBWriteContactSettingUnicode(hContact: THandle; const szModule: PChar; const szSetting: PChar; const val: PWideChar): Integer;
var
  cws: TDBCONTACTWRITESETTING;
begin
  cws.szModule     := szModule;
  cws.szSetting    := szSetting;
  cws.value._type  := DBVT_WCHAR;
  cws.value.szVal.w:= Val;
  Result := PluginLink^.CallService(MS_DB_CONTACT_WRITESETTING, hContact, lParam(@cws));
end;

// added by LA
function DBWriteContactSettingBlob(hContact: THandle; const szModule: PChar; const szSetting: PChar; const val: PChar; const cbVal:Integer): Integer;
var
  cws: TDBCONTACTWRITESETTING;
begin
  cws.szModule        := szModule;
  cws.szSetting       := szSetting;
  cws.value._type      := DBVT_BLOB;
  cws.value.szVal.a   := Val;
  cws.value.cpbVal    := cbVal;
  Result := PluginLink^.CallService(MS_DB_CONTACT_WRITESETTING, hContact, lParam(@cws));
end;

  {$endif}

{$endif}

{$ifdef M_NETLIB}

  {$ifdef M_API_UNIT}

function Netlib_CloseHandle(Handle: THandle): int;
function Netlib_GetBase64DecodedBufferSize(const cchEncoded: int): int;
function Netlib_GetBase64EncodedBufferSize(const cbDecoded: int): int;
function Netlib_Send(hConn: THandle; const buf: PChar; len: int; flags: int): int;
function Netlib_Recv(hConn: THandle; const buf: PChar; len: int; flags: int): int;
procedure Netlib_Log(hNetLib: THandle; const sz: PChar);

  {$else}

function Netlib_CloseHandle(Handle: THandle): int;
begin
  Result := PluginLink^.CallService(MS_NETLIB_CLOSEHANDLE, Handle, 0);
end;

function Netlib_GetBase64DecodedBufferSize(const cchEncoded: int): int;
begin
  Result := (cchEncoded shr 2) * 3;
end;

function Netlib_GetBase64EncodedBufferSize(const cbDecoded: int): int;
begin
  Result := (cbDecoded * 4+11) div 12*4+1;
end;

function Netlib_Send(hConn: THandle; const buf: PChar; len: int; flags: int): int;
var
  nlb: TNETLIBBUFFER;
begin
  nlb.buf   := buf;
  nlb.len   := len;
  nlb.flags := flags;
  Result := PluginLink^.CallService(MS_NETLIB_SEND, wParam(hConn), lParam(@nlb));
end;

function Netlib_Recv(hConn: THandle; const buf: PChar; len: int; flags: int): int;
var
  nlb: TNETLIBBUFFER;
begin
  nlb.buf   := buf;
  nlb.len   := len;
  nlb.flags := flags;
  Result := PluginLink^.CallService(MS_NETLIB_RECV, wParam(hConn), lParam(@nlb));
end;

procedure Netlib_Log(hNetLib: THandle; const sz: PChar);
begin
  PluginLink^.CallService(MS_NETLIB_LOG, hNetLib, lParam(sz));
end;

  {$endif}

{$endif}

{$ifdef M_UTILS}

  {$ifdef M_API_UNIT}

function WindowList_Add(hList: THandle; hWnd: HWND; hContact: THandle): int;
function WindowList_Remove(hList: THandle; hWnd: THandle): int;
function WindowList_Find(hList: THandle; hContact: THandle): int;
function WindowList_Broadcast(hList: THandle; message: int; wParam: WPARAM; lParam: LPARAM): int;
function Utils_SaveWindowPosition(hWnd: THandle; hContact: THandle; const szModule, szNamePrefix: PChar): int;
function Utils_RestoreWindowPosition(hWnd: THandle; hContact: THandle; Flags: int; const szModule, szNamePrefix: PChar): int;

  {$else}

function WindowList_Add(hList: THandle; hWnd: hWnd; hContact: THandle): int;
var
  wle: TWINDOWLISTENTRY;
begin
  wle.hList    := hList;
  wle.hWnd     := hWnd;
  wle.hContact := hContact;
  Result := PluginLink^.CallService(MS_UTILS_ADDTOWINDOWLIST, 0, lParam(@wle));
end;

function WindowList_Remove(hList: THandle; hWnd: THandle): int;
begin
  Result := PluginLink^.CallService(MS_UTILS_REMOVEFROMWINDOWLIST, hList, hWnd);
end;

function WindowList_Find(hList: THandle; hContact: THandle): int;
begin
  Result := PluginLink^.CallService(MS_UTILS_FINDWINDOWINLIST, hList, hContact);
end;

function WindowList_Broadcast(hList: THandle; message: int; wParam: WPARAM; lParam: LPARAM): int;
var
  msg: TMSG;
begin
  msg.message := message;
  msg.wParam  := wParam;
  msg.lParam  := lParam;
  Result := PluginLink^.CallService(MS_UTILS_BROADCASTTOWINDOWLIST, hList, Integer(@Msg));
end;

function Utils_SaveWindowPosition(hWnd: THandle; hContact: THandle; const szModule, szNamePrefix: PChar): int;
var
  swp: TSAVEWINDOWPOS;
begin
  swp.hWnd     := hWnd;
  swp.hContact := hContact;
  swp.szModule := szModule;
  swp.szNamePrefix := szNamePrefix;
  Result := PluginLink^.CallService(MS_UTILS_SAVEWINDOWPOSITION, 0, lParam(@swp));
end;

function Utils_RestoreWindowPosition(hWnd: THandle; hContact: THandle; Flags: int; const szModule, szNamePrefix: PChar): int;
var
  swp: TSAVEWINDOWPOS;
begin
  swp.hWnd         := hWnd;
  swp.hContact     := hContact;
  swp.szModule     := szModule;
  swp.szNamePrefix := szNamePrefix;
  Result := PluginLink^.CallService(MS_UTILS_RESTOREWINDOWPOSITION, Flags, lParam(@swp));
end;

  {$endif}

{$endif}

{$ifdef M_LANGPACK}

  {$ifdef M_API_UNIT}

function Translate(sz: PChar): PChar;
//function TranslateT(sz: PChar): PWideChar;
function Translatew(sz: PWideChar): PWideChar;
function TranslateString(sz: string): string;
function TranslateDialogDefault(hwndDlg: THandle): int;

  {$else}
(*
function TranslateT(sz: PChar): PWideChar;
var
  buf:pWideChar;
  len,l:integer;
begin
  l:=lstrlen(sz);
  len:=MultiByteToWideChar(CP_ACP,0,sz,l,NIL,0)+1;
  GetMem(buf,(len+1)*SizeOf(WideChar));
//  FillChar(dst^,(len+1)*SizeOf(WideChar),0);
  MultiByteToWideChar(CP_ACP,0,sz,l,buf,len+1);
  { the return value maybe NULL(0) -- it's upto the caller to know if the allocated
  string has to be removed from the DLL heap, this has little to do with Miranda,
  but if a dynamic string is passed and a return string is used -- the dynamic
  string is lost -- be careful, lazy? use TranslateString (note it's slower) }
  Result := PWideChar(PluginLink^.CallService(MS_LANGPACK_TRANSLATESTRING, LANG_UNICODE, lParam(buf)));
  FreeMem(buf);
end;
*)
function TranslateW(sz: PWideChar): PWideChar;
begin
  { the return value maybe NULL(0) -- it's upto the caller to know if the allocated
  string has to be removed from the DLL heap, this has little to do with Miranda,
  but if a dynamic string is passed and a return string is used -- the dynamic
  string is lost -- be careful, lazy? use TranslateString (note it's slower) }
  Result := PWideChar(PluginLink^.CallService(MS_LANGPACK_TRANSLATESTRING, LANG_UNICODE, lParam(sz)));
end;

function Translate(sz: PChar): PChar;
begin
  { the return value maybe NULL(0) -- it's upto the caller to know if the allocated
  string has to be removed from the DLL heap, this has little to do with Miranda,
  but if a dynamic string is passed and a return string is used -- the dynamic
  string is lost -- be careful, lazy? use TranslateString (note it's slower) }
  Result := PChar(PluginLink^.CallService(MS_LANGPACK_TRANSLATESTRING, 0, lParam(sz)));
end;

function TranslateString(sz:string):string;
begin
  Result:=string(PChar(PluginLink^.CallService(MS_LANGPACK_TRANSLATESTRING,0,lparam(sz))));
end;

function TranslateDialogDefault(hwndDlg: THandle): int;
var
  lptd: TLANGPACKTRANSLATEDIALOG;
begin
  lptd.cbSize         := sizeof(lptd);
  lptd.flags          := 0;
  lptd.hwndDlg        := hwndDlg;
  lptd.ignoreControls := nil;
  Result := PluginLink^.CallService(MS_LANGPACK_TRANSLATEDIALOG, 0, lParam(@lptd));
end;

  {$endif}

{$endif}

{$ifdef M_PROTOCOLS}
  {$ifdef M_API_UNIT}

function CallContactService(hContact: THandle; const szProtoService: PChar; wParam: WPARAM; lParam: LPARAM): int;
function CallProtoService(const szModule, szService: PChar; wParam: WPARAM; lParam: LPARAM): int;

  {$else}

function CallContactService(hContact: THandle; const szProtoService: PChar; wParam: WPARAM; lParam: LPARAM): int;
var
  css: TCCSDATA;
begin
  css.hContact       := hContact;
  css.szProtoService := szProtoService;
  css.wParam         := wParam;
  css.lParam         := lParam;
  Result := PluginLink^.CallService(MS_PROTO_CALLCONTACTSERVICE, 0, Integer(@css));
end;

function CallProtoService(const szModule, szService: PChar; wParam: WPARAM; lParam: LPARAM): int;
var
  szStr: array[0..MAXMODULELABELLENGTH] of Char;
begin
  lstrcpy(szStr, szModule);
  lstrcat(szStr, szService);
  Result := PluginLink^.CallService(szStr, wParam, lParam);
end;

  {$endif}
{$endif}

{$ifdef M_PROTOMOD}
  {$ifdef M_API_UNIT}

function ProtoBroadcastAck(const szModule: PChar; hContact: THandle; type_: int; result_: int; hProcess: THandle; lParam: LPARAM): int;
function CreateProtoServiceFunction(const szModule, szService: PChar; serviceProc: TMIRANDASERVICE): int;

  {$else}

function ProtoBroadcastAck(const szModule: PChar; hContact: THandle; type_: int; result_: int; hProcess: THandle; lParam: LPARAM): int;
var
  ack: TACKDATA;
begin
  ack.cbSize   := sizeof(TACKDATA);
  ack.szModule := szModule;
  ack.hContact := hContact;
  ack._type    := type_;
  ack._result  := result_;
  ack.hProcess := hProcess;
  ack.lParam   := lParam;
  Result := PluginLink^.CallService(MS_PROTO_BROADCASTACK, 0, Integer(@ack));
end;

function CreateProtoServiceFunction(const szModule, szService: PChar; serviceProc: TMIRANDASERVICE): int;
var
  szStr: array[0..MAXMODULELABELLENGTH] of Char;
begin
  lstrcpy(szStr, szModule);
  lstrcat(szStr, szService);
  Result := PluginLink^.CreateServiceFunction(szStr, @serviceProc);
end;

  {$endif}

{$endif}

{$ifdef M_SKIN}

  {$ifdef M_API_UNIT}

function LoadSkinnedIcon(id: int): THandle;
function LoadSkinnedProtoIcon(const szProto: PChar; status: int): THandle;
function SkinAddNewSound(const name, description, defaultFile: PChar): int;
function SkinPlaySound (const name: PChar): int;

  {$else}

function LoadSkinnedIcon(id: int): THandle;
begin
  Result := PluginLink^.CallService(MS_SKIN_LOADICON, id, 0);
end;

function LoadSkinnedProtoIcon(const szProto: PChar; status: int): THandle;
begin
  Result := PluginLink^.CallService(MS_SKIN_LOADPROTOICON, wParam(szProto), status);
end;

function SkinAddNewSound(const name, description, defaultFile: PChar): int;
var
  ssd: TSKINSOUNDDESC;
begin
  ssd.cbSize         := sizeof(ssd);
  ssd.pszName        := name;
  ssd.pszDescription := description;
  ssd.pszDefaultFile := defaultFile;
  Result := PluginLink^.CallService(MS_SKIN_ADDNEWSOUND, 0, lParam(@ssd));
end;

function SkinPlaySound (const name: PChar): int;
begin
  Result := PluginLink^.CallService(MS_SKIN_PLAYSOUND, 0, lParam(name));
end;

  {$endif}

{$endif}
