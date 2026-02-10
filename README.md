# Mods Updater for Nexusmod

> *Only for educational purposes*

## How to use

1. Specify mods you want to use in versions.csv (Only `modId` is required)
2. Log in to Nexus mod, then extract cookies and add to this folder as cookies.json
3. Config API key in config.json (Users can view their own API Keys by visiting [NXM Account](https://www.nexusmods.com/users/myaccount?tab=api%20access))
4. Run mods_updater.ps1

### Different Mod Group Setup (Stardew Valley) [^1]

1. Create a shortcut to **StardewModdingAPI.exe**.
2. Right-click the shortcut and choose **Properties**.
3. In the **Target** field, add the following **to the end** of the existing text: `--mods-path "ModsFolder"`. 
<sub>_Do **not** delete any existing text in the **Target** field._</sub>

**Example:** `"your-path-here\SteamLibrary\steamapps\common\Stardew Valley\StardewModdingAPI.exe" --mods-path "Mods (multiplayer)"`

> [!TIP]
> If you frequently switch between mod folders, you can add SMAPI as a **non-Steam game** in Steam and change its **Launch Options** instead.

[^1]: [Stardew Valley Wiki](https://stardewvalleywiki.com/Modding:Player_Guide/Getting_Started#Do_mods_work_in_multiplayer.3F)
