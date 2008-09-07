unit m_memory;

interface

uses
  m_globaldefs;



type
  PDWORD = ^DWORD;

const
  // Значения констант BLOCK_ALLOCED и BLOCK_FREED уменьшены,
  // чтобы они попадали в диапазон Integer,
  // т.к. DWORD переназначен как Integer
  // Также явно указан тип для контроля
  BLOCK_ALLOCED: DWORD = $5BBABABA;
  BLOCK_FREED: DWORD  = $7EADBEEF;

  function mir_alloc(size: DWORD): Pointer;
  function CheckBlock(blk: Pointer): Boolean;
  procedure mir_free(ptr: Pointer);
  function mir_calloc(size: DWORD): Pointer;
  function mir_realloc(ptr: Pointer; size: DWORD): Pointer;

implementation

function CheckBlock(blk: Pointer): Boolean;
var
  p, pF1, pF2: PChar;
  size: DWORD;
begin
  Result := False;
  try
    p := PChar(blk) - 2*SizeOf(DWORD); // Приводим p к началу всего блока
    size := PDWORD(p)^;
    pF1 := p + SizeOf(DWORD);
    pF2 := p + 2*SizeOf(DWORD) + size;
    if (PDWORD(pF1)^ <> BLOCK_ALLOCED) or (PDWORD(pF2)^ <> BLOCK_ALLOCED) then
      // OutputDebugStringA('memory block is already deleted or corrupted' +#10#13)
    else
      Result := True;
  except
    // OutputDebugStringA('access violation during checking memory block' +#10#13);
  end;
end;


function  mir_alloc(size: DWORD): Pointer;
var
  p: PChar;
begin
  Result := nil;
  if size = 0 then
    Exit;
  GetMem(p, size + 3*SizeOf(DWORD));
  if p = nil then
  begin
    // OutputDebugStringA('memory overflow'+#10#13);
    Exit;
  end;
  PDWORD(p)^ := size;
  PDWORD(p + SizeOf(DWORD))^ := BLOCK_ALLOCED;
  Result := p + 2*SizeOf(DWORD);
  PDWORD(p + 2*SizeOf(DWORD) + size)^ := BLOCK_ALLOCED;
end;

function mir_calloc(size: DWORD): Pointer;
var
  p: PChar;
begin
  Result := nil;
  p := mir_alloc(size);
  if p <> nil then
     FillChar(p^, size, 0); // memset(p, 0, size);
  Result := p;
end;

function mir_realloc(ptr: Pointer; size: DWORD): Pointer;
var
  p: PChar;
begin
  Result := nil;

  if ptr <> nil then
  begin
     if Not CheckBlock(ptr) then
        Exit;
     p := PChar(ptr) - 2*SizeOf(DWORD);
  end
  else
      Exit;

  ReallocMem(p, size + sizeof(DWORD)*3); // p = ( char* )realloc( p, size + sizeof(DWORD)*3 );
  if p = nil then
  begin
    // OutputDebugStringA('memory overflow'+#10#13);
    Exit;
  end;

  PDWORD(p)^ := size;
  PDWORD(p + SizeOf(DWORD))^ := BLOCK_ALLOCED;
  Result := p + 2*SizeOf(DWORD);
  PDWORD(p + 2*SizeOf(DWORD) + size)^ := BLOCK_ALLOCED;
end;

procedure mir_free(ptr: Pointer);
var
  p: PChar;
  size: DWORD;
begin
  if ptr = nil then
    Exit;
  if not CheckBlock(ptr) then
    Exit;
  p := PChar(ptr) - 2*SizeOf(DWORD); // Приводим p к началу всего блока
  size := PDWORD(p)^;
  PDWORD(p + SizeOf(DWORD))^ := BLOCK_FREED;
  PDWORD(p + 2*SizeOf(DWORD) + size)^ := BLOCK_FREED;
  FreeMem(p);
end;

end.

