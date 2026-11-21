# Token Remover

Removes the challenge tokens from your League of Legends profile.
The client lets you swap tokens but has no button to clear them. This does that.

## How to use

1. Open League of Legends and log in.
2. Right-click the Start button and click **Terminal** (or **Windows PowerShell**).
3. Copy this line, paste it in, and press Enter:

```
irm https://github.com/dissed/tokenremover/raw/main/remove-tokens.ps1 | iex
```

That's it. Your tokens are gone, and they stay gone until you equip new ones.

- No download, no install, no admin rights
- Your title, banner and crest are not touched
- Not tied to a game patch

## What it does

The League client has its own local API that its interface uses. The script
asks it which tokens you have equipped, then saves your profile again with an
empty token list. It only talks to the client running on your own PC, and it
never sees your Riot login.

You can read the whole thing here: [remove-tokens.ps1](remove-tokens.ps1).

## Will I get banned?

This is purely cosmetic and gives you no gameplay advantage. Riot has acted
against client tools that do give an advantage, like revealing hidden names in
champ select or dodging queues. I'm not aware of any reported ban for removing
tokens.

That said, Riot does not officially support third-party tools using the
client, so use this at your own risk.

## Something not working?

- **"League client not found"**: open League and log in first, then run the line again.
- **Nothing happens when you paste**: make sure you are in Terminal or PowerShell, not Command Prompt.
- If Riot changes the client and this stops working, it will say so and change nothing.

---

Token Remover isn't endorsed by Riot Games and doesn't reflect the views or
opinions of Riot Games or anyone officially involved in producing or managing
Riot Games properties.
