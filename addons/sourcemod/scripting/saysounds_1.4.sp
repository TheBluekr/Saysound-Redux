/**
 To-do:
 - Fix Admin menu integration
*/


#include <sourcemod>
#include <sdktools>
#include <clientprefs>

#undef REQUIRE_PLUGIN
#include <adminmenu>
#define REQUIRE_PLUGIN

#pragma semicolon 1

#define PLUGIN_VERSION "1.4"

#define SAYSOUND_FLAG_ADMIN		(1 << 0)
#define SAYSOUND_FLAG_DOWNLOAD		(1 << 1)
#define SAYSOUND_FLAG_CUSTOMVOLUME	(1 << 2)
#define SAYSOUND_FLAG_CUSTOMLENGTH	(1 << 3)

#define PLYR 35
#define SAYSOUND_TRIGGER_SIZE 64

enum {
	SAYSOUND_CLIENT = 0,
	SAYSOUND_DONOR,
	SAYSOUND_ADMIN
}

enum {
	CookieSoundDisabled = 0,
	CookieSoundBanned,
	CookieSoundCount,
	MaxCookies
};

public Plugin myinfo = {
	name = "Say Sounds (Redux, updated)",
	author = "Friagram, TheBluekr",
	description = "Plays sound files, updated by TheBluekr",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/groups/poniponiponi"
};

enum struct SoundStruct {
	ArrayList paths;
	char trigger[SAYSOUND_TRIGGER_SIZE];
	float length;
	float volume;
	int flags;
}

ConVar CvarEnabled;
ConVar CvarClientLimit;
ConVar CvarDonorLimit;
ConVar CvarAdminLimit;
ConVar CvarClientDelay;
ConVar CvarDonorDelay;
ConVar CvarAdminDelay;
ConVar CvarRound;
ConVar CvarSentence;
ConVar CvarBlockTrigger;
ConVar CvarExclude;
ConVar CvarExcludeClient;
ConVar CvarExcludeDonor;
ConVar CvarExcludeAdmin;
ConVar CvarPlayIngame;
ConVar CvarVolume;

Cookie m_hCookies[MaxCookies];
StringMap m_hPlayerFields[PLYR];
ArrayList m_aRecentSounds;
ArrayList m_aUserSerial;
ArrayList m_aSoundList;

bool bLameSoundEngine;

Handle gh_menu, gh_adminmenu;
Handle hAdminMenu = INVALID_HANDLE;

methodmap BasePlayer {
	public SaysoundClient(const int ind, bool uid=false) {
		int player=0;	// If you're using a userid and you know 100% it's valid, then set uid to true
		if( uid && GetClientOfUserId(ind) > 0 )
			player = (ind);
		else if( IsValidClient(ind) )
			player = GetClientUserId(ind);
		return view_as< BasePlayer >( player );
	}

	property int userid {
		public get() { return view_as< int >(this); }
	}
	property int index {
		public get() { return GetClientOfUserId( view_as< int >(this) ); }
	}

	/// Cookies
	property bool bSoundDisabled {
		public get() {
			int player = this.index;
			if(!player)
				return
			else if(!AreClientCookiesCached(player)) {
				bool i; m_hPlayerFields[player].GetValue("bSoundDisabled", i);
				return i;
			}
			char disabled[6];
			m_hCookies[CookieSoundDisabled].Get(player, disabled, sizeof(disabled));
			return( StringToInt(disabled) == 1 );
		}
		public set(const bool val) {
			int player = this.index;
			if(!player)
				return;
			m_hPlayerFields[player].SetValue("bSoundDisabled", val);
			if(!AreClientCookiesCached(player))
				return;
			char disabled[6];
			IntToString(val, disabled, sizeof(disabled));
			m_hCookies[CookieSoundDisabled].Set(player, disabled);
		}
	}
	property bool bSoundBanned {
		public get() {
			int player = this.index;
			if(!player)
				return
			else if(!AreClientCookiesCached(player)) {
				bool i; m_hPlayerFields[player].GetValue("bSoundBanned", i);
				return i;
			}
			char banned[6];
			m_hCookies[CookieSoundBanned].Get(player, banned, sizeof(banned));
			return( StringToInt(banned) == 1 );
		}
		public set(const bool val) {
			int player = this.index;
			if(!player)
				return;
			m_hPlayerFields[player].SetValue("bSoundBanned", val);
			if(!AreClientCookiesCached(player))
				return;
			char banned[6];
			IntToString(val, banned, sizeof(banned));
			m_hCookies[CookieSoundBanned].Set(player, banned);
		}
	}
	property int iSoundCount {
		public get() {
			int player = this.index;
			if(!player)
				return
			else if(!AreClientCookiesCached(player)) {
				int i; m_hPlayerFields[player].GetValue("iSoundCount", i);
				return i;
			}
			char left[8];
			m_hCookies[CookieSoundCount].Get(player, left, sizeof(left));
			return StringToInt(left);
		}
		public set(const bool val) {
			int player = this.index;
			if(!player)
				return;
			m_hPlayerFields[player].SetValue("iSoundCount", val);
			if(!AreClientCookiesCached(player))
				return;
			char left[8];
			IntToString(val, left, sizeof(left));
			m_hCookies[CookieSoundCount].Set(player, left);
		}
	}

	/// General properties
	property int iAccessType {
		public get() {
			int i; m_hPlayerFields[this.index].GetValue("iAccessType", i);
			return i;
		}
		public set(const int val) {
			m_hPlayerFields[this.index].SetValue("iAccessType", val);
		}
	}
	property float fSoundLastTime {
		public get() {
			float f; m_hPlayerFields[this.index].GetFloatValue("fSoundLastTime", f);
			return f;
		}
		public set(const float val) {
			m_hPlayerFields[this.index].SetFloatValue("fSoundLastTime", f);
		}
	}

	public DisplayRemainingSounds() {
		switch(this.iAccessType) {
			case SAYSOUND_CLIENT:
				if(CvarClientLimit.IntValue && IsValidClient(this.index))
					PrintToChat(this.index, "[SM] You have used %d/%d sounds", this.iSoundCount, CvarClientLimit.IntValue);
			case SAYSOUND_DONOR:
				if(CvarDonorLimit.FloatValue && IsValidClient(this.index))
					PrintToChat(this.index, "[SM] You have used %d/%d sounds", this.iSoundCount, CvarDonorLimit.IntValue);
			case SAYSOUND_ADMIN:
				if(CvarAdminLimit.FloatValue && IsValidClient(this.index))
					PrintToChat(this.index, "[SM] You have used %d/%d sounds", this.iSoundCount, CvarAdminLimit.IntValue);
		}
	}
}

public void OnPluginStart() {
	switch(GetEngineVersion()) {
		case Engine_CSGO, Engine_DOTA: bLameSoundEngine = true;
	}

	// ***Load Translations **
	LoadTranslations("common.phrases");

	CreateConVar("sm_saysounds_redux_version", PLUGIN_VERSION, "Say Sounds Version", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY|FCVAR_DONTRECORD);

	CvarEnabled = CreateConVar("sm_saysounds_enable","1","Turns Sounds On/Off", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	
	CvarClientLimit = CreateConVar("sm_saysounds_sound_limit","10","Maximum sounds per person (0 for unlimited)", FCVAR_PLUGIN, true, 0.0, false, 0.0);
	CvarDonorLimit = CreateConVar("sm_saysounds_donor_limit","15","Maximum sounds for saysounds_donor (0 for unlimited)", FCVAR_PLUGIN, true, 0.0, false, 0.0);
	CvarAdminLimit = CreateConVar("sm_saysounds_admin_limit","0","Maximum sounds per saysounds_admin (0 for unlimited)", FCVAR_PLUGIN, true, 0.0, false, 0.0);

	CvarClientDelay = CreateConVar("sm_saysounds_sound_delay","5.0","Time between each sound trigger, 0.0 to disable checking", FCVAR_PLUGIN, true, 0.0, false, 0.0);
	CvarDonorDelay = CreateConVar("sm_saysounds_donor_delay","3.0","User flags to bypass the Time between sounds check", FCVAR_PLUGIN, true, 0.0, false, 0.0);
	CvarAdminDelay = CreateConVar("sm_saysounds_admin_delay","1.0","User flags to bypass the Time between sounds check", FCVAR_PLUGIN, true, 0.0, false, 0.0);

	CvarRound = CreateConVar("sm_saysounds_round", "0", "If set, sm_saysoundhe_sound_limit is the limit per round instead of per map", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	CvarSentence = CreateConVar("sm_saysounds_sound_sentence", "1", "When set, will trigger sounds if keyword is embedded in a sentence", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	CvarBlockTrigger = CreateConVar("sm_saysounds_block_trigger", "0", "If set, block the sound trigger to be displayed in the chat window", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	CvarExclude = CreateConVar("sm_saysounds_exclude", "2", "Number of sounds that must be different before this sound can be replayed", FCVAR_PLUGIN, true, 0.0, false, 0.0);
	CvarExclude.AddChangeHook(Cvar_ExcludeChanged);

	CvarExcludeClient = CreateConVar("sm_saysounds_exclude_client", "1", "If set, clients obey exclude count", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	CvarExcludeDonor = CreateConVar("sm_saysounds_exclude_donor", "1", "If set, donors obey exclude count", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	CvarExcludeAdmin = CreateConVar("sm_saysounds_exclude_admin", "0", "If set, admins obey exclude count", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	CvarPlayIngame = CreateConVar("sm_saysounds_playingame", "0", "Play as an emit sound or direct (0 for emit, 1 for direct)", FCVAR_PLUGIN, true, 0.0, true, 1.0);
	CvarPlayIngame.AddChangeHook(Cvar_PlayIngameChanged);

	CvarVolume = CreateConVar("sm_saysounds_volume", "1.0", "Volume setting for Say Sounds (0.0 <= x <= 1.0)", FCVAR_PLUGIN, true, 0.0, true, 1.0);

	m_hCookies[CookieSoundDisabled] = new Cookie("saysounds_enabled", "Whether saysound sounds are enabled for client", CookieAccess_Protected);
	m_hCookies[CookieSoundBanned] = new Cookie("saysounds_banned", "Whether saysound is allowed for client", CookieAccess_Protected);
	m_hCookies[CookieSoundCount] = new Cookie("saysounds_count", "How many sounds client has used", CookieAccess_Protected);
	
	//m_hCookies[CookieSoundDisabled].SetPrefabMenu(CookieMenu_YesNo, "Enable Saysounds sounds", SaysoundClientPref);

	RegAdminCmd("sm_sound_ban", Command_Sound_Ban, ADMFLAG_BAN, "sm_sound_ban <user> : Bans a player from using sounds");
	RegAdminCmd("sm_sound_reset", Command_Sound_Reset, ADMFLAG_GENERIC, "sm_sound_reset <user | all> : Resets sound quota for user, or everyone if all");
	RegConsoleCmd("sm_soundlist", Command_Sound_Menu, "Display a menu sounds to play");
	RegConsoleCmd("sm_sounds", Command_Sound_Toggle, "Toggle Saysounds");

	AddCommandListener(Command_Say, "say");
	AddCommandListener(Command_Say, "say2");
	AddCommandListener(Command_Say, "say_team");

	HookEvent("teamplay_round_start", Event_RoundStart);

	/*Handle topmenu;
	if (LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE)) {
		OnAdminMenuReady(topmenu);
	}*/

	PrepareSounds();
	
	for(int i = MaxClients; i > 0; i--) {
		if(IsClientInGame(i)) {
			OnClientPutInServer(i);
		}
	}
}

public void OnClientPutInServer(int client) {
	if(m_hPlayerFields[client] != null)
		delete m_hPlayerFields[client];
	
	m_hPlayerFields[client] = new StringMap();
	BasePlayer player = BasePlayer(player);

	/// Properties
	m_hPlayerFields[client].SetValue("bSoundDisabled", false);
	m_hPlayerFields[client].SetValue("bSoundBanned", false);
	m_hPlayerFields[client].SetValue("iSoundCount", 0);

	if(!m_aUserSerial.FindValue(GetClientUserId(client))
		player.iSoundCount = 0;	/// Sound count has reset but user wasn't connected, let's reset now

	if(CheckCommandAccess(client, "saysounds_admin", ADMFLAG_CHAT, true))
		player.iAccessType = SAYSOUND_ADMIN;
	else if(CheckCommandAccess(client, "saysounds_donor", ADMFLAG_RESERVATION, true))
		player.iAccessType = SAYSOUND_DONOR;
	else
		player.iAccessType = SAYSOUND_CLIENT;
	player.fSoundLastTime = 0.0;
}

public void OnMapStart() {
	ResetClients();

	PrecacheSounds();
}

public void ResetClients() {
	m_aRecentSounds.Clear();
	m_aUserSerial.Clear();
	BasePlayer player;
	for(int i = MaxClients; i > 0; i--) {
		if(IsClientInGame(i)) {
			player = BasePlayer(i);
			player.iSoundCount = 0;
			player.fSoundLastTime = 0.0;
		}
	}
}

public void Cvar_ExcludeChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	while(m_aRecentSounds.Length > convar.IntValue)
		m_aRecentSounds.Erase(0);
}

public void Cvar_PlayIngameChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if(!!StringToInt(newValue)) {
		PrecacheSounds();
	}
}

public void PrecacheSounds() {
	char soundfile[PLATFORM_MAX_PATH];
	for(int i; i < m_aSoundList.Length; i++) {
		SoundStruct sound;
		sound = m_aSoundList.Get(i);
		ArrayList paths = sound.paths;
		for(int j; j < paths.Length; j++) {
			paths.GetString(j, soundfile, sizeof(soundfile));
			if(CvarPlayIngame.BoolValue) {
				if(bLameSoundEngine)
					AddToStringTable(FindStringTable("soundprecache"), soundfile);
				else
					PrecacheSound(soundfile, true);
			}

			if(sound.flags & SAYSOUND_FLAG_DOWNLOAD) {
				FormatEx(soundfile, sizeof(soundfile), "sound/%s", soundfile);
				AddFileToDownloadsTable(soundfile);
			}
		}
		delete paths;
	}
}

public void PrepareSounds() {
	m_aSoundList = new ArrayList(sizeof(SoundStruct));

	char soundListFile[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, soundlistfile, sizeof(soundListFile), "configs/saysounds.cfg");
	if(!FileExists(soundListFile)) {
		SetFailState("saysounds.cfg couldn't be parsed... file doesnt exist!");
	}
	else {
		KeyValues kv = new KeyValues("soundlist");
		kv.ImportFromFile(soundListFile);
		kv.Rewind();
		if(kv.GotoFirstSubKey() {
			/*gh_menu = CreateMenu(menu_handler);
			gh_adminmenu = CreateMenu(menu_handler);
			
			SetMenuTitle(gh_menu, "Saysounds\n ");
			SetMenuTitle(gh_adminmenu, "Saysounds\n ");*/

			while(kv.GotoNextKey()) {
				char filelocation[PLATFORM_MAX_PATH];
				kv.GetString("file", filelocation, sizeof(filelocation), "");
				if(filelocation[0] != '\0') {
					SoundStruct file;

					char trigger[SAYSOUND_TRIGGER_SIZE];
					kv.GetSectionName(trigger, sizeof(trigger));
					FormatEx(path.trigger, sizeof(path.trigger), "%s", trigger);

					if(kv.GetNum("admin", 0)) {
						file.flags |= SAYSOUND_FLAG_ADMIN;
					}
						/*AddMenuItem(gh_adminmenu, trigger, trigger);
					}
					else {
						AddMenuItem(gh_adminmenu, trigger, trigger);
						AddMenuItem(gh_menu, trigger, trigger);
					}*/

					if(kv.GetNum("download", 1))
						file.flags |= SAYSOUND_FLAG_DOWNLOAD;

					duration = kv.GetFloat("duration", 0.0);
					if(duration)
						file.flags |= SAYSOUND_FLAG_CUSTOMLENGTH;

					file.volume = kv.GetFloat("volume", 0.0);
					if(file.volume) {
						file.flags |= SAYSOUND_FLAG_CUSTOMVOLUME;
						if(file.volume > 2.0)
							file.volume = 2.0;
					}

					ArrayList pathList = new ArrayList();
					if(bLameSoundEngine)
						FormatEx(filelocation, sizeof(filelocation), "*%s", filelocation);	/// prefix asterisk for newer games
					pathList.Push(filelocation);

					for(int i = 2; i; i++) {
						char item[8];
						FormatEx(item, sizeof(item),  "file%d", i);
						kv.GetString(item, filelocation, sizeof(filelocation), "");
						if(filelocation[0] == '\0') {
							break;
						}
						if(bLameSoundEngine)
							FormatEx(filelocation, sizeof(filelocation), "*%s", filelocation);
						pathList.Push(filelocation);
					}
					file.paths = pathList;
					delete pathList;
					m_aSoundList.Push(file);
				}
			}
		}
		else
			SetFailState("saysounds.cfg not parsed...No subkeys found!");
		delete kv;
	}
}

public Action Event_RoundStart(Handle event, const char[] name, bool dontBroadcast) {
	if(CvarRound.BoolValue)
		ResetClients();
	return Plugin_Continue;
}

public void OnRebuildAdminCache(AdminCachePart part) {
    if(part == AdminCache_Admins)
        CreateTimer(1.0, Timer_WaitForAdminCacheReload, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_WaitForAdminCacheReload(Handle timer) {
    for(int i = MaxClients; i; i--)
        if(IsValidClient(i))
            OnClientPutInServer(i);
	return Plugin_Continue;
}

public Action Command_Say(int client, const char[] command, int argc) {
	BasePlayer player = BasePlayer(client);
	char speech[256];
	int startidx;

	if(CvarEnabled.BoolValue && !player.bSoundDisabled && !player.bSoundBanned)	{	/// enabled, they can emit sounds to others
		if (GetCmdArgString(speech, sizeof(speech)) >= 1) {
			startidx = 0;
			
			if(speech[strlen(speech)-1] == '"') {
				speech[strlen(speech)-1] = '\0';
				startidx = 1;
			}

			if(!strcmp(command, "say2", false)) {
				startidx += 4;
			}

			return Action AttemptSaySound(client, speech[startidx]);
		}
	}	
	return Plugin_Continue;
}

public Action AttemptSaySound(int client, char[] sound) {
	char buffer[PLATFORM_MAX_PATH];

	BasePlayer player = BasePlayer(client);

	switch(player.iAccessType) {
		case SAYSOUND_CLIENT:
			if(player.iSoundCount >= CvarClientLimit.IntValue)
				return Plugin_Continue;
		case SAYSOUND_DONOR:
			if(player.iSoundCount >= CvarDonorLimit.IntValue)
				return Plugin_Continue;
		case SAYSOUND_ADMIN:
			if(player.iSoundCount >= CvarAdminLimit.IntValue)
				return Plugin_Continue;
		default:
			return Plugin_Continue;
	}

	float time = GetEngineTime();	/// are they experiencing delay
	if(time > player.fSoundLastTime) {
		bool adminonly;

		for(int i; i < m_aSoundList.Length; i++) {
			SoundStruct soundfile;
			soundfile = m_aSoundList.Get(i);
			if((CvarSentence.BoolValue && StrContains(sound, soundfile.trigger, false) >= 0) || !strcmp(sound, soundfile.trigger, false)) {
				if((soundfile.flags & SAYSOUND_FLAG_ADMIN) && player.iAccessType != SAYSOUND_ADMIN) {
					adminonly = true;
					continue;	/// perhaps there is something similar they can use
				}

				switch(player.iAccessType) {
					case SAYSOUND_CLIENT:
						if(CvarExcludeClient.BoolValue)
							if(m_aRecentSounds.FindValue(i) != -1)
								if(IsValidClient(client))
									PrintToChat(client, "[SM] This sound was recently played");
								return Plugin_Continue;
					case SAYSOUND_DONOR:
						if(CvarExcludeDonor.BoolValue)
							if(m_aRecentSounds.FindValue(i) != -1)
								if(IsValidClient(client))
									PrintToChat(client, "[SM] This sound was recently played");
								return Plugin_Continue;
					case SAYSOUND_ADMIN:
						if(CvarExcludeAdmin.BoolValue)
							if(m_aRecentSounds.FindValue(i) != -1)
								if(IsValidClient(client))
									PrintToChat(client, "[SM] This sound was recently played");
								return Plugin_Continue;
				}

				ArrayList paths = soundfile.paths;
				paths.GetString(GetRandomInt(0, paths.Length-1), buffer, sizeof(buffer));
				delete paths;

				DoSaySound(buffer, (flags & SAYSOUND_FLAG_CUSTOMVOLUME) ? soundfile.volume : CvarVolume.FloatValue);

				if(m_aRecentSounds.Push(i) >= CvarExclude.IntValue)
					m_aRecentSounds.Remove(0);

				switch(player.iAccessType) {
					case SAYSOUND_CLIENT:
						if(CvarClientDelay.FloatValue)
							if(soundfile.flags & SAYSOUND_FLAG_CUSTOMLENGTH)
								player.fSoundLastTime = time + soundfile.length;
							else
								player.fSoundLastTime = time + CvarClientDelay.FloatValue;
					case SAYSOUND_DONOR:
						if(CvarDonorDelay.FloatValue)
							if(soundfile.flags & SAYSOUND_FLAG_CUSTOMLENGTH)
								player.fSoundLastTime = time + soundfile.length;
							else
								player.fSoundLastTime = time + CvarClientDelay.FloatValue;
					case SAYSOUND_ADMIN:
						if(CvarAdminDelay.FloatValue)
							if(soundfile.flags & SAYSOUND_FLAG_CUSTOMLENGTH)
								player.fSoundLastTime = time + soundfile.length;
							else
								player.fSoundLastTime = time + CvarClientDelay.FloatValue;
				}
				
				player.iSoundCount++;
				player.DisplayRemainingSounds();
				
				if(CvarBlockTrigger.BoolValue)
					return Plugin_Handled;

				return Plugin_Continue;
			}
		}
		
		if(adminonly)
			if(IsValidClient(client))
				PrintToChat(client, "[SM] You do not have access to this sound");
		}
	}

	return Plugin_Continue;
}

public void DoSaySound(char[] soundfile, float volume) {
	for(int target = MaxClients; target; target--) {
		if(IsValidClient(target) && !BasePlayer(target).bSoundDisabled) {
			if(CvarPlayIngame.BoolValue) {
				if(volume > 1.0) {
					volume *= 0.5;
					EmitSoundToClient(target, soundfile, .volume = volume);
					EmitSoundToClient(target, soundfile, .volume = volume);
				}
				else
					EmitSoundToClient(target, soundfile, .volume = volume);
			}
			else {
				if(volume >= 2.0)
					ClientCommand(target, "playgamesound \"%s\";playgamesound \"%s\"", soundfile, soundfile);
				else
					ClientCommand(target, "playgamesound \"%s\"", soundfile);
			}
		}
	}
}

public Action Command_Sound_Reset(int client, int args) {
	if(args < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_sound_reset <target>");
		return Plugin_Handled;
	}

	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));	

	char name[64];
	bool isml,clients[MAXPLAYERS+1];
	int count=ProcessTargetString(arg,client,clients,MAXPLAYERS+1,COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS,name,sizeof(name),isml);
	if(count > 0) {
		for(int x=0;x<count;x++) {
			g_soundcount[clients[x]] = 0;
			DisplayRemainingSounds(clients[x]);
		}
	}
	else {
		ReplyToTargetError(client, count);
	}

	return Plugin_Handled;
}

public Action Command_Sound_Ban(int client, int args) {
	if (args < 1) {
		ReplyToCommand(client, "[SM] Usage: sm_sound_ban <target>");
		return Plugin_Handled;	
	}

	char arg[64];
	GetCmdArg(1, arg, sizeof(arg));	

	char name[64];
	bool isml,clients[MAXPLAYERS+1];
	int count=ProcessTargetString(arg,client,clients,MAXPLAYERS+1,COMMAND_FILTER_CONNECTED|COMMAND_FILTER_NO_BOTS|COMMAND_FILTER_NO_MULTI,name,sizeof(name),isml);
	if (count == 1) {
		g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED] = !g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED];
		ReplyToCommand(client, "[SM] %N ban status set to: %s", clients[0], g_clientprefs[clients[0]][SAYSOUND_PREF_BANNED] ? "banned" : "unbanned");
	}
	else {
		ReplyToTargetError(client, count);
	}

	return Plugin_Handled;
}

public Action Command_Sound_Toggle(int client, int args) {
	if(IsValidClient(client)) {
		BasePlayer player = BasePlayer(client);
		player.bSoundDisabled = !player.bSoundDisabled;
		PrintToChat(client, "[SM] %s", player.bSoundDisabled ? "Saysounds disabled" : "Saysounds enabled");
	}

	return Plugin_Handled;
}

public Action Command_Sound_Menu(client, args)
{
	if(IsValidClient(client)) {
		/*if(g_access[client] == SAYSOUND_ADMIN)
		{
			DisplayMenu(gh_adminmenu, client, 60);
		}
		else
		{
			DisplayMenu(gh_menu, client, 60);
		}*/
	}

	return Plugin_Handled;
}

stock bool IsValidClient(int clientIdx, bool isPlayerAlive = false) {
	if(clientIdx <= 0 || clientIdx > MaxClients)
		return false;
	if(isPlayerAlive)
		return IsClientInGame(clientIdx) && IsPlayerAlive(clientIdx);
	return IsClientInGame(clientIdx);
}