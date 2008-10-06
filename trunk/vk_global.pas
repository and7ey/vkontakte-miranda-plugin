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
 vk_global.pas

 [ Description ]
 Definition of global variables

 [ Known Issues ]
 See the code
 - Preferrable to change structure of settings store (like to change user/newmessagessecs to MessagesUpdateFrequency)

 Contributors: LA
-----------------------------------------------------------------------------}

unit vk_global;

interface

uses
  m_globaldefs,
  m_api,

  Classes;

const
  // constants required for PluginInfo
  piShortName = 'VKontakte';
  piVersion = 0 shl 24 + 1 shl 16 + 5 shl 8 + 3;
  piDescription = 'VKontakte Protocol for Miranda IM';
  piAuthor = 'Andrey Lukyanov';
  piAuthorEmail = 'and7ey@gmail.com';
  piCopyright = '(c) 2008 Andrey Lukyanov';
  piHomepage = 'http://forum.miranda.im/showthread.php?p=28497';

const
  // URLs
  vk_url = 'http://vkontakte.ru';
  vk_url_pda = 'http://pda.vkontakte.ru';
  vk_url_pda_login = 'http://vkontakte.ru/login.php?pda=index&email=%s&pass=%s&expire=0';
  vk_url_pda_friendsonline = 'http://pda.vkontakte.ru/friendsonline%d';
  vk_url_pda_friends = 'http://pda.vkontakte.ru/friends%d';
  vk_url_pda_logout = 'http://pda.vkontakte.ru/logout';
  vk_url_pda_forgot = 'http://pda.vkontakte.ru/forgot';
  vk_url_friends_all = 'http://vkontakte.ru/friend.php';
  vk_url_register = 'http://vkontakte.ru/reg0';
  vk_url_forgot = 'http://vkontakte.ru/login.php?op=forgot';
  vk_url_pda_sendmsg_secureid = 'http://pda.vkontakte.ru/?act=write&to=%d';
  vk_url_pda_sendmsg = 'http://pda.vkontakte.ru/mailsent?pda=1&to_reply=0&to_id=%d&chas=%s&message=%s';
  vk_url_friend = 'http://vkontakte.ru/id%d';
  vk_url_photos = 'http://vkontakte.ru/photos.php?id=%d';
  vk_url_friends = 'http://vkontakte.ru/friend.php?id=%d';
  vk_url_wall = 'http://vkontakte.ru/wall.php?id=%d';
  vk_url_groups = 'http://vkontakte.ru/groups.php?id=%d';
  vk_url_audio = 'http://vkontakte.ru/audio.php?id=%d';
  vk_url_notes = 'http://vkontakte.ru/notes.php?id=%d';
  vk_url_questions = 'http://vkontakte.ru/questions.php?mid=%d';
  vk_url_frienddelete = 'http://vkontakte.ru/friend.php?act=do_delete&id=%d';
  vk_url_searchbyname = 'http://vkontakte.ru/search.php?act=adv&subm=1&first_name=%s&last_name=%s&o=0&st=%d';
  vk_url_pda_friend = 'http://pda.vkontakte.ru/id%d';
  vk_url_pda_keeponline = 'http://vkontakte.ru/profile.php';
  vk_url_feed2 = 'http://vkontakte.ru/feed2.php?mask=mf';
  vk_url_pda_msg = 'http://pda.vkontakte.ru/letter%d?';
  vk_url_username = 'http://vkontakte.ru/feed2.php?mask=u';  // http://vkontakte.ru/feed2.php?mask=ufpvmge
  vk_url_authrequestsend = 'http://vkontakte.ru/friend.php?act=addFriend&fid=%d&h=%s&message=%s';  // http://vkontakte.ru/friend.php?act=add&id=123456&h=8e30f2fe
  vk_url_authrequestreceivedallow = 'http://vkontakte.ru/friend.php?act=ajax&fid=%d&n=1';
  vk_url_authrequestreceiveddeny = 'http://vkontakte.ru/friend.php?act=ajax&fid=%d&n=0';
  vk_url_authrequestreceived_requestid = 'http://vkontakte.ru/friend.php?out=1';
  vk_url_pda_setstatus_securityhash = 'http://pda.vkontakte.ru/setstatus?pda=1';
  vk_url_pda_setstatus = 'http://pda.vkontakte.ru/setstatus?pda=1&activityhash=%s&setactivity=%s';
  vk_url_pda_statusdelete = 'http://pda.vkontakte.ru/setstatus?pda=1&activityhash=%s&clearactivity=1';
  vk_url_pda_news = 'http://pda.vkontakte.ru/news';
  vk_url_news = 'http://vkontakte.ru/news.php?act=friends';
  vk_url_photo_my = 'http://vkontakte.ru/profileEdit.php?page=photo';
  vk_url_photo_my_delete = 'http://vkontakte.ru/profileEdit.php?page=photo2&subm=%s&hash=%s';

const
  // error messages
  err_search_noconnection = 'Could not start a search on ''%s'', there was a problem - is %s connected?';
  err_search_title = 'Problem with search';
  err_sendmgs_offline = 'You cannot send messages when you are offline.';
  err_sendmgs_freq = 'You cannot send messages more often than once in 1 second. Please try again later.';

const
  // List of settings in DB
  opt_UserName: PChar = 'user/email';
  opt_UserPass: PChar = 'user/pass';
  opt_UserKeepOnline: PChar = 'user/keeponlinesecs';
  opt_UserCheckNewMessages: PChar = 'user/newmessagessecs';
  opt_UserUpdateFriendsStatus: PChar = 'user/friendsstatussecs';
  opt_UserGetMinInfo: PChar = 'user/getmininfo';
  opt_UserRemoveEmptySubj: PChar = 'user/removeemptysubject';
  opt_UserDefaultGroup: PChar = 'user/defaultgroup';
  opt_UserUpdateAddlStatus: PChar = 'user/updateadditionalstatus';
  opt_UserAvatarsSupport: PChar = 'user/avssupport';
  opt_UserAvatarsUpdateFreq: PChar = 'user/avsupdatefreq';
  opt_UserAvatarsUpdateWhenGetInfo: PChar = 'user/avsupdatewhengetinfo';
  opt_NewsSupport: PChar = 'NewsEnabled';
  opt_NewsSecs: PChar = 'NewsUpdateFrequencySecs';
  opt_NewsMin: PChar = 'NewsMinimalOnly';
  opt_NewsFilterPhotos: PChar = 'NewsFilterPhotos';
  opt_NewsFilterVideos: PChar = 'NewsFilterVideos';
  opt_NewsFilterNotes: PChar = 'NewsFilterNotes';
  opt_NewsFilterQuestions: PChar = 'NewsFilterQuestions';
  opt_NewsFilterThemes: PChar = 'NewsFilterThemes';
  opt_NewsFilterFriends: PChar = 'NewsFilterFriends';
  opt_NewsFilterStatuses: PChar = 'NewsFilterStatuses';
  opt_NewsFilterGroups: PChar = 'NewsFilterGroups';
  opt_NewsFilterMeetings: PChar = 'NewsFilterMeetings';
  opt_NewsFilterAudio: PChar = 'NewsFilterAudio';
  opt_NewsFilterPersonalData: PChar = 'NewsFilterPersonalData';
  opt_NewsLinks: PChar = 'NewsDisplayLinks';
  opt_NewsSeparateContact: PChar = 'NewsSeparateContact';
  opt_NewsLastUpdateDateTime: PChar = 'NewsLastUpdateDateTime';
  opt_NewsLastNewsDateTime: PChar = 'NewsLastNewsDateTime';
  opt_NewsSeparateContactID: PChar = 'NewsSeparateContactID';
  opt_NewsSeparateContactName: PChar = 'NewsSeparateContactName';

type
  TAdditionalStatusIcon = record
    Text: String;
    Name: String;
    IconIndex: Integer;
    IconExtraIndex: Integer;
    IcoLibIndex: Integer;
    StatusID: Byte; // id of status in accordance with ICQ xstatuses
  end;

const
  // list of additional statuses
  {$J+}  // writeable constant
  xStatuses: Array [1..8] of TAdditionalStatusIcon = (
    (Text: 'No'; Name: 'vk_icon_addstatus_no'; IconIndex: 0; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 0),
    (Text: 'Custom...'; Name: 'vk_icon_addstatus_custom'; IconIndex: 0; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 0),
    (Text: 'At home'; Name: 'vk_icon_addstatus_athome'; IconIndex: 210; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 10),
    (Text: 'At university'; Name: 'vk_icon_addstatus_atuniversity'; IconIndex: 217; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 17),
    (Text: 'At work'; Name: 'vk_icon_addstatus_atwork'; IconIndex: 223; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 23),
    (Text: 'At grass'; Name: 'vk_icon_addstatus_atgrass'; IconIndex: 214; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 12),
    (Text: 'At party'; Name: 'vk_icon_addstatus_atparty'; IconIndex: 204; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 4),
    (Text: 'Having dinner'; Name: 'vk_icon_addstatus_havingdinner'; IconIndex: 207; IconExtraIndex: 0; IcoLibIndex: 0; StatusID: 7)
    );
  {$J-}


type // for debuging purposes use Thread Names
  TThreadNameInfo = record
    FType: LongWord;     // must be 0x1000
    FName: PChar;        // pointer to name (in user address space)
    FThreadID: LongWord; // thread ID (-1 indicates caller thread)
    FFlags: LongWord;    // reserved for future use, must be zero
  end;


var
  vk_hNetlibUser: THandle;

  he_StatusAdditionalChanged: THandle;

  FolderAvatars: String; // global variable to keep path to avatars folder

  vk_o_login: String; // variables to keep user's login and pass
  vk_o_pass: String;

  ErrorCode: Byte; // global variable to keep error code of last exception
  CookiesGlobal: TStringList;

  vk_Status: Integer = ID_STATUS_OFFLINE;  // global variable to keep current and prev statuses
  vk_StatusPrevious: Integer = ID_STATUS_OFFLINE;

  psre_id: Integer;
  psre_secureid: String; // details of found contact

implementation

begin
end.

