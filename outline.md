A brief overview of what we are building:

"Blocker" is a minimalist app which uses parental controls pathways on iphone to restrict access to apps and/or their associated websites. Built in swift. 

Structure:
A. One-time setup workflow: (Presented the first time a user opens the app. Page by page each with accept button and explanation)
1. Screen Time Access
2. Setup Screentime password if it hasn't been set up already
3. Toggle Deleting Apps to "Don't allow."
3. Choose what to block (you can always add more later)
4. Block button with warning and explanation

B. Main Page:
-Block/unblock button.
-Countdown timer (visible if an unblock request is pending)
-Items to block input (typing text suggests popular apps and websites). Selecting an option adds the item to the block list. If Block both App and Website is set to false in Settings, a modal with a checkbox for web and app appears along with confirm and cancel buttons.
-Collapsable list with heading "Active Blocks". Each item in the list has the name of the item (e.g. tiktok, pornhub) a checkbox labelled "App" and a checkbox labelled "Web". (Checked checkboxes are greyed out checked.). If both checkboxes are unchecked, a delete button appears on the item. 
-Settings menu link

C. Settings:
Blocking
-toggle block both website and app (default: true)
Permissions (inaccessible while block toggled true)
-toggle screentime permissions
-toggle Deleting Apps

D. Unblock Flow:
When a user clicks unblock a 60-minute timer begins counting down. This timer's count should be saved in the device's memory so it keeps going down if the user closes Blocker.
At 40 minutes, a notification pauses the timer and asks the user if they'd like to reconsider. Yes or no?
At 20 minutes, another notification presents a similar choice, with a jokier prompt.
When the timers runs out, a notification is set that the block can now be lifted. When the user opens the app, they are routed to this page:

- Text: No more jokes. If you still want to unblock, we won't stop ya. 
- button: "None, I've changed my mind." 
- heading: Active Blocks:
- A list of the blocked items follows (the same as the one on the main menu). At the end of the list is a button to save changes and re-block.

If you click none you are routed back to the main menu with the block enabled again. If you click, save changes your blocks are updated and you are returned to the main menu.
