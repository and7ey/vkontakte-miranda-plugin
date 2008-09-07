(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (Ñ) 2008 Andrey Lukyanov

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
 vk_folders.pas

 [ Description ]
 Module to work with Custom profile folders plugin -
 http://addons.miranda-im.org/details.php?action=viewfile&id=2521

 [ Known Issues ]
 None

 Contributors: LA
-----------------------------------------------------------------------------}
unit vk_folders;

interface

  procedure FoldersInit();
  procedure FoldersDestroy();

implementation

uses
  m_globaldefs,
  m_api,

  vk_global, // module with global variables and constant used

  Windows,
  SysUtils;

  {$include api/m_folders.inc}

var
 vk_hFolderAvatars: THandle;

// =============================================================================
// function to initiate custom folders support
// -----------------------------------------------------------------------------
procedure FoldersInit();
var pszDest: String; // path to profile
begin
  vk_hFolderAvatars := FoldersRegisterCustomPath(piShortName, 'Avatars Cache', PROFILE_PATH + '\' + piShortName);
  if vk_hFolderAvatars <> 0 Then
    FolderAvatars := FoldersGetCustomPath(vk_hFolderAvatars)
  else
  begin
    // getting profile path & defined avatars path
    SetLength(pszDest, MAX_PATH);
    pluginLink^.CallService(MS_DB_GETPROFILEPATH, MAX_PATH, Windows.lParam(@pszDest[1]));
    SetLength(pszDest, StrLen(@pszDest[1]));
    FolderAvatars := pszDest + '\' + piShortName;
  end;
end;

// =============================================================================
// function to destroy custom folders support
// -----------------------------------------------------------------------------
procedure FoldersDestroy();
begin
  pluginLink^.DestroyServiceFunction(vk_hFolderAvatars);
end;



begin
end.
