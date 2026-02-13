# Mods Updater for Nexusmod

> *Only for educational purposes*
Tired of updating dozens of mods manually? Just one-time setup and everything will be updated with one click!

(Well, cookies could be expired so remember to refresh once in a while)

(Also this tool was created with Stardew Valley mods format, so keep in mind)

## How it works

1. Using your saved login sessions, it retrieve your Nexus Mods API key from your account page.
2. The same applied to Nexus Mods download token from the `nxm://` link of each mod page.
3. Requests download URL from Nexus Mods API using your API key plus the temporary token.
4. Download, extract zip files and save downloaded mods' version info.

## How to use

1. Install node packages with command `npm install`
2. Specify mods you want to use in versions.csv (Only `modId` is required)
3. Log in to Nexus mod, then extract cookies and add to this folder as cookies.json
4. Specify your game's name in config.json
5. Run mods_updater.ps1 and enjoy

### Different Mod Group Setup (Stardew Valley) [^1]

1. Create a shortcut to **StardewModdingAPI.exe**.
2. Right-click the shortcut and choose **Properties**.
3. In the **Target** field, add the following **to the end** of the existing text: `--mods-path "ModsFolder"`.
<sub> Do **not** delete any existing text in the **Target** field. </sub>

**Example:** `"your-path-here\SteamLibrary\steamapps\common\Stardew Valley\StardewModdingAPI.exe" --mods-path "Mods (multiplayer)"`

> [!TIP]
> If you frequently switch between mod folders, you can add SMAPI as a **non-Steam game** in Steam and change its **Launch Options** instead.

[^1]: [Stardew Valley Wiki](https://stardewvalleywiki.com/Modding:Player_Guide/Getting_Started#Do_mods_work_in_multiplayer.3F)
