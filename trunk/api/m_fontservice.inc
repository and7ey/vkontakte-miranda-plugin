// Copyright Scott Ellis (mail@scottellis.com.au) 2005
// This software is licenced under the GPL (General Public Licence)
// available at http://www.gnu.org/copyleft/gpl.html
{$ifndef FONT_SERVICE_API_INC}
{$define FONT_SERVICE_API_INC}

const
// style flags
  DBFONTF_BOLD      = 1;
  DBFONTF_ITALIC    = 2;
  DBFONTF_UNDERLINE = 4;
  DBFONTF_STRIKEOUT = 8;
// flags for compatibility
  FIDF_APPENDNAME       = 1;   // append 'Name' to the setting used to store
                               // font face (as CLC settings require)
  FIDF_NOAS             = 2;   // disable the <prefix>As setting to prevent
                               // 'same as' behaviour
  FIDF_SAVEACTUALHEIGHT = 4;   // write the actual height of a test string to the db
  FIDF_SAVEPOINTSIZE    = 8;   // write the font point size to the db
// additional flags
  FIDF_DEFAULTVALID     = 32;  // the default font settings are valid - else,
                               // just use generic default
  FIDF_NEEDRESTART      = 64;  // setting changes will not take effect until
                               // miranda is restarted
  FIDF_ALLOWREREGISTER  = 128; // allow plugins to register this font again
                               // (i.e. override already registered settings
                               // such as flags)
  FIDF_ALLOWEFFECTS     = 256; // allow setting of font effects
                               // (i.e. underline and strikeout)

type
// settings to be used for the value of 'deffontsettings' in the FontID
// structure below - i.e. defaults
  PFontSettings_tag = ^TFontSettings_tag;
  TFontSettings_tag = record
    colour  : TCOLORREF;
    size    : char;
    style   : BYTE; // see the DBFONTF_* flags above
    charset : BYTE;
    szFace  : array[0..(LF_FACESIZE)-1] of char;
  end;
  TFontSettings = TFontSettings_tag;
  PFontSettings = ^TFontSettings;

  PFontSettingsW_tag = ^TFontSettingsW_tag;
  TFontSettingsW_tag = record
    colour  : TCOLORREF;
    size    : char;
    style   : BYTE; // see the DBFONTF_* flags above
    charset : BYTE;
    szFace  : array[0..(LF_FACESIZE)-1] of WideChar;
  end;
  TFontSettingsW = TFontSettingsW_tag;
  PFontSettingsW = ^TFontSettingsW;

const
  FontIDW_SIZEOF_V2 = 660;
  FontID_SIZEOF_V2  = 372;

type
// a font identifier structire - used for registering a font,
// and getting one out again
  PFontID_tag = ^TFontID_tag;
  TFontID_tag = record
    cbSize         : int;
    // group the font belongs to - this is the 'Font Group' list in the options page
    group          : array[0..63] of char; 
    // the name of the font setting e.g. 'contacts' in the 'contact list' group
    name           : array[0..63] of char; 
    // the 'module' in the database where the font data is stored
    dbSettingsGroup: array[0..31] of char;
    // prepended to the settings used to store this font's data in the db
    prefix         : array[0..31] of char;
    // bitwise OR of the FIDF_* flags above
    flags          : DWORD;
    deffontsettings: TFontSettings; // defaults, if flags & FIDF_DEFAULTVALID
    // controls the order in the font group in which the fonts are listed in the
    // UI (if order fields are equal, they will be ordered alphabetically by name)
    order          : int;
    backgroundGroup:array [0..63] of char;
    backgroundName: array [0..63] of char;
  end;
  TFontID = TFontID_tag;
  PFontID = ^TFontID;

  PFontIDW_tag = ^TFontIDW_tag;
  TFontIDW_tag = record
    cbSize         : int;
    // group the font belongs to - this is the 'Font Group' list in the options page
    group          : array[0..63] of WideChar; 
    // the name of the font setting e.g. 'contacts' in the 'contact list' group
    name           : array[0..63] of WideChar; 
    // the 'module' in the database where the font data is stored
    dbSettingsGroup: array[0..31] of char;
    // prepended to the settings used to store this font's data in the db
    prefix         : array[0..31] of char;
    // bitwise OR of the FIDF_* flags above
    flags          : DWORD;
    deffontsettings: TFontSettingsW; // defaults, if flags & FIDF_DEFAULTVALID
    // controls the order in the font group in which the fonts are listed in the
    // UI (if order fields are equal, they will be ordered alphabetically by name)
    order          : int;
    backgroundGroup:array [0..63] of WideChar;
    backgroundName: array [0..63] of WideChar;
  end;
  TFontIDW = TFontIDW_tag;
  PFontIDW = ^TFontIDW;

  PColourID_tag = ^TColourID_tag;
  TColourID_tag = record
    cbSize          : int;
    group           : array[0..63] of char;
    name            : array[0..63] of char;
    dbSettingsGroup : array[0..31] of char;
    setting         : array[0..31] of char;
    flags           : DWORD;     // not used
    defcolour       : TCOLORREF; // default value
    order           : int;
  end;
  TColourID = TColourID_tag;
  PColourID = ^TColourID;

  PColourIDW_tag = ^TColourIDW_tag;
  TColourIDW_tag = record
    cbSize          : int;
    group           : array[0..63] of WideChar;
    name            : array[0..63] of WideChar;
    dbSettingsGroup : array[0..31] of char;
    setting         : array[0..31] of char;
    flags           : DWORD;     // not used
    defcolour       : TCOLORREF; // default value
    order           : int;
  end;
  TColourIDW = TColourIDW_tag;
  PColourIDW = ^TColourIDW;

const
  { register a font }
  { wparam = pointer to FontID structure}
  { lparam = 0 }
  MS_FONT_REGISTERA = 'Font/Register';
  MS_FONT_REGISTERW = 'Font/RegisterW';
  MS_FONT_REGISTER = MS_FONT_REGISTERW;

  { get a font }
  { wparam = pointer to FontID structure (only name and group matter) }
  { lParam = pointer to LOGFONT structure }
  { returns the font's colour }
  MS_FONT_GETA = 'Font/Get';
  MS_FONT_GETW = 'Font/GetW';
  MS_FONT_GET = MS_FONT_GETW;

  { fired when a user modifies font settings, so reget your fonts }
  ME_FONT_RELOAD = 'Font/Reload';

  { register a colour (this should be used for everything except actual text colour for registered fonts) }
  { [note - a colour with name 'Background' has special meaning and will be used as the background colour of  }
  { the font list box in the options, for the given group] }
  { wparam = pointer to ColourID structure }
  { lparam = 0 }
  MS_COLOUR_REGISTERA = 'Colour/Register';
  MS_COLOUR_REGISTERW = 'Colour/RegisterW';
  MS_COLOUR_REGISTER = MS_COLOUR_REGISTERW;

  { get a colour }
  { wparam = pointer to ColourID structure (only name and group matter) }
  { lParam = pointer to LOGFONT structure }
  MS_COLOUR_GETA = 'Colour/Get';
  MS_COLOUR_GETW = 'Colour/GetW';
  MS_COLOUR_GET = MS_COLOUR_GETW;

  { fired when a user modifies font settings, so reget your fonts and colours }
  ME_COLOUR_RELOAD = 'Colour/Reload';

{$endif}
