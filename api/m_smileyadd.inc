{
  Miranda SmileyAdd Plugin
  Plugin support header file
  Copyright (C) 2004 Rein-Peter de Boer (peacow), and followers

  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
}

{$IFNDEF M_SMILEYADD}
{$DEFINE M_SMILEYADD}
const
  SAFLRE_INSERTEMF = 2; // insert smiley as EMF into RichEdit, otherwise bitmap
                        // inserted this flag allows "true" transparency
type
  PSMADD_RICHEDIT3 = ^TSMADD_RICHEDIT3;
  TSMADD_RICHEDIT3 = record
    cbSize             :int;        // size of the structure
    hwndRichEditControl:HWND;       // handle to the rich edit control
    rangeToReplace     :PCHARRANGE; // same meaning as for normal Richedit use (NULL = replaceall)
    Protocolname       :Pchar;      // protocol to use... if you have defined a
       // protocol, u can use your own protocol name. SmileyAdd will
       // automatically select the smileypack that is defined for your protocol.
       // Or, use "Standard" for standard smiley set. Or "ICQ", "MSN"
       // if you prefer those icons.
       // If not found or NULL, "Standard" will be used
    flags              :dword;   // Flags (SAFLRE_*) that define the behaivior
    disableRedraw      :BOOL;    // Parameter have been depricated, have no effect on operation
    hContact           :THANDLE; // Contact handle
  end;

{
  Replace smileys in a rich edit control...
  wParam = (WPARAM) 0; not used
  lParam = (LPARAM) (SMADD_RICHEDIT3*) &smre;  //pointer to SMADD_RICHEDIT3
  return: TRUE if API succeeded (all parameters were valid) , FALSE if not.
}
const
  MS_SMILEYADD_REPLACESMILEYS = 'SmileyAdd/ReplaceSmileys';

type
  PSMADD_SHOWSEL3 = ^TSMADD_SHOWSEL3;
  TSMADD_SHOWSEL3 = record
    cbSize       : int;     // size of the structure
    Protocolname : Pchar;   // protocol to use... if you have defined a protocol,
      // you can use your own protocol name. Smiley add will automatically
      // select the smileypack that is defined for your protocol.
      // Or, use "Standard" for standard smiley set. Or "ICQ", "MSN"
      // if you prefer those icons.
      // If not found or NULL: "Standard" will be used
    xPosition    : int;     // Postition to place the selectwindow
    yPosition    : int;
    Direction    : int;     // Direction (i.e. size upwards/downwards/etc) of
                            // the window 0, 1, 2, 3
    hwndTarget   : HWND;    // Window, where to send the message when smiley
                            // is selected.
    targetMessage: DWORD;   // Target message, to be sent.
    targetWParam : LPARAM;  // Target WParam to be sent (LParam will be pchar to
                            // select smiley) see the example file.
    hwndParent   : HWND;    // Parent window for smiley dialog
    hContact     : THANDLE; // Contact handle
  end;

{
  Show smiley selection window
  wParam = (WPARAM) 0; not used
  lParam = (LPARAM) (SMADD_SHOWSEL3*) &smre;  //pointer to SMADD_SHOWSEL3
  return: TRUE if API succeeded (all parameters were valid) , FALSE if not.
}
const
  MS_SMILEYADD_SHOWSELECTION = 'SmileyAdd/ShowSmileySelection';

{
  get smiley button icon
  wParam = (WPARAM) 0; not used
  lParam = (LPARAM) (SMADD_INFO*) &smgi;  //pointer to SMADD_INFO
}
type
  PSMADD_INFO2 = ^TSMADD_INFO2;
  TSMADD_INFO2 = record
    cbSize                : int;   // size of the structure
    Protocolname          : Pchar;
    ButtonIcon            : HICON; // RETURN VALUE: this is filled with the
     // icon handle of the smiley that can be used on the button
     // do not destroy! NULL if the buttonicon is not defined...
    NumberOfVisibleSmileys: int;   // Number of visible smileys defined.
    NumberOfSmileys       : int;   // Number of total smileys defined
  end;

const
  MS_SMILEYADD_GETINFO2 = 'SmileyAdd/GetInfo2';

// Event notifies that options have changed
// Message dialogs usually need to redraw it's content on reception of this event
  ME_SMILEYADD_OPTIONSCHANGED = 'SmileyAdd/OptionsChanged';

  SAFL_PATH    = 1; // provide smiley file path, icon otherwise
  SAFL_UNICODE = 2; // string fields in OPTIONSDIALOGPAGE are WCHAR*

type
  PSMADD_BATCHPARSE2 = ^TSMADD_BATCHPARSE2;
  TSMADD_BATCHPARSE2 = record
    cbSize      :int;     // size of the structure
    Protocolname:PChar;   // protocol to use... if you have defined a protocol, u can
                          // use your own protocol name. Smiley add wil automatically
                          // select the smileypack that is defined for your protocol.
                          // Or, use "Standard" for standard smiley set. Or "ICQ", "MSN"
                          // if you prefer those icons.
                          // If not found or NULL: "Standard" will be used
    str         :TChar;   // String to parse
    flag        :dword;   // One of the SAFL_ flags specifies parsing requirements
                          // This parameter should be filled by the user
    numSmileys  :dword;   // Number of Smileys found, this parameter filled by SmileyAdd
    oflag       :dword;   // One of the SAFL_ flags specifies content of the parse results
                          // this parameter filled by SmileyAdd
    hContact    :THANDLE; // Contact handle
  end;

type
  PSMADD_BATCHPARSERES = ^TSMADD_BATCHPARSERES;
  TSMADD_BATCHPARSERES = record
    startChar:dword; // Starting smiley character
                     // Because of iterative nature of the API caller should
                     // set this parameter to correct value
    size     :dword; // Number of characters in smiley (0 if not found)
                     // Because of iterative nature of the API caller should
                     // set this parameter to correct value
    case boolean of
      false: (filepath:TChar);
      true:  (hIcon:HICON); // User responsible for destroying icon handle
  end;
const
//find all smileys in text, API parses the provided text and returns all smileys found
//wParam = (WPARAM) 0; not used
//lParam = (LPARAM) (SMADD_BATCHPARSE2*) &smgp;  //pointer to SMADD_BATCHPARSE2
//function returns pointer to array SMADD_BATCHPARSERES records for each smiley found
//if no smileys found NULL is returned
//if non NULL value returned pointer must be freed with MS_SMILEYADD_BATCHFREE API
  MS_SMILEYADD_BATCHPARSE = 'SmileyAdd/BatchParse';

//Free memory allocated by MS_SMILEYADD_BATCHPARSE
//wParam = (WPARAM) 0; not used
//lParam = (LPARAM) (SMADD_BATCHPARSERES*) &smgp;  //pointer to SMADD_BATCHPARSERES
  MS_SMILEYADD_BATCHFREE = 'SmileyAdd/BatchFree';

type
  PSMADD_REGCAT = ^TSMADD_REGCAT;
  TSMADD_REGCAT = record
    cbSize  :int;   // size of the structure
    name    :PChar; // smiley category name for reference
    dispname:PChar; // smiley category name for display
  end;
const
//Register smiley category
//wParam = (WPARAM) 0; not used
//lParam = (LPARAM) (SMADD_REGCAT*) &smgp;  //pointer to SMADD_REGCAT
  MS_SMILEYADD_REGISTERCATEGORY = 'SmileyAdd/RegisterCategory';

{$ENDIF}