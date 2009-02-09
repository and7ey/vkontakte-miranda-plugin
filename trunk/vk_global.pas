(*
    VKontakte plugin for Miranda IM: the free IM client for Microsoft Windows

    Copyright (С) 2008 Andrey Lukyanov

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
  piVersion = 0 shl 24 + 1 shl 16 + 7 shl 8 + 3;
  piDescription = 'VKontakte Protocol for Miranda IM';
  piAuthor = 'Andrey Lukyanov';
  piAuthorEmail = 'and7ey@gmail.com';
  piCopyright = '(c) 2008-2009 Andrey Lukyanov';
  piHomepage = 'http://forum.miranda.im/showthread.php?p=28497';

const
  // URLs
  vk_url = 'http://vkontakte.ru';
  // vk_url_pda = 'http://pda.vkontakte.ru';
  vk_url_pda_login = 'http://vkontakte.ru/login.php?pda=index&email=%s&pass=%s&expire=0';
  vk_url_pda_friendsonline = 'http://pda.vkontakte.ru/friendsonline%d?nr=1';
  vk_url_pda_friends = 'http://pda.vkontakte.ru/friends%d?nr=1';
  vk_url_pda_logout = 'http://pda.vkontakte.ru/logout';
  vk_url_pda_forgot = 'http://pda.vkontakte.ru/forgot';
  vk_url_friends_all = 'http://vkontakte.ru/friend.php';
  vk_url_register = 'http://vkontakte.ru/reg0';
  vk_url_forgot = 'http://vkontakte.ru/login.php?op=forgot';
  vk_url_pda_sendmsg_secureid = 'http://pda.vkontakte.ru/?act=write&to=%d';
  vk_url_pda_sendmsg = 'http://pda.vkontakte.ru/mailsent?pda=1&to_reply=0&to_id=%d&chas=%s&message=%s';
  vk_url_friend = 'http://vkontakte.ru/id%d';    // leads to online-on-site, used in get info
  vk_url_photos = 'http://vkontakte.ru/photos.php?id=%d';
  vk_url_friends = 'http://vkontakte.ru/friend.php?id=%d';
  vk_url_wall = 'http://vkontakte.ru/wall.php?id=%d';
  vk_url_groups = 'http://vkontakte.ru/groups.php?id=%d';
  vk_url_audio = 'http://vkontakte.ru/audio.php?id=%d';
  vk_url_notes = 'http://vkontakte.ru/notes.php?id=%d';
  vk_url_questions = 'http://vkontakte.ru/questions.php?mid=%d';
  vk_url_frienddelete = 'http://vkontakte.ru/friend.php?act=do_delete&id=%d';
  // vk_url_searchbyname = 'http://vkontakte.ru/search.php?act=adv&subm=1&first_name=%s&last_name=%s&o=0';
  vk_url_search = 'http://vkontakte.ru/search.php?act=adv&subm=1&g=0&first_name=%s&last_name=%s&sex=%d&status=%d&political=%d&bday_day=%d&bday_month=%d&bday_year=%d&country=%d&uni_city=%d&university=%d&faculty=%d&chair=%d&graduation=%d&edu_form=%d&online=%d';
  vk_url_search_suffix = '&st=%d';
  // vk_url_searchbyanydata = 'http://vkontakte.ru/search.php?q=%s&act=quick';
  vk_url_searchbyid = 'http://vkontakte.ru/search.php?id=%d';
  vk_url_pda_friend = 'http://pda.vkontakte.ru/id%d';
  vk_url_pda_keeponline = 'http://vkontakte.ru/profile.php';   // leads to online-on-site
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
  // err_search_noconnection = 'Could not start a search on ''%s'', there was a problem - is %s connected?';
  // err_search_title = 'Problem with search';
  err_sendmgs_offline = 'You cannot send messages when you are offline.';
  err_sendmgs_freq = 'You cannot send messages more often than once in 1 second. Please try again later.';

  // questions
  qst_read_info = 'Updating of user details requires status change to Online. Would you like to change status and update details now?';

  // confirmations
  conf_info_update_completed = 'Details update completed for all contacts.';

const
  // List of settings in DB
  opt_UserName: PChar = 'user/email';
  opt_UserPass: PChar = 'user/pass';
  opt_UserKeepOnline: PChar = 'user/keeponlinesecs';
  opt_UserCheckNewMessages: PChar = 'user/newmessagessecs';
  opt_UserUpdateFriendsStatus: PChar = 'user/friendsstatussecs';
  opt_UserGetMinInfo: PChar = 'user/getmininfo';
  opt_UserRemoveEmptySubj: PChar = 'user/removeemptysubject';
  opt_UserDefaultGroup: PChar = 'User/DefaultGroup';
  opt_UserUpdateAddlStatus: PChar = 'user/updateadditionalstatus';
  opt_UserAvatarsSupport: PChar = 'user/avssupport';
  opt_UserAvatarsUpdateFreq: PChar = 'user/avsupdatefreq';
  opt_UserAvatarsUpdateWhenGetInfo: PChar = 'user/avsupdatewhengetinfo';
  opt_UserVKontakteURL: PChar = 'User/VKontakteURL';
  opt_UserAddlStatusForOffline: PChar = 'User/AddlStatusForOffline';
  opt_UserUseLocalTimeForIncomingMessages: PChar = 'User/UseLocalTimeForIncomingMessages';
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
  opt_NewsFilterTags: PChar = 'NewsFilterTags';
  opt_NewsLinks: PChar = 'NewsDisplayLinks';
  opt_NewsSeparateContact: PChar = 'NewsSeparateContact';
  opt_NewsLastUpdateDateTime: PChar = 'LastUpdateDateTimeNews';
  opt_NewsLastNewsDateTime: PChar = 'NewsLastNewsDateTime';
  opt_NewsSeparateContactID: PChar = 'NewsSeparateContactID';
  opt_NewsSeparateContactName: PChar = 'NewsSeparateContactName';
  opt_LastUpdateDateTimeMsgs: PChar = 'LastUpdateDateTimeMsgs';
  opt_LastUpdateDateTimeFriendsStatus: PChar = 'LastUpdateDateTimeFriendsStatus';
  opt_LastUpdateDateTimeKeepOnline: PChar = 'LastUpdateDateTimeKeepOnline';
  opt_LastUpdateDateTimeAvatars: PChar = 'LastUpdateDateTimeAvatars';

type
  TAdditionalStatusIcon = record
    Text: String;
    Name: String;
    IconIndex: Integer;
    IconExtraIndex: Integer;
    IcoLibIndex: Integer;
    StatusID: Byte; // id of status in accordance with ICQ xstatuses
  end;

type
  TComboBoxItem = record
    Index: Integer;
    Name: String;
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

  // list of values for Advanced search
  GenderField: Array [0..1] of TComboBoxItem = ((Index: 1; Name: 'Female'), (Index: 2; Name: 'Male'));
  MaritalStatusField: Array [0..5] of TComboBoxItem = ((Index: 1; Name: 'Single'), (Index: 2; Name: 'In a relationship'), (Index: 3; Name: 'Engaged'), (Index: 4; Name: 'Married'), (Index: 5; Name: 'It''s complicated'), (Index: 6; Name: 'Actively searching'));
  PoliticalViewsField: Array [0..7] of TComboBoxItem = ((Index: 8; Name: 'Apathetic'), (Index: 1; Name: 'Communist'), (Index: 2; Name: 'Socialist'), (Index: 3; Name: 'Moderate'), (Index: 4; Name: 'Liberal'), (Index: 5; Name: 'Conservative'), (Index: 6; Name: 'Monarchist'), (Index: 7; Name: 'Ultraconservative'));
  DOBField: Array [0..30] of TComboBoxItem = ((Index: 1; Name: '1'), (Index: 2; Name: '2'), (Index: 3; Name: '3'), (Index: 4; Name: '4'), (Index: 5; Name: '5'), (Index: 6; Name: '6'), (Index: 7; Name: '7'), (Index: 8; Name: '8'), (Index: 9; Name: '9'), (Index: 10; Name: '10'), (Index: 11; Name: '11'), (Index: 12; Name: '12'), (Index: 13; Name: '13'), (Index: 14; Name: '14'), (Index: 15; Name: '15'), (Index: 16; Name: '16'), (Index: 17; Name: '17'), (Index: 18; Name: '18'), (Index: 19; Name: '19'), (Index: 20; Name: '20'), (Index: 21; Name: '21'), (Index: 22; Name: '22'), (Index: 23; Name: '23'), (Index: 24; Name: '24'), (Index: 25; Name: '25'), (Index: 26; Name: '26'), (Index: 27; Name: '27'), (Index: 28; Name: '28'), (Index: 29; Name: '29'), (Index: 30; Name: '30'), (Index: 31; Name: '31'));
  MOBField: Array [0..11] of TComboBoxItem = ((Index: 1; Name: 'January'), (Index: 2; Name: 'February'), (Index: 3; Name: 'March'), (Index: 4; Name: 'April'), (Index: 5; Name: 'May'), (Index: 6; Name: 'June'), (Index: 7; Name: 'July'), (Index: 8; Name: 'August'), (Index: 9; Name: 'September'), (Index: 10; Name: 'October'), (Index: 11; Name: 'November'), (Index: 12; Name: 'December'));
  YearsField: Array [0..101] of TComboBoxItem =((Index: 2021; Name: '2021'), (Index: 2020; Name: '2020'), (Index: 2019; Name: '2019'), (Index: 2018; Name: '2018'), (Index: 2017; Name: '2017'), (Index: 2016; Name: '2016'), (Index: 2015; Name: '2015'), (Index: 2014; Name: '2014'), (Index: 2013; Name: '2013'), (Index: 2012; Name: '2012'), (Index: 2011; Name: '2011'), (Index: 2010; Name: '2010'), (Index: 2009; Name: '2009'), (Index: 2008; Name: '2008'), (Index: 2007; Name: '2007'), (Index: 2006; Name: '2006'), (Index: 2005; Name: '2005'), (Index: 2004; Name: '2004'), (Index: 2003; Name: '2003'), (Index: 2002; Name: '2002'), (Index: 2001; Name: '2001'),
                                              (Index: 2000; Name: '2000'), (Index: 1999; Name: '1999'), (Index: 1998; Name: '1998'), (Index: 1997; Name: '1997'), (Index: 1996; Name: '1996'), (Index: 1995; Name: '1995'), (Index: 1994; Name: '1994'), (Index: 1993; Name: '1993'), (Index: 1992; Name: '1992'), (Index: 1991; Name: '1991'), (Index: 1990; Name: '1990'), (Index: 1989; Name: '1989'), (Index: 1988; Name: '1988'), (Index: 1987; Name: '1987'), (Index: 1986; Name: '1986'), (Index: 1985; Name: '1985'), (Index: 1984; Name: '1984'), (Index: 1983; Name: '1983'), (Index: 1982; Name: '1982'), (Index: 1981; Name: '1981'), (Index: 1980; Name: '1980'),
                                              (Index: 1979; Name: '1979'), (Index: 1978; Name: '1978'), (Index: 1977; Name: '1977'), (Index: 1976; Name: '1976'), (Index: 1975; Name: '1975'), (Index: 1974; Name: '1974'), (Index: 1973; Name: '1973'), (Index: 1972; Name: '1972'), (Index: 1971; Name: '1971'), (Index: 1970; Name: '1970'), (Index: 1969; Name: '1969'), (Index: 1968; Name: '1968'), (Index: 1967; Name: '1967'), (Index: 1966; Name: '1966'), (Index: 1965; Name: '1965'), (Index: 1964; Name: '1964'), (Index: 1963; Name: '1963'), (Index: 1962; Name: '1962'), (Index: 1961; Name: '1961'), (Index: 1960; Name: '1960'),
                                              (Index: 1959; Name: '1959'), (Index: 1958; Name: '1958'), (Index: 1957; Name: '1957'), (Index: 1956; Name: '1956'), (Index: 1955; Name: '1955'), (Index: 1954; Name: '1954'), (Index: 1953; Name: '1953'), (Index: 1952; Name: '1952'), (Index: 1951; Name: '1951'), (Index: 1950; Name: '1950'), (Index: 1949; Name: '1949'), (Index: 1948; Name: '1948'), (Index: 1947; Name: '1947'), (Index: 1946; Name: '1946'), (Index: 1945; Name: '1945'), (Index: 1944; Name: '1944'), (Index: 1943; Name: '1943'), (Index: 1942; Name: '1942'), (Index: 1941; Name: '1941'), (Index: 1940; Name: '1940'),
                                              (Index: 1939; Name: '1939'), (Index: 1938; Name: '1938'), (Index: 1937; Name: '1937'), (Index: 1936; Name: '1936'), (Index: 1935; Name: '1935'), (Index: 1934; Name: '1934'), (Index: 1933; Name: '1933'), (Index: 1932; Name: '1932'), (Index: 1931; Name: '1931'), (Index: 1930; Name: '1930'), (Index: 1929; Name: '1929'), (Index: 1928; Name: '1928'), (Index: 1927; Name: '1927'), (Index: 1926; Name: '1926'), (Index: 1925; Name: '1925'), (Index: 1924; Name: '1924'), (Index: 1923; Name: '1923'), (Index: 1922; Name: '1922'), (Index: 1921; Name: '1921'), (Index: 1920; Name: '1920'));
  CountryField: Array [0..17] of TComboBoxItem = ((Index: 1; Name: 'Russia'), (Index: 2; Name: 'Ukraine'), (Index: 3; Name: 'Belarus'), (Index: 4; Name: 'Kazakhstan'), (Index: 5; Name: 'Azerbaijan'), (Index: 6; Name: 'Armenia'), (Index: 7; Name: 'Georgia'), (Index: 8; Name: 'Israel'), (Index: 9; Name: 'USA'), (Index: 10; Name: 'Canada'), (Index: 11; Name: 'Kyrgyzstan'), (Index: 12; Name: 'Latvia'),
                                                  (Index: 13; Name: 'Lithuania'), (Index: 14; Name: 'Estonia'), (Index: 15; Name: 'Moldova'), (Index: 16; Name: 'Tajikistan'), (Index: 17; Name: 'Turkmenistan'), (Index: 18; Name: 'Uzbekistan'));
  EdStatusField: Array [0..2] of TComboBoxItem = ((Index: 1; Name: 'Full-time'), (Index: 2; Name: 'Part-time'), (Index: 3; Name: 'Correspondence'));
  CitiesField: Array [0..18] of TComboBoxItem = ((Index: 1; Name: 'Москва'), (Index: 2; Name: 'Санкт-Петербург'), (Index: 35; Name: 'Великий Новгород'), (Index: 10; Name: 'Волгоград'), (Index: 49; Name: 'Екатеринбург'), (Index: 60; Name: 'Казань'), (Index: 61; Name: 'Калининград'), (Index: 72; Name: 'Краснодар'), (Index: 73; Name: 'Красноярск'), (Index: 87; Name: 'Мурманск'), (Index: 95; Name: 'Нижний Новгород'), (Index: 99; Name: 'Новосибирск'), (Index: 104; Name: 'Омск'), (Index: 110; Name: 'Пермь'), (Index: 119; Name: 'Ростов-на-Дону'), (Index: 123; Name: 'Самара'), (Index: 125; Name: 'Саратов'), (Index: 151; Name: 'Уфа'), (Index: 158; Name: 'Челябинск'));


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

  psreID: Integer;
  psreSecureID: String; // details of found contact

  ConnectionErrorsCount: Integer; // global variable to keep connection errors count

implementation

begin
end.

