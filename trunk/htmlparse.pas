unit htmlparse;

interface

uses
  SysUtils,
  Classes;

  function TextBetweenInc(WholeText: string; BeforeText: string; AfterText: string): string;
  function TextBetween(WholeText: string; BeforeText: string; AfterText: string): string;
  function FindLine(Pattern: string; List: TStringList; StartAt: Integer): Integer;
  function FindFullLine(Line: string; List: TStringList; StartAt: Integer): Integer;
  function LastPos(ASearch: string; AText: string): Integer;
  function URLEncode(const AStr: string): string;
  function URLDecode(const AStr: string): string;  
  function HTMLRemoveTags(const Value: string): string;
  function HTMLDecode(const Value: string): string;
  function TextBetweenTagsInc(WholeText, Tag: string): string;
  function TextBetweenTagsAttrInc(WholeText, Tag, AttrName, AttrValue: string): string;
  function ReplaceLink(WholeText: string): string;
  function RemoveDuplicates(WholeText: string): string;
  function PosEx(Const SubStr, S: String; Offset: Cardinal = 1): Integer;  


var
  RemainingText: string;

implementation

// ****************************************************************************
// String functions
// ****************************************************************************

{    Returns the text between BeforeText and AfterText (including these two strings),
     It takes the first AfterText occurence found after the position of BeforeText  }
function TextBetweenInc(WholeText: string; BeforeText: string; AfterText: string): string;
var
  FoundPos: Integer;
  WorkText: string;
begin
  RemainingText := WholeText;
  Result := '';
  FoundPos := Pos(BeforeText, WholeText);
  if FoundPos = 0 then
    Exit;
  WorkText := Copy(WholeText, FoundPos, Length(WholeText));
  FoundPos := Pos(AfterText, WorkText);
  if FoundPos = 0 then
    Exit;
  Result := Copy(WorkText, 1, FoundPos - 1 + Length(AfterText));
  RemainingText := Copy(WorkText, FoundPos + Length(AfterText), Length(WorkText));
end;


{    Returns the text between BeforeText and AfterText (without these two strings),
     It takes the first AfterText occurence found after the position of BeforeText
     Function created by Antoine Potten}
function TextBetween(WholeText: string; BeforeText: string; AfterText: string): string;
var
  FoundPos: Integer;
  WorkText: string;
begin
  RemainingText := WholeText;
  Result := '';
  FoundPos := Pos(BeforeText, WholeText);
  if FoundPos = 0 then
    Exit;
  WorkText := Copy(WholeText, FoundPos + Length(BeforeText), Length(WholeText));
  FoundPos := Pos(AfterText, WorkText);
  if FoundPos = 0 then
    Exit;
  Result := Copy(WorkText, 1, FoundPos - 1);
  RemainingText := Copy(WorkText, FoundPos + Length(AfterText), Length(WorkText));
end;


{    Searches for a starting from defined position
     Function taken from StrUtils module   }
function PosEx(Const SubStr, S: String; Offset: Cardinal = 1): Integer;
var
  I,X: Integer;
  Len, LenSubStr: Integer;
begin
  If Offset = 1 Then
    Result := Pos(SubStr, S)
  Else
  begin
    I := Offset;
    LenSubStr := Length(SubStr);
    Len := Length(S) - LenSubStr + 1;
    While I <= Len Do
    begin
      If S[I] = SubStr[1] Then
      begin
        X := 1;
        While (X < LenSubStr) And (S[I + X] = SubStr[X + 1]) Do
          Inc(X);
        If (X = LenSubStr) Then
        begin
          Result := I;
          Exit;
        End;
      End;
      Inc(I);
    End;
    Result := 0;
  End;
End;


function TextBetweenTagsInc(WholeText, Tag: string): string;
var
  WorkText: string;
  BlockStart, BlockEnd, TagStart: integer;
begin
  Result := '';
  Tag := LowerCase(Tag);
  BlockStart := Pos('<'+Tag, LowerCase(WholeText));
  if BlockStart > 0 then
  begin
    BlockEnd := PosEx('</'+Tag, LowerCase(WholeText), BlockStart);
    if BlockEnd > 0 then
    begin
      TagStart := 1;
      while TagStart > 0 do
      begin
        WorkText := Copy(WholeText, BlockStart, BlockEnd - BlockStart + Length('</'+Tag) + 1);
        TagStart := PosEx('<'+Tag, LowerCase(WorkText), TagStart + 1);
        BlockEnd := PosEx('</'+Tag, LowerCase(WholeText), BlockEnd + 1);
      end;
      Result := WorkText;
    end;
  end;
end;

function TextBetweenTagsAttrInc(WholeText, Tag, AttrName, AttrValue: string): string;
var
  WorkText: string;
  BlockStart, BlockEnd, TagStart, TagEnd: integer;
begin
  Result := '';
  Tag := LowerCase(Tag);
  AttrName := LowerCase(AttrName);
  AttrValue := LowerCase(AttrValue);
  BlockStart := Pos('<'+Tag, LowerCase(WholeText));
  while BlockStart > 0 do
  begin
    TagEnd := PosEx('>', WholeText, BlockStart);
    WorkText := Copy(WholeText, BlockStart, TagEnd - BlockStart + 1);
    if (Pos(AttrName + '=' + AttrValue, LowerCase(WorkText)) > 0) or
       (Pos(AttrName + '="' + AttrValue + '"', LowerCase(WorkText)) > 0) or
       (Pos(AttrName + '=''' + AttrValue + '''', LowerCase(WorkText)) > 0) then
       break;
    BlockStart := PosEx('<'+Tag, LowerCase(WholeText), BlockStart + 1);
  end;

  if BlockStart > 0 then
  begin
    BlockEnd := PosEx('</'+Tag, LowerCase(WholeText), BlockStart);
    if BlockEnd > 0 then
    begin
      TagStart := 1;
      while TagStart > 0 do
      begin
        WorkText := Copy(WholeText, BlockStart, BlockEnd - BlockStart + Length('</'+Tag) + 1);
        TagStart := PosEx('<'+Tag, LowerCase(WorkText), TagStart + 1);
        BlockEnd := PosEx('</'+Tag, LowerCase(WholeText), BlockEnd + 1);
      end;
      Result := WorkText;
    end;
  end;
end;

function RemoveDuplicates(WholeText: string): string;
var DupBegin, DupEnd: Integer;
    DupText: String;
begin
  DupBegin := Pos('(', WholeText);
  while DupBegin > 0 do
  begin
    DupEnd := PosEx(')', WholeText, DupBegin);
    if DupEnd > 0 then
    begin
      DupText := Copy(WholeText, DupBegin, DupEnd-DupBegin+1);
      if PosEx(DupText, WholeText, DupEnd) > 0 then
        Delete(WholeText, DupBegin, DupEnd-DupBegin+2);
      DupBegin := PosEx('(', WholeText, DupBegin + 1);
    end
    else
      break;
  end;
  Result := WholeText;
end;

function ReplaceLink(WholeText: string): string;
var OpenTagStart, OpenTagEnd, CloseTagStart, LinkStart, LinkEnd: integer;
    LinkText: String;
begin
  OpenTagStart := Pos('<a', WholeText);
  while OpenTagStart > 0 do
  begin
    OpenTagEnd := PosEx('>', WholeText, OpenTagStart);
    CloseTagStart := PosEx('</a>', WholeText, OpenTagEnd);
    if (OpenTagEnd > 0) and (CloseTagStart > 0) then
    begin
      LinkText := Copy(WholeText, OpenTagStart, OpenTagEnd-OpenTagStart+1);
      LinkStart := Pos('href=', LinkText) + 5;
      LinkEnd := LinkStart + 1;
      while ((LinkText[LinkEnd]<>' ') or (LinkText[LinkEnd]<>'''') or (LinkText[LinkEnd]<>'"') or
            (LinkText[LinkEnd]<>'>')) and (LinkEnd<=Length(LinkText)) do
        Inc(LinkEnd);
      LinkText := Copy(LinkText, LinkStart, LinkEnd-LinkStart-1);
      if (LinkText[1] = '"') or (LinkText[1] = '''') then
        LinkText := Copy(LinkText, 2, Length(LinkText)-2);
      Insert(' (http://vkontakte.ru/'+LinkText+')', WholeText, CloseTagStart + 4);
      Delete(WholeText, CloseTagStart, 4);
      Delete(WholeText, OpenTagStart, OpenTagEnd-OpenTagStart+1);
    end
    else
      break;
    OpenTagStart := Pos('<a', WholeText);
  end;
  Result := WholeText;
end;

{    Searches for a partial text of one of the items of a TStringList
     Returns -1 if not found
     Function created by Antoine Potten   }
function FindLine(Pattern: string; List: TStringList; StartAt: Integer): Integer;
var
  i: Integer;
begin
  result := -1;
  if StartAt < 0 then
    StartAt := 0;
  for i := StartAt to List.Count-1 do
    if Pos(Pattern, List.Strings[i]) <> 0 then
    begin
      result := i;
      Break;
    end;
end;


{    Searches for a full text of one of the items of a TStringList
     Returns -1 if not found
     Function created by Antoine Potten  }
function FindFullLine(Line: string; List: TStringList; StartAt: Integer): Integer;
var
  i: Integer;
begin
  result := -1;
  if StartAt < 0 then
    StartAt := 0;
  for i := StartAt to List.Count-1 do
    if Line = List.Strings[i] then
    begin
      result := i;
      Break;
    end;
end;

{       Like the Pos function, but returns the last occurence instead of the first one
        Function created by Antoine Potten
}
function LastPos(ASearch: string; AText: string): Integer;
var
  CurPos, PrevPos: Integer;
begin
  PrevPos := 0;
  CurPos := Pos(ASearch, AText);
  while CurPos > 0 do
  begin
    if PrevPos = 0 then
      PrevPos := CurPos
    else
      PrevPos := PrevPos + CurPos + Length(ASearch) - 1;
    Delete(AText, 1, CurPos + Length(ASearch) - 1);
    CurPos := Pos(ASearch, AText);
  end;
  Result := PrevPos;
end;

function HTMLRemoveTags(const Value: string): string;
var
  i, Max: Integer;
begin
  result := '';
  Max := Length(Value);
  i := 1;
  while i <= Max do
  begin
    if Value[i] = '<' then
    begin
      repeat
        inc(i);
      until (i > Max) or (Value[i-1] = '>');
    end else
    begin
      result := result + Value[i];
      inc(i);
    end;
  end;
end;


function HTMLDecode(const Value: string): string;
const
  Symbols: array [32..255] of string = (
                        'nbsp',   '',       'quot',   '',       '',       '',       'amp',    '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    'lt',     '',       'gt',     '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       '',       '',       '',       '',       '',       '',       '',       '',       '',
    '',       'iexcl',  'cent',   'pound',  'curren', 'yen',    'brvbar', 'sect',   'uml',    'copy',
    'ordf',   'laquo',  'not',    'shy',    'reg',    'macr',   'deg',    'plusmn', 'sup2',   'sup3',
    'acute',  'micro',  'para',   'middot', 'cedil',  'sup1',   'ordm',   'raquo',  'frac14', 'frac12',
    'frac34', 'iquest', 'Agrave', 'Aacute', 'Acirc',  'Atilde', 'Auml',   'Aring',  'AElig',  'Ccedil',
    'Egrave', 'Eacute', 'Ecirc',  'Euml',   'Igrave', 'Iacute', 'Icirc',  'Iuml',   'ETH',    'Ntilde',
    'Ograve', 'Oacute', 'Ocirc',  'Otilde', 'Ouml',   'times',  'Oslash', 'Ugrave', 'Uacute', 'Ucirc',
    'Uuml',   'Yacute', 'THORN',  'szlig',  'agrave', 'aacute', 'acirc',  'atilde', 'auml',   'aring',
    'aelig',  'ccedil', 'egrave', 'eacute', 'ecirc',  'euml',   'igrave', 'iacute', 'icirc',  'iuml',
    'eth',    'ntilde', 'ograve', 'oacute', 'ocirc',  'otilde', 'ouml',   'divide', 'oslash', 'ugrave',
    'uacute', 'ucirc',  'uuml',   'yacute', 'thorn',  'yuml'
  );
var
  i, Max, p1, p2: Integer;
  Symbol: string;
  SymbolLength: Integer;

  function IndexStr(const AText: string; const AValues: array of string): Integer;
  var
    i: Integer;
  begin
    Result := -1;
    for i := Low(AValues) to High(AValues) do
      if AText = AValues[i] then
      begin
        Result := i;
        Break;
      end;
  end;

begin
  result := '';
  Max := Length(Value);
  i := 1;
  while i <= Max do
  begin
    if (Value[i] = '&') and (i + 1 < Max) then
    begin
      Symbol := copy(Value, i + 1, Max);
      p1 := Pos(' ', Symbol);
      p2 := Pos(';', Symbol);
      if (p2 > 0) and ((p2 < p1) xor (p1 = 0)) then
      begin
        Symbol := Copy(Symbol, 1, pos(';', Symbol) - 1);
        SymbolLength := Length(Symbol) + 1;
        if Symbol[1] <> '#' then
        begin
          Symbol := IntToStr(IndexStr(Symbol, Symbols) + 32);
        end else
          Delete(Symbol, 1, 1);
        Symbol := char(StrToIntDef(Symbol, 0));
        result := result + Symbol;
        inc(i, SymbolLength);
      end else
        result := result + Value[i];
    end else
      result := result + Value[i];
    inc(i);
  end;
end;

// ****************************************************************************
// URL encode function
// ****************************************************************************
function URLEncode(const AStr: string): string;
const
  NoConversion = ['0'..'9','A'..'Z','a'..'z'];
var
  Sp, Rp: PChar;
begin
  SetLength(Result, Length(AStr) * 3);
  Sp := PChar(AStr);
  Rp := PChar(Result);
  while Sp^ <> #0 do
  begin
    if Sp^ in NoConversion then
      Rp^ := Sp^
    else
    begin
      FormatBuf(Rp^, 3, '%%%.2x', 6, [Ord(Sp^)]);
      Inc(Rp,2);
    end;

    Inc(Rp);
    Inc(Sp);
  end;
  SetLength(Result, Rp - PChar(Result));
end;

// ****************************************************************************
// URL decode function
// ****************************************************************************
function URLDecode(const AStr: string): string;
const HexChar = '0123456789ABCDEF';
var I,J: integer;
begin
  SetLength(Result, Length(AStr));
  I:=1;
  J:=1;
  while (I <= Length(AStr)) do
  begin
    if (AStr[I] = '%') and (I+2 < Length(AStr)) then
    begin
      Result[J] := chr(((pred(Pos(AStr[I+1],HexChar)))shl 4) or (pred(Pos(AStr[I+2],HexChar))));
      Inc(I, 2);
    end
    else
      Result[J] := AStr[I];
    Inc(I);
    Inc(J);
  end;
  SetLength(Result, pred(J));
end;


end.
